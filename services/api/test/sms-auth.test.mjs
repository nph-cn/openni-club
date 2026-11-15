import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {createApp,readConfig} from '../src/app.mjs';
import {smsClientIP} from '../src/sms-auth.mjs';
const admin='sms-test-admin-credential-123456789';
const production={API_MODE:'production',SMS_PROVIDER:'tencent',SMS_HASH_SECRET:'k'.repeat(43),TENCENT_SMS_SECRET_ID:'fixture-id',TENCENT_SMS_SECRET_KEY:'fixture-secret',TENCENT_SMS_SDK_APP_ID:'1400000000',TENCENT_SMS_SIGN_NAME:'测试签名',TENCENT_SMS_TEMPLATE_ID:'123456',TENCENT_SMS_REGION:'ap-guangzhou'};
async function setup(t,{env={},overrides={},ready=false}={}){
  let time=Date.now();const sent=[],dataDir=mkdtempSync(join(tmpdir(),'openni-sms-'));
  const integrations={sendTencentLoginCode:async args=>{sent.push(args);return {accepted:true};},exchangeWechatCode:async({code})=>({openid:'mini-'+code}),exchangeWechatAppCode:async({code})=>({openid:'app-'+code}),createAppOrder:async()=>({paymentParams:{prepayId:'fixture'}}),...overrides.integrations};
  let currentEnv={API_MODE:'demo',SMS_PROVIDER:'test',ADMIN_TOKEN:admin,CLUB_CONFIG_PATH:'none',CORS_ORIGINS:'https://club.example',...env};
  const configuration=()=>({...readConfig(currentEnv),dataDir,now:()=>time,...overrides,integrations});
  let cfg=configuration();
  let server=createApp(cfg);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(async()=>{await new Promise(resolve=>{server.closeAllConnections();server.close(resolve);});rmSync(dataDir,{recursive:true,force:true});});
  let base=`http://127.0.0.1:${server.address().port}/api/v1`;
  async function call(path,body,token,method=body===undefined?'GET':'POST',headers={}){const response=await fetch(base+path,{method,headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{}),...headers},body:body===undefined?undefined:JSON.stringify(body)});return {status:response.status,data:await response.json(),headers:response.headers};}
  if(ready)assert.equal((await call('/admin/club',{demoData:false,legalEntity:'测试运营方',supportContact:'测试客服',privacyText:'测试隐私完整说明',termsText:'测试服务完整约定'},admin,'PATCH')).status,200);
  const challenge=phone=>call('/auth/sms/challenges',{phone});
  const verify=(c,code=c.data.testCode)=>call('/auth/sms/verify',{challengeId:c.data.challengeId,code});
  async function restart({env={},beforeStart}={}){await new Promise(resolve=>{server.closeAllConnections();server.close(resolve);});if(beforeStart)beforeStart();currentEnv={...currentEnv,...env};cfg=configuration();server=createApp(cfg);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));base=`http://127.0.0.1:${server.address().port}/api/v1`;}
  return {call,challenge,verify,sent,dataDir,restart,advance:ms=>time+=ms,now:()=>time};
}
test('test capabilities and single-use verification create a customer; normalized phone reuses account',async t=>{
  const {call,challenge,verify,advance}=await setup(t);const cap=(await call('/auth/capabilities')).data;
  assert.equal(cap.sms.enabled,true);assert.equal(cap.sms.testMode,true);assert.equal(cap.wechatMini.enabled,false);
  const c=await challenge('13800138000');assert.equal(c.status,201);assert.match(c.data.testCode,/^\d{6}$/);assert.equal(c.data.delivery,'test');assert.equal(c.data.phoneMasked,'138****8000');
  const result=await call('/auth/sms/verify',{challengeId:c.data.challengeId,code:c.data.testCode,role:'owner',userId:'admin'});assert.equal(result.status,200);assert.equal(result.data.role,'customer');assert.equal(result.data.demo,true);
  assert.equal((await call('/me',undefined,result.data.token)).data.user.id,result.data.user.id);
  assert.equal((await verify(c)).data.error.code,'OTP_USED');advance(60001);const newer=await challenge('+8613800138000');assert.equal((await verify(newer)).data.user.id,result.data.user.id);
});
test('resend cooldown and superseded codes are explicit with authoritative retry headers',async t=>{
  const {challenge,verify,advance}=await setup(t),first=await challenge('13800138000');
  const early=await challenge('+8613800138000');assert.equal(early.status,429);assert.equal(early.data.error.code,'SMS_COOLDOWN');assert.equal(early.data.error.retryAfterSeconds,60);assert.equal(early.headers.get('retry-after'),'60');
  advance(60001);const second=await challenge('13800138000');assert.equal(second.status,201);assert.equal((await verify(first)).data.error.code,'OTP_SUPERSEDED');assert.equal((await verify(second)).status,200);
});
test('wrong and malformed code attempts persist, lock after five, and expired codes never authenticate',async t=>{
  const {challenge,verify,advance}=await setup(t),c=await challenge('13800138000'),wrong=c.data.testCode==='000000'?'000001':'000000';
  let r=await verify(c,'x');assert.equal(r.data.error.code,'OTP_FORMAT_INVALID');assert.equal(r.data.error.attemptsRemaining,4);
  for(let n=3;n>=1;n--){r=await verify(c,wrong);assert.equal(r.data.error.attemptsRemaining,n);assert.equal(r.status,401);}
  assert.equal((await verify(c,wrong)).data.error.code,'OTP_ATTEMPTS_EXCEEDED');assert.equal((await verify(c)).data.error.attemptsRemaining,0);
  advance(300001);assert.equal((await verify(c)).data.error.code,'OTP_EXPIRED');
  const newer=await challenge('13800138000');advance(300001);assert.equal((await verify(newer)).status,410);
});
test('phone/hour and IP/hour limits persist independently of changing challenges',async t=>{
  const a=await setup(t);for(let n=0;n<5;n++){assert.equal((await a.challenge('13800138000')).status,201);a.advance(60001);}let r=await a.challenge('13800138000');assert.equal(r.data.error.code,'SMS_RATE_LIMIT');assert.ok(r.data.error.retryAfterSeconds>3000);
  const b=await setup(t);for(let n=0;n<20;n++)assert.equal((await b.challenge('1390013'+String(n).padStart(4,'0'))).status,201);r=await b.challenge('13900139999');assert.equal(r.data.error.code,'SMS_RATE_LIMIT');
});
test('verify IP limit counts unknown challenges; spoofed forwarding is ignored unless trusted',async t=>{
  const {call}=await setup(t);for(let n=0;n<60;n++)assert.equal((await call('/auth/sms/verify',{challengeId:'unknown',code:'111111'},null,'POST',{'x-forwarded-for':'1.2.3.'+n})).status,401);
  assert.equal((await call('/auth/sms/verify',{challengeId:'unknown',code:'111111'})).status,429);
  const req={socket:{remoteAddress:'::ffff:127.0.0.1'},headers:{'x-forwarded-for':'1.1.1.1, 10.0.0.2'}};assert.equal(smsClientIP(req,[]),'127.0.0.1');assert.equal(smsClientIP(req,['127.0.0.1']),'10.0.0.2');assert.equal(smsClientIP(req,['127.0.0.1','10.0.0.2']),'1.1.1.1');
});
test('concurrent challenge sends reserve cooldown before provider I/O and verification consumes once',async t=>{
  let release;const waiting=new Promise(resolve=>release=resolve);let sends=0;
  const f=await setup(t,{env:production,ready:true,overrides:{integrations:{sendTencentLoginCode:async args=>{f.sent.push(args);sends++;await waiting;return {accepted:true};}}}});
  const first=f.challenge('13800138000');await new Promise(resolve=>setTimeout(resolve,20));const second=await f.challenge('13800138000');assert.equal(second.status,429);release();const c=await first;assert.equal(c.status,201);assert.equal(sends,1);
  const results=await Promise.all([f.verify(c,f.sent[0].code),f.verify(c,f.sent[0].code)]);assert.deepEqual(results.map(r=>r.status).sort(),[200,410]);
});
test('production missing config fails closed, test provider is forbidden, and provider errors never expose data',async t=>{
  const base={...production,ADMIN_TOKEN:admin,CORS_ORIGINS:'https://club.example'};
  assert.throws(()=>readConfig({...base,SMS_PROVIDER:'test'}),/forbidden/);assert.throws(()=>readConfig({...base,SMS_HASH_SECRET:''}),/SMS_HASH_SECRET/);
  const disabled=await setup(t,{env:{API_MODE:'production',SMS_PROVIDER:'disabled'}});assert.equal((await disabled.call('/auth/capabilities')).data.sms.enabled,false);assert.equal((await disabled.challenge('13800138000')).data.error.code,'SMS_NOT_CONFIGURED');
  const notReady=await setup(t,{env:production});assert.equal((await notReady.challenge('13800138000')).data.error.code,'CLUB_NOT_READY');assert.equal(notReady.sent.length,0);
  const failed=await setup(t,{env:production,ready:true,overrides:{integrations:{sendTencentLoginCode:async()=>{throw Error('sensitive-provider-phone-and-secret');}}}});const result=await failed.challenge('13800138000');assert.equal(result.status,502);assert.equal(result.data.error.code,'SMS_DELIVERY_FAILED');assert.equal(JSON.stringify(result).includes('sensitive'),false);assert.equal((await failed.challenge('13800138000')).status,429);
});
test('real-provider mode never returns OTP, stores only keyed hashes, and deleting account revokes phone and sessions',async t=>{
  const f=await setup(t,{env:production,ready:true});const c=await f.challenge('13800138000');assert.equal(c.data.testCode,undefined);assert.equal(c.data.delivery,'accepted');assert.equal(f.sent.length,1);
  const db=new DatabaseSync(join(f.dataDir,'openni.sqlite'));const row=db.prepare('SELECT * FROM sms_challenges').get();assert.notEqual(row.code_hash,f.sent[0].code);assert.equal(JSON.stringify(row).includes('13800138000'),false);db.close();
  const logged=await f.verify(c,f.sent[0].code);assert.equal(logged.status,200);assert.equal(logged.data.demo,false);assert.equal((await f.call('/account',undefined,logged.data.token,'DELETE')).status,200);assert.equal((await f.call('/me',undefined,logged.data.token)).status,401);
  f.advance(60001);const again=await f.challenge('13800138000'),newUser=await f.verify(again,f.sent.at(-1).code);assert.notEqual(newUser.data.user.id,logged.data.user.id);
});
test('provider failure preserves previous challenge and does not pretend delivery succeeded',async t=>{
  let fail=false;const sent=[];const f=await setup(t,{env:production,ready:true,overrides:{integrations:{sendTencentLoginCode:async args=>{sent.push(args);if(fail)throw Error('failed');return {accepted:true};}}}});
  const first=await f.challenge('13800138000');f.advance(60001);fail=true;assert.equal((await f.challenge('13800138000')).status,502);assert.equal((await f.verify(first,sent[0].code)).status,200);
});
test('explicit WeChat link keeps SMS account and role, rejects collisions and enables same-order APP payment',async t=>{
  const f=await setup(t,{env:production,ready:true,overrides:{wechat:{appid:'wx-mini',appSecret:'secret'},wechatNative:{appid:'wx-app',appSecret:'secret'},wechatPay:{appid:'wx-mini'},wechatAppPay:{appid:'wx-app'}}});
  const c=await f.challenge('13800138000'),user=await f.verify(c,f.sent[0].code),token=user.data.token;
  const booked=await f.call('/orders',{serviceId:'s1',scheduledAt:new Date(Date.now()+3600000).toISOString(),contact:'fixture-only',idempotencyKey:'sms-to-app'},token);assert.equal(booked.status,201);
  assert.equal((await f.call('/orders/'+booked.data.id+'/pay',{},token)).data.error.code,'WECHAT_LINK_REQUIRED');
  const linked=await f.call('/auth/wechat-app/link',{code:'owned',role:'owner'},token);assert.equal(linked.status,200);assert.equal(linked.data.user.id,user.data.user.id);assert.equal(linked.data.role,'customer');
  assert.equal((await f.call('/orders/'+booked.data.id+'/pay',{},linked.data.token)).status,200);
  const mini=await f.call('/auth/wechat/link',{code:'owned-mini'},token);assert.equal(mini.status,200);assert.equal(mini.data.user.id,user.data.user.id);
  assert.equal((await f.call('/orders/'+booked.data.id+'/pay',{},mini.data.token)).data.error.code,'PAYMENT_APP_MISMATCH');
  assert.equal((await f.call('/auth/wechat-app/link',{code:'other'},token)).data.error.code,'WECHAT_ACCOUNT_ALREADY_LINKED');
  const other=(await f.call('/auth/wechat-app',{code:'other-account'})).data;
  assert.equal((await f.call('/auth/wechat-app/link',{code:'owned'},other.token)).data.error.code,'WECHAT_IDENTITY_IN_USE');
  assert.equal((await f.call('/auth/wechat-app',{code:'owned'})).data.user.id,user.data.user.id);
  assert.equal((await f.call('/auth/wechat-app/link',{code:'owned'},token)).status,200);
});
test('concurrent identity links have one owner, and deletion removes all application identities',async t=>{
  const f=await setup(t,{env:production,ready:true,overrides:{wechat:{appid:'wx-mini',appSecret:'secret'},wechatNative:{appid:'wx-app',appSecret:'secret'}}});
  const users=[];for(const phone of ['13800138000','13900139000']){const c=await f.challenge(phone);users.push((await f.verify(c,f.sent.at(-1).code)).data);}
  const links=await Promise.all(users.map(u=>f.call('/auth/wechat/link',{code:'shared'},u.token)));assert.deepEqual(links.map(r=>r.status).sort(),[200,409]);
  const i=links.findIndex(r=>r.status===200),owner=users[i];assert.equal((await f.call('/auth/wechat-app/link',{code:'native-owned'},owner.token)).status,200);
  assert.equal((await f.call('/account',undefined,owner.token,'DELETE')).status,200);assert.equal((await f.call('/me',undefined,links[i].data.token)).status,401);
  const newMini=(await f.call('/auth/wechat',{code:'shared'})).data,newApp=(await f.call('/auth/wechat-app',{code:'native-owned'})).data;assert.notEqual(newMini.user.id,owner.user.id);assert.notEqual(newApp.user.id,owner.user.id);
});

