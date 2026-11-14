import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createApp,readConfig} from '../src/app.mjs';
import {generateKeyPairSync,createCipheriv,sign} from 'node:crypto';
import {decryptWechatPayNotification,validateWechatPayOrder,decryptWechatRefundNotification,validateWechatRefundOrder} from '../../integrations/src/wechat.mjs';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const admin='test-only-admin-credential-123456789';
async function setup(t,mode='demo',overrides={}) {
  const server=createApp({...readConfig({API_MODE:mode,ADMIN_TOKEN:admin,CORS_ORIGINS:'https://club.example',CLUB_CONFIG_PATH:'none'}),dataDir:':memory:',...overrides});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>{server.closeAllConnections();server.close(resolve);}));
  const base=`http://127.0.0.1:${server.address().port}`;
  async function call(path,{token,method='GET',body,origin,extraHeaders={}}={}) {
    const headers={'Content-Type':'application/json',...extraHeaders};
    if(token)headers.Authorization=`Bearer ${token}`;
    if(origin)headers.Origin=origin;
    const r=await fetch(base+path,{method,headers,body:body===undefined?undefined:JSON.stringify(body)});
    return {status:r.status,data:await r.json(),headers:r.headers};
  }
  const login=async()=> (await call('/api/v1/auth/demo',{method:'POST',body:{name:'演示成员'}})).data.token;
  return {call,login};
}
const booking=(extra={})=>({serviceId:'s1',playerId:'p1',scheduledAt:new Date(Date.now()+3600000).toISOString(),contact:'demo-contact',note:'模拟预约',idempotencyKey:'test-key',...extra});

test('public catalog and deliberate demo flags',async t=>{
  const {call}=await setup(t);assert.equal((await call('/health')).data.realPaymentsEnabled,false);
  const r=await call('/api/v1/services');assert.equal(r.status,200);assert.equal(r.data[0].id,'s1');
  assert.equal((await call('/api/v1/club')).data.demo,true);
  assert.equal((await call('/api/v1/services/missing')).status,404);
});
test('order ownership, authoritative pricing, idempotency and state transitions',async t=>{
  const {call,login}=await setup(t),token=await login(),other=await login();
  assert.equal((await call('/api/v1/orders')).status,401);
  assert.equal((await call('/api/v1/orders',{method:'POST',token,body:booking({priceCents:1})})).status,400);
  const body=booking(),created=await call('/api/v1/orders',{method:'POST',token,body});
  assert.equal(created.status,201);assert.equal(created.data.priceCents,3900);assert.equal(created.data.paymentStatus,'unpaid');
  const again=await call('/api/v1/orders',{method:'POST',token,body});assert.equal(again.status,200);assert.equal(again.data.id,created.data.id);
  assert.equal((await call('/api/v1/orders',{method:'POST',token,body:{...body,note:'changed'}})).status,409);
  assert.deepEqual((await call('/api/v1/orders',{token:other})).data,[]);
  assert.equal((await call(`/api/v1/orders/${created.data.id}`,{token:other})).status,404);
  assert.equal((await call(`/api/v1/orders/${created.data.id}/cancel`,{method:'PATCH',token:other})).status,404);
  assert.equal((await call('/api/v1/admin/orders',{token})).status,401);
  const path=`/api/v1/admin/orders/${created.data.id}`;
  assert.equal((await call(path,{method:'PATCH',token:admin,body:{status:'completed'}})).status,409);
  assert.equal((await call(path,{method:'PATCH',token:admin,body:{status:'confirmed'}})).data.error.code,'USE_FULFILLMENT_FLOW');
  assert.equal((await call(path,{method:'PATCH',token:admin,body:{status:'completed'}})).status,409);
  assert.equal((await call(`/api/v1/orders/${created.data.id}/cancel`,{method:'PATCH',token})).data.status,'cancelled');
});
test('valid cancellation is idempotent and cannot be reactivated',async t=>{
  const {call,login}=await setup(t),token=await login();
  const order=(await call('/api/v1/orders',{method:'POST',token,body:booking()})).data;
  const path=`/api/v1/orders/${order.id}/cancel`;
  assert.equal((await call(path,{method:'PATCH',token})).data.status,'cancelled');
  assert.equal((await call(path,{method:'PATCH',token})).data.status,'cancelled');
  assert.equal((await call(`/api/v1/admin/orders/${order.id}`,{method:'PATCH',token:admin,body:{status:'confirmed'}})).status,409);
});
test('validation rejects stale dates and incompatible players',async t=>{
  const {call,login}=await setup(t),token=await login();
  for(const body of [booking({scheduledAt:'bad'}),booking({scheduledAt:new Date(0).toISOString()}),booking({playerId:'p3'}),booking({contact:''}),booking({serviceId:'missing'})]) {
    assert.equal((await call('/api/v1/orders',{method:'POST',token,body})).status,400);
  }
});
test('production denies demo auth and transactions; status never leaks secrets',async t=>{
  const {call}=await setup(t,'production');
  assert.equal((await call('/api/v1/auth/demo',{method:'POST',body:{}})).status,403);
  assert.equal((await call('/api/v1/orders',{token:'any-token'})).status,503);
  const r=await call('/api/v1/admin/config/status',{token:admin});
  assert.equal(r.data.realAuth,false);assert.equal(r.data.payments,false);assert.ok(!JSON.stringify(r.data).includes(admin));
});
test('CORS rejects untrusted web origins and config rejects weak admin credentials',async t=>{
  const {call}=await setup(t);
  assert.equal((await call('/api/v1/club',{origin:'https://evil.example'})).status,403);
  assert.equal((await call('/api/v1/club',{origin:'https://club.example'})).headers.get('access-control-allow-origin'),'https://club.example');
  assert.throws(()=>readConfig({ADMIN_TOKEN:'weak'}));
  assert.throws(()=>readConfig({ADMIN_TOKEN:'password-with-symbols-!@#$-123456'}),/base64url/);
  assert.throws(()=>readConfig({API_MODE:'typo'}));
  assert.throws(()=>readConfig({API_MODE:'production',ADMIN_TOKEN:admin,CORS_ORIGINS:'http://example.com'}));
});

