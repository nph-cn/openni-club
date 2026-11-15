const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const root=path.resolve(__dirname,'..');

async function setup(t,mode='demo'){
  const {createApp,readConfig}=await import('../../../services/api/src/app.mjs');
  const server=createApp({...readConfig({API_MODE:mode,CLUB_CONFIG_PATH:'none',ADMIN_TOKEN:'fixture-admin-token-1234567890',CORS_ORIGINS:'https://club.test'}),dataDir:':memory:',...(mode==='production'?{wechat:{appid:'wx-fixture',appSecret:'fixture-secret'},wechatPay:{appid:'wx-fixture'},integrations:{exchangeWechatCode:async()=>({openid:'fixture-openid'}),createJsapiOrder:async()=>({paymentParams:{timeStamp:'123',nonceStr:'nonce',package:'prepay_id=fixture',signType:'RSA',paySign:'fixture-sign'}})}}:{})});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>{server.closeAllConnections();server.close(resolve);}));
  const actualBase=`http://127.0.0.1:${server.address().port}/api/v1`,apiBaseUrl=mode==='production'?'https://club.test/api/v1':actualBase,storage=new Map(),cache=new Map(),navigations=[];
  if(mode==='production')await fetch(actualBase+'/admin/club',{method:'PATCH',headers:{'content-type':'application/json',authorization:'Bearer fixture-admin-token-1234567890'},body:JSON.stringify({demoData:false})});
  let paymentCalls=0;
  const wx={
    getStorageSync:k=>storage.get(k),setStorageSync:(k,v)=>storage.set(k,v),removeStorageSync:k=>storage.delete(k),
    request(o){fetch(o.url.replace(apiBaseUrl,actualBase),{method:o.method,headers:o.header,body:o.data===undefined?undefined:JSON.stringify(o.data)}).then(async r=>o.success({statusCode:r.status,data:await r.json()})).catch(o.fail);},
    login:o=>o.success({code:'fixture-code'}),requestPayment:o=>{paymentCalls++;o.success({errMsg:'requestPayment:ok'});},
    navigateTo:o=>navigations.push(o.url),redirectTo:o=>navigations.push(o.url),switchTab:o=>navigations.push(o.url),
    stopPullDownRefresh(){},showToast(){},showModal:o=>o.success({confirm:true})
  };
  let captured;
  function load(file){
    file=path.resolve(file.endsWith('.js')?file:file+'.js');
    if(file===path.join(root,'utils/config.js'))return {apiBaseUrl,mode};
    if(cache.has(file))return cache.get(file).exports;
    const module={exports:{}};cache.set(file,module);
    const context={module,exports:module.exports,require:p=>load(path.resolve(path.dirname(file),p)),wx,Page:p=>captured=p,App(){},Date,console,Promise,setTimeout};
    vm.runInNewContext(fs.readFileSync(file,'utf8'),context,{filename:file});return module.exports;
  }
  function page(name){const file=path.join(root,'pages',name,name+'.js');cache.delete(file);load(file);const p=captured;p.setData=function(update){Object.assign(this.data,update);};return p;}
  return {page,navigations,apiBaseUrl,storage,async call(route,method='GET',data,token='fixture-admin-token-1234567890'){const r=await fetch(actualBase+route,{method,headers:{'content-type':'application/json',authorization:'Bearer '+token},body:data===undefined?undefined:JSON.stringify(data)});return {status:r.status,data:await r.json()};},getPaymentCalls:()=>paymentCalls};
}

test('every registered native page and template exists, JSON parses, bindings are present',()=>{
  const app=JSON.parse(fs.readFileSync(path.join(root,'app.json'),'utf8'));
  assert.equal(app.pages.length,15);
  for(const p of app.pages){
    const script=fs.readFileSync(path.join(root,p+'.js'),'utf8');new vm.Script(script);
    const xml=fs.readFileSync(path.join(root,p+'.wxml'),'utf8');assert.equal(xml.includes('template is="demo"'),p==='pages/booking/booking');
    assert.ok(!xml.includes('<br'));JSON.parse(fs.readFileSync(path.join(root,p+'.json'),'utf8'));
  }
  for(const tab of app.tabBar.list)assert.ok(app.pages.includes(tab.pagePath));
});

test('production uses WeChat code exchange and never treats SDK success as paid',async t=>{
  const {page,navigations,storage,getPaymentCalls}=await setup(t,'production');
  const booking=page('booking');booking.serviceId='s1';booking.playerId='p1';await booking.load();
  const tomorrow=new Date(Date.now()+86400000);booking.setData({date:tomorrow.toISOString().slice(0,10),time:'14:00',contact:'fixture-only',note:'',playerIndex:0});
  await booking.submit();assert.equal(booking.data.submitError,'');assert.equal(storage.get('openni-session').mode,'production');
  const id=navigations.at(-1).split('id=')[1].split('&')[0],detail=page('order');detail.id=id;await detail.load();
  assert.equal(detail.data.order.demo,false);assert.equal(detail.data.order.canPay,true);
  await detail.pay();assert.equal(getPaymentCalls(),1);assert.equal(detail.data.order.paymentStatus,'pending');assert.equal(detail.data.order.canCancel,true);
  assert.ok(detail.data.paymentMessage.includes('服务器'));
});
test('native page loaders and booking communicate with real API',async t=>{
  const {page,navigations}=await setup(t);
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
  const {page,storage,call}=await setup(t);
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
