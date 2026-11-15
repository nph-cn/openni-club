import http from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { randomBytes, randomUUID, createHash, timingSafeEqual, createPrivateKey, createPublicKey } from 'node:crypto';
import { club, services, players, announcements } from './seed.mjs';
import * as wechatIntegrations from '../../integrations/src/wechat.mjs';
import {createOperations} from './operations.mjs';
import {createOperationsRoutes} from './operations-routes.mjs';
import {readBranding,brandFields} from './branding.mjs';
import {validateServiceSpec,validateVariants,quoteService} from './service-spec.mjs';

const hash = value => createHash('sha256').update(value).digest('hex');
const fail = (status, code, message) => Object.assign(new Error(message), { status, code });
const same = (a,b) => { const x=Buffer.from(a), y=Buffer.from(b); return x.length === y.length && timingSafeEqual(x,y); };

export function readConfig(env = process.env) {
  const mode=env.API_MODE || 'demo';
  if (!['demo','production'].includes(mode)) throw Error('API_MODE must be demo or production');
  const port=Number(env.PORT || 8787);
  if (!Number.isInteger(port) || port<1 || port>65535) throw Error('PORT must be 1–65535');
  const adminToken=env.ADMIN_TOKEN || '';
  if (adminToken && adminToken.length<24) throw Error('ADMIN_TOKEN must contain at least 24 characters');
  if(adminToken&&!/^[A-Za-z0-9_-]+$/.test(adminToken))throw Error('ADMIN_TOKEN must contain only letters, digits, underscore or hyphen (base64url)');
  if (mode==='production' && !adminToken) throw Error('Production requires ADMIN_TOKEN (at least 24 characters)');
  const origins=(env.CORS_ORIGINS || 'http://localhost:4173,http://127.0.0.1:4173,http://localhost:8788,http://127.0.0.1:8788').split(',').map(x=>x.trim()).filter(Boolean);
  for (const value of origins) {
    let u; try {u=new URL(value);} catch {throw Error('CORS_ORIGINS must be comma-separated http(s) origins');}
    if (!['http:','https:'].includes(u.protocol) || u.origin!==value) throw Error('CORS_ORIGINS cannot include wildcards or paths');
    if (mode==='production' && u.protocol!=='https:') throw Error('Production CORS_ORIGINS must use HTTPS');
  }
  const wechat={appid:env.WECHAT_APP_ID||'',appSecret:env.WECHAT_APP_SECRET||''};
  const wechatNative={appid:env.WECHAT_NATIVE_APP_ID||'',appSecret:env.WECHAT_NATIVE_APP_SECRET||''};
  function paymentConfig(native=false) {
    const flag=native?'WECHAT_NATIVE_PAY_ENABLED':'WECHAT_PAY_ENABLED';
    if(env[flag]&&!['true','false'].includes(env[flag]))throw Error(`${flag} must be true or false`);
    if(env[flag]!=='true')return null;
    if(mode!=='production')throw Error(`${flag} requires production mode`);
    const prefix=native?'WECHAT_NATIVE':'WECHAT',notifyKey=native?'WECHAT_NATIVE_PAY_NOTIFY_URL':'WECHAT_PAY_NOTIFY_URL';
    const required=[`${prefix}_APP_ID`,`${prefix}_APP_SECRET`,'WECHAT_PAY_MCH_ID','WECHAT_PAY_MERCHANT_SERIAL','WECHAT_PAY_PRIVATE_KEY_PATH','WECHAT_PAY_API_V3_KEY',notifyKey,'WECHAT_PAY_PLATFORM_KEY_ID','WECHAT_PAY_PLATFORM_KEY_PATH'];
    for(const key of required)if(!env[key])throw Error(`Missing required payment configuration: ${key}`);
    let notify;try{notify=new URL(env[notifyKey]);}catch{throw Error(`${notifyKey} must be an HTTPS URL`);}
    if(notify.protocol!=='https:'||notify.username||notify.password||notify.hash)throw Error(`${notifyKey} must be an HTTPS URL`);
    const payment={appid:(native?wechatNative:wechat).appid,tradeType:native?'APP':'JSAPI',mchid:env.WECHAT_PAY_MCH_ID,merchantSerial:env.WECHAT_PAY_MERCHANT_SERIAL,apiV3Key:env.WECHAT_PAY_API_V3_KEY,notifyUrl:env[notifyKey],platformKeys:{}};
    if(Buffer.byteLength(payment.apiV3Key)!==32)throw Error('WECHAT_PAY_API_V3_KEY must contain exactly 32 bytes');
    const refundKey=native?'WECHAT_NATIVE_PAY_REFUND_NOTIFY_URL':'WECHAT_PAY_REFUND_NOTIFY_URL';
    if(env[refundKey]){let refund;try{refund=new URL(env[refundKey]);}catch{throw Error(`${refundKey} must be an HTTPS URL`);}if(refund.protocol!=='https:'||refund.username||refund.password||refund.hash)throw Error(`${refundKey} must be an HTTPS URL`);payment.refundNotifyUrl=env[refundKey];}
    try{payment.merchantPrivateKey=readFileSync(env.WECHAT_PAY_PRIVATE_KEY_PATH,'utf8');payment.platformKeys[env.WECHAT_PAY_PLATFORM_KEY_ID]=readFileSync(env.WECHAT_PAY_PLATFORM_KEY_PATH,'utf8');}catch{throw Error('Unable to read configured WeChat payment PEM files');}
    try{const key=createPrivateKey(payment.merchantPrivateKey),platform=createPublicKey(payment.platformKeys[env.WECHAT_PAY_PLATFORM_KEY_ID]);if(key.asymmetricKeyType!=='rsa'||key.asymmetricKeyDetails.modulusLength<2048||platform.asymmetricKeyType!=='rsa'||platform.asymmetricKeyDetails.modulusLength<2048)throw Error();}catch{throw Error('WeChat merchant and platform keys must be valid RSA PEM keys of at least 2048 bits');}
    return payment;
  }
  return {mode,port,adminToken,origins,wechat,wechatNative,wechatPay:paymentConfig(),wechatAppPay:paymentConfig(true),host:env.HOST || '127.0.0.1',dataDir:env.DATA_DIR || './data',...readBranding(env)};
}