test('authenticated order limits are per user behind a shared proxy connection',async t=>{
  const {call,login}=await setup(t),first=await login(),second=await login();
  for(let i=0;i<60;i++)assert.equal((await call('/api/v1/orders',{method:'POST',token:first,body:booking({serviceId:'missing'})})).status,400);
  assert.equal((await call('/api/v1/orders',{method:'POST',token:first,body:booking()})).status,429);
  assert.equal((await call('/api/v1/orders',{method:'POST',token:second,body:booking()})).status,201);
});

test('content CRUD persists active catalog, validates amounts and archives without breaking old orders',async t=>{
  const {call,login}=await setup(t),token=await login();
  const body=booking();const original=(await call('/api/v1/orders',{method:'POST',token,body})).data;
  assert.equal((await call('/api/v1/admin/services/s1',{method:'PATCH',token:admin,body:{priceCents:-1}})).status,400);
  assert.equal((await call('/api/v1/admin/services/s1',{method:'PATCH',token:admin,body:{priceCents:5900,title:'新服务名称'}})).status,200);
  assert.equal((await call('/api/v1/services/s1')).data.priceCents,5900);
  assert.equal((await call(`/api/v1/orders/${original.id}`,{token})).data.priceCents,3900);
  assert.equal((await call('/api/v1/admin/services/s1',{method:'DELETE',token:admin})).data.archived,true);
  assert.equal((await call('/api/v1/services/s1')).status,404);
  assert.equal((await call('/api/v1/orders',{method:'POST',token,body})).data.id,original.id);
  assert.equal((await call('/api/v1/orders',{method:'POST',token,body:{...body,idempotencyKey:'fresh'}})).status,400);
  assert.equal((await call('/api/v1/admin/club',{method:'PATCH',token:admin,body:{name:'真实俱乐部',demoData:false}})).data.demoData,false);
  assert.equal((await call('/api/v1/club')).data.name,'真实俱乐部');
  assert.equal((await call('/api/v1/admin/announcements',{method:'POST',token:admin,body:{title:'新公告',body:'内容',publishedAt:new Date().toISOString()}})).status,201);
  assert.equal((await call('/api/v1/announcements')).data.length,4);
});

