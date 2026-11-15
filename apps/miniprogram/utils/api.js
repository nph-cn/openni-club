const config = require('./config');
let signingIn;
function request(path, method, data, token) {
  if(!['demo','production'].includes(config.mode))return Promise.reject(new Error('俱乐部运行模式配置无效。'));
  if(config.mode==='production'&&!/^https:\/\//.test(config.apiBaseUrl))return Promise.reject(new Error('正式环境须使用 HTTPS 俱乐部服务地址。'));
  return new Promise((resolve, reject) => wx.request({
    url: config.apiBaseUrl + path, method: method || 'GET', data,
    timeout: 12000,
    header: Object.assign({'content-type':'application/json'}, token ? {Authorization:'Bearer '+token} : {}),
    success(res) {
      if (res.statusCode >= 200 && res.statusCode < 300) return resolve(res.data);
      const detail = res.data && res.data.error;
      const error = new Error(detail ? detail.message : '请求失败，请稍后重试。');
      error.status = res.statusCode; error.code=detail&&detail.code; error.retryAfterSeconds=detail&&detail.retryAfterSeconds; error.attemptsRemaining=detail&&detail.attemptsRemaining; reject(error);
    },
    fail() { reject(new Error('暂时连接不上俱乐部，请检查网络后重试。')); }
  }));
}
function session() {
  const saved = wx.getStorageSync('openni-session');
  return saved && saved.mode===config.mode && saved.expiresAt > Date.now() ? saved : null;
}
function saveSession(result) {
  wx.setStorageSync('openni-session',{token:result.token,user:result.user,mode:config.mode,expiresAt:Date.now()+result.expiresIn*1000});
  return result.token;
}
function login() {
  const saved=session();
  if(saved)return Promise.resolve(saved.token);
  if (!signingIn) signingIn = (config.mode==='demo' ? request('/auth/demo','POST',{name:'微信演示访客'}) : new Promise((resolve,reject)=>wx.login({success(result){if(result.code)resolve(result.code);else reject(new Error('未能获取微信登录信息，请重试。'));},fail(){reject(new Error('微信登录失败，请重试。'));}})).then(code=>request('/auth/wechat','POST',{code}))).then(result => {
    return saveSession(result);
  }).finally(() => { signingIn = null; });
  return signingIn;
}
function authError(){const error=new Error('登录后继续');error.code='AUTH_REQUIRED';return error;}
function authorized(path, method, data) {
  const saved=session();if(!saved)return Promise.reject(authError());
  return request(path, method, data, saved.token).catch(error => {
    if(error.status===401) {wx.removeStorageSync('openni-session');throw authError();}
    throw error;
  });
}
function linkWechat(){return new Promise((resolve,reject)=>wx.login({success(result){if(result.code)resolve(result.code);else reject(new Error('未能获取微信登录信息，请重试。'));},fail(){reject(new Error('微信登录失败，请重试。'));}})).then(code=>authorized('/auth/wechat/link','POST',{code})).then(saveSession);}
const routes=['home','services','service','players','player','booking','orders','order','profile','announcements','settings','member','availability','earnings','notifications'];
function safeReturnUrl(value){if(typeof value==='string'&&value.startsWith('%2F')){try{value=decodeURIComponent(value);}catch(_){return '/pages/profile/profile';}}if(typeof value!=='string'||value.length>1500)return '/pages/profile/profile';const route=value.split('?')[0];return routes.some(name=>route==='/pages/'+name+'/'+name)&&!/[\r\n#]/.test(value)?value:'/pages/profile/profile';}
function openLogin(returnTo){
  if(!returnTo&&typeof getCurrentPages==='function'){const pages=getCurrentPages(),page=pages[pages.length-1];if(page){const query=Object.keys(page.options||{}).map(key=>encodeURIComponent(key)+'='+encodeURIComponent(page.options[key])).join('&');returnTo='/'+page.route+(query?'?'+query:'');}}
  wx.navigateTo({url:'/pages/login/login?returnTo='+encodeURIComponent(safeReturnUrl(returnTo))});
}
module.exports = {get:path=>request(path),post:(path,data)=>request(path,'POST',data),authorized,config,session,login,saveSession,openLogin,safeReturnUrl,linkWechat};
