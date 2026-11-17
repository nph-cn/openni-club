const {api,createPage,order}=require('../../utils/page');
const PAY=['awaiting_payment'];
const WAITING=['awaiting_assignment','awaiting_acceptance'];
const ACTIVE=['scheduled','in_progress','awaiting_confirmation'];
const DONE=['completed','cancelled'];
Page(createPage({
  data:{all:[],orders:[],active:'active',counts:{pay:0,waiting:0,active:0,done:0},tabs:[{id:'active',name:'进行中'},{id:'awaiting_confirmation',name:'待确认'},{id:'completed',name:'已完成'},{id:'all',name:'全部'}]},
  onShow(){this.load();},
  load(){return this.run(async()=>{const all=(await api.authorized('/orders')).map(order);this.setData({all});this.filter();});},
  choose(e){this.setData({active:e.currentTarget.dataset.id});this.filter();},
  filter(){
    const all=this.data.all;
    const inSet=(o,set)=>set.includes(o.fulfillmentStatus);
    this.setData({
      counts:{
        pay:all.filter(o=>inSet(o,PAY)).length,
        waiting:all.filter(o=>inSet(o,WAITING)).length,
        active:all.filter(o=>inSet(o,ACTIVE)).length,
        done:all.filter(o=>inSet(o,DONE)).length
      },
      orders:all.filter(o=>{
        switch(this.data.active){
          case 'all':return true;
          case 'pay':return inSet(o,PAY);
          case 'waiting':return inSet(o,WAITING);
          case 'active':return inSet(o,ACTIVE);
          case 'done':return inSet(o,DONE);
          case 'awaiting_confirmation':return o.fulfillmentStatus==='awaiting_confirmation';
          case 'completed':return o.fulfillmentStatus==='completed';
          default:return !DONE.includes(o.fulfillmentStatus);
        }
      })
    });
  }
}));
