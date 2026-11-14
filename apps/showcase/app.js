const $ = selector => document.querySelector(selector);
const names = {platform:{flutter:'iOS / Android',mini:'微信小程序',admin:'运营后台'},role:{customer:'客户',member:'成员',operator:'运营'},flow:{discover:'发现与了解',booking:'预约与付款',fulfillment:'履约与售后',member:'成员工作台',account:'资料与设置'}};
let screens = [], platform = 'flutter', role = 'all', flow = 'all', query = '', favoriteOnly = false, view = 'screens', currentId = '';
let favorites; try { favorites = new Set(JSON.parse(localStorage.getItem('openni:favorites') || '[]')); } catch { favorites = new Set(); }
const dialog = $('#detail');
const node = (tag,text,className) => { const item=document.createElement(tag);if(text!==undefined)item.textContent=text;if(className)item.className=className;return item; };
function matched() { return screens.filter(screen=>screen.platform===platform&&(role==='all'||screen.role===role)&&(flow==='all'||screen.flow===flow)&&(!favoriteOnly||favorites.has(screen.id))&&`${screen.title} ${screen.description} ${names.flow[screen.flow]||''}`.toLowerCase().includes(query.toLowerCase())); }
function screenImage(screen) { const img=node('img');img.src=screen.image;img.alt=`${names.platform[screen.platform]} · ${screen.title}真实运行界面`;img.width=screen.width||390;img.height=screen.height||844;img.loading='lazy';return img; }
function render() {
 const shown=matched();$('#result-count').textContent=`${shown.length} 个界面`;$('#favorites span').textContent=favorites.size;$('#gallery').replaceChildren();$('#flow-gallery').replaceChildren();$('#gallery').hidden=view!=='screens';$('#flow-gallery').hidden=view!=='flows';$('#empty').hidden=shown.length>0;$('#gallery').classList.toggle('desktop',platform==='admin');
 $('#view-heading').replaceChildren(node('span',view==='flows'?'完整流程':favoriteOnly?'我的收藏':'界面图库','heading-text'),Object.assign(node('span',String(screens.length)),{id:'total-count'}));
 const filters=[role!=='all'?names.role[role]:null,flow!=='all'?names.flow[flow]:null,query?`“${query}”`:null,favoriteOnly?'已收藏':null].filter(Boolean);$('#active-filters').hidden=!filters.length;$('#filter-summary').textContent=filters.join(' / ');
 if(view==='flows'){renderFlows(shown);return;}
 for(const screen of shown){
  const article=node('article',undefined,'screen-card'),open=node('button',undefined,'screen-open'),mat=node('div',undefined,'screen-mat');
  open.setAttribute('aria-label',`查看${screen.title}截图与详情`);mat.append(screenImage(screen));open.append(mat);open.onclick=()=>show(screen);
  const caption=node('div',undefined,'screen-caption'),text=node('div');text.append(node('h3',screen.title),node('p',`${names.role[screen.role]||'客户'} · ${names.flow[screen.flow]||'产品界面'}`));
  const bookmark=node('button',undefined,'bookmark'+(favorites.has(screen.id)?' saved':''));bookmark.setAttribute('aria-label',`${favorites.has(screen.id)?'取消收藏':'收藏'}${screen.title}`);bookmark.setAttribute('aria-pressed',String(favorites.has(screen.id)));bookmark.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 4h12v17l-6-4-6 4z"/></svg>';bookmark.onclick=()=>{favorites.has(screen.id)?favorites.delete(screen.id):favorites.add(screen.id);try{localStorage.setItem('openni:favorites',JSON.stringify([...favorites]));}catch{}render();};
  caption.append(text,bookmark);article.append(open,caption);$('#gallery').append(article);
 }
}
function renderFlows(shown){
 const journeys=[{name:'选服务与成员',keys:['home','services','players','player','service']},{name:'下单',keys:['service','service_120','booking','checkout','order']},{name:'履约与售后',keys:['orders','order','support']},{name:'成员工作台',keys:['member','member_orders','member_order','delivery','availability','earnings','member_notifications']},{name:'派单与结算',keys:['admin-overview','admin-dispatch','admin-order','admin-disputes','admin-settlements']},{name:'品牌与资料',keys:['profile','settings','notifications','announcements','admin-club','admin-services','admin-players','admin-announcements','admin-connection']}];
 for(const journey of journeys){const items=journey.keys.flatMap(id=>shown.filter(s=>s.id===id||s.id===`mini-${id}`));if(!items.length)continue;const section=node('section',undefined,'flow-item'),head=node('header');head.append(node('h3',journey.name),node('span',`${items.length} 个界面`));const row=node('div',undefined,'flow-screens');for(const [index,screen] of items.entries()){const button=node('button',undefined,'flow-screen');button.append(screenImage(screen),node('span',`${String(index+1).padStart(2,'0')}  ${screen.title}`));button.onclick=()=>show(screen);row.append(button);}section.append(head,row);$('#flow-gallery').append(section);}
}
function show(screen){
 currentId=screen.id;$('#detail-title').textContent=screen.title;$('#detail-desc').textContent=screen.description;$('#detail-role').textContent=`${names.role[screen.role]||'客户'}体验`;
 $('#detail-platform').textContent=names.platform[screen.platform];$('#detail-state').textContent=({available:'服务详情',discovery:'首页',profile:'成员档案',in_progress:'服务中',pending:'待处理',demo:'演示',empty:'空状态',ready:'已就绪'}[screen.state]||'运行截图');$('#detail-flow').textContent=names.flow[screen.flow]||'产品界面';
 const source=screen.source||'apps/mobile/lib/screens.dart';$('#detail-source').replaceChildren(Object.assign(node('a',source+' ↗'),{href:'https://github.com/nph-cn/openni-club/blob/main/'+source,target:'_blank',rel:'noreferrer'}));
 $('#detail-img').src=screen.image;$('#detail-img').alt=screen.title;$('#detail-demo').href=screen.demo||(screen.platform==='admin'?'/admin/':screen.platform==='mini'?'/guide/05-wechat-release.html':`/demo/?screen=${encodeURIComponent(screen.id)}`);$('#detail-demo').textContent=screen.platform==='mini'?'查看小程序运行方式 ↗':'打开交互演示 ↗';$('#detail-download').href=screen.image;dialog.classList.toggle('wide-detail',screen.platform==='admin');
 const list=matched(),index=list.findIndex(s=>s.id===screen.id);$('#detail-position').textContent=`${index+1} / ${list.length}`;$('#previous-screen').disabled=index<=0;$('#next-screen').disabled=index>=list.length-1;
 if(!dialog.open)dialog.showModal();
}
function next(offset){const list=matched(),index=list.findIndex(s=>s.id===currentId);if(list[index+offset])show(list[index+offset]);}
$('#close-detail').onclick=()=>dialog.close();$('#previous-screen').onclick=()=>next(-1);$('#next-screen').onclick=()=>next(1);dialog.addEventListener('keydown',event=>{if(event.key==='ArrowLeft')next(-1);if(event.key==='ArrowRight')next(1);});dialog.onclick=event=>{if(event.target===dialog)dialog.close();};
function buttons(key,value){document.querySelectorAll(`[data-${key}]`).forEach(button=>button.classList.toggle('selected',button.dataset[key]===value));}
document.querySelectorAll('[data-platform]').forEach(button=>button.onclick=()=>{platform=button.dataset.platform;if(role!=='all'&&!screens.some(screen=>screen.platform===platform&&screen.role===role)){role='all';$('#role-filter').value=role;}buttons('platform',platform);render();});
function setRole(value){role=value;if(role==='operator')platform='admin';else if(role==='member'&&platform==='admin')platform='flutter';$('#role-filter').value=role;buttons('platform',platform);render();}
$('#role-filter').onchange=event=>setRole(event.target.value);
$('#flow-filter').onchange=event=>{flow=event.target.value;render();};
document.querySelectorAll('[data-explore-role]').forEach(link=>link.onclick=()=>{flow='all';$('#flow-filter').value=flow;setRole(link.dataset.exploreRole);});
document.querySelectorAll('[data-view]').forEach(button=>button.onclick=()=>{view=button.dataset.view;favoriteOnly=false;$('#favorites').classList.remove('selected');buttons('view',view);render();});
$('#favorites').onclick=()=>{favoriteOnly=!favoriteOnly;view='screens';$('#favorites').classList.toggle('selected',favoriteOnly);buttons('view',favoriteOnly?'':view);render();};
$('#search').oninput=event=>{query=event.target.value.trim();render();};
function reset(){role='all';flow='all';query='';favoriteOnly=false;$('#search').value='';$('#favorites').classList.remove('selected');$('#role-filter').value=role;$('#flow-filter').value=flow;buttons('view',view);render();}
$('#reset').onclick=reset;$('#reset-empty').onclick=reset;
document.addEventListener('keydown',event=>{if(event.key==='/'&&!/INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName)&&!dialog.open){event.preventDefault();$('#search').focus();}});
try{const response=await fetch('/screens.json');if(!response.ok)throw Error();screens=await response.json();for(const button of document.querySelectorAll('[data-platform]')){const count=screens.filter(s=>s.platform===button.dataset.platform).length;button.hidden=!count;button.querySelector('span').textContent=count;}render();}catch{$('#empty').hidden=false;$('#empty h3').textContent='截图目录暂时未加载';$('#empty p').textContent='请刷新页面重试。';}