test('real production payment callback is signed, amount-bound, idempotent and gates cancellation',async t=>{
  const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048});
  const config={appid:'wx_fixture',mchid:'123456',apiV3Key:'12345678901234567890123456789012',platformKeys:{FIXTURE:publicKey.export({type:'spki',format:'pem'})}};
  let upstreamOrder;
  const integrations={
    exchangeWechatCode:async({code})=>({openid:'openid-'+code,sessionKey:'must-never-leak'}),
    createJsapiOrder:async({order})=>{upstreamOrder=order;return {paymentParams:{package:'prepay_id=fixture'}};},
    decryptWechatPayNotification,validateWechatPayOrder
  };
  const {call}=await setup(t,'production',{wechat:{appid:config.appid,appSecret:'fixture-secret'},wechatPay:config,integrations});
  assert.equal((await call('/api/v1/auth/wechat',{method:'POST',body:{code:'customer'}})).data.error.code,'CLUB_NOT_READY');
  await call('/api/v1/admin/club',{method:'PATCH',token:admin,body:{demoData:false}});
  const auth=await call('/api/v1/auth/wechat',{method:'POST',body:{code:'customer'}}),token=auth.data.token;
  assert.ok(token);assert.ok(!JSON.stringify(auth.data).includes('must-never-leak'));
  const secondAuth=await call('/api/v1/auth/wechat',{method:'POST',body:{code:'customer'}});assert.equal(secondAuth.data.user.id,auth.data.user.id);
  const order=(await call('/api/v1/orders',{method:'POST',token,body:booking()})).data;
  assert.equal(order.demo,false);
  await call('/api/v1/admin/club',{method:'PATCH',token:admin,body:{demoData:true}});
  assert.equal((await call(`/api/v1/orders/${order.id}/pay`,{method:'POST',token})).status,409);
  await call('/api/v1/admin/club',{method:'PATCH',token:admin,body:{demoData:false}});
  assert.equal((await call(`/api/v1/orders/${order.id}/pay`,{method:'POST',token})).status,200);
  assert.equal(upstreamOrder.totalCents,3900);assert.equal(upstreamOrder.id,order.id.replaceAll('-',''));assert.equal(upstreamOrder.openid,'openid-customer');
  assert.equal((await call(`/api/v1/orders/${order.id}/cancel`,{method:'PATCH',token})).status,502);
  async function notify(total=3900,transaction='tx1',payer='openid-customer',badSignature=false){
    const nonce='123456789012',aad='transaction';
    const payment={appid:config.appid,mchid:config.mchid,trade_state:'SUCCESS',trade_type:'JSAPI',amount:{total,currency:'CNY'},out_trade_no:upstreamOrder.id,transaction_id:transaction,payer:{openid:payer},success_time:new Date().toISOString()};
    const cipher=createCipheriv('aes-256-gcm',Buffer.from(config.apiV3Key),Buffer.from(nonce));cipher.setAAD(Buffer.from(aad));
    const encrypted=Buffer.concat([cipher.update(JSON.stringify(payment)),cipher.final(),cipher.getAuthTag()]);
    const body={id:'notification-fixture',event_type:'TRANSACTION.SUCCESS',resource:{algorithm:'AEAD_AES_256_GCM',original_type:'transaction',nonce,associated_data:aad,ciphertext:encrypted.toString('base64')}};
    const raw=JSON.stringify(body),time=String(Math.floor(Date.now()/1000)),random='signed-notification';
    const signature=sign('RSA-SHA256',Buffer.from(`${time}\n${random}\n${raw}\n`),privateKey).toString('base64');
    return call('/api/v1/payments/wechat/notify',{method:'POST',body,extraHeaders:{'Wechatpay-Timestamp':time,'Wechatpay-Nonce':random,'Wechatpay-Serial':'FIXTURE','Wechatpay-Signature':badSignature?'bad':signature}});
  }
  assert.equal((await notify(3900,'tx1','openid-customer',true)).status,401);
  assert.equal((await notify(1)).status,400);
  assert.equal((await notify(3900,'tx1','different-payer')).status,400);
  assert.equal((await notify()).status,200);assert.equal((await notify()).status,200);
  assert.equal((await call(`/api/v1/orders/${order.id}`,{token})).data.paymentStatus,'paid');
  assert.equal((await notify(3900,'different-tx')).status,409);
  assert.equal((await call(`/api/v1/orders/${order.id}/pay`,{method:'POST',token})).status,409);
});

