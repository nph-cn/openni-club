import {el,icon,money,dateTime,safeImage,apiAddress,shanghaiInput,fromShanghaiInput,fulfillmentLabels as statuses,ledgerLabels,paymentLabels} from './ui.js';
import {contentManager} from './content.js';
import {applyDemoOverlay,saveDemoSection,resetDemoPreview,hasDemoEdits} from './demo-store.js';

const $=selector=>document.querySelector(selector);
document.querySelectorAll('[data-icon]').forEach(node=>node.replaceChildren(icon(node.dataset.icon)));
const titles={overview:'今日待办',dispatch:'派单工作台',orders:'全部订单',members:'打手管理',settlements:'收入与结算',disputes:'售后处理',brand:'品牌与发布',connection:'连接与集成',services:'服务目录',games:'游戏类目',features:'能力开通',announcements:'俱乐部公告',banners:'首页横幅'};
const tierNames={S:'王牌',A:'资深',B:'熟练',C:'新锐'};
let data={orders:[],players:[],services:[],games:[],features:[],announcements:[],banners:[],club:{},overview:{counts:{},totals:{}},settlements:{entries:[],totals:{},settlements:[]},disputes:[]};
let workspace='overview',apiBase='',adminToken='',orderFilter='all',orderSearch='',currentOrderId=null,actionSubmit=null,loadVersion=0;
let rosterTier='all',rosterState='all',rosterSearch='',gameCategory='all',gameSearch='';
const connected=()=>Boolean(apiBase&&adminToken);
const mobileNavigation=matchMedia('(max-width:900px)');
const navBackdrop=el('button',{type:'button',class:'sidebar-backdrop','aria-label':'关闭菜单',hidden:true,onclick:()=>setMenu(false)});
document.body.append(navBackdrop);
function setMenu(open){$('.ops-sidebar').classList.toggle('open',open);syncMenu();}
function syncMenu(){const open=$('.ops-sidebar').classList.contains('open');$('.ops-sidebar').inert=mobileNavigation.matches&&!open;navBackdrop.hidden=!(mobileNavigation.matches&&open);$('#ops-menu').setAttribute('aria-expanded',String(open));}
mobileNavigation.addEventListener('change',syncMenu);
const player=id=>data.players.find(p=>p.id===id);
const shortId=id=>String(id||'').slice(0,8).toUpperCase();
const badge=(text,state='neutral')=>el('span',{class:`badge ${state}`},text);
const statusBadge=o=>badge(statuses[o.fulfillmentStatus]||o.fulfillmentStatus,o.fulfillmentStatus);
const button=(text,fn,style='soft',disabled=false)=>el('button',{type:'button',class:`action ${style}`,onclick:event=>{Promise.resolve().then(()=>fn(event)).catch(error=>notify(error.message,true));},disabled},text);
const empty=text=>el('div',{class:'empty-state'},el('span',{class:'empty-symbol'},icon('empty')),el('p',{},text));
const header=(title,action,kicker)=>el('div',{class:'ops-page-header'},el('div',{class:'page-heading'},kicker?el('span',{class:'page-kicker'},kicker):null,el('h1',{},title)),action||null);
const panel=(title,body,action)=>el('section',{class:'ops-panel'},el('div',{class:'panel-header'},el('h2',{},title),action||null),body);
const field=(label,input)=>el('label',{class:'ops-field'},el('span',{},label),input);
const fact=(label,value)=>el('div',{},el('dt',{},label),el('dd',{},value??'—'));
const notify=(text,error=false)=>{const node=$('#global-message');node.textContent=text;node.hidden=!text;node.className=error?'error':'';};
const activePlayer=p=>!p.archived&&p.status!=='paused';
const tierBadge=tier=>tier?el('span',{class:`tier-badge tier-${tier}`},el('b',{},tier),el('span',{},tierNames[tier]||'')):el('span',{class:'tier-badge tier-none'},'未分级');
const certifiedBadge=()=>el('span',{class:'cert-badge'},icon('checkCircle'),'认证');
const demoNote=(text,label='示例数据')=>el('div',{class:'demo-note'},el('span',{class:'status-dot'}),el('strong',{},label),el('p',{},text));
const switchButton=(checked,label,onclick,disabled=false)=>el('button',{type:'button',class:`switch${checked?' on':''}`,role:'switch','aria-checked':String(Boolean(checked)),'aria-label':label,disabled,onclick},el('span',{class:'switch-knob'}));

async function request(path,options={}){
 if(!connected())throw Error('请先连接俱乐部后端。');
 let response;
 try{response=await fetch(`${apiBase}${path}`,{...options,headers:{'Content-Type':'application/json',Authorization:`Bearer ${adminToken}`,...options.headers},credentials:'omit',redirect:'error',cache:'no-store',signal:AbortSignal.timeout(15000)});}catch{throw Error('连接失败，请检查 API 地址、网络与服务器 CORS 设置。');}
 if(options.csv&&response.ok)return response.blob();
 const result=await response.json().catch(()=>null);
 if(!response.ok)throw Error(result?.error?.message||`请求失败（${response.status}）`);
 return result;
}
const content=contentManager({request,isConnected:connected,getData:()=>data,onChange:refresh});

