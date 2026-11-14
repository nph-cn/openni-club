import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createApp,readConfig} from '../src/app.mjs';
import {request as httpRequest} from 'node:http';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const admin='operations-test-admin-1234567890';
async function setup(t,overrides={}){
  const server=createApp({...readConfig({ADMIN_TOKEN:admin,CLUB_CONFIG_PATH:'none'}),dataDir:':memory:',...overrides});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>{if(!server.listening)return;return new Promise(resolve=>{server.closeAllConnections();server.close(resolve);});});
  const base=`http://127.0.0.1:${server.address().port}/api/v1`;
  async function call(path,token,method='GET',body){const response=await fetch(base+path,{method,headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body)});return {status:response.status,data:await response.json()};}
  const login=async(role='customer',playerId)=>{const result=await call('/auth/demo',null,'POST',{role,playerId});assert.equal(result.status,201);return result.data.token;};
  const book=async(token,extra={})=>{const result=await call('/orders',token,'POST',{serviceId:'s1',scheduledAt:new Date(Date.now()+5*60000).toISOString(),contact:'test-only-contact',idempotencyKey:crypto.randomUUID(),...extra});assert.equal(result.status,201,JSON.stringify(result.data));return result.data;};
  async function fulfill(customer,member,extra={}){const order=await book(customer,extra);assert.equal((await call(`/admin/orders/${order.id}/assign`,admin,'POST',{playerId:'p1',commissionBps:2000})).status,200);assert.equal((await call(`/member/orders/${order.id}/accept`,member,'POST',{})).status,200);assert.equal((await call(`/member/orders/${order.id}/start`,member,'POST',{})).status,200);assert.equal((await call(`/member/orders/${order.id}/submit`,member,'POST',{summary:'已完成约定的一小时组队服务。',evidenceUrl:'https://example.com/test-evidence'})).status,200);return order;}
  return {call,login,book,fulfill,base,server};
}

test('assigned service, member acceptance, delivery, customer confirmation and manual settlement form one ledger',async t=>{
  const {call,login,book}=await setup(t),customer=await login(),member=await login('member','p1'),other=await login('member','p2');
  const order=await book(customer);assert.equal(order.fulfillmentStatus,'awaiting_assignment');assert.equal(order.events[0].type,'created');
  const originalSlots=(await call('/member/availability',member)).data.slots;
  assert.equal((await call('/member/availability',member,'PUT',{slots:originalSlots})).status,200);
  const changedPast=originalSlots.map(slot=>({...slot}));changedPast[0].startAt=new Date(Date.parse(changedPast[0].startAt)-60000).toISOString();
  assert.equal((await call('/member/availability',member,'PUT',{slots:changedPast})).status,400);
  assert.equal((await call(`/member/orders/${order.id}/accept`,customer,'POST',{})).status,403);
  await call('/admin/services/s1',admin,'PATCH',{priceCents:9900,durationMinutes:120});
  const assigned=await call(`/admin/orders/${order.id}/assign`,admin,'POST',{playerId:'p1',commissionBps:2000});
  assert.equal(assigned.status,200);assert.equal(assigned.data.memberCents,3120);assert.equal(assigned.data.clubCents,780);assert.equal(assigned.data.durationMinutes,60);
  assert.equal((await call(`/member/orders/${order.id}/accept`,other,'POST',{})).status,404);
  assert.equal((await call(`/member/orders/${order.id}`,other)).status,404);
  assert.equal((await call(`/member/orders/${order.id}`,member)).status,200);
  assert.equal((await call(`/member/orders/${order.id}/accept`,member,'POST',{})).data.fulfillmentStatus,'scheduled');
  assert.equal((await call(`/member/orders/${order.id}/accept`,member,'POST',{})).data.fulfillmentStatus,'scheduled');
  assert.equal((await call('/member/availability',member,'PUT',{slots:[]})).status,409);
  assert.equal((await call(`/member/orders/${order.id}/start`,member,'POST',{})).data.fulfillmentStatus,'in_progress');
  assert.equal((await call(`/orders/${order.id}/cancel`,customer,'PATCH')).status,409);
  assert.equal((await call(`/member/orders/${order.id}/submit`,member,'POST',{summary:'交付记录',evidenceUrl:'http://unsafe.example'})).status,400);
  assert.equal((await call(`/member/orders/${order.id}/submit`,member,'POST',{summary:'交付记录'})).data.fulfillmentStatus,'awaiting_confirmation');
  assert.equal((await call('/member/earnings',member)).data.totals.heldCents,3120);
  assert.equal((await call(`/orders/${order.id}/confirm`,other,'POST',{rating:5})).status,404);
  assert.equal((await call(`/orders/${order.id}/confirm`,customer,'POST',{rating:5,comment:'流程测试'})).data.fulfillmentStatus,'completed');
  await call(`/orders/${order.id}/confirm`,customer,'POST',{rating:1});
  const earnings=(await call('/member/earnings',member)).data;assert.equal(earnings.entries.length,1);assert.equal(earnings.totals.availableCents,3120);
  const request={entryIds:[earnings.entries[0].id],paymentReference:'DEMO-NO-TRANSFER-001',note:'演示凭据，不产生转账'};
  const settled=await call('/admin/settlements',admin,'POST',request);assert.equal(settled.status,201);assert.equal(settled.data.moneyTransferred,false);assert.equal(settled.data.memberCents,3120);
  assert.equal((await call('/admin/settlements',admin,'POST',request)).data.id,settled.data.id);
  assert.equal((await call('/admin/settlements',admin,'POST',{...request,paymentReference:'different-reference'})).status,409);
  assert.equal((await call('/member/earnings',member)).data.totals.settledCents,3120);
  assert.equal((await call(`/orders/${order.id}/dispute`,customer,'POST',{reason:'已结算后须人工处理'})).status,409);
  const notices=(await call('/notifications',member)).data;assert.ok(notices.some(item=>item.type==='settlement_recorded'));
  assert.equal((await call(`/notifications/${notices[0].id}/read`,other,'PATCH')).status,404);
  assert.equal((await call(`/notifications/${notices[0].id}/read`,member,'PATCH')).status,200);
});

