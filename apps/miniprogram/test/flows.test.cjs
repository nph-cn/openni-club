const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const root=path.resolve(__dirname,'..');

async function setup(t,mode='demo',options={}){
  const {createApp,readConfig}=await import('../../../services/api/src/app.mjs');
  const server=createApp({...readConfig({API_MODE:mode,SMS_PROVIDER:options.sms?'test':'disabled',CLUB_CONFIG_PATH:'none',ADMIN_TOKEN:'fixture-admin-token-1234567890',CORS_ORIGINS:'https://club.test'}),dataDir:':memory:',...(mode==='production'?{wechat:{appid:'wx-fixture',appSecret:'fixture-secret'},wechatPay:{appid:'wx-fixture'},integrations:{exchangeWechatCode:async()=>({openid:'fixture-openid'}),createJsapiOrder:async()=>({paymentParams:{timeStamp:'123',nonceStr:'nonce',package:'prepay_id=fixture',signType:'RSA',paySign:'fixture-sign'}})}}:{})});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>{server.closeAllConnections();server.close(resolve);}));
  const actualBase=`http://127.0.0.1:${server.address().port}/api/v1`,apiBaseUrl=mode==='production'?'https://club.test/api/v1':actualBase,storage=new Map(),cache=new Map(),navigations=[];
  if(mode==='production')await fetch(actualBase+'/admin/club',{method:'PATCH',headers:{'content-type':'application/json',authorization:'Bearer fixture-admin-token-1234567890'},body:JSON.stringify({demoData:false})});
  let paymentCalls=0;
  const wx={
    getStorageSync:k=>storage.get(k),setStorageSync:(k,v)=>storage.set(k,v),removeStorageSync:k=>storage.delete(k),
    request(o){fetch(o.url.replace(apiBaseUrl,actualBase),{method:o.method,headers:o.header,body:o.data===undefined?undefined:JSON.stringify(o.data)}).then(async r=>o.success({statusCode:r.status,data:await r.json()})).catch(o.fail);},
    login:o=>o.success({code:'fixture-code'}),requestPayment:o=>{paymentCalls++;o.success({errMsg:'requestPayment:ok'});},
    navigateBack:()=>navigations.push("BACK"),navigateTo:o=>navigations.push(o.url),redirectTo:o=>navigations.push(o.url),switchTab:o=>navigations.push(o.url),
    stopPullDownRefresh(){},showToast(){},showModal:o=>o.success({confirm:true})
  };
  let captured;
  function load(file){
    file=path.resolve(file.endsWith('.js')?file:file+'.js');
    if(file===path.join(root,'utils/config.js'))return {apiBaseUrl,mode};
    if(cache.has(file))return cache.get(file).exports;
    const module={exports:{}};cache.set(file,module);
    const context={module,exports:module.exports,require:p=>load(path.resolve(path.dirname(file),p)),wx,Page:p=>captured=p,App(){},getCurrentPages:()=>options.stack||[],Date,console,Promise,setTimeout,setInterval,clearInterval};
    vm.runInNewContext(fs.readFileSync(file,'utf8'),context,{filename:file});return module.exports;
  }
  function page(name){const file=path.join(root,'pages',name,name+'.js');cache.delete(file);load(file);const p=captured;p.setData=function(update){Object.assign(this.data,update);};return p;}
  const api=load(path.join(root,"utils/api.js"));
  return {page,navigations,apiBaseUrl,storage,api,async call(route,method='GET',data,token='fixture-admin-token-1234567890'){const r=await fetch(actualBase+route,{method,headers:{'content-type':'application/json',authorization:'Bearer '+token},body:data===undefined?undefined:JSON.stringify(data)});return {status:r.status,data:await r.json()};},getPaymentCalls:()=>paymentCalls};
}

test('every registered native page and template exists, JSON parses, bindings are present',()=>{
  const app=JSON.parse(fs.readFileSync(path.join(root,'app.json'),'utf8'));
  assert.equal(app.pages.length,16);
  for(const p of app.pages){
    const script=fs.readFileSync(path.join(root,p+'.js'),'utf8');new vm.Script(script);
    const xml=fs.readFileSync(path.join(root,p+'.wxml'),'utf8');assert.equal(xml.includes('template is="demo"'),p==='pages/booking/booking');
    assert.ok(!xml.includes('<br'));JSON.parse(fs.readFileSync(path.join(root,p+'.json'),'utf8'));
  }
  for(const tab of app.tabBar.list)assert.ok(app.pages.includes(tab.pagePath));
});