async function refresh(){
 const version=++loadVersion;$('#refresh-all').disabled=true;
 try{
  let next;
  if(connected()){
   const paths={overview:'/admin/overview',orders:'/admin/orders',players:'/admin/players',services:'/admin/services',announcements:'/admin/announcements',banners:'/admin/banners',club:'/admin/club',settlements:'/admin/settlements',disputes:'/admin/disputes',config:'/admin/config/status'};
   const results=await Promise.all(Object.entries(paths).map(async([key,path])=>[key,await request(path)]));next=Object.fromEntries(results);
  }else{const response=await fetch('/admin/demo-snapshot.json',{cache:'no-store'});if(!response.ok)throw Error('示例数据暂时无法读取。');next=applyDemoOverlay(await response.json());}
  if(version!==loadVersion)return;
  data=next;render();if(currentOrderId&&$('#order-drawer').open)renderOrder(currentOrderId);
 }catch(e){if(version===loadVersion)notify(e.message,true);throw e;}finally{if(version===loadVersion)$('#refresh-all').disabled=false;}
}
function navigate(next){workspace=next;notify('');render();$('#ops-content').focus({preventScroll:true});setMenu(false);}
function render(){
 const club=data.club||{};$('#club-name').textContent=club.name||'俱乐部工作台';
 const logo=safeImage(club.logoUrl);$('#club-logo').src=logo||'/icon.svg';
 $('#workspace-label').textContent=titles[workspace];
 $('#today-label').textContent=new Intl.DateTimeFormat('zh-CN',{month:'long',day:'numeric',weekday:'long',timeZone:'Asia/Shanghai'}).format(new Date(connected()?Date.now():data.generatedAt||Date.now()));
 $('#mode-label').textContent=connected()?(data.config?.demo?'演示后端':'已连接'):'示例工作台';
 $('#mode-label').classList.toggle('live',connected()&&!data.config?.demo);
 $('#open-connection').textContent=connected()?'连接设置':'连接俱乐部';$('#preview-banner').hidden=connected();
 $('#dispatch-count').textContent=data.overview.counts.awaitingAssignment||0;$('#dispute-count').textContent=data.overview.counts.disputed||0;
 const enabledFeatures=(data.features||[]).filter(feature=>feature.enabled).length,enabledGames=(data.games||[]).filter(game=>game.enabled).length;
 if($('#feature-count'))$('#feature-count').textContent=connected()?'—':enabledFeatures;
 if($('#game-count'))$('#game-count').textContent=connected()?'—':enabledGames;
 document.querySelectorAll('[data-workspace],[data-section]').forEach(node=>{const active=(node.dataset.workspace||node.dataset.section)===workspace;node.classList.toggle('selected',active);node.setAttribute('aria-current',active?'page':'false');});
 const isContent=['services','announcements','banners'].includes(workspace);$('#content-panel').hidden=!isContent;$('#orders-panel').hidden=isContent;
 if(isContent){content.show(workspace);return;}
 const views={overview:renderOverview,dispatch:renderDispatch,orders:renderOrders,members:renderRoster,settlements:renderSettlements,disputes:renderDisputes,games:renderGames,features:renderFeatures,brand:renderBrand,connection:renderConnection};
 $('#ops-content').replaceChildren(views[workspace]());
}
function metrics(items){return el('div',{class:'metrics'},items.map(([label,value,foot,fn])=>el(fn?'button':'div',{class:'metric',...(fn?{onclick:fn}:{})},el('span',{class:'metric-label'},label),el('strong',{class:'metric-value'},value),foot?el('span',{class:'metric-footer'},foot):null)));}
function orderTitle(order){return el('div',{class:'table-main'},order.serviceTitle,el('span',{class:'table-sub'},`#${shortId(order.id)}${order.serviceSnapshot?.variantTitle?` · ${order.serviceSnapshot.variantTitle}`:''}`));}
function renderOverview(){
 const counts=data.overview.counts,totals=data.overview.totals;
 const rows=[['待派单',counts.awaitingAssignment,'dispatch'],['待接单',counts.awaitingAcceptance,'dispatch'],['服务中',counts.inProgress,'orders'],['待客户确认',counts.awaitingConfirmation,'orders'],['待处理售后',counts.disputed,'disputes']];
 const queue=el('div',{class:'queue-list'},rows.map(([label,count,tab],index)=>el('button',{class:'queue-row',onclick:()=>navigate(tab)},el('span',{class:'queue-icon'},icon(['dispatch','clock','play','check','disputes'][index])),el('span',{class:'queue-text'},label),el('strong',{class:'queue-number'},count||0),el('span',{class:'row-arrow','aria-hidden':'true'},'→'))));
 const upcoming=data.orders.filter(o=>!['completed','cancelled'].includes(o.fulfillmentStatus)).sort((a,b)=>a.scheduledAt.localeCompare(b.scheduledAt)).slice(0,5);
 return el('div',{},header('今天的安排',button('开始派单',()=>navigate('dispatch'),'dark')),
  metrics([['待派单',counts.awaitingAssignment||0,'等待安排成员',()=>navigate('dispatch')],['进行中',(counts.inProgress||0)+(counts.awaitingConfirmation||0),'服务与确认',()=>navigate('orders')],['售后',counts.disputed||0,'待处理',()=>navigate('disputes')],['待结算',money(totals.memberAvailableCents),'成员收入',()=>navigate('settlements')]]),
  el('div',{class:'ops-columns'},panel('需要处理',queue),panel('预约安排',upcoming.length?el('div',{class:'upcoming-list'},upcoming.map(o=>el('button',{class:'mini-order',onclick:()=>openOrder(o.id)},el('div',{class:'mini-time'},dateTime(o.scheduledAt).split(' ')[1]||dateTime(o.scheduledAt)),el('div',{class:'mini-copy'},el('strong',{},o.serviceTitle),el('span',{},player(o.assignedPlayerId)?.name||'待分配')),statusBadge(o)))):empty('暂无预约'),button('全部订单 →',()=>navigate('orders'),'plain'))),
  panel('经营概况',el('div',{class:'finance-strip'},fact('订单金额',money(totals.grossCents)),fact('已收款',money(totals.paidCents)),fact('已退款',money(totals.refundedCents)),fact('订单总数',totals.orderCount||0)))
 );
}
function renderDispatch(){
 const columns=[['awaiting_assignment','待派单'],['awaiting_acceptance','待接单'],['scheduled','待开始'],['in_progress','服务中']];
 return el('div',{},header('派单工作台'),el('div',{class:'queue-board'},columns.map(([state,title])=>{
  const orders=data.orders.filter(o=>o.fulfillmentStatus===state);
  return el('section',{class:'queue-column'},el('h2',{},title,el('span',{},orders.length)),orders.length?orders.map(o=>el('article',{class:'dispatch-card'},el('button',{class:'card-title',onclick:()=>openOrder(o.id)},o.serviceTitle),el('p',{class:'card-meta'},dateTime(o.scheduledAt),` · ${o.durationMinutes} 分钟`),el('div',{class:'dispatch-member'},avatar(player(o.assignedPlayerId)),el('span',{},player(o.assignedPlayerId)?.name||'尚未指派')),el('div',{class:'card-bottom'},el('strong',{class:'card-price'},money(o.priceCents)),state==='awaiting_assignment'?button('派单',()=>assign(o),'dark',!connected()):button('查看',()=>openOrder(o.id),'plain')),o.acceptBy?el('p',{class:'card-deadline'},`${dateTime(o.acceptBy)} 前接单`):null)):el('div',{class:'board-empty'},'暂无订单'));
 })));
}
function orderTable(orders){
 const table=el('table',{class:'ops-table'},el('thead',{},el('tr',{},['服务 / 订单','预约时间','成员','金额','履约',''].map(label=>el('th',{},label)))));
 table.append(el('tbody',{},orders.map(o=>el('tr',{},el('td',{},orderTitle(o)),el('td',{},dateTime(o.scheduledAt),el('span',{class:'table-sub'},`${o.durationMinutes} 分钟`)),el('td',{},player(o.assignedPlayerId)?.name||'—'),el('td',{class:'table-money'},money(o.priceCents),el('span',{class:'table-sub'},o.demo?'演示订单':paymentLabels[o.paymentStatus]||o.paymentStatus)),el('td',{},statusBadge(o)),el('td',{},button('详情 →',()=>openOrder(o.id),'plain'))))));
 return el('div',{class:'ops-table-wrap'},orders.length?table:empty('没有符合条件的订单'));
}
function renderOrders(){
 const root=el('div',{},header('全部订单',connected()?button('清理超时未付单',expirePayments,'soft'):null));
 const chips=el('div',{class:'ops-chips'},[['all','全部'],['awaiting_assignment','待派单'],['in_progress','服务中'],['awaiting_confirmation','待确认'],['completed','已完成'],['cancelled','已取消']].map(([value,label])=>el('button',{class:orderFilter===value?'selected':'',onclick:()=>{orderFilter=value;render();}},label)));
 const input=el('input',{type:'search',class:'ops-search',placeholder:'搜索订单、服务或成员','aria-label':'搜索订单',value:orderSearch});
 const region=el('div');const update=()=>{const search=orderSearch.toLowerCase();region.replaceChildren(orderTable(data.orders.filter(o=>(orderFilter==='all'||o.fulfillmentStatus===orderFilter)&&[o.id,o.serviceTitle,player(o.assignedPlayerId)?.name].join(' ').toLowerCase().includes(search))));};input.oninput=()=>{orderSearch=input.value;update();};update();
 root.append(el('div',{class:'ops-table-tools'},chips,input),region);return root;
}
function avatar(p){const image=safeImage(p?.avatarUrl);return image?el('img',{class:'member-avatar',src:image,alt:''}):el('span',{class:'member-avatar'},p?.initials||'—');}
const playerRating=p=>{const rating=Number(p?.rating);return Number.isFinite(rating)&&rating>0?rating.toFixed(1):'—';};
const playerHourly=p=>{const cents=Number(p?.hourlyRateCents);return Number.isFinite(cents)&&cents>0?`${money(cents)}/时`:'—';};
const splitList=value=>String(value||'').split(/[,，]/).map(item=>item.trim()).filter(Boolean);