test('overlapping assignment is rejected, decline and acceptance expiry release the reservation',async t=>{
  let clock=Date.now();const {call,login,book}=await setup(t,{now:()=>clock}),customer=await login(),member=await login('member','p1');
  const scheduledAt=new Date(clock+2*3600000).toISOString(),first=await book(customer,{scheduledAt}),second=await book(customer,{scheduledAt});
  const assign=id=>call(`/admin/orders/${id}/assign`,admin,'POST',{playerId:'p1'});
  assert.equal((await assign(first.id)).status,200);assert.equal((await assign(second.id)).data.error.code,'SCHEDULE_CONFLICT');
  assert.equal((await call(`/member/orders/${first.id}/decline`,member,'POST',{reason:'临时无法上线'})).data.fulfillmentStatus,'awaiting_assignment');
  assert.equal((await assign(second.id)).status,200);
  clock+=16*60000;
  assert.equal((await call(`/orders/${second.id}`,customer)).data.fulfillmentStatus,'awaiting_assignment');
  assert.equal((await call(`/member/orders/${second.id}/accept`,member,'POST',{})).status,404);
  assert.equal((await assign(first.id)).status,200);
  const date=new Date(Date.parse(scheduledAt)+8*3600000).toISOString().slice(0,10),available=await call('/players/p1/availability?date='+date);
  assert.equal(available.data.timezone,'Asia/Shanghai');assert.ok(available.data.slots.some(slot=>slot.busy));
});

