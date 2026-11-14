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
      error.status = res.statusCode; error.code=detail&&detail.code; reject(error);
    },
    fail() { reject(new Error('暂时连接不上俱乐部。开发预览请先启动 API，并检查请求域名配置。')); }
  }));
}
function login() {
  const saved = wx.getStorageSync('openni-session');
  if (saved && saved.mode===config.mode && saved.expiresAt > Date.now()) return Promise.resolve(saved.token);
  if (!signingIn) signingIn = (config.mode==='demo' ? request('/auth/demo','POST',{name:'微信演示访客'}) : new Promise((resolve,reject)=>wx.login({success(result){if(result.code)resolve(result.code);else reject(new Error('未能获取微信登录信息，请重试。'));},fail(){reject(new Error('微信登录失败，请重试。'));}})).then(code=>request('/auth/wechat','POST',{code}))).then(result => {
    wx.setStorageSync('openni-session',{token:result.token, user:result.user, mode:config.mode, expiresAt:Date.now()+result.expiresIn*1000});
    return result.token;
  }).finally(() => { signingIn = null; });
  return signingIn;
}
function authorized(path, method, data, retried) {
  return login().then(token => request(path, method, data, token)).catch(error => {
    if(error.status===401 && !retried) {wx.removeStorageSync('openni-session');return authorized(path,method,data,true);}
    throw error;
  });
}
module.exports = { get:path=>request(path), authorized, config };
