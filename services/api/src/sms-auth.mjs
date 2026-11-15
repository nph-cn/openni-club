import {createHmac,randomBytes,randomInt,randomUUID,timingSafeEqual} from 'node:crypto';
import {isIP} from 'node:net';
import {sendTencentLoginCode} from '../../integrations/src/tencent-sms.mjs';
const LIFE=300000,COOLDOWN=60000,ATTEMPTS=5;
const error=(status,code,message,details={})=>Object.assign(new Error(message),{status,code,details});
const normalizeIP=value=>String(value||'').replace(/^::ffff:/,'');
export function readSmsConfig(env,mode){
  const provider=env.SMS_PROVIDER||'disabled';
  if(!['disabled','test','tencent'].includes(provider))throw Error('SMS_PROVIDER must be disabled, test or tencent');
  if(provider==='test'&&mode!=='demo')throw Error('SMS_PROVIDER=test is forbidden in production');
  if(provider==='tencent'&&mode!=='production')throw Error('Real SMS requires API_MODE=production');
  const hashSecret=env.SMS_HASH_SECRET||(provider==='test'?'openni-demo-only-sms-key-never-use-in-production':'');
  if(provider==='tencent'&&!/^[A-Za-z0-9_-]{43,128}$/.test(hashSecret))throw Error('SMS_HASH_SECRET requires at least 43 base64url characters');
  const trustedProxies=(env.SMS_TRUSTED_PROXY_IPS||'').split(',').filter(Boolean).map(value=>normalizeIP(value.trim()));
  if(trustedProxies.some(ip=>!isIP(ip)))throw Error('SMS_TRUSTED_PROXY_IPS must list exact proxy IPs; no wildcard or CIDR');
  const keys={secretId:'TENCENT_SMS_SECRET_ID',secretKey:'TENCENT_SMS_SECRET_KEY',sdkAppId:'TENCENT_SMS_SDK_APP_ID',signName:'TENCENT_SMS_SIGN_NAME',templateId:'TENCENT_SMS_TEMPLATE_ID',region:'TENCENT_SMS_REGION'};
  const tencent={};for(const [key,envKey]of Object.entries(keys)){tencent[key]=env[envKey]||'';if(provider==='tencent'&&(!tencent[key].trim()||tencent[key].length>512||/[\r\n\0]/.test(tencent[key])))throw Error(`Missing or invalid SMS configuration: ${envKey}`);}
  if(env.TENCENT_SMS_TEMPLATE_HAS_MINUTES&&!['true','false'].includes(env.TENCENT_SMS_TEMPLATE_HAS_MINUTES))throw Error('TENCENT_SMS_TEMPLATE_HAS_MINUTES must be true or false');
  tencent.templateHasMinutes=env.TENCENT_SMS_TEMPLATE_HAS_MINUTES==='true';
  return {provider,hashSecret,trustedProxies,tencent};
}
export function smsClientIP(req,trusted=[]){
  const remote=normalizeIP(req.socket.remoteAddress);
  if(!trusted.includes(remote))return remote;
  const chain=String(req.headers['x-forwarded-for']||'').split(',').map(v=>normalizeIP(v.trim()));
  if(!chain.length||chain.length>16||chain.some(ip=>!isIP(ip)))return remote;
  // Walk from the socket side, trusting only explicitly configured hops.
  for(let i=chain.length-1;i>=0;i--)if(!trusted.includes(chain[i]))return chain[i];
  return remote;
}
export function createSmsAuth({db,config,clubReady,issueSession,now=Date.now,sendCode=sendTencentLoginCode}){
  const sms=config.sms||{provider:'disabled',trustedProxies:[]},key=sms.hashSecret||randomBytes(32).toString('base64url');
  const phoneSchema=`CREATE TABLE phone_identities(phone_key TEXT NOT NULL,user_id TEXT UNIQUE NOT NULL REFERENCES users(id),verification_source TEXT NOT NULL DEFAULT 'legacy' CHECK(verification_source IN ('test','tencent','legacy')),PRIMARY KEY(verification_source,phone_key))`;
  db.exec(`${phoneSchema.replace('CREATE TABLE','CREATE TABLE IF NOT EXISTS')};
    CREATE TABLE IF NOT EXISTS sms_challenges(id TEXT PRIMARY KEY,phone_key TEXT NOT NULL,code_hash TEXT,created_at INTEGER NOT NULL,expires_at INTEGER NOT NULL,status TEXT NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,verification_source TEXT NOT NULL DEFAULT 'legacy');
    CREATE INDEX IF NOT EXISTS sms_phone ON sms_challenges(phone_key,created_at);
    CREATE TABLE IF NOT EXISTS sms_send_events(id TEXT PRIMARY KEY,phone_key TEXT NOT NULL,ip_key TEXT NOT NULL,created_at INTEGER NOT NULL,verification_source TEXT NOT NULL DEFAULT 'legacy');
    CREATE INDEX IF NOT EXISTS sms_send_phone ON sms_send_events(phone_key,created_at);
    CREATE INDEX IF NOT EXISTS sms_send_ip ON sms_send_events(ip_key,created_at);
    CREATE TABLE IF NOT EXISTS sms_verify_events(id TEXT PRIMARY KEY,ip_key TEXT NOT NULL,created_at INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS sms_verify_ip ON sms_verify_events(ip_key,created_at);`);
  // Older records cannot prove whether their phone was verified by Tencent or the
  // public test-code endpoint. Retain their accounts/orders, but never promote them.
  transaction(()=>{
    if(!db.prepare('PRAGMA table_info(phone_identities)').all().some(column=>column.name==='verification_source')){
      db.exec(`ALTER TABLE phone_identities RENAME TO phone_identities_legacy;
        ${phoneSchema};
        INSERT INTO phone_identities(phone_key,user_id,verification_source) SELECT phone_key,user_id,'legacy' FROM phone_identities_legacy;
        DELETE FROM sessions WHERE user_id IN (SELECT user_id FROM phone_identities_legacy);
        DROP TABLE phone_identities_legacy;`);
    }
    for(const table of ['sms_challenges','sms_send_events'])if(!db.prepare(`PRAGMA table_info(${table})`).all().some(column=>column.name==='verification_source'))db.exec(`ALTER TABLE ${table} ADD COLUMN verification_source TEXT NOT NULL DEFAULT 'legacy'`);
    db.exec("UPDATE sms_challenges SET status='failed',code_hash=NULL WHERE verification_source='legacy' AND status IN ('pending','active')");
  });
  const digest=(purpose,value)=>createHmac('sha256',key).update(purpose+'\0'+value).digest('hex');
  const retry=until=>Math.max(1,Math.ceil((until-now())/1000));
  const available=()=>sms.provider==='test'?config.mode==='demo':sms.provider==='tencent'&&config.mode==='production';
  function capability(){const enabled=available()&&(config.mode==='demo'||clubReady());return {enabled,provider:sms.provider,testMode:sms.provider==='test',codeLength:6,expiresInSeconds:300,retryAfterSeconds:60,reasonCode:!available()?'SMS_NOT_CONFIGURED':!enabled?'CLUB_NOT_READY':null};}
  function assertEnabled(){const state=capability();if(!state.enabled)throw error(state.reasonCode==='CLUB_NOT_READY'?409:503,state.reasonCode,state.reasonCode==='CLUB_NOT_READY'?'俱乐部尚未完成经营与隐私资料。':'短信登录尚未配置，请使用其他登录方式。');}
  function cleanup(){const before=now()-86400000;db.prepare('DELETE FROM sms_send_events WHERE created_at<=?').run(before);db.prepare('DELETE FROM sms_verify_events WHERE created_at<=?').run(now()-600000);db.prepare('DELETE FROM sms_challenges WHERE expires_at<?').run(before);}
  function transaction(fn){db.exec('BEGIN IMMEDIATE');try{const value=fn();db.exec('COMMIT');return value;}catch(e){db.exec('ROLLBACK');throw e;}}
  function limit(table,column,value,window,max){const cutoff=now()-window,scoped=table==='sms_send_events',rows=db.prepare(`SELECT created_at FROM ${table} WHERE ${column}=? AND created_at>? ${scoped?'AND verification_source=?':''} ORDER BY created_at`).all(value,cutoff,...(scoped?[sms.provider]:[]));if(rows.length>=max)throw error(429,'SMS_RATE_LIMIT','操作过于频繁，请稍后重试。',{retryAfterSeconds:retry(rows[rows.length-max].created_at+window)});}
  function phoneValue(value){if(typeof value!=='string')throw error(400,'PHONE_INVALID','请输入有效的中国大陆手机号。');const phone=value.trim().replace(/^\+86/,'');if(!/^1[3-9]\d{9}$/.test(phone))throw error(400,'PHONE_INVALID','请输入有效的中国大陆手机号。');return '+86'+phone;}
  async function challenge(req,data){
    assertEnabled();const phone=phoneValue(data.phone),phoneKey=digest('phone',phone),ipKey=digest('ip',smsClientIP(req,sms.trustedProxies)),at=now(),id=randomBytes(24).toString('base64url'),code=String(randomInt(1000000)).padStart(6,'0');
    transaction(()=>{cleanup();const latest=db.prepare('SELECT created_at FROM sms_send_events WHERE phone_key=? AND verification_source=? ORDER BY created_at DESC LIMIT 1').get(phoneKey,sms.provider);if(latest&&latest.created_at+COOLDOWN>at)throw error(429,'SMS_COOLDOWN','请等待后再获取验证码。',{retryAfterSeconds:retry(latest.created_at+COOLDOWN)});
      for(const [column,value,window,max]of [['phone_key',phoneKey,3600000,5],['phone_key',phoneKey,86400000,10],['ip_key',ipKey,3600000,20],['ip_key',ipKey,86400000,100]])limit('sms_send_events',column,value,window,max);
      db.prepare('INSERT INTO sms_send_events(id,phone_key,ip_key,created_at,verification_source) VALUES(?,?,?,?,?)').run(id,phoneKey,ipKey,at,sms.provider);db.prepare('INSERT INTO sms_challenges(id,phone_key,code_hash,created_at,expires_at,status,verification_source) VALUES(?,?,?,?,?,?,?)').run(id,phoneKey,digest('otp',id+':'+code),at,at+LIFE,'pending',sms.provider);});
    if(sms.provider==='tencent')try{const result=await sendCode({config:sms.tencent,phone,code,challengeId:id,now:at});if(result?.accepted!==true)throw Error();}catch{db.prepare("UPDATE sms_challenges SET status='failed',code_hash=NULL WHERE id=?").run(id);throw error(502,'SMS_DELIVERY_FAILED','验证码请求未获确认，请稍后重试。',{retryAfterSeconds:retry(at+COOLDOWN)});}
    const activation=transaction(()=>{
      const row=db.prepare('SELECT rowid,status,expires_at FROM sms_challenges WHERE id=?').get(id);
      if(!row||row.status!=='pending')return error(410,'OTP_SUPERSEDED','请使用最近一次获取的验证码。');
      if(row.expires_at<=now()){db.prepare("UPDATE sms_challenges SET status='expired',code_hash=NULL WHERE id=?").run(id);return error(410,'OTP_EXPIRED','验证码已过期，请重新获取。');}
      // Only supersede earlier requests. A late older provider response cannot revoke
      // a newer accepted code, and a failed newer request cannot revoke the older code.
      db.prepare("UPDATE sms_challenges SET status='superseded',code_hash=NULL WHERE phone_key=? AND verification_source=? AND rowid<? AND status IN ('pending','active')").run(phoneKey,sms.provider,row.rowid);
      db.prepare("UPDATE sms_challenges SET status='active' WHERE id=?").run(id);
    });if(activation)throw activation;
    return {challengeId:id,phoneMasked:phone.slice(3,6)+'****'+phone.slice(-4),expiresInSeconds:Math.max(0,Math.floor((at+LIFE-now())/1000)),retryAfterSeconds:retry(at+COOLDOWN),delivery:sms.provider==='test'?'test':'accepted',...(sms.provider==='test'?{testCode:code}:{})};
  }
  function verify(req,data){
    assertEnabled();const ipKey=digest('ip',smsClientIP(req,sms.trustedProxies));
    // Persist the IP budget separately so invalid requests cannot roll it back.
    transaction(()=>{cleanup();limit('sms_verify_events','ip_key',ipKey,600000,60);db.prepare('INSERT INTO sms_verify_events VALUES(?,?,?)').run(randomUUID(),ipKey,now());});
    const result=transaction(()=>{
      const id=typeof data.challengeId==='string'&&data.challengeId.length<=128?data.challengeId:'',row=db.prepare('SELECT * FROM sms_challenges WHERE id=?').get(id);
      if(!row||row.verification_source!==sms.provider)return {error:error(401,'OTP_INVALID','验证码无效，请核对后重试。')};
      if(row.status==='used')return {error:error(410,'OTP_USED','此验证码已使用，请重新获取。')};
      if(row.status==='superseded')return {error:error(410,'OTP_SUPERSEDED','请使用最近一次获取的验证码。')};
      if(row.expires_at<=now())return {error:error(410,'OTP_EXPIRED','验证码已过期，请重新获取。')};
      if(row.attempts>=ATTEMPTS)return {error:error(429,'OTP_ATTEMPTS_EXCEEDED','尝试次数已用完，请稍后重新获取。',{attemptsRemaining:0,retryAfterSeconds:retry(row.expires_at)})};
      if(row.status!=='active')return {error:error(401,'OTP_INVALID','验证码无效，请核对后重试。')};
      const format=typeof data.code==='string'&&/^\d{6}$/.test(data.code),expected=Buffer.from(row.code_hash),actual=Buffer.from(digest('otp',id+':'+(format?data.code:'')));
      if(!format||!timingSafeEqual(expected,actual)){
        db.prepare('UPDATE sms_challenges SET attempts=attempts+1 WHERE id=?').run(id);const remaining=ATTEMPTS-row.attempts-1;
        return {error:remaining?error(format?401:400,format?'OTP_INVALID':'OTP_FORMAT_INVALID',format?'验证码无效，请核对后重试。':'请输入六位数字验证码。',{attemptsRemaining:remaining}):error(429,'OTP_ATTEMPTS_EXCEEDED','尝试次数已用完，请稍后重新获取。',{attemptsRemaining:0,retryAfterSeconds:retry(row.expires_at)})};
      }
      db.prepare("UPDATE sms_challenges SET status='used',code_hash=NULL WHERE id=?").run(id);
      if(sms.provider==='tencent'&&db.prepare("SELECT 1 FROM phone_identities WHERE phone_key=? AND verification_source='legacy'").get(row.phone_key))return {error:error(409,'SMS_IDENTITY_REVIEW_REQUIRED','此手机号需要联系客服核实后登录。')};
      let account=db.prepare('SELECT u.id,u.name,u.role,u.player_id FROM users u JOIN phone_identities p ON p.user_id=u.id WHERE p.phone_key=? AND p.verification_source=?').get(row.phone_key,sms.provider);
      if(!account){account={id:randomUUID(),name:'手机用户',role:'customer',player_id:null};db.prepare('INSERT INTO users(id,name) VALUES(?,?)').run(account.id,account.name);db.prepare('INSERT INTO phone_identities(phone_key,user_id,verification_source) VALUES(?,?,?)').run(row.phone_key,account.id,sms.provider);}
      return {session:{...issueSession(account.id,account.name,config.mode==='demo'?'demo':'sms'),role:account.role,playerId:account.player_id||null}};
    });if(result.error)throw result.error;return result.session;
  }
  function forget(userId){const row=db.prepare('SELECT phone_key,verification_source FROM phone_identities WHERE user_id=?').get(userId);if(row){db.prepare('DELETE FROM sms_challenges WHERE phone_key=? AND verification_source=?').run(row.phone_key,row.verification_source);db.prepare('DELETE FROM phone_identities WHERE user_id=?').run(userId);}}
  return {capability,available,challenge,verify,forget};
}