test('disputes freeze earnings; resume restores eligibility, demo refund reverses it without claiming money moved',async t=>{
  const {call,login,fulfill}=await setup(t),customer=await login(),member=await login('member','p1');
  const order=await fulfill(customer,member);
  await call(`/orders/${order.id}/confirm`,customer,'POST',{rating:4});
  const dispute=await call(`/orders/${order.id}/dispute`,customer,'POST',{reason:'交付有遗漏',details:'需要核对服务记录'});assert.equal(dispute.data.fulfillmentStatus,'disputed');
  const earnings=(await call('/member/earnings',member)).data;assert.equal(earnings.totals.heldCents,3120);
  assert.equal((await call('/admin/settlements',admin,'POST',{entryIds:[earnings.entries[0].id],paymentReference:'not-allowed'})).status,409);
  assert.equal((await call(`/admin/orders/${order.id}/resolve`,admin,'POST',{outcome:'resume',reason:'双方确认已交付'})).data.fulfillmentStatus,'completed');
  assert.equal((await call('/member/earnings',member)).data.totals.availableCents,3120);
  const another=await fulfill(customer,member);
  await call(`/orders/${another.id}/dispute`,customer,'POST',{reason:'客户申请售后'});
  const reversed=await call(`/admin/orders/${another.id}/resolve`,admin,'POST',{outcome:'refund',reason:'演示撤单，不转账'});
  assert.equal(reversed.data.fulfillmentStatus,'cancelled');assert.equal(reversed.data.paymentStatus,'unpaid');assert.equal(reversed.data.demo,true);
  assert.equal((await call('/member/earnings',member)).data.totals.reversedCents,3120);
  assert.equal((await call('/admin/disputes',admin)).data.length,0);
});

test('production member role requires an expiring single-use owner invitation',async t=>{
  let clock=Date.now();const {call}=await setup(t,{mode:'production',now:()=>clock,wechat:{appid:'wx_test',appSecret:'test'},integrations:{exchangeWechatCode:async({code})=>({openid:'openid-'+code})}});
  await call('/admin/club',admin,'PATCH',{demoData:false});
  const customer=(await call('/auth/wechat',null,'POST',{code:'customer'})).data.token;
  assert.equal((await call('/auth/demo/role',customer,'POST',{role:'member',playerId:'p1'})).status,403);
  assert.equal((await call('/member/orders',customer)).status,403);
  const expired=(await call('/admin/players/p1/invitation',admin,'POST',{})).data;
  clock+=61*60000;
  assert.equal((await call('/member/invitation/accept',customer,'POST',{code:expired.code})).status,400);
  const invitation=(await call('/admin/players/p1/invitation',admin,'POST',{})).data;
  const accepted=await call('/member/invitation/accept',customer,'POST',{code:invitation.code});assert.equal(accepted.data.role,'member');assert.equal(accepted.data.playerId,'p1');
  assert.equal((await call('/member/invitation/accept',customer,'POST',{code:invitation.code})).status,400);
  assert.equal((await call('/admin/players/p1/invitation',admin,'POST',{})).status,409);
  assert.deepEqual((await call('/member/availability',customer)).data.slots,[]);
});

test('pending payment cancellation waits for provider close AND query confirmation',async t=>{
  let state='NOTPAY',orderId,closed=0,confirmClosed=false;
  const payment={appid:'wx_test',mchid:'merchant',tradeType:'JSAPI'};
  const {call,book}=await setup(t,{mode:'production',wechat:{appid:'wx_test',appSecret:'test'},wechatPay:payment,integrations:{
    exchangeWechatCode:async()=>({openid:'payer'}),createJsapiOrder:async({order})=>{orderId=order.id;return {paymentParams:{package:'prepay_id=test'}};},
    queryWechatOrder:async()=>({state,orderId,totalCents:3900,currency:'CNY',appid:'wx_test',mchid:'merchant',openid:'payer',transactionId:'paid-tx',paidAt:new Date().toISOString()}),
    closeWechatOrder:async()=>{closed++;if(confirmClosed)state='CLOSED';return {accepted:true,orderId};}
  }});
  await call('/admin/club',admin,'PATCH',{demoData:false});
  const customer=(await call('/auth/wechat',null,'POST',{code:'customer'})).data.token,order=await book(customer);
  assert.equal(order.fulfillmentStatus,'awaiting_payment');await call(`/orders/${order.id}/pay`,customer,'POST',{});
  assert.equal((await call(`/orders/${order.id}/cancel`,customer,'PATCH')).status,409);
  assert.equal((await call(`/orders/${order.id}`,customer)).data.paymentStatus,'pending');
  confirmClosed=true;assert.equal((await call(`/orders/${order.id}/cancel`,customer,'PATCH')).data.fulfillmentStatus,'cancelled');assert.equal(closed,2);
  const paid=await book(customer);await call(`/orders/${paid.id}/pay`,customer,'POST',{});state='SUCCESS';
  assert.equal((await call(`/orders/${paid.id}/cancel`,customer,'PATCH')).data.error.code,'REFUND_REQUIRED');
  assert.equal((await call(`/orders/${paid.id}`,customer)).data.fulfillmentStatus,'awaiting_assignment');
});