// Role changes show actual runtime captures; no invented dashboard or payment state.
const stageRoles={
 customer:{image:'/screens/home.png',alt:'北岸电竞玩家首页真实运行截图',caption:'一起上场',steps:['选服务','约成员','确认订单'],browse:'浏览玩家界面',demo:'/demo/'},
 member:{image:'/screens/member.png',alt:'北岸电竞成员工作台真实运行截图',caption:'把每一场，配合好',steps:['确认接单','开始服务','提交交付'],browse:'浏览成员界面',demo:'/demo/?screen=member'},
 operator:{image:'/screens/admin-dispatch.png',alt:'北岸电竞运营派单工作台真实运行截图',caption:'每一单，都有着落',steps:[],browse:'浏览运营界面',demo:'/admin/'}
};
const reduceMotion=matchMedia('(prefers-reduced-motion: reduce)');
let stageRequest=0;
async function setStage(key){
 const config=stageRoles[key];if(!config)return;
 const request=++stageRequest,image=new Image();image.src=config.image;
 try{await image.decode();}catch{return;}
 if(request!==stageRequest)return;
 const target=$('#stage-image');target.src=config.image;target.alt=config.alt;
 $('#product-stage').dataset.role=key;$('#stage-caption').textContent=config.caption;
 $('#stage-steps').replaceChildren(...config.steps.map(text=>node('span',text)));
 $('#stage-launch').href=config.demo;$('#stage-browse').dataset.exploreRole=key;
 $('#stage-browse').replaceChildren(node('span',config.browse),node('span','↘'));
 $('#stage-panel').setAttribute('aria-labelledby',`role-${key}`);
 document.querySelectorAll('[data-stage-role]').forEach(button=>{const selected=button.dataset.stageRole===key;button.setAttribute('aria-selected',String(selected));button.tabIndex=selected?0:-1;});
 if(!reduceMotion.matches)$('#stage-panel').animate([{opacity:.25,transform:'translateY(12px)'},{opacity:1,transform:'translateY(0)'}],{duration:440,easing:'cubic-bezier(.22,.61,.36,1)'});
}
const roleTabs=[...document.querySelectorAll('[data-stage-role]')];
roleTabs.forEach((button,index)=>{button.onclick=()=>setStage(button.dataset.stageRole);button.onkeydown=event=>{let next;if(event.key==='ArrowRight'||event.key==='ArrowDown')next=(index+1)%roleTabs.length;else if(event.key==='ArrowLeft'||event.key==='ArrowUp')next=(index+roleTabs.length-1)%roleTabs.length;else if(event.key==='Home')next=0;else if(event.key==='End')next=roleTabs.length-1;else return;event.preventDefault();roleTabs[next].focus();setStage(roleTabs[next].dataset.stageRole);};});
if(!reduceMotion.matches){$('.hero-wordmark').animate([{opacity:0,transform:'translateY(22px)'},{opacity:1,transform:'translateY(0)'}],{duration:850,easing:'cubic-bezier(.22,.61,.36,1)'});}