function demoSave(section,records){data={...data,[section]:records};saveDemoSection(section,records);render();}
function updatePlayer(target,patch){if(connected())return false;demoSave('players',data.players.map(item=>item.id===target.id?{...item,...patch}:item));return true;}
function togglePlayer(target){
 const paused=target.status==='paused';
 if(updatePlayer(target,{status:paused?'active':'paused'}))notify(`${target.name} 已${paused?'恢复接单':'暂停接单'}（示例预览）。`);
}
function resetDemoData(){
 if(!confirm('恢复示例数据？将清除本机保存的打手、游戏类目和能力开通预览改动。'))return;
 resetDemoPreview();refresh().then(()=>notify('已恢复示例快照。')).catch(error=>notify(error.message,true));
}
function openPlayerTier(target){
 if(connected()){notify('已连接后端：分级与认证由后端成员资料管理，示例界面不可修改。',true);return;}
 const select=el('select',{name:'tier'},...['S','A','B','C'].map(tier=>el('option',{value:tier},`${tier} · ${tierNames[tier]}`)));select.value=target.tier||'B';
 const rating=el('input',{type:'number',name:'rating',min:'0',max:'5',step:'0.1',value:target.rating??5});
 const certified=el('input',{type:'checkbox',name:'certified'});certified.checked=Boolean(target.certified);
 showAction({title:`${target.name} · 分级与认证`,fields:[
  field('服务分级',select),
  field('客户评分 / 5',rating),
  el('label',{class:'check-field full-width'},certified,el('span',{},'展示认证打手标识'))
 ],note:'示例数据：保存后仅写入本机浏览器，不会请求后端。',submit:'保存分级',run:async()=>{
  const tier=select.value;updatePlayer(target,{tier,tierLabel:tierNames[tier],certified:certified.checked,rating:Number(rating.value)||0});
  notify(`已更新 ${target.name} 的分级与认证（示例预览）。`);
 }});
}
function openPlayerEditor(target=null){
 if(connected()){content.editMember(target);return;}
 const draft=target||{};
 const name=el('input',{type:'text',name:'name',value:draft.name||'',required:true,maxlength:20,placeholder:'如：阿屿'});
 const role=el('input',{type:'text',name:'role',value:draft.role||'',required:true,maxlength:30,placeholder:'如：小队指挥'});
 const games=el('input',{type:'text',name:'games',value:(draft.games||[]).join('，'),required:true,placeholder:'用逗号分隔，如：三角洲行动，CS2'});
 const tier=el('select',{name:'tier'},...['S','A','B','C'].map(item=>el('option',{value:item},`${item} · ${tierNames[item]}`)));tier.value=draft.tier||'B';
 const hourly=el('input',{type:'number',name:'hourlyRateCents',min:'0',step:'1',value:draft.hourlyRateCents===undefined?'':draft.hourlyRateCents/100});
 const rating=el('input',{type:'number',name:'rating',min:'0',max:'5',step:'0.1',value:draft.rating??5});
 const completed=el('input',{type:'number',name:'completedOrders',min:'0',step:'1',value:draft.completedOrders??0});
 const specialties=el('input',{type:'text',name:'specialties',value:(draft.specialties||[]).join('，'),placeholder:'用逗号分隔'});
 const tags=el('input',{type:'text',name:'tags',value:(draft.tags||[]).join('，'),placeholder:'用逗号分隔'});
 const bio=el('textarea',{name:'bio',rows:3,placeholder:'擅长什么、如何沟通、预约前需要确认什么。'});bio.value=draft.bio||'';
 const certified=el('input',{type:'checkbox',name:'certified'});certified.checked=Boolean(draft.certified);
 showAction({title:target?`编辑 ${target.name}`:'新增打手',fields:[
  field('打手名称',name),field('定位 / 角色',role),field('擅长游戏',games),field('服务分级',tier),field('时薪 / 元',hourly),field('客户评分 / 5',rating),field('完成订单',completed),field('擅长专项',specialties),field('标签',tags),
  el('label',{class:'ops-field full-width'},el('span',{},'个人介绍'),bio),
  el('label',{class:'check-field full-width'},certified,el('span',{},'展示认证打手标识'))
 ],note:'示例数据：保存后仅写入本机浏览器（localStorage），不会请求后端。',submit:target?'保存资料':'添加打手',run:async()=>{
  const chosenTier=tier.value,patch={
   name:name.value.trim(),role:role.value.trim(),games:splitList(games.value),tags:splitList(tags.value),specialties:splitList(specialties.value),bio:bio.value.trim(),
   tier:chosenTier,tierLabel:tierNames[chosenTier],certified:certified.checked,rating:Number(rating.value)||0,completedOrders:Number(completed.value)||0,hourlyRateCents:Math.round(Number(hourly.value||0)*100)
  };
  if(target){updatePlayer(target,patch);notify(`已保存 ${patch.name} 的资料（示例预览）。`);}
  else{
   const palette=['#2455E7','#137B57','#AC4B38','#7356AA','#2F6B8F','#8A5A44'];
   demoSave('players',[...data.players,{id:`p-${crypto.randomUUID().slice(0,8)}`,initials:patch.name.slice(0,1)||'新',color:palette[data.players.length%palette.length],avatarUrl:'',coverUrl:'',archived:false,boundUserId:null,memberName:null,status:'active',...patch}]);
   notify(`已添加打手 ${patch.name}（示例预览）。`);
  }
 }});
}
function renderRoster(){
 const players=data.players||[];
 const actions=el('div',{class:'header-actions'},!connected()&&hasDemoEdits()?button('恢复示例数据',resetDemoData,'plain'):null,connected()?button('新增成员',()=>content.editMember(null),'dark'):button('新增打手',()=>openPlayerEditor(),'dark'));
 const root=el('div',{},header('打手管理',actions,'成员与分级'),connected()
  ?demoNote('已连接后端：分级、认证与启停为只读展示；成员资料仍使用原有的编辑、排班与邀请流程。','只读展示')
  :demoNote('打手分级、认证与启停改动只保存在本机浏览器，可随时恢复示例数据；不会写入后端。','示例数据 · 可编辑预览'));
 const ratings=players.map(item=>Number(item.rating)).filter(Number.isFinite),average=ratings.length?ratings.reduce((sum,value)=>sum+value,0)/ratings.length:0;
 root.append(metrics([['打手总数',players.length,'含停用与归档'],['在岗打手',players.filter(activePlayer).length,'可接单'],['认证打手',players.filter(item=>item.certified).length,'展示认证'],['平均评分',average?average.toFixed(1):'—','客户评价']]));
 const segmented=el('div',{class:'segmented',role:'group','aria-label':'按打手分级筛选'},[['all','全部分级'],['S','S 王牌'],['A','A 资深'],['B','B 熟练'],['C','C 新锐']].map(([value,label])=>el('button',{type:'button',class:rosterTier===value?'selected':'',onclick:()=>{rosterTier=value;render();}},label)));
 const states=el('div',{class:'ops-chips'},[['all','全部状态'],['active','在岗'],['paused','已停用'],['certified','已认证']].map(([value,label])=>el('button',{type:'button',class:rosterState===value?'selected':'',onclick:()=>{rosterState=value;render();}},label)));
 const search=el('input',{type:'search',class:'ops-search',placeholder:'搜索打手、定位或擅长游戏','aria-label':'搜索打手',value:rosterSearch});
 const grid=el('div',{class:'roster-grid'});
 const update=()=>{
  const query=rosterSearch.trim().toLowerCase();
  const filtered=players.filter(item=>{
   if(rosterTier!=='all'&&item.tier!==rosterTier)return false;
   if(rosterState==='active'&&(!activePlayer(item)||item.archived))return false;
   if(rosterState==='paused'&&item.status!=='paused')return false;
   if(rosterState==='certified'&&!item.certified)return false;
   if(!query)return true;
   return [item.name,item.role,...(item.games||[]),...(item.specialties||[]),...(item.tags||[])].join(' ').toLowerCase().includes(query);
  });
  if(!filtered.length){grid.replaceChildren(el('div',{class:'empty-state roster-empty'},el('span',{class:'empty-symbol'},icon('search')),el('p',{},'没有符合筛选条件的打手'),button('清除筛选',()=>{rosterTier='all';rosterState='all';rosterSearch='';render();},'soft')));return;}
  grid.replaceChildren(...filtered.map(rosterCard));
 };
 search.oninput=()=>{rosterSearch=search.value;update();};
 update();
 root.append(el('div',{class:'roster-toolbar'},segmented,states,search),grid);
 return root;
}
function rosterCard(p){
 const currentOrders=data.orders.filter(order=>order.assignedPlayerId===p.id&&!['completed','cancelled'].includes(order.fulfillmentStatus)).length;
 const paused=p.status==='paused';
 const card=el('article',{class:`roster-card${paused?' is-paused':''}${p.archived?' is-archived':''}`});
 const head=el('div',{class:'roster-head'},avatar(p),el('div',{class:'roster-identity'},
  el('div',{class:'roster-name'},el('h2',{},p.name),tierBadge(p.tier)),
  el('p',{class:'roster-role'},p.role||'未填写定位'),
  el('div',{class:'roster-badges'},p.certified?certifiedBadge():badge('未认证','neutral'),p.archived?badge('已归档','neutral'):paused?badge('已停用','held'):badge('在岗','completed')))
 );
 const stats=el('div',{class:'roster-stats'},
  el('div',{},el('strong',{},playerRating(p)),el('span',{},'客户评分')),
  el('div',{},el('strong',{},p.completedOrders??0),el('span',{},'完成订单')),
  el('div',{},el('strong',{},playerHourly(p)),el('span',{},'时薪')));
 const games=el('div',{class:'member-games'},(p.games||[]).map(game=>badge(game,'game-badge')));
 const specialties=(p.specialties||[]).length?el('p',{class:'roster-specialties'},`擅长：${p.specialties.join(' · ')}`):null;
 const foot=el('div',{class:'roster-foot'},el('span',{class:'roster-meta'},`当前订单 ${currentOrders} · 账号 ${p.boundUserId?'已绑定':'未绑定'}`),connected()
  ?el('div',{class:'roster-actions'},button('排班',()=>availability(p),'soft'),button('资料',()=>content.editMember(p),'plain'),!p.boundUserId?button('邀请',()=>invitation(p),'plain'):null)
  :el('div',{class:'roster-actions'},button('编辑资料',()=>openPlayerEditor(p),'soft'),button('分级与认证',()=>openPlayerTier(p),'plain'),button(paused?'启用':'停用',()=>togglePlayer(p),'plain')));
 card.append(head,stats,games,specialties,foot);return card;
}