test('real full refund freezes available earnings then reverses them once on verified completion',async t=>{
  let merchantOrder,refundRequest;
  const payment={appid:'wx_test',mchid:'merchant',tradeType:'JSAPI',refundNotifyUrl:'https://example.com/refund'};
  const notification=()=>({orderId:merchantOrder,totalCents:3900,currency:'CNY',appid:'wx_test',mchid:'merchant',openid:'payer-customer',transactionId:'real-test-tx',state:'SUCCESS',paidAt:new Date().toISOString()});
  const refund=status=>({orderId:merchantOrder,transactionId:'real-test-tx',refundId:refundRequest.refundId,providerRefundId:'provider-refund',totalCents:3900,refundCents:3900,status});
  const {call,book}=await setup(t,{mode:'production',wechat:{appid:'wx_test',appSecret:'test'},wechatPay:payment,integrations:{
    exchangeWechatCode:async({code})=>({openid:'payer-'+code}),queryWechatOrder:async({orderId})=>{merchantOrder=orderId;return notification();},
    createWechatRefund:async request=>{refundRequest=request;return refund('PROCESSING');},decryptWechatRefundNotification:async()=>refund('SUCCESS')
  }});
  await call('/admin/club',admin,'PATCH',{demoData:false});
  const customer=(await call('/auth/wechat',null,'POST',{code:'customer'})).data.token,member=(await call('/auth/wechat',null,'POST',{code:'member'})).data.token;
  const invite=(await call('/admin/players/p1/invitation',admin,'POST',{})).data;
  await call('/member/invitation/accept',member,'POST',{code:invite.code});
  await call('/member/availability',member,'PUT',{slots:[{startAt:new Date(Date.now()+60000).toISOString(),endAt:new Date(Date.now()+2*3600000).toISOString()}]});
  const order=await book(customer);
  assert.equal((await call(`/admin/orders/${order.id}/payment-sync`,admin,'POST',{})).data.fulfillmentStatus,'awaiting_assignment');
  assert.equal((await call(`/admin/orders/${order.id}/assign`,admin,'POST',{playerId:'p1'})).status,200);
  await call(`/member/orders/${order.id}/accept`,member,'POST',{});await call(`/member/orders/${order.id}/start`,member,'POST',{});await call(`/member/orders/${order.id}/submit`,member,'POST',{summary:'已交付'});await call(`/orders/${order.id}/confirm`,customer,'POST',{rating:4});
  const entry=(await call('/member/earnings',member)).data.entries[0];assert.equal(entry.state,'available');
  assert.equal((await call(`/admin/orders/${order.id}/refund`,admin,'POST',{reason:'双方协商全额退款'})).data.paymentStatus,'refund_pending');
  assert.equal((await call('/member/earnings',member)).data.totals.heldCents,3120);
  assert.equal((await call('/admin/settlements',admin,'POST',{entryIds:[entry.id],paymentReference:'cannot-settle'})).status,409);
  assert.equal((await call('/payments/wechat/refund-notify',null,'POST',{})).status,200);assert.equal((await call('/payments/wechat/refund-notify',null,'POST',{})).status,200);
  const final=(await call(`/orders/${order.id}`,customer)).data;
  assert.equal(final.fulfillmentStatus,'cancelled');assert.equal(final.events.filter(event=>event.type==='refunded').length,1);assert.equal((await call('/member/earnings',member)).data.totals.reversedCents,3120);
});