test('provider response order cannot revive an older code, and newer failed sends preserve older pending code',async t=>{
  for(const newerFails of [false,true]){
    let release,entered;const waiting=new Promise(resolve=>release=resolve),started=new Promise(resolve=>entered=resolve),sent=[];
    const f=await setup(t,{env:production,ready:true,overrides:{integrations:{sendTencentLoginCode:async args=>{sent.push(args);if(sent.length===1){entered();await waiting;}else if(newerFails)throw Error('rejected');return {accepted:true};}}}});
    const first=f.challenge('13800138000');await started;f.advance(60001);
    const newer=await f.challenge('13800138000');release();const older=await first;
    if(newerFails){assert.equal(newer.status,502);assert.equal(older.status,201);assert.equal((await f.verify(older,sent[0].code)).status,200);}
    else{assert.equal(older.data.error.code,'OTP_SUPERSEDED');assert.equal((await f.verify(newer,sent[1].code)).status,200);}
  }
});
test('an earlier accepted response leaves a newer pending send intact',async t=>{
  let releaseFirst,releaseSecond,enterFirst,enterSecond;const firstWait=new Promise(r=>releaseFirst=r),secondWait=new Promise(r=>releaseSecond=r),firstStarted=new Promise(r=>enterFirst=r),secondStarted=new Promise(r=>enterSecond=r),sent=[];
  const f=await setup(t,{env:production,ready:true,overrides:{integrations:{sendTencentLoginCode:async args=>{sent.push(args);if(sent.length===1){enterFirst();await firstWait;}else{enterSecond();await secondWait;}return {accepted:true};}}}});
  const first=f.challenge('13800138000');await firstStarted;f.advance(60001);const second=f.challenge('13800138000');await secondStarted;releaseFirst();const older=await first;assert.equal(older.status,201);releaseSecond();const newer=await second;assert.equal(newer.status,201);assert.equal((await f.verify(older,sent[0].code)).data.error.code,'OTP_SUPERSEDED');assert.equal((await f.verify(newer,sent[1].code)).status,200);
});
test('restart preserves cooldown, attempts, identity and the unbound payment channel of SMS orders',async t=>{
  const f=await setup(t,{env:production,ready:true,overrides:{wechatNative:{appid:'wx-app',appSecret:'secret'}}});
  const c=await f.challenge('13800138000');await f.restart();assert.equal((await f.challenge('13800138000')).data.error.code,'SMS_COOLDOWN');
  const wrong=f.sent[0].code==='000000'?'000001':'000000';assert.equal((await f.verify(c,wrong)).data.error.attemptsRemaining,4);await f.restart();assert.equal((await f.verify(c,wrong)).data.error.attemptsRemaining,3);
  const user=(await f.verify(c,f.sent[0].code)).data;await f.call('/auth/wechat-app/link',{code:'persist'},user.token);
  const order=await f.call('/orders',{serviceId:'s1',scheduledAt:new Date(Date.now()+3600000).toISOString(),contact:'fixture',idempotencyKey:'restart-unbound'},user.token);assert.equal(order.status,201);await f.restart();
  const db=new DatabaseSync(join(f.dataDir,'openni.sqlite'));assert.equal(db.prepare('SELECT payment_appid FROM orders WHERE id=?').get(order.data.id).payment_appid,null);db.close();
  f.advance(60001);const next=await f.challenge('13800138000');assert.equal((await f.verify(next,f.sent.at(-1).code)).data.user.id,user.user.id);
});
test('daily phone and IP budgets do not reset when hourly windows expire',async t=>{
  const f=await setup(t);for(let round=0;round<2;round++){for(let n=0;n<5;n++){assert.equal((await f.challenge('13800138000')).status,201);f.advance(60001);}f.advance(3600001);}
  const blocked=await f.challenge('13800138000');assert.equal(blocked.data.error.code,'SMS_RATE_LIMIT');assert.ok(blocked.data.error.retryAfterSeconds>50000);
  const g=await setup(t);for(let round=0;round<5;round++){for(let n=0;n<20;n++)assert.equal((await g.challenge('139'+String(round*20+n).padStart(8,'0'))).status,201);g.advance(3600001);}
  assert.equal((await g.challenge('13999999999')).data.error.code,'SMS_RATE_LIMIT');g.advance(86400001);assert.equal((await g.challenge('13999999999')).status,201);
});
test('deletion while WeChat provider responds prevents linking and issuing a replacement session',async t=>{
  let release,enter;const waiting=new Promise(r=>release=r),started=new Promise(r=>enter=r);
  const f=await setup(t,{env:production,ready:true,overrides:{wechat:{appid:'wx-mini',appSecret:'secret'},integrations:{exchangeWechatCode:async()=>{enter();await waiting;return {openid:'delayed'};}}}});
  const c=await f.challenge('13800138000'),user=(await f.verify(c,f.sent[0].code)).data;
  const linking=f.call('/auth/wechat/link',{code:'delayed'},user.token);await started;assert.equal((await f.call('/account',undefined,user.token,'DELETE')).status,200);release();assert.equal((await linking).status,401);
  const db=new DatabaseSync(join(f.dataDir,'openni.sqlite'));assert.equal(db.prepare('SELECT count(*) n FROM wechat_identities').get().n,0);assert.equal(db.prepare('SELECT count(*) n FROM sessions').get().n,0);db.close();
});
test('only owner invitations grant membership and repeat SMS login retains that exact role',async t=>{
  const f=await setup(t,{env:production,ready:true});const c=await f.challenge('13800138000'),user=(await f.verify(c,f.sent[0].code)).data;
  assert.equal(user.role,'customer');assert.equal((await f.call('/auth/demo',{role:'member',playerId:'p1'})).status,403);
  const invitation=await f.call('/admin/players/p1/invitation',{},admin);assert.equal(invitation.status,201);
  const accepted=await f.call('/member/invitation/accept',{code:invitation.data.code},user.token);assert.equal(accepted.data.role,'member');assert.equal(accepted.data.playerId,'p1');
  assert.equal((await f.call('/admin/players/p1/invitation',{},admin)).data.error.code,'MEMBER_ALREADY_BOUND');
  f.advance(60001);const next=await f.challenge('13800138000'),again=(await f.verify(next,f.sent.at(-1).code)).data;assert.equal(again.user.id,user.user.id);assert.equal(again.role,'member');assert.equal(again.playerId,'p1');
});