function gameCounts(game){return {players:(data.players||[]).filter(item=>!item.archived&&(item.games||[]).includes(game.name)).length,services:(data.services||[]).filter(item=>item.game===game.name&&!item.archived).length};}
function toggleGame(game){
 if(connected()){notify('已连接后端：游戏类目为只读展示，请在服务端配置。',true);return;}
 const next=data.games.map(item=>item.id===game.id?{...item,enabled:!item.enabled}:item);
 data={...data,games:next};saveDemoSection('games',next);render();
 notify(`已${game.enabled?'停用':'启用'}「${game.name}」游戏类目（示例预览）。`);
}
function openGameServices(name){content.showServicesFor(name);navigate('services');}
function gameCard(game){
 const counts=gameCounts(game),accent=/^#[0-9a-f]{6}$/i.test(game.accent||'')?game.accent:'#5b6472';
 const tile=el('span',{class:'game-tile',style:`--game-accent:${accent};--game-soft:${accent}1f;--game-line:${accent}3d`},(game.shortName||game.name).slice(0,2));
 const card=el('article',{class:`game-card${game.enabled?'':' is-off'}`});
 const head=el('div',{class:'game-head'},tile,el('div',{class:'game-title'},el('div',{class:'game-name-row'},el('h2',{},game.name),badge(game.enabled?'已启用':'已停用',game.enabled?'completed':'held')),el('p',{},`${game.shortName||game.name} · ${game.category}`)));
 const stats=el('div',{class:'game-stats'},el('div',{},el('strong',{},counts.players),el('span',{},'打手')),el('div',{},el('strong',{},counts.services),el('span',{},'服务')),el('div',{},el('strong',{},game.category),el('span',{},'分类')));
 const foot=el('div',{class:'game-foot'},el('div',{class:'switch-line'},switchButton(game.enabled,`${game.name} 启用状态`,()=>toggleGame(game),connected()),el('span',{},game.enabled?'客户端可见':'客户端隐藏')),button('查看服务',()=>openGameServices(game.name),'plain'));
 card.append(head,stats,foot);return card;
}
function renderGames(){
 const root=el('div',{},header('游戏类目',button('打开服务目录',()=>{content.clearServiceFilter();navigate('services');},'soft'),'俱乐部设置'),connected()
  ?demoNote('已连接后端：游戏类目为只读展示；服务筛选仍按后端返回的服务数据工作。','只读展示')
  :demoNote('游戏启停与分类改动只保存在本机浏览器；游戏与服务目录的筛选联动可直接预览。','示例数据 · 可编辑预览'));
 const games=data.games||[];
 if(!games.length){root.append(el('div',{class:'empty-state'},el('span',{class:'empty-symbol'},icon('games')),el('p',{},'当前后端未返回游戏类目数据；未连接时可查看示例数据。')));return root;}
 root.append(metrics([['游戏总数',games.length,'含停用'],['已启用',games.filter(game=>game.enabled).length,'客户端可见'],['覆盖服务',(data.services||[]).length,'服务目录'],['打手覆盖',games.filter(game=>gameCounts(game).players>0).length,'有专长的游戏']]));
 const categories=['all',...new Set(games.map(game=>game.category))];
 const chips=el('div',{class:'ops-chips',role:'group','aria-label':'按游戏分类筛选'},categories.map(value=>el('button',{type:'button',class:gameCategory===value?'selected':'',onclick:()=>{gameCategory=value;render();}},value==='all'?'全部分类':value)));
 const search=el('input',{type:'search',class:'ops-search',placeholder:'搜索游戏名称或分类','aria-label':'搜索游戏',value:gameSearch});
 const grid=el('div',{class:'game-grid'});
 const update=()=>{
  const query=gameSearch.trim().toLowerCase();
  const filtered=games.filter(game=>(gameCategory==='all'||game.category===gameCategory)&&(!query||[game.name,game.shortName,game.category].join(' ').toLowerCase().includes(query)));
  if(!filtered.length){grid.replaceChildren(el('div',{class:'empty-state game-empty'},el('span',{class:'empty-symbol'},icon('games')),el('p',{},'没有符合条件的游戏'),button('清除筛选',()=>{gameCategory='all';gameSearch='';render();},'soft')));return;}
  grid.replaceChildren(...filtered.map(gameCard));
 };
 search.oninput=()=>{gameSearch=search.value;update();};
 update();
 root.append(el('div',{class:'roster-toolbar'},chips,search),grid);return root;
}