test('production uses WeChat code exchange and never treats SDK success as paid',async t=>{
  const {page,navigations,storage,getPaymentCalls,api}=await setup(t,'production');await api.login();
  const booking=page('booking');booking.serviceId='s1';booking.playerId='p1';await booking.load();
  const tomorrow=new Date(Date.now()+86400000);booking.setData({date:tomorrow.toISOString().slice(0,10),time:'14:00',contact:'fixture-only',note:'',playerIndex:0});
  await booking.submit();assert.equal(booking.data.submitError,'');assert.equal(storage.get('openni-session').mode,'production');
  const id=navigations.at(-1).split('id=')[1].split('&')[0],detail=page('order');detail.id=id;await detail.load();
  assert.equal(detail.data.order.demo,false);assert.equal(detail.data.order.canPay,true);
  await detail.pay();assert.equal(getPaymentCalls(),1);assert.equal(detail.data.order.paymentStatus,'pending');assert.equal(detail.data.order.canCancel,true);
  assert.ok(detail.data.paymentMessage.includes('服务器'));
});
test('native page loaders and booking communicate with real API',async t=>{
  const {page,navigations,api}=await setup(t);await api.login();
  for(const name of ['home','services','players','announcements','profile','orders']){
    const p=page(name);await p.load();assert.equal(p.data.error,'',`${name}: ${p.data.error}`);assert.equal(p.data.loading,false);
  }
  const booking=page('booking');booking.serviceId='s1';booking.playerId='p1';await booking.load();
  const tomorrow=new Date(Date.now()+86400000);booking.setData({date:tomorrow.toISOString().slice(0,10),time:'14:00',contact:'wx-test-fixture',note:'not real',playerIndex:0});
  await booking.submit();assert.equal(booking.data.submitError,'');assert.ok(navigations.at(-1).startsWith('/pages/order/order?id='));
  const id=navigations.at(-1).split('id=')[1].split('&')[0];
  const detail=page('order');detail.id=id;await detail.load();assert.equal(detail.data.order.serviceId,'s1');assert.equal(detail.data.order.priceCents,3900);assert.equal(detail.data.order.paymentStatus,'unpaid');
  const orders=page('orders');await orders.load();assert.equal(orders.data.orders.length,1);
  const services=page('services');await services.load();services.search({detail:{value:'不存在的游戏'}});assert.equal(services.data.services.length,0);
});

test('member pages complete real assignment, delivery, customer confirmation and income flow',async t=>{
  const {page,storage,call,api}=await setup(t);await api.login();
  const profile=page('profile');await profile.load();
  const token=storage.get('openni-session').token;
  const created=await call('/orders','POST',{serviceId:'s1',scheduledAt:new Date(Date.now()+5*60000).toISOString(),contact:'flow-fixture',idempotencyKey:'mini-full-flow-001'},token);
  assert.equal(created.status,201);
  assert.equal((await call('/admin/orders/'+created.data.id+'/assign','POST',{playerId:'p1'})).status,200);
  await profile.switchRole({currentTarget:{dataset:{role:'member',id:'p1'}}});
  const member=page('member');await member.load();assert.equal(member.data.pending,1);assert.equal(member.data.orders.length,1);
  const detail=page('order');detail.id=created.data.id;detail.setData({memberView:true});await detail.load();
  await detail.perform('accept');assert.equal(detail.data.order.fulfillmentStatus,'scheduled');
  await detail.perform('start');assert.equal(detail.data.order.fulfillmentStatus,'in_progress');
  detail.setData({action:'submit',actionText:'Completed agreed session',evidenceUrl:''});await detail.submitAction();
  assert.equal(detail.data.order.fulfillmentStatus,'awaiting_confirmation');
  const earnings=page('earnings');await earnings.load();assert.equal(earnings.data.totals.held,'31.20');
  const availability=page('availability');await availability.load();assert.ok(availability.data.slots.length>0);
  const notifications=page('notifications');await notifications.load();assert.ok(notifications.data.notifications.length>0);
  await profile.switchRole({currentTarget:{dataset:{role:'customer'}}});
  detail.setData({memberView:false,action:'confirm',actionText:'Verified',rating:5});await detail.submitAction();
  assert.equal(detail.data.order.fulfillmentStatus,'completed');
  await profile.switchRole({currentTarget:{dataset:{role:'member',id:'p1'}}});await earnings.load();
  assert.equal(earnings.data.totals.available,'31.20');assert.equal(earnings.data.entries.length,1);
});

test('browsing is public and protected screens require an explicit login',async t=>{
  const {page,storage,navigations,api}=await setup(t);
  const home=page('home');await home.load();assert.equal(home.data.error,'');assert.equal(home.data.signedIn,false);assert.equal(storage.has('openni-session'),false);
  const orders=page('orders');await orders.load();assert.equal(orders.data.authRequired,true);assert.equal(storage.has('openni-session'),false);
  const booking=page('booking');booking.serviceId='s1';booking.playerId='';booking.variantId='v1';booking.setData({contact:'preserved-contact',note:'preserved-note'});await booking.submit();
  assert.match(navigations.at(-1),/^\/pages\/login\/login\?returnTo=/);assert.equal(booking.data.contact,'preserved-contact');assert.equal(booking.data.note,'preserved-note');
  assert.equal(api.safeReturnUrl('https://other.test'),'/pages/profile/profile');assert.equal(api.safeReturnUrl('%2Fpages%2Fbooking%2Fbooking%3FserviceId%3Ds1'),'/pages/booking/booking?serviceId=s1');assert.equal(api.safeReturnUrl('/pages/booking/booking?serviceId=s1'),'/pages/booking/booking?serviceId=s1');
});

