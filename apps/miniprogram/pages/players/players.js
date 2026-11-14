const {api,createPage,player}=require('../../utils/page');
Page(createPage({data:{players:[],all:[],query:''},onLoad(){this.load();},load(){return this.run(async()=>{const p=(await api.get('/players')).map(player);this.setData({players:p,all:p});});},search(e){const q=e.detail.value.trim();this.setData({query:q,players:this.data.all.filter(p=>(p.name+p.role+p.games.join('')).includes(q))});}}));