const featureIcons={'经营基础':'services','打手管理':'members','履约效率':'dispatch','增长转化':'star','财务结算':'settlements','数据洞察':'analytics'};
function toggleFeature(feature){
 if(connected()){notify('已连接后端：能力开通为只读展示，请在服务端配置。',true);return;}
 const next=data.features.map(item=>item.id===feature.id?{...item,enabled:!item.enabled}:item);
 data={...data,features:next};saveDemoSection('features',next);render();
 notify(`已${feature.enabled?'关闭':'开通'}「${feature.name}」预览（仅本机示例，不影响后端）。`);
}
function featureCard(feature){
 const card=el('article',{class:`feature-card${feature.enabled?' is-on':''}`});
 const head=el('div',{class:'feature-head'},el('span',{class:'feature-icon'},icon(featureIcons[feature.category]||'features')),el('div',{class:'feature-title'},el('div',{class:'feature-name'},el('h3',{},feature.name),feature.recommended?badge('推荐','reco'):null),el('p',{class:'feature-category'},feature.category)));
 const description=el('p',{class:'feature-desc'},feature.description);
 const foot=el('div',{class:'feature-foot'},badge(feature.enabled?'已开通':'未开通',feature.enabled?'completed':'neutral'),switchButton(feature.enabled,`${feature.name} 开通状态`,()=>toggleFeature(feature),connected()));
 card.append(head,description,foot);return card;
}
function renderFeatures(){
 const features=data.features||[];
 const root=el('div',{},header('能力开通',!connected()&&hasDemoEdits()?button('恢复示例数据',resetDemoData,'soft'):null,'俱乐部设置'),connected()
  ?demoNote('已连接后端：能力开通为只读展示，实际开通请在服务端配置。','只读展示')
  :demoNote('开关只在本机浏览器预览，不会改变后端能力；所有模块凭据均为示例数据。','示例数据 · 仅预览'));
 if(!features.length){root.append(el('div',{class:'empty-state'},el('span',{class:'empty-symbol'},icon('features')),el('p',{},'当前后端未返回可开通模块；未连接时可查看示例清单。')));return root;}
 const enabled=features.filter(feature=>feature.enabled).length;
 root.append(metrics([['可开通模块',features.length,'俱乐部能力清单'],['已开通',enabled,'当前预览状态'],['推荐开通',features.filter(feature=>feature.recommended).length,'优先配置'],['待开通',features.length-enabled,'可随时预览']]));
 const groups=new Map();for(const feature of features){if(!groups.has(feature.category))groups.set(feature.category,[]);groups.get(feature.category).push(feature);}
 for(const [category,items]of groups){
  root.append(el('section',{class:'feature-group'},el('div',{class:'feature-group-head'},el('h2',{},category),el('span',{},`${items.filter(item=>item.enabled).length}/${items.length} 已开通`)),el('div',{class:'feature-grid'},items.map(featureCard))));
 }
 return root;
}

