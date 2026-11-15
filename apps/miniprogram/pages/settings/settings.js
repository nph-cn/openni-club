const {api,createPage}=require('../../utils/page');
Page(createPage({
  data:{mode:api.config.mode,version:'0.2.0',deleting:false,accountMessage:'',club:{},legalView:''},
  onLoad(options){if(options&&["terms","privacy"].includes(options.legal))this.setData({legalView:options.legal});this.load();},
  load(){return this.run(async()=>{this.setData({club:await api.get('/club')});});},
  toggleLegal(event){const view=event.currentTarget.dataset.view;this.setData({legalView:this.data.legalView===view?'':view});},
  clearSession(){wx.showModal({title:'退出当前会话？',content:'退出后需要重新登录。',confirmText:'退出会话',success:r=>{if(r.confirm){wx.removeStorageSync('openni-session');wx.showToast({title:'已退出',icon:'success'});wx.switchTab({url:'/pages/profile/profile'});}}});},
  deleteAccount(){
    if(this.data.deleting)return;
    wx.showModal({title:'注销账号并移除个人资料？',content:'此操作无法撤销。未结预约或待确认款项须先处理；注销将清除会话、微信身份关联、订单联系方式及备注，必要的交易记录会匿名保留。',confirmText:'确认注销',confirmColor:'#A43D2D',success:async result=>{
      if(!result.confirm)return;this.setData({deleting:true,accountMessage:''});
      try{await api.authorized('/account','DELETE');wx.removeStorageSync('openni-session');this.setData({accountMessage:'账号已注销，身份关联和个人联系资料已移除。'});}
      catch(error){this.setData({accountMessage:error.message});}
      finally{this.setData({deleting:false});}
    }});
  }
}));
