const {api,createPage}=require('../../utils/page');
Page(createPage({
  data:{skeletonKind:'form',step:'choose',capabilities:null,phone:'',code:'',phoneMasked:'',challengeId:'',testCode:'',delivery:'',remaining:0,agreed:false,busy:false,formError:'',locked:false,expired:false,brandName:(api.config.brand||{}).name||'俱乐部'},
  onLoad(options){this.returnTo=api.safeReturnUrl(options.returnTo||'/pages/profile/profile');this.load();},
  onShow(){this.refreshCountdown();},
  onHide(){this.stopTimer();},onUnload(){this.unloaded=true;this.stopTimer();},
  load(){return this.run(async()=>{const capabilities=await api.get('/auth/capabilities');if(capabilities.mode!==api.config.mode)throw new Error('登录配置不一致，请联系俱乐部。');this.setData({capabilities});});},
  agree(e){this.setData({agreed:e.detail.value.includes('agree'),formError:''});},
  phoneEntry(){this.setData({step:'phone',formError:''});},
  back(){if(this.data.busy)return;if(this.data.step==='code')this.setData({step:'phone',code:'',formError:''});else this.setData({step:'choose',formError:''});},
  changePhone(e){this.setData({phone:e.detail.value.trim().replace(/^\+86/,''),formError:''});},
  changeCode(e){this.setData({code:e.detail.value.replace(/\D/g,'').slice(0,6),formError:''});},
  policy(e){wx.navigateTo({url:'/pages/settings/settings?legal='+e.currentTarget.dataset.view});},
  ensureConsent(){if(this.data.agreed)return true;this.setData({formError:'请先阅读并同意服务协议与隐私说明。'});return false;},
  async wechat(){if(this.data.busy||!this.ensureConsent())return;this.setData({busy:true,formError:''});try{await api.login();this.finish();}catch(error){this.setData({formError:error.message});}finally{this.setData({busy:false});}},
  async sendCode(){
    if(this.data.busy||this.data.remaining>0||!this.ensureConsent())return;
    if(!this.data.capabilities||!this.data.capabilities.sms.enabled){this.setData({formError:'俱乐部尚未开通短信登录。'});return;}
    const phone=this.data.phone.trim().replace(/^\+86/,'');if(!/^1[3-9]\d{9}$/.test(phone)){this.setData({formError:'请输入 11 位中国大陆手机号。'});return;}
    this.setData({busy:true,formError:''});
    try{const challenge=await api.post('/auth/sms/challenges',{phone});this.setData({step:'code',phoneMasked:challenge.phoneMasked,challengeId:challenge.challengeId,code:'',testCode:challenge.delivery==='test'?challenge.testCode:'',delivery:challenge.delivery,locked:false,expired:false});this.expiresAt=Date.now()+challenge.expiresInSeconds*1000;this.startCountdown(challenge.retryAfterSeconds);}
    catch(error){this.setData({formError:error.message});if(error.retryAfterSeconds)this.startCountdown(error.retryAfterSeconds);}
    finally{this.setData({busy:false});}
  },
  async verify(){
    if(this.data.busy||this.data.locked)return;
    if(this.expiresAt&&Date.now()>=this.expiresAt){this.setData({expired:true,formError:'验证码已过期，请重新获取。'});return;}
    if(!/^\d{6}$/.test(this.data.code)){this.setData({formError:'请输入 6 位验证码。'});return;}
    this.setData({busy:true,formError:''});
    try{api.saveSession(await api.post('/auth/sms/verify',{challengeId:this.data.challengeId,code:this.data.code}));this.finish();}
    catch(error){const locked=['OTP_ATTEMPTS_EXCEEDED','OTP_USED','OTP_SUPERSEDED'].includes(error.code),expired=error.code==='OTP_EXPIRED';this.setData({formError:error.message+(Number.isInteger(error.attemptsRemaining)?' 还可尝试 '+error.attemptsRemaining+' 次。':''),locked,expired});if(error.retryAfterSeconds)this.startCountdown(error.retryAfterSeconds);}
    finally{this.setData({busy:false});}
  },
  startCountdown(seconds){this.retryAt=Date.now()+Math.max(0,seconds)*1000;this.refreshCountdown();},
  refreshCountdown(){this.stopTimer();const tick=()=>{const remaining=Math.max(0,Math.ceil(((this.retryAt||0)-Date.now())/1000));this.setData({remaining,expired:!!this.expiresAt&&Date.now()>=this.expiresAt});if(!remaining&&(!this.expiresAt||Date.now()>=this.expiresAt))this.stopTimer();};tick();if(this.data.remaining>0||(this.expiresAt&&Date.now()<this.expiresAt))this.timer=setInterval(tick,1000);},
  stopTimer(){if(this.timer)clearInterval(this.timer);this.timer=null;},
  finish(){this.stopTimer();if(this.unloaded)return;this.setData({code:'',testCode:''});const pages=typeof getCurrentPages==='function'?getCurrentPages():[];if(pages.length>1){wx.navigateBack({delta:1});return;}const returnTo=this.returnTo||'/pages/profile/profile';if(['/pages/home/home','/pages/services/services','/pages/orders/orders','/pages/profile/profile'].includes(returnTo.split('?')[0]))wx.switchTab({url:returnTo.split('?')[0]});else wx.redirectTo({url:returnTo});}
}));