export function createApp(config) {
  if (config.dataDir!==':memory:') mkdirSync(config.dataDir,{recursive:true,mode:0o700});
  const db=new DatabaseSync(config.dataDir===':memory:' ? ':memory:' : join(config.dataDir,'openni.sqlite'));
  db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
    CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY,name TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),expires_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS orders(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),service_id TEXT NOT NULL,service_title TEXT NOT NULL,player_id TEXT,scheduled_at TEXT NOT NULL,contact TEXT NOT NULL,note TEXT NOT NULL,price_cents INTEGER NOT NULL,status TEXT NOT NULL,created_at TEXT NOT NULL,idempotency_key TEXT NOT NULL,request_hash TEXT NOT NULL,UNIQUE(user_id,idempotency_key));
    CREATE INDEX IF NOT EXISTS order_owner ON orders(user_id,created_at);
    CREATE TABLE IF NOT EXISTS audit(id TEXT PRIMARY KEY,order_id TEXT NOT NULL,actor TEXT NOT NULL,old_status TEXT NOT NULL,new_status TEXT NOT NULL,created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS catalog(kind TEXT NOT NULL,id TEXT NOT NULL,body TEXT NOT NULL,archived INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(kind,id));
    CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);`);
  if(!db.prepare("SELECT value FROM metadata WHERE key='catalog_initialized'").get()){
    db.exec('BEGIN IMMEDIATE');try{
      for(const [kind,items] of Object.entries(config.initialSeed?{services:config.initialSeed.services,players:config.initialSeed.players,announcements:config.initialSeed.announcements,banners:config.initialSeed.banners||[]}:{services,players,announcements,banners:[]}))for(const item of items)db.prepare('INSERT INTO catalog(kind,id,body) VALUES(?,?,?)').run(kind,item.id,JSON.stringify(content(kind,item)));
      db.prepare('INSERT INTO metadata VALUES(?,?)').run('club',JSON.stringify(config.initialSeed?.club||{...club,demoData:true}));
      db.prepare('INSERT INTO metadata VALUES(?,?)').run('catalog_initialized','true');db.exec('COMMIT');
    }catch(err){db.exec('ROLLBACK');throw err;}
  }
  const clubData=()=>({...JSON.parse(db.prepare("SELECT value FROM metadata WHERE key='club'").get().value),...config.publicBrand,configManaged:Boolean(config.publicBrand),configHash:config.publicBrand?.configHash||null});
  const clubReady=()=>{const data=clubData();return data.demoData===false&&['privacyText','termsText','supportContact','legalEntity'].every(key=>typeof data[key]==='string'&&data[key].trim());};
  function assertClubReady(){if(config.mode==='production'&&!clubReady())throw fail(409,'CLUB_NOT_READY','俱乐部尚未完成真实资料、隐私说明、服务协议、客服与经营主体配置。');}
  const catalog=(kind,admin=false)=>db.prepare(`SELECT body,archived FROM catalog WHERE kind=? ${admin?'':'AND archived=0'} ORDER BY rowid`).all(kind).map(r=>({...JSON.parse(r.body),...(admin?{archived:Boolean(r.archived)}:{})}));
  const entry=(kind,id,admin=false)=>catalog(kind,admin).find(x=>x.id===id);
  function addColumn(table,column,type){if(!db.prepare(`PRAGMA table_info(${table})`).all().some(x=>x.name===column))db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${type}`);}
  addColumn('users','wechat_openid','TEXT');
  addColumn('users','wechat_appid','TEXT');
  addColumn('sessions','source',"TEXT NOT NULL DEFAULT 'demo'");
  addColumn('orders','payment_status',"TEXT NOT NULL DEFAULT 'unpaid'");
  addColumn('orders','transaction_id','TEXT');
  addColumn('orders','demo','INTEGER NOT NULL DEFAULT 1');
  addColumn('orders','payment_appid','TEXT');
  addColumn('orders','payment_channel','TEXT');
  addColumn('orders','refund_id','TEXT');
  addColumn('orders','provider_refund_id','TEXT');
  addColumn('orders','refund_status','TEXT');
  db.exec('DROP INDEX IF EXISTS user_wechat; CREATE UNIQUE INDEX IF NOT EXISTS user_wechat_app ON users(wechat_appid,wechat_openid) WHERE wechat_openid IS NOT NULL; CREATE UNIQUE INDEX IF NOT EXISTS order_transaction ON orders(transaction_id) WHERE transaction_id IS NOT NULL; CREATE INDEX IF NOT EXISTS merchant_order ON orders(replace(id,\'-\',\'\'));');
  if(config.wechat?.appid)db.prepare('UPDATE users SET wechat_appid=? WHERE wechat_openid IS NOT NULL AND wechat_appid IS NULL').run(config.wechat.appid);
  db.exec("UPDATE orders SET payment_appid=(SELECT wechat_appid FROM users WHERE id=orders.user_id),payment_channel='JSAPI' WHERE demo=0 AND payment_appid IS NULL");
  const integrations={...wechatIntegrations,...config.integrations};
  let ops;
  const authReady=()=>Boolean((config.wechat?.appid&&config.wechat?.appSecret)||(config.wechatNative?.appid&&config.wechatNative?.appSecret));
  const paymentsReady=()=>Boolean(config.wechatPay||config.wechatAppPay);
  const limits=new Map();
  let requests=0;
  function rateLimit(req, route,identity) {
    const now=Date.now(); const key=`${identity?'user:'+identity:'ip:'+req.socket.remoteAddress}:${route}`;
    if (++requests%100===0) for(const [k,v] of limits) if(v.until<now) limits.delete(k);
    let value=limits.get(key);
    if (!value || value.until<now) {value={count:0,until:now+60000};limits.set(key,value);}
    if (++value.count>60) throw fail(429,'RATE_LIMIT','请求过于频繁，请稍后重试。');
  }
  function authenticate(req, admin=false) {
    const bearer=/^Bearer ([A-Za-z0-9_-]+)$/.exec(req.headers.authorization || '')?.[1] || '';
    if(admin) {
      if(!config.adminToken) throw fail(503,'ADMIN_NOT_CONFIGURED','管理员访问未配置。');
      if(!same(bearer,config.adminToken)) throw fail(401,'UNAUTHORIZED','管理员凭证无效。');
      return 'admin';
    }
    if(config.mode!=='demo' && !authReady()) throw fail(503,'AUTH_PROVIDER_NOT_CONFIGURED','微信身份验证尚未配置；生产环境不能使用演示登录。');
    const session=db.prepare('SELECT user_id,source FROM sessions WHERE token_hash=? AND expires_at>?').get(hash(bearer),Date.now());
    if(!session) throw fail(401,'UNAUTHORIZED','登录已失效，请重新登录。');
    if(!(config.mode==='demo'?['demo']:['wechat','wechat-app']).includes(session.source))throw fail(401,'SESSION_MODE_MISMATCH','当前会话与运行环境不匹配，请重新登录。');
    req.authSource=session.source;
    return session.user_id;
  }
  function orderView(row) {return {id:row.id,serviceId:row.service_id,serviceTitle:row.service_title,playerId:row.player_id,scheduledAt:row.scheduled_at,contact:row.contact,note:row.note,priceCents:row.price_cents,status:row.status,createdAt:row.created_at,paymentStatus:row.payment_status||'unpaid',refundStatus:row.refund_status||null,demo:Boolean(row.demo),...(ops?ops.view(row):{})};}
  function send(res,status,value) {
    res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(value));
  }
  async function rawBody(req) {
    if(!(req.headers['content-type'] || '').startsWith('application/json')) throw fail(415,'JSON_REQUIRED','请使用 application/json。');
    const chunks=[];let bytes=0;for await(const chunk of req){bytes+=chunk.length;if(bytes>196608)throw fail(413,'BODY_TOO_LARGE','提交内容过长。');chunks.push(chunk);}
    return Buffer.concat(chunks).toString('utf8');
  }
  async function body(req){const text=await rawBody(req);try{const data=JSON.parse(text||'{}');if(!data||typeof data!=='object'||Array.isArray(data))throw Error();return data;}catch{throw fail(400,'INVALID_JSON','JSON 格式无效。');}}
  function issueSession(id,name,source){const token=randomBytes(32).toString('base64url');db.prepare('DELETE FROM sessions WHERE expires_at<=?').run(Date.now());db.prepare('INSERT INTO sessions(token_hash,user_id,expires_at,source) VALUES(?,?,?,?)').run(hash(token),id,Date.now()+86400000,source);return {token,user:{id,name},demo:source==='demo',expiresIn:86400};}
  function str(value,name,max,required=true) {
    if(!required && (value===undefined || value===null))return '';
    if(typeof value!=='string'||(required&&!value.trim())||value.length>max)throw fail(400,'VALIDATION',`${name}不能为空且不得超过 ${max} 个字符。`);
    return value.trim();
  }
  function content(kind,data) {
    const id=str(data.id,'内容编号',64);if(!/^[A-Za-z0-9_-]+$/.test(id))throw fail(400,'VALIDATION','内容编号只能使用字母、数字、下划线和连字符。');
    const list=(value,name,max=40)=>{if(!Array.isArray(value)||value.length>10)throw fail(400,'VALIDATION',`${name}须为不超过 10 项的列表。`);return value.map(x=>str(x,name,max));};
    const image=(value,name)=>{if(!value)return '';const text=str(value,name,2048);let url;try{url=new URL(text);}catch{throw fail(400,'VALIDATION',`${name}须为 HTTPS 地址。`);}if(url.protocol!=='https:'||url.username||url.password)throw fail(400,'VALIDATION',`${name}须为 HTTPS 地址。`);return text;};
    if(kind==='services') {
      if(!Number.isInteger(data.priceCents)||data.priceCents<1||data.priceCents>10000000)throw fail(400,'VALIDATION','价格须为 1 至 10000000 分之间的整数。');
      if(!Number.isInteger(data.durationMinutes)||data.durationMinutes<15||data.durationMinutes>720)throw fail(400,'VALIDATION','时长须为 15 至 720 分钟之间的整数。');
      return {id,title:str(data.title,'服务名称',100),game:str(data.game,'游戏',60),category:str(data.category,'类别',40),description:str(data.description,'介绍',3000),priceCents:data.priceCents,durationMinutes:data.durationMinutes,tags:list(data.tags||[],'标签'),inclusions:list(data.inclusions||[],'服务包含',240),requirements:list(data.requirements||[],'预约要求',240),coverUrl:image(data.coverUrl,'服务封面'),gameIconUrl:image(data.gameIconUrl,'游戏图标'),bannerUrl:image(data.bannerUrl,'游戏横幅'),...validateServiceSpec(data,fail),variants:validateVariants(data.variants,fail)};
    }
    if(kind==='banners'){
      const imageUrl=image(str(data.imageUrl,'横幅图片',2048),'横幅图片'),serviceId=str(data.serviceId,'目标服务',64,false),game=str(data.game,'目标游戏',60,false),sortOrder=data.sortOrder??0;
      if(!serviceId&&!game)throw fail(400,'VALIDATION','横幅须关联一个服务或游戏。');
      if(serviceId&&!db.prepare("SELECT 1 FROM catalog WHERE kind='services' AND id=? AND archived=0").get(serviceId))throw fail(400,'VALIDATION','横幅关联的服务不存在或已归档。');
      if(!Number.isInteger(sortOrder)||sortOrder<0||sortOrder>1000)throw fail(400,'VALIDATION','排序须为 0 至 1000 的整数。');
      return {id,title:str(data.title,'横幅标题',100),imageUrl,serviceId,game,sortOrder};
    }
    if(kind==='players') {
      if(!/^#[0-9a-fA-F]{6}$/.test(data.color||''))throw fail(400,'VALIDATION','头像颜色须为 #RRGGBB。');
      return {id,name:str(data.name,'姓名',60),role:str(data.role,'角色',60),bio:str(data.bio,'介绍',2000),games:list(data.games||[],'游戏'),tags:list(data.tags||[],'标签'),initials:str(data.initials,'头像文字',4),color:data.color,avatarUrl:image(data.avatarUrl,'成员头像'),coverUrl:image(data.coverUrl,'成员封面')};
    }
    if(!Number.isFinite(Date.parse(data.publishedAt)))throw fail(400,'VALIDATION','公告时间无效。');
    return {id,title:str(data.title,'标题',150),body:str(data.body,'正文',8000),publishedAt:new Date(data.publishedAt).toISOString()};
  }
  function auditContent(resource,before,after){db.prepare('INSERT INTO audit VALUES(?,?,?,?,?,?)').run(randomUUID(),resource,'admin',JSON.stringify(before),JSON.stringify(after),new Date().toISOString());}
  function findOrder(id,user) {
    const row=db.prepare('SELECT * FROM orders WHERE id=?').get(id);
    if(!row || (user!=='admin' && row.user_id!==user))throw fail(404,'NOT_FOUND','找不到这条预约。');
    return row;
  }
  function paymentFor(row) {
    const payment=row.payment_channel==='APP'?config.wechatAppPay:config.wechatPay;
    if(row.demo||!payment||payment.appid!==row.payment_appid)throw fail(503,'PAYMENTS_NOT_CONFIGURED','订单对应的支付应用尚未配置。');
    return payment;
  }
  function recordPayment(row,notification) {
    const user=db.prepare('SELECT wechat_openid FROM users WHERE id=?').get(row.user_id);
    try{integrations.validateWechatPayOrder(notification,{id:row.id.replaceAll('-',''),totalCents:row.price_cents,openid:user.wechat_openid||undefined});}catch{throw fail(400,'PAYMENT_MISMATCH','支付通知与订单不匹配。');}
    if(['paid','refund_pending','refunded'].includes(row.payment_status)){
      if(row.transaction_id!==notification.transactionId)throw fail(409,'TRANSACTION_CONFLICT','支付流水冲突。');
      return row;
    }
    if(row.status==='cancelled')throw fail(409,'ORDER_CANCELLED','已取消订单需人工核实付款并退款。');
    db.exec('BEGIN IMMEDIATE');try{
      db.prepare("UPDATE orders SET payment_status='paid',transaction_id=? WHERE id=?").run(notification.transactionId,row.id);
      ops.paid(row);
      db.prepare('INSERT INTO audit VALUES(?,?,?,?,?,?)').run(randomUUID(),row.id,'wechat-pay',row.payment_status,'paid',new Date().toISOString());db.exec('COMMIT');
    }catch{db.exec('ROLLBACK');throw fail(409,'TRANSACTION_CONFLICT','支付流水冲突。');}
    return findOrder(row.id,'admin');
  }
  function recordRefund(row,refund) {
    try{integrations.validateWechatRefundOrder(refund,{id:row.id.replaceAll('-',''),transactionId:row.transaction_id,totalCents:row.price_cents},row.refund_id);}catch{throw fail(400,'REFUND_MISMATCH','退款通知与订单不匹配。');}
    if(row.provider_refund_id&&row.provider_refund_id!==refund.providerRefundId)throw fail(409,'REFUND_CONFLICT','退款流水冲突。');
    if(row.payment_status==='refunded')return row;
    const paymentStatus=refund.status==='SUCCESS'?'refunded':refund.status==='CLOSED'?'paid':'refund_pending';
    const status=refund.status==='SUCCESS'?'cancelled':row.status;
    db.exec('BEGIN IMMEDIATE');try{
      db.prepare('UPDATE orders SET payment_status=?,status=?,refund_status=?,provider_refund_id=? WHERE id=?').run(paymentStatus,status,refund.status,refund.providerRefundId,row.id);
      if(refund.status==='SUCCESS')ops.refunded(row);else if(refund.status==='CLOSED')ops.refundClosed(row);else ops.ledger.hold(row.id);
      db.prepare('INSERT INTO audit VALUES(?,?,?,?,?,?)').run(randomUUID(),row.id,'wechat-refund',row.payment_status,`${paymentStatus}:${refund.status}`,new Date().toISOString());db.exec('COMMIT');
    }catch(error){db.exec('ROLLBACK');throw error;}
    return findOrder(row.id,'admin');
  }
  async function requestRefund(original,reason){
    let row=findOrder(original.id,'admin');const payment=paymentFor(row);
    if(!payment.refundNotifyUrl)throw fail(503,'REFUND_NOT_CONFIGURED','请配置此支付应用的 HTTPS 退款回调地址。');
    reason=str(reason,'退款原因',80);
    if(row.payment_status==='refunded')return row;
    if(!['paid','refund_pending'].includes(row.payment_status)||!row.transaction_id)throw fail(409,'ORDER_NOT_REFUNDABLE','只有已确认付款的订单可以发起全额退款。');
    if(!row.refund_id||row.refund_status==='CLOSED'){
      const refundId=randomUUID().replaceAll('-','');
      db.exec('BEGIN IMMEDIATE');try{
        ops.refundStarted(row);
        db.prepare("UPDATE orders SET payment_status='refund_pending',refund_id=?,refund_status='PROCESSING',provider_refund_id=NULL WHERE id=?").run(refundId,row.id);
        db.prepare('INSERT INTO audit VALUES(?,?,?,?,?,?)').run(randomUUID(),row.id,'admin-refund',row.payment_status,JSON.stringify({status:'refund_pending',refundId,reason}),new Date().toISOString());db.exec('COMMIT');
      }catch(error){db.exec('ROLLBACK');throw error;}
      row=findOrder(row.id,'admin');
    }
    let refund;try{refund=await integrations.createWechatRefund({config:payment,order:{id:row.id.replaceAll('-',''),transactionId:row.transaction_id,totalCents:row.price_cents},refundId:row.refund_id,reason});}catch{throw fail(502,'REFUND_PROVIDER_ERROR','退款请求结果待核实，请同步支付状态后重试；不会创建新的退款单号。');}
    return recordRefund(findOrder(row.id,'admin'),refund);
  }
  async function cancelOrder(original,actor,message='预约已取消。'){
    let row=findOrder(original.id,'admin');if(row.fulfillment_status==='cancelled')return row;
    if(!['awaiting_payment','awaiting_assignment','awaiting_acceptance','scheduled'].includes(row.fulfillment_status))throw fail(409,'INVALID_FULFILLMENT_STATE','服务已经开始，请通过售后流程处理。');
    if(row.payment_status==='pending'){
      const payment=paymentFor(row);let result;
      try{result=await integrations.queryWechatOrder({config:payment,orderId:row.id.replaceAll('-','')});}catch{throw fail(502,'PAYMENT_QUERY_ERROR','无法核实付款状态，暂未取消，请稍后重试。');}
      if(result.orderId!==row.id.replaceAll('-','')||result.totalCents!==row.price_cents||result.appid!==payment.appid||result.mchid!==payment.mchid)throw fail(400,'PAYMENT_MISMATCH','支付查询与订单不匹配。');
      if(result.state==='SUCCESS'){recordPayment(findOrder(row.id,'admin'),result);throw fail(409,'REFUND_REQUIRED','微信已确认付款，请联系客服退款。');}
      if(result.state==='NOTPAY'){
        try{await integrations.closeWechatOrder({config:payment,orderId:row.id.replaceAll('-','')});result=await integrations.queryWechatOrder({config:payment,orderId:row.id.replaceAll('-','')});}catch{throw fail(502,'PAYMENT_CLOSE_UNCONFIRMED','微信关单结果尚未确认，订单保留，请稍后重试。');}
      }
      if(result.state!=='CLOSED'||result.orderId!==row.id.replaceAll('-','')||result.totalCents!==row.price_cents)throw fail(409,'PAYMENT_CLOSE_UNCONFIRMED','微信未确认关闭订单，暂不能取消。');
      row=findOrder(row.id,'admin');
    }
    if(!['unpaid','pending'].includes(row.payment_status))throw fail(409,'REFUND_REQUIRED','订单已付款或退款中，请通过售后流程处理。');
    return ops.transaction(()=>{row=findOrder(row.id,'admin');if(!['unpaid','pending'].includes(row.payment_status))throw fail(409,'PAYMENT_CHANGED','支付状态已变化，请刷新。');ops.cancelled(row,actor,message);db.prepare("UPDATE orders SET payment_status='unpaid' WHERE id=?").run(row.id);return findOrder(row.id,'admin');});
  }
  ops=createOperations({db,config,fail,clubData,catalog,entry});
  const operationsRoutes=createOperationsRoutes({ops,config,authenticate,body,send,orderView,fail,requestRefund,cancelOrder,catalog});
  const server=http.createServer(async(req,res)=>{
    res.setHeader('X-Content-Type-Options','nosniff');
    res.setHeader('Referrer-Policy','no-referrer');
    res.setHeader('X-Frame-Options','DENY');
    const origin=req.headers.origin;
    if(origin && !config.origins.includes(origin)) return send(res,403,{error:{code:'ORIGIN_DENIED',message:'当前网页来源未被允许。'}});
    if(origin){res.setHeader('Access-Control-Allow-Origin',origin);res.setHeader('Vary','Origin');}
    res.setHeader('Access-Control-Allow-Methods','GET, POST, PUT, PATCH, DELETE, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers','Content-Type, Authorization');
    if(req.method==='OPTIONS'){res.writeHead(204);res.end();return;}
    try {
      const url=new URL(req.url,'http://localhost'); const path=url.pathname;
      if(req.method==='GET'&&path==='/health')return send(res,200,{ok:true,mode:config.mode,version:'0.1.0',transactionsEnabled:config.mode==='demo'||authReady(),realPaymentsEnabled:paymentsReady()});
      if(!path.startsWith('/api/v1/'))throw fail(404,'NOT_FOUND','接口不存在。');
      const route=path.slice(7);
      if(route==='/brand/logo.png'&&req.method==='GET'){if(!config.brandLogo)throw fail(404,'NOT_FOUND','品牌 Logo 尚未生成。');res.writeHead(200,{'Content-Type':'image/png','Cache-Control':'public, max-age=300'});res.end(config.brandLogo);return;}
      ops.tick();
      if(await operationsRoutes(req,res,route,url))return;
      if(req.method==='GET') {
        if(route==='/club')return send(res,200,{...clubData(),demo:config.mode==='demo'});
        if(route==='/services')return send(res,200,catalog('services'));
        if(route==='/players')return send(res,200,catalog('players'));
        if(route==='/banners')return send(res,200,catalog('banners').filter(b=>!b.serviceId||entry('services',b.serviceId)).sort((a,b)=>a.sortOrder-b.sortOrder||a.id.localeCompare(b.id)));
        if(route==='/announcements')return send(res,200,catalog('announcements'));
        const match=/^\/(services|players)\/([^/]+)$/.exec(route);
        if(match){const item=entry(match[1],match[2]);if(!item)throw fail(404,'NOT_FOUND','内容不存在。');return send(res,200,item);}
      }
      if(route==='/auth/demo'&&req.method==='POST') {
        if(config.mode!=='demo')throw fail(403,'DEMO_DISABLED','生产环境禁用演示登录。');
        rateLimit(req,'auth');const data=await body(req);const name=str(data.name || '演示访客','昵称',40);
        const id=randomUUID();db.prepare('INSERT INTO users(id,name) VALUES(?,?)').run(id,name);
        if(data.role)ops.demoRole(id,data.role,data.playerId);
        return send(res,201,{...issueSession(id,name,'demo'),role:ops.me(id).role,playerId:ops.me(id).playerId});
      }
      if(['/auth/wechat','/auth/wechat-app'].includes(route)&&req.method==='POST') {
        if(config.mode!=='production')throw fail(403,'PRODUCTION_ONLY','演示环境请使用演示登录。');
        const native=route==='/auth/wechat-app',provider=native?config.wechatNative:config.wechat;
        if(!provider?.appid||!provider?.appSecret)throw fail(503,'AUTH_PROVIDER_NOT_CONFIGURED','微信登录尚未配置。');
        assertClubReady();
        rateLimit(req,'auth');const data=await body(req),code=str(data.code,'微信登录代码',256);
        let identity;try{identity=await (native?integrations.exchangeWechatAppCode:integrations.exchangeWechatCode)({...provider,code});}catch{throw fail(401,'WECHAT_LOGIN_FAILED','微信登录失败，请重新尝试。');}
        let user=db.prepare('SELECT id,name FROM users WHERE wechat_appid=? AND wechat_openid=?').get(provider.appid,identity.openid);
        if(!user){user={id:randomUUID(),name:'微信用户'};db.prepare('INSERT INTO users(id,name,wechat_appid,wechat_openid) VALUES(?,?,?,?)').run(user.id,user.name,provider.appid,identity.openid);}
        return send(res,200,issueSession(user.id,user.name,native?'wechat-app':'wechat'));
      }
      if(['/payments/wechat/notify','/payments/wechat-app/notify'].includes(route)&&req.method==='POST') {
        const paymentConfig=route==='/payments/wechat-app/notify'?config.wechatAppPay:config.wechatPay;
        if(!paymentConfig)throw fail(503,'PAYMENTS_NOT_CONFIGURED','支付未配置。');
        const raw=await rawBody(req);let notification;
        try{notification=await integrations.decryptWechatPayNotification({headers:req.headers,rawBody:raw,config:paymentConfig});}catch{throw fail(401,'INVALID_PAYMENT_NOTIFICATION','支付通知验证失败。');}
        const row=db.prepare("SELECT * FROM orders WHERE replace(id,'-','')=?").get(notification.orderId);
        if(!row||row.demo)throw fail(404,'UNKNOWN_PAYMENT_ORDER','支付订单不存在。');
        if(row.payment_appid!==paymentConfig.appid||row.payment_channel!==(paymentConfig.tradeType||'JSAPI'))throw fail(400,'PAYMENT_MISMATCH','支付应用与订单不匹配。');
        recordPayment(row,notification);
        return send(res,200,{code:'SUCCESS',message:'成功'});
      }
      if(['/payments/wechat/refund-notify','/payments/wechat-app/refund-notify'].includes(route)&&req.method==='POST') {
        const paymentConfig=route.includes('/wechat-app/')?config.wechatAppPay:config.wechatPay;
        if(!paymentConfig)throw fail(503,'PAYMENTS_NOT_CONFIGURED','支付未配置。');
        const raw=await rawBody(req);let refund;
        try{refund=await integrations.decryptWechatRefundNotification({headers:req.headers,rawBody:raw,config:paymentConfig});}catch{throw fail(401,'INVALID_REFUND_NOTIFICATION','退款通知验证失败。');}
        const row=db.prepare("SELECT * FROM orders WHERE replace(id,'-','')=? AND refund_id=?").get(refund.orderId,refund.refundId);
        if(!row||row.demo)throw fail(404,'UNKNOWN_REFUND_ORDER','退款订单不存在。');
        if(row.payment_appid!==paymentConfig.appid||row.payment_channel!==(paymentConfig.tradeType||'JSAPI'))throw fail(400,'REFUND_MISMATCH','退款应用与订单不匹配。');
        recordRefund(row,refund);
        return send(res,200,{code:'SUCCESS',message:'成功'});
      }
      if(route==='/account'&&req.method==='DELETE') {
        const userId=authenticate(req);
        const account=ops.user(userId);
        if(account.player_id&&(db.prepare("SELECT id FROM orders WHERE assigned_player_id=? AND fulfillment_status NOT IN ('completed','cancelled')").get(account.player_id)||db.prepare("SELECT id FROM earnings WHERE player_id=? AND state IN ('held','available')").get(account.player_id)))throw fail(409,'UNSETTLED_MEMBER_WORK','仍有成员履约任务或未结算收入，请先与俱乐部完成处理。');
        const rows=db.prepare('SELECT * FROM orders WHERE user_id=?').all(userId);
        if(rows.some(row=>!['completed','cancelled'].includes(row.status)||['pending','refund_pending'].includes(row.payment_status)))throw fail(409,'UNSETTLED_ORDERS','仍有未结束的预约或待确认款项，请先完成、取消预约或联系客服处理退款后再注销。');
        db.exec('BEGIN IMMEDIATE');try{
          db.prepare('DELETE FROM sessions WHERE user_id=?').run(userId);
          db.prepare("UPDATE users SET name='已注销用户',wechat_openid=NULL,wechat_appid=NULL,role='customer',player_id=NULL WHERE id=?").run(userId);
          db.prepare("UPDATE orders SET contact='',note='' WHERE user_id=?").run(userId);
          db.prepare('INSERT INTO audit VALUES(?,?,?,?,?,?)').run(randomUUID(),'account:'+userId,userId,'active','anonymized',new Date().toISOString());
          db.exec('COMMIT');
        }catch(error){db.exec('ROLLBACK');throw error;}
        return send(res,200,{deleted:true,retainedOrders:rows.length});
      }
      if(route==='/orders'&&req.method==='GET') {
        const user=authenticate(req);return send(res,200,db.prepare('SELECT * FROM orders WHERE user_id=? ORDER BY created_at DESC').all(user).map(orderView));
      }
      if(route==='/orders'&&req.method==='POST') {
        const user=authenticate(req);assertClubReady();rateLimit(req,'order',user);const data=await body(req);
        const serviceId=str(data.serviceId,'服务',80);
        if(['priceCents','status','userId','commissionBps','memberCents','clubCents','assignedPlayerId','fulfillmentStatus','durationMinutes'].some(key=>Object.hasOwn(data,key)))throw fail(400,'READ_ONLY_FIELD','金额、分成、履约状态、时长和用户身份由服务器确定。');
        const playerId=str(data.playerId,'成员',80,false)||null;
        const scheduledAt=str(data.scheduledAt,'预约时间',80),when=new Date(scheduledAt).getTime();
        if(!Number.isFinite(when))throw fail(400,'INVALID_SCHEDULE','预约时间格式无效。');
        const contact=str(data.contact,'联系方式',120),note=str(data.note,'备注',500,false),idempotencyKey=str(data.idempotencyKey,'幂等请求标识',100);
        const variantId=str(data.variantId,'服务规格',64,false)||null;
        const canonical={serviceId,playerId,scheduledAt:new Date(when).toISOString(),contact,note,...(variantId?{variantId}:{})};
        const requestHash=hash(JSON.stringify(canonical));
        const existing=db.prepare('SELECT * FROM orders WHERE user_id=? AND idempotency_key=?').get(user,idempotencyKey);
        if(existing){if(existing.request_hash!==requestHash)throw fail(409,'IDEMPOTENCY_CONFLICT','此请求标识已用于其他预约。');return send(res,200,orderView(existing));}
        const source=entry('services',serviceId);if(!source)throw fail(400,'INVALID_SERVICE','请选择有效的服务。');
        const service=quoteService(source,variantId,fail);
        if(playerId&&!catalog('players').some(x=>x.id===playerId&&x.games.includes(service.game)))throw fail(400,'INVALID_PLAYER','该成员不提供所选游戏的服务。');
        if(when<Date.now()+60000||when>Date.now()+30*86400000)throw fail(400,'INVALID_SCHEDULE','预约时间须在 1 分钟后至 30 天内。');
        const identity=db.prepare('SELECT wechat_appid FROM users WHERE id=?').get(user);
        const row={id:randomUUID(),user_id:user,service_id:serviceId,service_title:service.title,player_id:playerId,scheduled_at:canonical.scheduledAt,contact,note,price_cents:service.priceCents,status:'pending',created_at:ops.iso(),payment_status:'unpaid',demo:config.mode==='demo'?1:0,payment_appid:identity.wechat_appid,payment_channel:req.authSource==='wechat-app'?'APP':'JSAPI'};
        ops.transaction(()=>{db.prepare('INSERT INTO orders(id,user_id,service_id,service_title,player_id,scheduled_at,contact,note,price_cents,status,created_at,idempotency_key,request_hash,payment_status,demo,payment_appid,payment_channel) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)').run(row.id,user,serviceId,service.title,playerId,row.scheduled_at,contact,note,service.priceCents,'pending',row.created_at,idempotencyKey,requestHash,'unpaid',row.demo,row.payment_appid,row.payment_channel);ops.created(row,service);});
        return send(res,201,orderView(findOrder(row.id,user)));
      }
      const pay=/^\/orders\/([^/]+)\/pay$/.exec(route);
      if(pay&&req.method==='POST') {
        const userId=authenticate(req);rateLimit(req,'pay',userId);const row=findOrder(pay[1],userId);
        const native=req.authSource==='wechat-app',paymentConfig=native?config.wechatAppPay:config.wechatPay;
        if(row.demo||!paymentConfig)throw fail(503,'PAYMENTS_NOT_CONFIGURED','当前环境不能发起真实支付。');
        assertClubReady();
        if(row.status==='cancelled'||row.status==='completed'||!['unpaid','pending'].includes(row.payment_status))throw fail(409,'ORDER_NOT_PAYABLE','当前订单不能再次付款。');
        const user=db.prepare('SELECT wechat_openid,wechat_appid FROM users WHERE id=?').get(userId);
        if(user.wechat_appid!==paymentConfig.appid)throw fail(409,'PAYMENT_APP_MISMATCH','登录应用与支付配置不一致，请重新登录。');
        db.prepare("UPDATE orders SET payment_status='pending' WHERE id=?").run(row.id);
        let result;try{result=await (native?integrations.createAppOrder:integrations.createJsapiOrder)({config:paymentConfig,order:{id:row.id.replaceAll('-',''),description:row.service_title,totalCents:row.price_cents,openid:user.wechat_openid}});}catch{throw fail(502,'PAYMENT_PROVIDER_ERROR','暂时无法发起支付。请稍后重试；支付状态须由商户核实。');}
        return send(res,200,{paymentParams:result.paymentParams,paymentStatus:'pending'});
      }
      const own=/^\/orders\/([^/]+)(\/cancel)?$/.exec(route);
      if(own){const user=authenticate(req),row=findOrder(own[1],user);if(req.method==='GET'&&!own[2])return send(res,200,orderView(row));if(req.method==='PATCH'&&own[2])return send(res,200,orderView(await cancelOrder(row,ops.actor(user,'customer'))));}
      if(route.startsWith('/admin/')) {
        authenticate(req,true);
        if(route==='/admin/config/status'&&req.method==='GET')return send(res,200,{mode:config.mode,database:true,admin:true,realAuth:authReady(),payments:paymentsReady(),wechatMiniAuth:Boolean(config.wechat?.appid&&config.wechat?.appSecret),wechatNativeAuth:Boolean(config.wechatNative?.appid&&config.wechatNative?.appSecret),wechatMiniPay:Boolean(config.wechatPay),wechatNativePay:Boolean(config.wechatAppPay),catalogReady:clubReady(),sms:false,storage:false,demo:config.mode==='demo'});
        if(route==='/admin/club'){
          if(req.method==='GET')return send(res,200,clubData());
          if(req.method==='PATCH'){
            const original=clubData(),input=await body(req);
            if(config.publicBrand&&brandFields.some(key=>Object.hasOwn(input,key)))throw fail(409,'BRAND_MANAGED_BY_CONFIG','品牌资料由统一配置文件管理，请在品牌工作室更新配置并重新应用。');
            const data={...original,...input};
            if(typeof data.demoData!=='boolean')throw fail(400,'VALIDATION','demoData 须为布尔值。');
            const commissionBps=data.commissionBps??2000;if(!Number.isInteger(commissionBps)||commissionBps<0||commissionBps>10000)throw fail(400,'VALIDATION','默认抽成须为 0 至 10000 基点。');
            const updated={id:original.id,name:str(data.name,'俱乐部名称',100),tagline:str(data.tagline,'标语',150),description:str(data.description,'介绍',5000),city:str(data.city,'城市',100),notice:str(data.notice,'提示',500),privacyText:str(data.privacyText,'隐私说明',20000,false),termsText:str(data.termsText,'服务协议',20000,false),supportContact:str(data.supportContact,'客服联系方式',200,false),legalEntity:str(data.legalEntity,'经营主体',200,false),demoData:data.demoData,commissionBps};
            db.exec('BEGIN IMMEDIATE');try{db.prepare("UPDATE metadata SET value=? WHERE key='club'").run(JSON.stringify(updated));auditContent('club',original,updated);db.exec('COMMIT');}catch(err){db.exec('ROLLBACK');throw err;}
            return send(res,200,clubData());
          }
        }
        const resource=/^\/admin\/(services|players|announcements|banners)(?:\/([^/]+))?$/.exec(route);
        if(resource){
          const [,kind,id]=resource;
          if(req.method==='GET'&&!id)return send(res,200,catalog(kind,true));
          if(req.method==='POST'&&!id){const data=await body(req),item=content(kind,{...data,id:data.id||randomUUID()});if(entry(kind,item.id,true))throw fail(409,'ID_EXISTS','内容编号已存在。');db.exec('BEGIN IMMEDIATE');try{db.prepare('INSERT INTO catalog(kind,id,body) VALUES(?,?,?)').run(kind,item.id,JSON.stringify(item));auditContent(`${kind}/${item.id}`,null,item);db.exec('COMMIT');}catch(err){db.exec('ROLLBACK');throw err;}return send(res,201,{...item,archived:false});}
          if(id){const original=entry(kind,id,true);if(!original)throw fail(404,'NOT_FOUND','内容不存在。');
            if(req.method==='PATCH'){const data=await body(req),item=content(kind,{...original,...data,id}),archived=data.archived===undefined?original.archived:data.archived;if(typeof archived!=='boolean')throw fail(400,'VALIDATION','archived 须为布尔值。');db.exec('BEGIN IMMEDIATE');try{db.prepare('UPDATE catalog SET body=?,archived=? WHERE kind=? AND id=?').run(JSON.stringify(item),archived?1:0,kind,id);auditContent(`${kind}/${id}`,original,{...item,archived});db.exec('COMMIT');}catch(err){db.exec('ROLLBACK');throw err;}return send(res,200,{...item,archived});}
            if(req.method==='DELETE'){db.exec('BEGIN IMMEDIATE');try{db.prepare('UPDATE catalog SET archived=1 WHERE kind=? AND id=?').run(kind,id);auditContent(`${kind}/${id}`,original,{...original,archived:true});db.exec('COMMIT');}catch(err){db.exec('ROLLBACK');throw err;}return send(res,200,{...original,archived:true});}
          }
        }
        if(route==='/admin/orders'&&req.method==='GET')return send(res,200,db.prepare('SELECT * FROM orders ORDER BY created_at DESC').all().map(orderView));
        const settlement=/^\/admin\/orders\/([^/]+)\/(payment-sync|refund)$/.exec(route);
        if(settlement&&req.method==='POST') {
          rateLimit(req,'settlement','admin');let row=findOrder(settlement[1],'admin');const payment=paymentFor(row);
          if(settlement[2]==='refund'){
            return send(res,200,orderView(await requestRefund(row,(await body(req)).reason)));
          }
          if(row.refund_id&&row.refund_status!=='CLOSED'){
            let refund;try{refund=await integrations.queryWechatRefund({config:payment,refundId:row.refund_id});}catch{throw fail(502,'REFUND_QUERY_ERROR','暂时无法查询退款，请稍后重试。');}
            return send(res,200,orderView(recordRefund(findOrder(row.id,'admin'),refund)));
          }
          let result;try{result=await integrations.queryWechatOrder({config:payment,orderId:row.id.replaceAll('-','')});}catch{throw fail(502,'PAYMENT_QUERY_ERROR','暂时无法查询支付，请稍后重试。');}
          row=findOrder(row.id,'admin');
          if(result.orderId!==row.id.replaceAll('-','')||result.totalCents!==row.price_cents||result.currency!=='CNY'||result.appid!==payment.appid||result.mchid!==payment.mchid)throw fail(400,'PAYMENT_MISMATCH','查询结果与订单不匹配。');
          if(result.state==='SUCCESS')row=recordPayment(row,result);
          else if(result.state==='CLOSED'&&['pending','unpaid'].includes(row.payment_status)){
            ops.transaction(()=>{ops.cancelled(row,ops.owner,'微信已确认未付款关单，预约取消。');db.prepare("UPDATE orders SET payment_status='unpaid' WHERE id=?").run(row.id);});row=findOrder(row.id,'admin');
          }
          return send(res,200,{...orderView(row),providerTradeState:result.state});
        }
        const m=/^\/admin\/orders\/([^/]+)$/.exec(route);
        if(m&&req.method==='PATCH'){const data=await body(req),row=findOrder(m[1],'admin');if(data.status!=='cancelled')throw fail(409,'USE_FULFILLMENT_FLOW','请使用派单、成员接单及客户确认流程，不可直接标记完成。');return send(res,200,orderView(await cancelOrder(row,ops.owner)));}
      }
      throw fail(404,'NOT_FOUND','接口不存在或请求方法不支持。');
    }catch(err){if(!res.writableEnded)send(res,err.status||500,{error:{code:err.code||'INTERNAL',message:err.status?err.message:'服务器暂时不可用，请稍后重试。'}});if(!err.status)console.error('API request failed:',err.name);}
  });
  server.requestTimeout=15000;server.headersTimeout=10000;
  server.on('close',()=>db.close());
  return server;
}
