import {randomUUID} from 'node:crypto';
export function createWechatAuth({db,config,integrations,authenticate,issueSession,rateLimit,assertClubReady,fail,str}){
  db.exec(`CREATE TABLE IF NOT EXISTS wechat_identities(appid TEXT NOT NULL,openid TEXT NOT NULL,user_id TEXT NOT NULL REFERENCES users(id),PRIMARY KEY(appid,openid),UNIQUE(user_id,appid));
    INSERT OR IGNORE INTO wechat_identities(appid,openid,user_id) SELECT wechat_appid,wechat_openid,id FROM users WHERE wechat_appid IS NOT NULL AND wechat_openid IS NOT NULL;`);
  const identity=(userId,appid)=>db.prepare('SELECT appid,openid FROM wechat_identities WHERE user_id=? AND appid=?').get(userId,appid||'');
  async function login(req,data,{native=false,link=false}={}){
    if(config.mode!=='production')throw fail(403,'PRODUCTION_ONLY','演示环境请使用演示登录。');
    const provider=native?config.wechatNative:config.wechat;
    if(!provider?.appid||!provider?.appSecret)throw fail(503,'AUTH_PROVIDER_NOT_CONFIGURED','微信登录尚未配置。');
    const target=link?authenticate(req):null;assertClubReady();rateLimit(req,'auth',target||undefined);
    const code=str(data.code,'微信登录代码',256);let verified;
    try{verified=await (native?integrations.exchangeWechatAppCode:integrations.exchangeWechatCode)({...provider,code});}catch{throw fail(401,'WECHAT_LOGIN_FAILED','微信登录失败，请重新尝试。');}
    if(typeof verified?.openid!=='string'||!verified.openid||verified.openid.length>256)throw fail(401,'WECHAT_LOGIN_FAILED','微信登录失败，请重新尝试。');
    db.exec('BEGIN IMMEDIATE');try{
      let account=db.prepare('SELECT u.id,u.name,u.role,u.player_id FROM users u JOIN wechat_identities w ON w.user_id=u.id WHERE w.appid=? AND w.openid=?').get(provider.appid,verified.openid);
      if(link){
        // A logout or deletion while the provider was responding must invalidate this link.
        if(authenticate(req)!==target)throw fail(401,'UNAUTHORIZED','请重新登录。');
        if(account&&account.id!==target)throw fail(409,'WECHAT_IDENTITY_IN_USE','此微信已关联其他账户，请联系俱乐部客服；不会自动合并账号。');
        const current=identity(target,provider.appid);if(current&&current.openid!==verified.openid)throw fail(409,'WECHAT_ACCOUNT_ALREADY_LINKED','当前账号已关联此应用的另一个微信身份。');
        account=db.prepare('SELECT id,name,role,player_id FROM users WHERE id=?').get(target);
      }
      if(!account){account={id:randomUUID(),name:'微信用户',role:'customer',player_id:null};db.prepare('INSERT INTO users(id,name) VALUES(?,?)').run(account.id,account.name);}
      if(!identity(account.id,provider.appid))db.prepare('INSERT INTO wechat_identities VALUES(?,?,?)').run(provider.appid,verified.openid,account.id);
      // Keep legacy columns for old databases/tools; all payment identity checks use the mapping.
      db.prepare('UPDATE users SET wechat_appid=?,wechat_openid=? WHERE id=? AND wechat_openid IS NULL').run(provider.appid,verified.openid,account.id);
      const result={...issueSession(account.id,account.name,native?'wechat-app':'wechat'),role:account.role,playerId:account.player_id||null};
      db.exec('COMMIT');return result;
    }catch(e){db.exec('ROLLBACK');throw e;}
  }
  return {identity,login};
}