test('restarting with production never promotes test codes, accounts or self-selected member roles',async t=>{
  const f=await setup(t,{env:{SMS_HASH_SECRET:production.SMS_HASH_SECRET},ready:true});
  const first=await f.challenge('13800138000'),demo=(await f.verify(first)).data;
  assert.equal((await f.call('/auth/demo/role',{role:'member',playerId:'p1'},demo.token)).status,200);
  f.advance(60001);const testCode=await f.challenge('13800138000');
  await f.restart({env:production});
  assert.equal((await f.verify(testCode)).data.error.code,'OTP_INVALID');
  assert.equal((await f.call('/me',undefined,demo.token)).status,401);
  // A test send neither reserves production cooldown nor supersedes its challenge.
  const realCode=await f.challenge('13800138000');assert.equal(realCode.status,201);
  const real=(await f.verify(realCode,f.sent.at(-1).code)).data;
  assert.notEqual(real.user.id,demo.user.id);assert.equal(real.role,'customer');assert.equal(real.playerId,null);
  const invitation=await f.call('/admin/players/p1/invitation',{},admin);assert.equal(invitation.status,201);
  assert.equal((await f.call('/member/invitation/accept',{code:invitation.data.code},real.token)).data.role,'member');
  const pending=await f.challenge('13900139000'),pendingCode=f.sent.at(-1).code;
  await f.restart({env:{API_MODE:'demo',SMS_PROVIDER:'test'}});
  assert.equal((await f.verify(pending,pendingCode)).data.error.code,'OTP_INVALID');
  assert.equal((await f.verify(testCode)).data.user.id,demo.user.id);
  await f.restart({env:production});
  assert.equal((await f.verify(pending,pendingCode)).status,200);
  assert.equal((await f.call('/me',undefined,real.token)).data.user.id,real.user.id);
});