test('native APP login isolates app identities and dispatches signed payment parameters',async t=>{
  let providerOrder;
  const {call}=await setup(t,'production',{
    wechat:{appid:'wx-mini',appSecret:'secret'},wechatNative:{appid:'wx-native',appSecret:'secret'},
    wechatAppPay:{appid:'wx-native',tradeType:'APP'},
    integrations:{exchangeWechatCode:async()=>({openid:'same-openid'}),exchangeWechatAppCode:async()=>({openid:'same-openid',accessToken:'private-oauth-token'}),createAppOrder:async input=>{providerOrder=input;return {paymentParams:{appId:'wx-native',partnerId:'mch',prepayId:'prepay',package:'Sign=WXPay',nonceStr:'nonce',timeStamp:'123',sign:'signature'}};}}
  });
  await call('/api/v1/admin/club',{method:'PATCH',token:admin,body:{demoData:false}});
  const native=(await call('/api/v1/auth/wechat-app',{method:'POST',body:{code:'native-code'}})).data;
  const mini=(await call('/api/v1/auth/wechat',{method:'POST',body:{code:'mini-code'}})).data;
  assert.notEqual(native.user.id,mini.user.id);assert.ok(!JSON.stringify(native).includes('private-oauth-token'));
  const created=(await call('/api/v1/orders',{method:'POST',token:native.token,body:booking()})).data;
  assert.equal((await call(`/api/v1/orders/${created.id}`,{token:mini.token})).status,404);
  await call('/api/v1/admin/club',{method:'PATCH',token:admin,body:{demoData:false}});
  const payment=await call(`/api/v1/orders/${created.id}/pay`,{method:'POST',token:native.token});
  assert.equal(payment.status,200);assert.equal(payment.data.paymentParams.package,'Sign=WXPay');assert.equal(providerOrder.config.tradeType,'APP');assert.equal(providerOrder.order.totalCents,3900);
  assert.equal((await call('/api/v1/account',{method:'DELETE',token:native.token})).status,409);
});

test('account deletion rejects active orders then revokes sessions and anonymizes retained history',async t=>{
  const {call,login}=await setup(t),token=await login();
  assert.equal((await call('/api/v1/account',{method:'DELETE'})).status,401);
  const created=(await call('/api/v1/orders',{method:'POST',token,body:booking()})).data;
  assert.equal((await call('/api/v1/account',{method:'DELETE',token})).status,409);
  await call(`/api/v1/orders/${created.id}/cancel`,{method:'PATCH',token});
  assert.deepEqual((await call('/api/v1/account',{method:'DELETE',token})).data,{deleted:true,retainedOrders:1});
  assert.equal((await call('/api/v1/orders',{token})).status,401);
  const retained=(await call('/api/v1/admin/orders',{token:admin})).data[0];
  assert.equal(retained.contact,'');assert.equal(retained.note,'');assert.equal(retained.priceCents,3900);
});