test('phone code flow uses the live API, keeps wrong-code state, and returns to the intended page',async t=>{
  const {page,storage,navigations}=await setup(t,'demo',{sms:true});
  const login=page('login');t.after(()=>login.stopTimer());login.returnTo='/pages/booking/booking?serviceId=s1';await login.load();
  assert.equal(login.data.capabilities.sms.enabled,true);login.phoneEntry();login.setData({phone:'13800138000'});await login.sendCode();assert.ok(login.data.formError.includes('协议'));assert.equal(login.data.challengeId,'');
  login.setData({agreed:true,phone:'123'});await login.sendCode();assert.ok(login.data.formError.includes('11 位'));
  login.setData({phone:'13800138000'});await login.sendCode();assert.equal(login.data.step,'code');assert.equal(login.data.delivery,'test');assert.match(login.data.testCode,/^\d{6}$/);assert.ok(login.data.remaining>0);const firstId=login.data.challengeId,code=login.data.testCode;
  await login.sendCode();assert.equal(login.data.challengeId,firstId);
  login.setData({code:code==='000000'?'111111':'000000'});await login.verify();assert.equal(storage.has('openni-session'),false);assert.equal(login.data.step,'code');assert.ok(login.data.formError);assert.equal(login.data.locked,false);
  login.setData({code});await login.verify();assert.ok(storage.get('openni-session').token);assert.equal(navigations.at(-1),'/pages/booking/booking?serviceId=s1');assert.equal(login.data.testCode,'');assert.equal(login.data.code,'');
});

test('unconfigured production SMS cannot create a session or claim a code was sent',async t=>{
  const {page,storage}=await setup(t,'production');const login=page('login');await login.load();assert.equal(login.data.capabilities.sms.enabled,false);login.setData({agreed:true,phone:'13800138000'});await login.sendCode();assert.match(login.data.formError,/尚未开通/);assert.equal(login.data.delivery,'');assert.equal(storage.has('openni-session'),false);
});

test('countdown survives background time and expired codes cannot be verified',async t=>{
  const {page,api}=await setup(t,'demo',{sms:true});const login=page('login');t.after(()=>login.stopTimer());await login.load();login.setData({agreed:true,phone:'13800138001'});await login.sendCode();
  login.stopTimer();login.retryAt=Date.now()-1000;login.expiresAt=Date.now()-1000;login.refreshCountdown();assert.equal(login.data.remaining,0);assert.equal(login.data.expired,true);
  let calls=0;const original=api.post;api.post=(...args)=>{calls++;return original(...args);};login.setData({code:login.data.testCode});await login.verify();assert.equal(calls,0);assert.match(login.data.formError,/过期/);
  const challengeId=login.data.challengeId;await login.sendCode();assert.equal(login.data.challengeId,challengeId);assert.equal(login.data.expired,true);assert.ok(login.data.remaining>0);assert.equal(calls,1);assert.ok(login.data.formError);
});

test('successful login returns to the existing page without replaying its mutation',async t=>{
  const {page,navigations}=await setup(t,'demo',{stack:[{route:'pages/booking/booking'},{route:'pages/login/login'}]});const login=page('login');login.returnTo='/pages/booking/booking?serviceId=s1';login.setData({agreed:true});await login.wechat();assert.deepEqual(navigations,['BACK']);
});

test('failed explicit WeChat linking preserves the order and never invokes payment',async t=>{
  const {page,api,getPaymentCalls}=await setup(t,'production');await api.login();const detail=page('order');detail.id='preserved-order';detail.setData({wechatLinkRequired:true,order:{id:'preserved-order',paymentStatus:'unpaid'}});
  let paymentRequests=0;api.linkWechat=async()=>{const e=new Error('此微信已关联其他账号');e.code='WECHAT_IDENTITY_IN_USE';throw e;};api.authorized=async()=>{paymentRequests++;throw new Error('must not reach payment');};await detail.linkAndPay();assert.equal(paymentRequests,0);assert.equal(getPaymentCalls(),0);assert.equal(detail.data.wechatLinkRequired,true);assert.equal(detail.data.order.id,'preserved-order');assert.equal(detail.data.order.paymentStatus,'unpaid');assert.match(detail.data.paymentMessage,/其他账号/);
});

test('phone paste normalizes +86 and mismatched server mode blocks login choices',async t=>{
  const {page,api}=await setup(t);const login=page('login');login.changePhone({detail:{value:' +8613800138000 '}});assert.equal(login.data.phone,'13800138000');api.get=async()=>({mode:'production',sms:{enabled:true,testMode:false}});await login.load();assert.ok(login.data.error);assert.equal(login.data.capabilities,null);
});

test('leaving verification does not navigate an unrelated page when the response arrives',async t=>{
  const {page,navigations}=await setup(t);const login=page('login');login.onUnload();login.finish();assert.deepEqual(navigations,[]);
});
