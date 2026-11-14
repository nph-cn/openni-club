import {el,money,dateTime,safeImage,apiAddress,shanghaiInput,fromShanghaiInput,fulfillmentLabels as statuses,ledgerLabels,paymentLabels} from './ui.js';
import {contentManager} from './content.js';

const $=selector=>document.querySelector(selector);
const titles={overview:'今日待办',dispatch:'派单工作台',orders:'全部订单',members:'成员与排班',settlements:'收入与结算',disputes:'售后处理',brand:'品牌与发布',connection:'连接与集成',services:'服务目录',announcements:'俱乐部公告'};
let data={orders:[],players:[],services:[],announcements:[],club:{},overview:{counts:{},totals:{}},settlements:{entries:[],totals:{},settlements:[]},disputes:[]};
let workspace='overview',apiBase='',adminToken='',orderFilter='all',orderSearch='',currentOrderId=null,actionSubmit=null,loadVersion=0;
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
const empty=text=>el('div',{class:'empty-state'},el('span',{class:'empty-symbol'},'✓'),text);
const header=(title,action)=>el('div',{class:'ops-page-header'},el('h1',{},title),action||null);
const panel=(title,body,action)=>el('section',{class:'ops-panel'},el('div',{class:'panel-header'},el('h2',{},title),action||null),body);
const field=(label,input)=>el('label',{class:'ops-field'},el('span',{},label),input);
const fact=(label,value)=>el('div',{},el('dt',{},label),el('dd',{},value??'—'));
const notify=(text,error=false)=>{const node=$('#global-message');node.textContent=text;node.hidden=!text;node.className=error?'error':'';};

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
   const paths={overview:'/admin/overview',orders:'/admin/orders',players:'/admin/players',services:'/admin/services',announcements:'/admin/announcements',club:'/admin/club',settlements:'/admin/settlements',disputes:'/admin/disputes',config:'/admin/config/status'};
   const results=await Promise.all(Object.entries(paths).map(async([key,path])=>[key,await request(path)]));next=Object.fromEntries(results);
  }else{const response=await fetch('/admin/demo-snapshot.json',{cache:'no-store'});if(!response.ok)throw Error('示例数据暂时无法读取。');next=await response.json();}
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
 $('#mode-label').textContent=connected()?(data.config?.demo?'演示后端':'已连接'):'只读示例';
 $('#mode-label').classList.toggle('live',connected()&&!data.config?.demo);
 $('#open-connection').textContent=connected()?'连接设置':'连接俱乐部';$('#preview-banner').hidden=connected();
 $('#dispatch-count').textContent=data.overview.counts.awaitingAssignment||0;$('#dispute-count').textContent=data.overview.counts.disputed||0;
 document.querySelectorAll('[data-workspace],[data-section]').forEach(node=>{const active=(node.dataset.workspace||node.dataset.section)===workspace;node.classList.toggle('selected',active);node.setAttribute('aria-current',active?'page':'false');});
 const isContent=['services','announcements'].includes(workspace);$('#content-panel').hidden=!isContent;$('#orders-panel').hidden=isContent;
 if(isContent){content.show(workspace);return;}
 const views={overview:renderOverview,dispatch:renderDispatch,orders:renderOrders,members:renderMembers,settlements:renderSettlements,disputes:renderDisputes,brand:renderBrand,connection:renderConnection};
 $('#ops-content').replaceChildren(views[workspace]());
}
function metrics(items){return el('div',{class:'metrics'},items.map(([label,value,foot,fn])=>el(fn?'button':'div',{class:'metric',...(fn?{onclick:fn}:{})},el('span',{class:'metric-label'},label),el('strong',{class:'metric-value'},value),foot?el('span',{class:'metric-footer'},foot):null)));}
function orderTitle(order){return el('div',{class:'table-main'},order.serviceTitle,el('span',{class:'table-sub'},`#${shortId(order.id)}${order.serviceSnapshot?.variantTitle?` · ${order.serviceSnapshot.variantTitle}`:''}`));}
function renderOverview(){
 const counts=data.overview.counts,totals=data.overview.totals;
 const rows=[['待派单',counts.awaitingAssignment,'dispatch'],['待接单',counts.awaitingAcceptance,'dispatch'],['服务中',counts.inProgress,'orders'],['待客户确认',counts.awaitingConfirmation,'orders'],['待处理售后',counts.disputed,'disputes']];
 const queue=el('div',{class:'queue-list'},rows.map(([label,count,tab],index)=>el('button',{class:'queue-row',onclick:()=>navigate(tab)},el('span',{class:'queue-icon'},['↗','◷','▷','✓','!'][index]),el('span',{class:'queue-text'},label),el('strong',{class:'queue-number'},count||0),el('span',{class:'row-arrow'},'→'))));
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
function renderMembers(){
 return el('div',{},header('成员与排班',connected()?button('新增成员',()=>content.editMember(null),'dark'):null),el('div',{class:'member-grid'},data.players.map(p=>{
  const active=data.orders.filter(o=>o.assignedPlayerId===p.id&&!['completed','cancelled'].includes(o.fulfillmentStatus)).length;
  return el('article',{class:'member-card'},el('div',{class:'member-card-head'},avatar(p),el('div',{},el('h2',{},p.name),el('p',{},p.role)),p.archived?badge('已归档'):null),el('div',{class:'member-games'},(p.games||[]).map(g=>badge(g))),el('dl',{class:'member-facts'},fact('当前订单',active),fact('成员账号',p.boundUserId?'已绑定':'未绑定')),el('div',{class:'member-card-actions'},button('排班',()=>availability(p),'soft',!connected()),button('资料',()=>content.editMember(p),'plain'),!p.boundUserId?button('邀请',()=>invitation(p),'plain',!connected()):null));
 })));
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
 if(!connected())return;const service=data.services.find(s=>s.id===order.serviceId),eligible=data.players.filter(p=>!p.archived&&(!service?.game||p.games?.includes(service.game)));
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

$('#action-form').onsubmit=async event=>{event.preventDefault();if(!actionSubmit||!connected())return;const submit=$('#action-submit');submit.disabled=true;try{const run=actionSubmit;await run();$('#action-dialog').close();}catch(e){$('#action-error').textContent=e.message;}finally{submit.disabled=false;}};
$('#close-action').onclick=$('#cancel-action').onclick=()=>$('#action-dialog').close();
$('#close-order').onclick=()=>$('#order-drawer').close();$('#order-drawer').addEventListener('close',()=>{currentOrderId=null;});
document.querySelectorAll('[data-workspace],[data-section]').forEach(node=>node.onclick=()=>navigate(node.dataset.workspace||node.dataset.section));
$('#open-connection').onclick=$('#connect-banner').onclick=()=>navigate('connection');
$('#refresh-all').onclick=()=>{notify('');refresh().catch(()=>{});};
$('#ops-menu').onclick=()=>setMenu(!$('.ops-sidebar').classList.contains('open'));
window.addEventListener('keydown',event=>{if(event.key==='Escape')setMenu(false);});
syncMenu();
window.addEventListener('pagehide',()=>{adminToken='';});
refresh().catch(()=>{});