test('default-key demo phone members do not occupy production invitations after configuring a real key',async t=>{
  const f=await setup(t,{ready:true}),code=await f.challenge('13800138000'),demo=(await f.verify(code)).data;
  assert.equal((await f.call('/auth/demo/role',{role:'member',playerId:'p1'},demo.token)).status,200);
  await f.restart({env:production});
  const invitation=await f.call('/admin/players/p1/invitation',{},admin);assert.equal(invitation.status,201);
  const realCode=await f.challenge('13800138000'),real=(await f.verify(realCode,f.sent.at(-1).code)).data;
  assert.notEqual(real.user.id,demo.user.id);assert.equal(real.role,'customer');
  assert.equal((await f.call('/member/invitation/accept',{code:invitation.data.code},real.token)).status,200);
  assert.equal((await f.call('/admin/players/p1/invitation',{},admin)).data.error.code,'MEMBER_ALREADY_BOUND');
});

test('send budgets, resend supersession and account deletion stay within their persisted verification source',async t=>{
  const f=await setup(t,{env:{SMS_HASH_SECRET:production.SMS_HASH_SECRET},ready:true});
  let demoCode;for(let n=0;n<5;n++){demoCode=await f.challenge('13800138000');assert.equal(demoCode.status,201);f.advance(60001);}
  assert.equal((await f.challenge('13800138000')).data.error.code,'SMS_RATE_LIMIT');
  await f.restart({env:production});
  const realCode=await f.challenge('13800138000'),code=f.sent.at(-1).code;assert.equal(realCode.status,201);
  await f.restart({env:{API_MODE:'demo',SMS_PROVIDER:'test'}});
  const demo=(await f.verify(demoCode)).data;assert.ok(demo.token);
  assert.equal((await f.call('/account',undefined,demo.token,'DELETE')).status,200);
  await f.restart({env:production});
  assert.equal((await f.verify(realCode,code)).status,200);
});