test('configured brand is authoritative while existing catalog survives a brand revision',async t=>{
  const dataDir=mkdtempSync(join(tmpdir(),'openni-brand-'));t.after(()=>rmSync(dataDir,{recursive:true,force:true}));
  const brand={id:'configured-club',name:'统一品牌甲',demoData:true,configHash:'revision-a'};
  const first=await setup(t,{dataDir,publicBrand:brand});
  assert.equal((await first.call('/club')).data.configManaged,true);
  assert.equal((await first.call('/admin/club',admin,'PATCH',{name:'不能另存'})).data.error.code,'BRAND_MANAGED_BY_CONFIG');
  assert.equal((await first.call('/admin/services/s1',admin,'PATCH',{priceCents:5500})).status,200);
  await new Promise(resolve=>{first.server.closeAllConnections();first.server.close(resolve);});
  const second=await setup(t,{dataDir,publicBrand:{...brand,name:'统一品牌乙',configHash:'revision-b'},initialSeed:{club:brand,services:[],players:[],announcements:[]}});
  assert.equal((await second.call('/club')).data.name,'统一品牌乙');assert.equal((await second.call('/club')).data.configHash,'revision-b');
  assert.equal((await second.call('/services/s1')).data.priceCents,5500);
});

test('request buffering preserves split UTF-8 and accepts full Chinese policy documents within byte limits',async t=>{
  const {base}=await setup(t),payload={name:'北岸🌊电竞',privacyText:'隐'.repeat(20000),termsText:'约'.repeat(20000)};
  const bytes=Buffer.from(JSON.stringify(payload)),cut=bytes.indexOf(Buffer.from('北'))+1;
  const result=await new Promise((resolve,reject)=>{
    const request=httpRequest(base+'/admin/club',{method:'PATCH',headers:{'content-type':'application/json',authorization:'Bearer '+admin}},response=>{const chunks=[];response.on('data',chunk=>chunks.push(chunk));response.on('end',()=>resolve({status:response.statusCode,data:JSON.parse(Buffer.concat(chunks).toString('utf8'))}));});
    request.on('error',reject);request.write(bytes.subarray(0,cut));setImmediate(()=>request.end(bytes.subarray(cut)));
  });
  assert.equal(result.status,200);assert.equal(result.data.name,payload.name);assert.equal(result.data.privacyText,payload.privacyText);assert.equal(result.data.termsText,payload.termsText);
});

test('SKU quotes and fulfillment rules are server-selected and immutable after booking',async t=>{
  const {call,login}=await setup(t),customer=await login();
  const variants=[{id:'pc-60',title:'PC 60 minutes',priceCents:3900,durationMinutes:60,platform:'PC',rules:['One member, sixty minutes.']},{id:'mobile-120',title:'Mobile 120 minutes',priceCents:7200,durationMinutes:120,platform:'mobile',rules:['One member, two hours.']}];
  assert.equal((await call('/admin/services/s1',admin,'PATCH',{variants})).status,200);
  const payload={serviceId:'s1',variantId:'mobile-120',scheduledAt:new Date(Date.now()+3600000).toISOString(),contact:'fixture',idempotencyKey:'sku-test-quote-1'};
  const missing={...payload};delete missing.variantId;
  assert.equal((await call('/orders',customer,'POST',missing)).data.error.code,'VARIANT_REQUIRED');
  assert.equal((await call('/orders',customer,'POST',{...payload,priceCents:1})).status,400);
  const booked=await call('/orders',customer,'POST',payload);assert.equal(booked.status,201);assert.equal(booked.data.priceCents,7200);assert.equal(booked.data.durationMinutes,120);assert.equal(booked.data.serviceSnapshot.platform,'mobile');
  variants[1].priceCents=1;variants[1].rules=['New rules'];
  await call('/admin/services/s1',admin,'PATCH',{variants});
  const same=(await call('/orders',customer,'POST',payload)).data;assert.equal(same.id,booked.data.id);assert.equal(same.priceCents,7200);assert.deepEqual(same.serviceSnapshot.rules,['One member, two hours.']);
  assert.equal((await call('/orders',customer,'POST',{...payload,variantId:'pc-60'})).data.error.code,'IDEMPOTENCY_CONFLICT');
  assert.equal((await call('/admin/services/s1',admin,'PATCH',{variants:[...variants,variants[0]]})).status,400);
  await call('/admin/services/s1',admin,'PATCH',{variants:[],teamSize:2});
  assert.equal((await call('/orders',customer,'POST',{...missing,idempotencyKey:'two-member-unsupported'})).data.error.code,'MULTI_MEMBER_NOT_SUPPORTED');
});