function renderSettlements(){
 const summary=data.settlements,selected=new Set();
 const recordButton=button('记录转账凭据',()=>recordSettlement([...selected]),'dark',true);
 const body=el('tbody',{},summary.entries.map(entry=>{
  const check=el('input',{type:'checkbox','aria-label':`选择 ${player(entry.playerId)?.name||entry.playerId} 的结算条目`,disabled:!connected()||entry.state!=='available',onchange:event=>{if(event.target.checked)selected.add(entry.id);else selected.delete(entry.id);recordButton.disabled=!selected.size;recordButton.textContent=selected.size?`记录 ${selected.size} 笔凭据`:'记录转账凭据';}});
  return el('tr',{},el('td',{},check),el('td',{},player(entry.playerId)?.name||entry.playerId),el('td',{},el('button',{class:'table-action',onclick:()=>openOrder(entry.orderId)},`#${shortId(entry.orderId)}`)),el('td',{class:'table-money'},money(entry.grossCents)),el('td',{class:'table-money'},money(entry.memberCents)),el('td',{},badge(ledgerLabels[entry.state]||entry.state,entry.state)),el('td',{},dateTime(entry.availableAt||entry.createdAt)));
 }));
 const table=el('table',{class:'ops-table'},el('thead',{},el('tr',{},['','成员','订单','订单金额','成员收入','状态','时间'].map(t=>el('th',{},t)))),body);
 return el('div',{},header('收入与结算',button('导出 CSV',exportSettlements,'soft',!connected())),metrics([['待结算',money(summary.totals.availableCents)],['冻结中',money(summary.totals.heldCents)],['已记录',money(summary.totals.settledCents)],['已冲回',money(summary.totals.reversedCents)]]),panel('成员收入',el('div',{class:'ops-table-wrap'},summary.entries.length?table:empty('暂无收入条目')),recordButton),panel('转账凭据',summary.settlements.length?el('div',{class:'receipt-list'},summary.settlements.map(row=>el('article',{class:'receipt-row'},el('div',{},el('strong',{},row.paymentReference),el('p',{},row.note||`${row.entryIds.length} 笔收入`)),el('div',{},el('strong',{},money(row.memberCents)),el('time',{},dateTime(row.createdAt)))))):empty('尚未记录凭据')));
}
function renderDisputes(){return el('div',{},header('售后处理'),data.disputes.length?el('div',{class:'dispute-list'},data.disputes.map(o=>el('article',{class:'dispute-card'},el('div',{class:'dispute-heading'},el('div',{},el('h2',{},o.dispute?.reason||'待处理争议'),el('p',{class:'muted'},o.serviceTitle,` · #${shortId(o.id)}`)),statusBadge(o)),el('p',{},o.dispute?.details||'未填写补充说明'),el('div',{class:'dispute-footer'},el('span',{class:'muted'},dateTime(o.dispute?.createdAt)),button('查看与处理',()=>openOrder(o.id),'dark'))))):empty('当前没有待处理售后'));}
function renderBrand(){
 const club=data.club;
 return el('div',{},header('品牌与发布',el('a',{class:'action dark',href:'/studio/'},'打开品牌工作室 ↗')),el('section',{class:'brand-panel'},el('div',{class:'brand-identity'},el('img',{src:safeImage(club.logoUrl)||'/icon.svg',alt:''}),el('div',{},el('h2',{},club.name),el('p',{},club.tagline))),el('dl',{class:'detail-facts'},fact('品牌简称',club.shortName),fact('经营主体',club.legalEntity),fact('客服',club.supportContact),fact('品牌来源',club.configManaged?'配置文件 · 只读':'后端资料'),fact('配置版本',club.configHash?club.configHash.slice(0,16):'—'),fact('当前模式',club.demoData?'演示':'正式')),el('div',{class:'legal-grid'},el('details',{},el('summary',{},'隐私政策'),el('p',{},club.privacyText||'尚未填写')),el('details',{},el('summary',{},'服务协议'),el('p',{},club.termsText||'尚未填写')))),el('div',{class:'brand-links'},el('a',{href:'/guide/10-single-config-workflow.html'},'品牌配置与发布手册 ↗'),el('a',{href:'/demo/'},'打开客户端 ↗')));
}
function renderConnection(){
 const form=el('form',{class:'connection-panel'}),url=el('input',{type:'url',name:'api',required:true,placeholder:'https://api.example.com/api/v1',value:apiBase||'','aria-label':'API 地址'}),token=el('input',{type:'password',name:'token',required:true,autocomplete:'off',placeholder:'ADMIN_TOKEN','aria-label':'管理员令牌'});
 const error=el('p',{class:'error',role:'alert'}),submit=el('button',{type:'submit',class:'action dark'},connected()?'重新连接':'连接');
 form.append(el('h2',{},'连接俱乐部'),el('div',{class:'ops-fields'},field('API 地址',url),field('管理员令牌',token)),el('p',{class:'input-note'},'令牌仅保留在当前页面内存中。'),error,el('div',{class:'connection-actions'},submit,connected()?button('断开连接',async()=>{adminToken='';apiBase='';currentOrderId=null;$('#order-drawer').close();await refresh().catch(()=>{});},'soft'):null));
 form.onsubmit=async event=>{event.preventDefault();submit.disabled=true;const previous={apiBase,adminToken};try{const nextBase=apiAddress(url.value.trim()),nextToken=token.value.trim();if(!/^[A-Za-z0-9_-]{24,}$/.test(nextToken))throw Error('管理员令牌须为至少 24 位的 base64url 字符。');apiBase=nextBase;adminToken=nextToken;await refresh();token.value='';notify('已连接俱乐部。');}catch(e){apiBase=previous.apiBase;adminToken=previous.adminToken;error.textContent=e.message;}finally{submit.disabled=false;}};
 const states=[['database','数据库'],['admin','后台鉴权'],['catalogReady','经营资料'],['wechatMiniAuth','小程序微信登录'],['wechatNativeAuth','App 微信登录'],['wechatMiniPay','小程序支付'],['wechatNativePay','App 支付']];
 return el('div',{},header('连接与集成'),form,panel('服务状态',el('div',{class:'integration-list'},states.map(([key,label])=>el('div',{class:'integration-item'},el('span',{},label),badge(!connected()?'未连接':data.config?.[key]?'已配置':'未配置',connected()&&data.config?.[key]?'completed':'neutral'))))));
}

