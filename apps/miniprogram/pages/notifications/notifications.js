const {api,createPage,datetime}=require('../../utils/page');

function categoryOf(n){
  const type=String(n.type||'');
  if(type.includes('refund')||type.includes('settlement')||type.includes('ledger'))return '金额';
  if(type.includes('membership')||type.includes('bound'))return '系统';
  return '订单';
}

Page(createPage({
  data:{all:[],notifications:[],categories:['全部','订单','金额','系统'],active:'全部'},
  onShow(){this.load();},
  load(){
    return this.run(async()=>{
      const all=(await api.authorized('/notifications')).map(n=>Object.assign({},n,{time:datetime(n.createdAt)}));
      this.setData({all});
      this.filter();
    });
  },
  choose(e){this.setData({active:e.currentTarget.dataset.value});this.filter();},
  filter(){
    this.setData({notifications:this.data.all.filter(n=>this.data.active==='全部'||categoryOf(n)===this.data.active)});
  },
  async open(e){
    const item=this.data.all.find(n=>n.id===e.currentTarget.dataset.id);
    try{
      await api.authorized('/notifications/'+item.id+'/read','PATCH');
      if(item.orderId)wx.navigateTo({url:'/pages/order/order?id='+item.orderId+(item.role==='member'?'&member=1':'')});
      else await this.load();
    }catch(error){this.setData({error:error.message});}
  }
}));