test('full refund is idempotent, binds signed callback to saved payment and never regresses settled state',async t=>{
  const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048});
  const config={appid:'wx_refund',mchid:'123456',tradeType:'JSAPI',refundNotifyUrl:'https://club.example/refund',apiV3Key:'12345678901234567890123456789012',platformKeys:{FIXTURE:publicKey.export({type:'spki',format:'pem'})}};
  let orderId,refundRequest,refundCalls=0;
  const payment=()=>({state:'SUCCESS',orderId,transactionId:'payment-tx',totalCents:3900,currency:'CNY',appid:config.appid,mchid:config.mchid,openid:'owner',paidAt:new Date().toISOString(),tradeType:'JSAPI'});
  const refund=(extra={})=>({refundId:refundRequest.refundId,providerRefundId:'provider-refund',status:'PROCESSING',orderId,transactionId:'payment-tx',totalCents:3900,refundCents:3900,...extra});
  const {call}=await setup(t,'production',{wechat:{appid:config.appid,appSecret:'secret'},wechatPay:config,wechatAppPay:{...config,appid:'wx_other',tradeType:'APP'},integrations:{
    exchangeWechatCode:async()=>({openid:'owner'}),queryWechatOrder:async()=>payment(),
    createWechatRefund:async request=>{if(refundRequest)assert.equal(request.refundId,refundRequest.refundId);refundRequest=request;refundCalls++;return refund();},
    queryWechatRefund:async()=>refund(),decryptWechatRefundNotification,validateWechatRefundOrder,
    decryptWechatPayNotification:async()=>payment()
  }});
  await call('/api/v1/admin/club',{method:'PATCH',token:admin,body:{demoData:false}});
  const token=(await call('/api/v1/auth/wechat',{method:'POST',body:{code:'owner'}})).data.token;
  const created=(await call('/api/v1/orders',{method:'POST',token,body:booking()})).data;orderId=created.id.replaceAll('-','');
  const base=`/api/v1/admin/orders/${created.id}`;
  assert.equal((await call(base+'/refund',{method:'POST',token:admin,body:{reason:'客户申请'}})).status,409);
  assert.equal((await call(base+'/payment-sync',{method:'POST',token:admin})).data.paymentStatus,'paid');
  assert.equal((await call(base+'/refund',{method:'POST',token,body:{reason:'客户申请'}})).status,401);
  assert.equal((await call(base+'/refund',{method:'POST',token:admin,body:{reason:'客户申请'}})).data.paymentStatus,'refund_pending');
  assert.equal((await call(base+'/refund',{method:'POST',token:admin,body:{reason:'客户申请'}})).data.paymentStatus,'refund_pending');
  assert.equal(refundCalls,2);assert.equal(refundRequest.order.totalCents,3900);
  assert.equal((await call('/api/v1/account',{method:'DELETE',token})).status,409);
  assert.equal((await call('/api/v1/payments/wechat/notify',{method:'POST',body:{}})).status,200);
  assert.equal((await call(`/api/v1/orders/${created.id}`,{token})).data.paymentStatus,'refund_pending');
  async function notify(amount=3900,route='wechat',badSignature=false){
    const nonce='123456789012',aad='refund';
    const payload={mchid:config.mchid,out_trade_no:orderId,transaction_id:'payment-tx',out_refund_no:refundRequest.refundId,refund_id:'provider-refund',refund_status:'SUCCESS',amount:{total:3900,refund:amount,payer_total:3900,payer_refund:amount},success_time:new Date().toISOString()};
    const cipher=createCipheriv('aes-256-gcm',Buffer.from(config.apiV3Key),Buffer.from(nonce));cipher.setAAD(Buffer.from(aad));
    const encrypted=Buffer.concat([cipher.update(JSON.stringify(payload)),cipher.final(),cipher.getAuthTag()]);
    const body={id:'refund-notification',event_type:'REFUND.SUCCESS',resource:{algorithm:'AEAD_AES_256_GCM',original_type:'refund',nonce,associated_data:aad,ciphertext:encrypted.toString('base64')}};
    const time=String(Math.floor(Date.now()/1000)),random='signed-refund';
    const signature=sign('RSA-SHA256',Buffer.from(`${time}\n${random}\n${JSON.stringify(body)}\n`),privateKey).toString('base64');
    return call(`/api/v1/payments/${route}/refund-notify`,{method:'POST',body,extraHeaders:{'Wechatpay-Timestamp':time,'Wechatpay-Nonce':random,'Wechatpay-Serial':'FIXTURE','Wechatpay-Signature':badSignature?'bad':signature}});
  }
  assert.equal((await notify(3900,'wechat',true)).status,401);
  assert.equal((await notify(1)).status,400);
  assert.equal((await notify(3900,'wechat-app')).status,400);
  assert.equal((await notify()).status,200);assert.equal((await notify()).status,200);
  const settled=(await call(`/api/v1/orders/${created.id}`,{token})).data;
  assert.equal(settled.paymentStatus,'refunded');assert.equal(settled.status,'cancelled');
  assert.equal((await call(base+'/payment-sync',{method:'POST',token:admin})).data.paymentStatus,'refunded');
  assert.equal((await call('/api/v1/payments/wechat/notify',{method:'POST',body:{}})).status,200);
  assert.equal((await call('/api/v1/account',{method:'DELETE',token})).data.deleted,true);
  assert.equal((await notify()).status,200);
});

test('catalog survives restart and production does not accept persisted demo sessions',async t=>{
  const dataDir=mkdtempSync(join(tmpdir(),'openni-api-'));t.after(()=>rmSync(dataDir,{recursive:true,force:true}));
  const config={...readConfig({ADMIN_TOKEN:admin,CLUB_CONFIG_PATH:'none'}),dataDir};
  const first=createApp(config);await new Promise(r=>first.listen(0,'127.0.0.1',r));
  const base=`http://127.0.0.1:${first.address().port}/api/v1`;
  const session=await(await fetch(base+'/auth/demo',{method:'POST',headers:{'content-type':'application/json'},body:'{}'})).json();
  await fetch(base+'/admin/club',{method:'PATCH',headers:{'content-type':'application/json',authorization:'Bearer '+admin},body:JSON.stringify({name:'持久化俱乐部'})});
  await new Promise(r=>{first.closeAllConnections();first.close(r);});
  const {call}=await setup(t,'production',{dataDir,wechat:{appid:'wx-fixture',appSecret:'fixture'}});
  assert.equal((await call('/api/v1/club')).data.name,'持久化俱乐部');
  assert.equal((await call('/api/v1/orders',{token:session.token})).status,401);
});