function openOrder(id){currentOrderId=id;renderOrder(id);if(!$('#order-drawer').open)$('#order-drawer').showModal();}
function renderOrder(id){
 const order=data.orders.find(o=>o.id===id);if(!order)return;$('#drawer-title').textContent=`订单 #${shortId(id)}`;
 const actions=el('div',{class:'drawer-actions'});
 if(['awaiting_assignment','awaiting_acceptance','scheduled'].includes(order.fulfillmentStatus))actions.append(button(order.assignedPlayerId?'改派成员':'安排成员',()=>assign(order),'dark',!connected()));
 if(order.fulfillmentStatus==='disputed')actions.append(button('处理售后',()=>resolveDispute(order),'dark',!connected()));
 if(!order.demo&&['pending','paid','refunding'].includes(order.paymentStatus))actions.append(button('同步支付状态',()=>mutate(`/admin/orders/${id}/payment-sync`,{},'支付状态已同步。'),'soft',!connected()));
 if(!order.demo&&order.paymentStatus==='paid'&&!order.refundStatus&&order.fulfillmentStatus!=='disputed')actions.append(button('申请全额退款',()=>refund(order),'soft',!connected()));
 if(['awaiting_payment','awaiting_assignment','awaiting_acceptance','scheduled'].includes(order.fulfillmentStatus))actions.append(button('取消订单',()=>cancelOrder(order),'plain',!connected()));
 const snapshot=order.serviceSnapshot||{};
 const detail=el('div',{},el('section',{class:'drawer-section'},el('div',{class:'drawer-title-row'},statusBadge(order),el('strong',{class:'drawer-price'},money(order.priceCents))),el('h3',{class:'drawer-service'},order.serviceTitle),snapshot.variantTitle?el('p',{},snapshot.variantTitle):null,el('dl',{class:'detail-facts'},fact('预约时间',dateTime(order.scheduledAt)),fact('服务时长',`${order.durationMinutes} 分钟`),fact('成员',player(order.assignedPlayerId)?.name||'待分配'),fact('付款',order.demo?'演示 · 未付款':paymentLabels[order.paymentStatus]||order.paymentStatus),fact('联系方式',order.contact),fact('备注',order.note||'—'),order.commissionBps!==null?fact('俱乐部抽成',`${(order.commissionBps||0)/100}%`):null,order.memberCents!==null?fact('成员收入',money(order.memberCents)):null),actions));
 if(order.dispute)detail.append(el('section',{class:'drawer-section'},el('h3',{},'售后'),el('strong',{},order.dispute.reason),el('p',{class:'dispute-copy'},order.dispute.details||''),order.dispute.resolution?el('p',{},order.dispute.resolution):null));
 if(order.delivery){const evidence=safeImage(order.delivery.evidenceUrl);detail.append(el('section',{class:'drawer-section'},el('h3',{},'交付记录'),el('p',{class:'delivery-copy'},order.delivery.summary),evidence?el('a',{href:evidence,target:'_blank',rel:'noopener noreferrer'},'查看交付附件 ↗'):null));}
 if(order.review)detail.append(el('section',{class:'drawer-section'},el('h3',{},'客户评价'),el('strong',{},`${order.review.rating} / 5`),el('p',{},order.review.comment||'无文字评价')));
 detail.append(el('section',{class:'drawer-section'},el('h3',{},'履约记录'),el('ol',{class:'timeline'},(order.events||[]).map(event=>el('li',{class:'timeline-item'},el('div',{},el('strong',{},event.actor?.name||event.actor?.role||'系统'),el('time',{},dateTime(event.at))),el('p',{},event.message))))));
 $('#drawer-content').replaceChildren(detail);
}
function showAction({title,fields=[],note='',submit='确认',run}){
 $('#action-title').textContent=title;$('#action-fields').replaceChildren(...fields);$('#action-note').textContent=note;$('#action-note').hidden=!note;$('#action-error').textContent='';$('#action-submit').textContent=submit;$('#action-submit').hidden=!run;actionSubmit=run;if(!$('#action-dialog').open)$('#action-dialog').showModal();
}
async function mutate(path,body,message,method='POST'){
 if(!connected())throw Error('示例工作台为只读。');await request(path,{method,body:JSON.stringify(body)});await refresh();notify(message);
}
function assign(order){
 if(!connected())return;const service=data.services.find(s=>s.id===order.serviceId),eligible=data.players.filter(p=>!p.archived&&p.status!=='paused'&&(!service?.game||p.games?.includes(service.game)));
 const select=el('select',{name:'playerId',required:true},el('option',{value:''},'选择成员'),eligible.map(p=>el('option',{value:p.id},p.name)));select.value=order.assignedPlayerId||'';
 const commission=el('input',{type:'number',name:'commission',min:0,max:100,step:0.01,value:(order.commissionBps??2000)/100,required:true});
 const reason=el('textarea',{name:'reason',rows:3,required:Boolean(order.assignedPlayerId),maxlength:1000});
 showAction({title:order.assignedPlayerId?'改派成员':'安排成员',fields:[field('成员',select),field('俱乐部抽成 / %',commission),field(order.assignedPlayerId?'改派原因':'派单备注',reason)],note:`预约 ${dateTime(order.scheduledAt)} · ${order.durationMinutes} 分钟，服务器将检查排班与冲突。`,submit:'确认派单',run:async()=>mutate(`/admin/orders/${order.id}/assign`,{playerId:select.value,commissionBps:Math.round(Number(commission.value)*100),reason:reason.value.trim()},'已派单，等待成员接单。')});
}
function resolveDispute(order){const outcome=el('select',{name:'outcome'},el('option',{value:'resume'},'恢复履约'),el('option',{value:'refund'},'全额退款')),reason=el('textarea',{name:'reason',required:true,rows:4,maxlength:1000});showAction({title:'处理售后',fields:[field('处理方式',outcome),field('处理说明',reason)],note:order.demo?'演示退款不会转移资金。':'退款结果以微信确认状态为准。',submit:'提交处理',run:()=>mutate(`/admin/orders/${order.id}/resolve`,{outcome:outcome.value,reason:reason.value.trim()},'售后处理已提交。')});}
function refund(order){const reason=el('textarea',{name:'reason',required:true,rows:3,maxlength:80});showAction({title:`全额退款 ${money(order.priceCents)}`,fields:[field('退款原因',reason)],note:'提交后将向微信商户接口申请退款。',submit:'申请退款',run:()=>mutate(`/admin/orders/${order.id}/refund`,{reason:reason.value.trim()},'退款申请已提交，请核对状态。')});}
function cancelOrder(order){showAction({title:'取消订单',note:`${order.serviceTitle} · ${dateTime(order.scheduledAt)}`,submit:'确认取消',run:()=>mutate(`/admin/orders/${order.id}`,{status:'cancelled'},'订单状态已更新。','PATCH')});}
async function availability(p){
 if(!connected())return;
 try{
  const result=await request(`/admin/players/${encodeURIComponent(p.id)}/availability`),list=el('div',{class:'slot-list full-width'});
  const addSlot=(slot={})=>{const start=el('input',{type:'datetime-local',required:true,'aria-label':'开始时间',value:slot.startAt?shanghaiInput(slot.startAt):''}),end=el('input',{type:'datetime-local',required:true,'aria-label':'结束时间',value:slot.endAt?shanghaiInput(slot.endAt):''});const row=el('div',{class:'slot-row'},start,el('span',{},'至'),end,button('移除',()=>row.remove(),'plain'));row.dataset.slot='';list.append(row);};
  result.slots.forEach(addSlot);
  const add=button('＋ 添加时段',()=>addSlot(),'soft');add.type='button';
  showAction({title:`${p.name} · 排班`,fields:[list,add],note:'上海时间；保存将替换全部时段，已预约时段须保留。',submit:'保存排班',run:async()=>{const slots=[...list.querySelectorAll('[data-slot]')].map(row=>{const inputs=row.querySelectorAll('input');return {startAt:fromShanghaiInput(inputs[0].value),endAt:fromShanghaiInput(inputs[1].value)};});await request(`/admin/players/${encodeURIComponent(p.id)}/availability`,{method:'PUT',body:JSON.stringify({slots})});notify('排班已保存。');}});
 }catch(e){notify(e.message,true);}
}
function invitation(p){
 showAction({title:`邀请 ${p.name}`,note:'生成后，由成员在登录客户端中接受邀请。',submit:'生成邀请码',run:async()=>{
  const result=await request(`/admin/players/${encodeURIComponent(p.id)}/invitation`,{method:'POST',body:'{}'});
  setTimeout(()=>showAction({title:'成员邀请码',fields:[el('output',{class:'invitation-code'},result.code)],note:`有效至 ${dateTime(result.expiresAt)}，仅可使用一次。`}),0);
 }});
}
function recordSettlement(entryIds){
 const entries=data.settlements.entries.filter(e=>entryIds.includes(e.id)),reference=el('input',{name:'reference',required:true,maxlength:200}),note=el('textarea',{name:'note',rows:3,maxlength:1000});
 showAction({title:`记录 ${money(entries.reduce((sum,e)=>sum+e.memberCents,0))} 转账凭据`,fields:[field('外部转账凭据号',reference),field('备注',note)],note:'请先完成并核对外部转账。此操作仅记账，不会打款。',submit:'保存凭据',run:()=>mutate('/admin/settlements',{entryIds,paymentReference:reference.value.trim(),note:note.value.trim()},'转账凭据已记录。')});
}
async function exportSettlements(){try{const blob=await request('/admin/settlements/export.csv',{csv:true}),url=URL.createObjectURL(blob),link=el('a',{href:url,download:'openni-settlements.csv'});document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);}catch(e){notify(e.message,true);}}
function expirePayments(){showAction({title:'清理超时未付订单',note:'处理超过 30 分钟的未付款订单。已发起支付的订单将先向微信核验并关单。',submit:'开始处理',run:async()=>{const result=await request('/admin/orders/expire-unpaid',{method:'POST',body:'{}'});await refresh();const failures=result.results.filter(r=>r.error);notify(`已处理 ${result.results.length-failures.length} 笔${failures.length?`，${failures.length} 笔待重试`:''}。`,Boolean(failures.length));}});}

$('#action-form').onsubmit=async event=>{event.preventDefault();if(!actionSubmit)return;const submit=$('#action-submit');submit.disabled=true;try{const run=actionSubmit;await run();$('#action-dialog').close();}catch(e){$('#action-error').textContent=e.message;}finally{submit.disabled=false;}};
$('#close-action').onclick=$('#cancel-action').onclick=()=>$('#action-dialog').close();
$('#close-order').onclick=()=>$('#order-drawer').close();$('#order-drawer').addEventListener('close',()=>{currentOrderId=null;});
document.querySelectorAll('[data-workspace],[data-section]').forEach(node=>node.onclick=()=>{if(node.dataset.section==='services')content.clearServiceFilter();navigate(node.dataset.workspace||node.dataset.section);});
$('#open-connection').onclick=$('#connect-banner').onclick=()=>navigate('connection');
$('#refresh-all').onclick=()=>{notify('');refresh().catch(()=>{});};
$('#ops-menu').onclick=()=>setMenu(!$('.ops-sidebar').classList.contains('open'));
window.addEventListener('keydown',event=>{if(event.key==='Escape')setMenu(false);});
syncMenu();
window.addEventListener('pagehide',()=>{adminToken='';});
refresh().catch(()=>{});