test('an actual old-schema database reopens fail-closed without losing or forking its retained account and order',async t=>{
  const f=await setup(t,{env:production,ready:true});
  const first=await f.challenge('13800138000'),user=(await f.verify(first,f.sent.at(-1).code)).data;
  const booked=await f.call('/orders',{serviceId:'s1',scheduledAt:new Date(Date.now()+3600000).toISOString(),contact:'migration fixture',idempotencyKey:'legacy-retained'},user.token);assert.equal(booked.status,201);
  f.advance(60001);const oldCode=await f.challenge('13800138000'),oldValue=f.sent.at(-1).code;
  await f.restart({beforeStart:()=>{
    const db=new DatabaseSync(join(f.dataDir,'openni.sqlite'));
    db.exec(`BEGIN IMMEDIATE;
      ALTER TABLE phone_identities RENAME TO phone_identities_new;
      CREATE TABLE phone_identities(phone_key TEXT PRIMARY KEY,user_id TEXT UNIQUE NOT NULL REFERENCES users(id));
      INSERT INTO phone_identities SELECT phone_key,user_id FROM phone_identities_new;
      DROP TABLE phone_identities_new;
      ALTER TABLE sms_challenges DROP COLUMN verification_source;
      ALTER TABLE sms_send_events DROP COLUMN verification_source;
      UPDATE users SET role='member',player_id='p1';
      COMMIT;`);db.close();
  }});
  assert.equal((await f.call('/me',undefined,user.token)).status,401);
  assert.equal((await f.verify(oldCode,oldValue)).data.error.code,'OTP_INVALID');
  assert.equal((await f.call('/admin/players/p1/invitation',{},admin)).status,201);
  f.advance(60001);const fresh=await f.challenge('13800138000'),blocked=await f.verify(fresh,f.sent.at(-1).code);
  assert.equal(blocked.status,409);assert.equal(blocked.data.error.code,'SMS_IDENTITY_REVIEW_REQUIRED');
  assert.equal(blocked.data.error.message,'此手机号需要联系客服核实后登录。');
  await f.restart();
  const db=new DatabaseSync(join(f.dataDir,'openni.sqlite'));
  assert.equal(db.prepare('SELECT verification_source FROM phone_identities WHERE user_id=?').get(user.user.id).verification_source,'legacy');
  assert.equal(db.prepare('SELECT code_hash FROM sms_challenges WHERE id=?').get(oldCode.data.challengeId).code_hash,null);
  assert.equal(db.prepare('SELECT user_id FROM orders WHERE id=?').get(booked.data.id).user_id,user.user.id);
  assert.equal(db.prepare('SELECT count(*) n FROM users').get().n,1);
  assert.equal(db.prepare('SELECT count(*) n FROM sessions').get().n,0);db.close();
});
