import {labels, stateGroup, matchScreens, groupFlows, parseLocation, gallerySearch} from './gallery-model.js';
const $ = selector => document.querySelector(selector);
const names = labels;
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
let screens = [], loadError = false, currentId = '';
let {platform, role, flow, state, query, view, screenId: initialScreen} = parseLocation(location.search);
let favoriteOnly = false;
let favorites;
try { const stored=JSON.parse(localStorage.getItem('openni:favorites') || '[]'); favorites=new Set(Array.isArray(stored)?stored:[]); }
catch { favorites = new Set(); }
const dialog = $('#detail');
const node = (tag, text, className) => { const item=document.createElement(tag); if(text!==undefined)item.textContent=text; if(className)item.className=className; return item; };
const filters = () => ({platform, role, flow, state, query, view, favoriteOnly});
const matched = () => matchScreens(screens, filters(), favorites);
function locationFor(screenId='') { return `${location.pathname}${gallerySearch(filters(),screenId)}${location.hash}`; }
function writeLocation(screenId='') { history.replaceState(null,'',locationFor(screenId)); }
function buttons(key,value) {
 document.querySelectorAll(`[data-${key}]`).forEach(button=>{ const selected=button.dataset[key]===value; button.classList.toggle('selected',selected); button.setAttribute('aria-pressed',String(selected)); });
}
function syncControls() {
 $('#role-filter').value=role; $('#flow-filter').value=flow; $('#state-filter').value=state; if(document.activeElement!==$('#search'))$('#search').value=query;
 buttons('platform',platform); buttons('view',favoriteOnly?'':view); $('#favorites').classList.toggle('selected',favoriteOnly); $('#favorites').setAttribute('aria-pressed',String(favoriteOnly));
}
function screenImage(screen) {
 const img=node('img'); img.alt=`${names.platform[screen.platform]} · ${screen.title}`; img.width=screen.width||390; img.height=screen.height||844; img.loading='lazy'; img.decoding='async'; img.dataset.loaded='false';
 img.onload=()=>img.dataset.loaded='true'; img.onerror=()=>{img.dataset.loaded='error';img.alt=`${screen.title} · 图片未加载`;}; img.src=screen.image; return img;
}
function render({sync=true}={}) {
 const shown=matched(); syncControls();
 $('#result-count').textContent=`${shown.length} 个界面`; $('#favorites span').textContent=favorites.size;
 $('#gallery').replaceChildren(); $('#flow-gallery').replaceChildren(); $('#gallery').hidden=view!=='screens'; $('#flow-gallery').hidden=view!=='flows';
 $('#empty').hidden=shown.length>0; $('#empty h3').textContent='没有找到这个界面'; $('#empty p').textContent='试试其他筛选条件。'; $('#reset-empty').textContent='清除筛选';
 $('#gallery').classList.toggle('desktop',platform==='admin');
 $('#view-heading').replaceChildren(node('span',view==='flows'?'完整流程':favoriteOnly?'我的收藏':'界面图库','heading-text'),Object.assign(node('span',String(screens.length)),{id:'total-count'}));
 const active=[role!=='all'?names.role[role]:null,flow!=='all'?names.flow[flow]:null,state!=='all'?names.state[state]:null,query?`“${query}”`:null,favoriteOnly?'已收藏':null].filter(Boolean);
 $('#active-filters').hidden=!active.length; $('#filter-summary').textContent=active.join(' / ');
 if(view==='flows') renderFlows(shown);
 else for(const screen of shown) {
  const article=node('article',undefined,'screen-card'),open=node('button',undefined,'screen-open'),mat=node('div',undefined,'screen-mat');
  open.setAttribute('aria-label',`查看${screen.title}截图与详情`); mat.append(screenImage(screen)); open.append(mat); open.onclick=()=>show(screen);
  const caption=node('div',undefined,'screen-caption'),text=node('div'); text.append(node('h3',screen.title));
  const group=stateGroup(screen); text.append(node('p',group==='ready'?(names.flow[screen.flow]||'产品界面'):names.state[group]));
  const bookmark=node('button',undefined,'bookmark'+(favorites.has(screen.id)?' saved':'')); bookmark.setAttribute('aria-label',`${favorites.has(screen.id)?'取消收藏':'收藏'}${screen.title}`); bookmark.setAttribute('aria-pressed',String(favorites.has(screen.id)));
  bookmark.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 4h12v17l-6-4-6 4z"/></svg>';
  bookmark.onclick=()=>{favorites.has(screen.id)?favorites.delete(screen.id):favorites.add(screen.id);try{localStorage.setItem('openni:favorites',JSON.stringify([...favorites]));}catch{}render();};
  caption.append(text,bookmark); article.append(open,caption); $('#gallery').append(article);
 }
 if(sync)writeLocation();
}
function renderFlows(shown) {
 for(const group of groupFlows(shown)) {
  const section=node('section',undefined,'flow-item'),head=node('header'); head.append(node('h3',group.name),node('span',`${group.screens.length} 个界面`));
  const row=node('div',undefined,'flow-screens'); row.setAttribute('role','group'); row.setAttribute('aria-label',group.name);
  for(const [index,screen] of group.screens.entries()) { const button=node('button',undefined,'flow-screen');button.setAttribute('aria-label',`查看${screen.title}截图与详情`);button.append(screenImage(screen),node('span',`${String(index+1).padStart(2,'0')}  ${screen.title}`));button.onclick=()=>show(screen);row.append(button); }
  section.append(head,row); $('#flow-gallery').append(section);
 }
}
function show(screen) {
 currentId=screen.id; $('#detail-title').textContent=screen.title; $('#detail-platform').textContent=names.platform[screen.platform];
 const group=stateGroup(screen); $('#detail-state').hidden=group==='ready'; $('#detail-state').textContent=names.state[group]; $('#detail-flow').textContent=names.flow[screen.flow]||'产品界面';
 const source=screen.source; $('#detail-source').replaceChildren(Object.assign(node('a',source+' ↗'),{href:'https://github.com/nph-cn/openni-club/blob/main/'+source,target:'_blank',rel:'noreferrer'}));
 const img=$('#detail-img'); img.hidden=false; $('#detail-image-error').hidden=true; img.alt=screen.title;
 img.onload=()=>{img.hidden=false;$('#detail-image-error').hidden=true;}; img.onerror=()=>{img.hidden=true;$('#detail-image-error').hidden=false;}; img.src=screen.image;
 $('#detail-demo').href=screen.demo||(screen.platform==='admin'?'/admin/':screen.platform==='mini'?'/guide/05-wechat-release.html':`/demo/?screen=${encodeURIComponent(screen.id)}`);
 $('#detail-demo').textContent=screen.platform==='mini'?'查看小程序运行方式 ↗':screen.platform==='admin'?'打开后台 ↗':'打开 App ↗'; $('#detail-download').href=screen.image;
 dialog.classList.toggle('wide-detail',screen.platform==='admin'); dialog.classList.remove('zoomed'); $('#toggle-zoom').textContent='放大'; $('#toggle-zoom').setAttribute('aria-label','放大截图'); $('#toggle-zoom').setAttribute('aria-pressed','false'); $('#copy-link').textContent='复制链接';
 const list=matched(),index=list.findIndex(s=>s.id===screen.id); $('#detail-position').textContent=`${index+1} / ${list.length}`; $('#previous-screen').disabled=index<=0; $('#next-screen').disabled=index>=list.length-1;
 if(!dialog.open)dialog.showModal(); $('.detail-body').scrollTop=0; $('.detail-stage').scrollTop=0; writeLocation(screen.id);
}
function next(offset) {const list=matched(),index=list.findIndex(s=>s.id===currentId);if(list[index+offset])show(list[index+offset]);}
$('#close-detail').onclick=()=>dialog.close(); dialog.addEventListener('close',()=>{currentId='';writeLocation();});
$('#previous-screen').onclick=()=>next(-1); $('#next-screen').onclick=()=>next(1);
dialog.addEventListener('keydown',event=>{if(event.key==='ArrowLeft'){event.preventDefault();next(-1);}if(event.key==='ArrowRight'){event.preventDefault();next(1);}});
dialog.addEventListener('click',event=>{if(event.target===dialog){const r=dialog.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)dialog.close();}});
$('#toggle-zoom').onclick=()=>{const zoomed=dialog.classList.toggle('zoomed');$('#toggle-zoom').textContent=zoomed?'适合屏幕':'放大';$('#toggle-zoom').setAttribute('aria-label',zoomed?'缩小至适合屏幕':'放大截图');$('#toggle-zoom').setAttribute('aria-pressed',String(zoomed));};
$('#copy-link').onclick=async()=>{try{const url=new URL(location.href);url.search=gallerySearch({platform},currentId);url.hash='gallery-region';await navigator.clipboard.writeText(url.href);$('#copy-link').textContent='已复制';}catch{$('#copy-link').textContent='请复制地址栏';}};
$('#retry-image').onclick=()=>{const screen=screens.find(s=>s.id===currentId);if(screen)show(screen);};
document.querySelectorAll('[data-platform]').forEach(button=>button.onclick=()=>{platform=button.dataset.platform;if(role!=='all'&&!screens.some(screen=>screen.platform===platform&&screen.role===role))role='all';render();});
function setRole(value) {role=value;if(role==='operator')platform='admin';else if(role==='member'&&platform==='admin')platform='flutter';render();}
$('#role-filter').onchange=event=>setRole(event.target.value); $('#flow-filter').onchange=event=>{flow=event.target.value;render();}; $('#state-filter').onchange=event=>{state=event.target.value;render();};
document.querySelectorAll('[data-explore-role]').forEach(link=>link.onclick=()=>{flow='all';state='all';query='';favoriteOnly=false;setRole(link.dataset.exploreRole);});
document.querySelectorAll('[data-view]').forEach(button=>button.onclick=()=>{view=button.dataset.view;favoriteOnly=false;render();});
$('#favorites').onclick=()=>{favoriteOnly=!favoriteOnly;view='screens';render();};
$('#search').oninput=event=>{query=event.target.value.trim();render();};
function reset() {role='all';flow='all';state='all';query='';favoriteOnly=false;render();}
$('#reset').onclick=reset; $('#reset-empty').onclick=()=>loadError?loadScreens():reset();
document.addEventListener('keydown',event=>{if(event.key==='/'&&!/INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName)&&!dialog.open){event.preventDefault();$('#search').focus();}});
async function loadScreens() {
 loadError=false; $('#gallery-loading').hidden=false; $('#empty').hidden=true; $('#gallery').setAttribute('aria-busy','true');
 try {
  const response=await fetch('/screens.json');if(!response.ok)throw Error('index');const data=await response.json();if(!Array.isArray(data))throw Error('index');
  screens=data;
  for(const button of document.querySelectorAll('[data-platform]')){const count=screens.filter(s=>s.platform===button.dataset.platform).length;button.hidden=!count;button.querySelector('span').textContent=count;}
  for(const item of document.querySelectorAll('[data-count-platform]'))item.textContent=screens.filter(s=>s.platform===item.dataset.countPlatform).length;
  const requested=screens.find(screen=>screen.id===initialScreen);if(requested){platform=requested.platform;if(!matched().includes(requested)){role='all';flow='all';state='all';query='';favoriteOnly=false;}}
  render();if(requested)show(requested);initialScreen='';
 } catch {loadError=true;$('#empty').hidden=false;$('#empty h3').textContent='界面目录未能加载';$('#empty p').textContent='';$('#reset-empty').textContent='重新加载';}
 finally {$('#gallery-loading').hidden=true;$('#gallery').setAttribute('aria-busy','false');}
}
syncControls(); await loadScreens();

// Role changes show actual runtime captures; no invented dashboard or payment state.
const stageRoles={
 customer:{image:'/screens/home.png',alt:'北岸电竞玩家首页真实运行截图',caption:'用户首页',browse:'查看用户端界面',demo:'/demo/'},
 member:{image:'/screens/member.png',alt:'北岸电竞成员工作台真实运行截图',caption:'成员工作台',browse:'查看成员端界面',demo:'/demo/?screen=member'},
 operator:{image:'/screens/admin-dispatch.png',alt:'北岸电竞运营派单工作台真实运行截图',caption:'派单工作台',browse:'查看后台界面',demo:'/admin/'}
};
let stageRequest=0;
async function setStage(key){
 const config=stageRoles[key];if(!config)return;
 const request=++stageRequest,image=new Image();image.src=config.image;
 try{await image.decode();}catch{return;}
 if(request!==stageRequest)return;
 const target=$('#stage-image');target.src=config.image;target.alt=config.alt;
 $('#product-stage').dataset.role=key;$('#stage-caption').textContent=config.caption;
 $('#stage-launch').href=config.demo;$('#stage-launch').textContent=key==='operator'?'打开后台 ↗':'打开 App ↗';$('#stage-browse').dataset.exploreRole=key;
 $('#stage-browse').replaceChildren(node('span',config.browse),node('span','↘'));
 $('#stage-panel').setAttribute('aria-labelledby',`role-${key}`);
 document.querySelectorAll('[data-stage-role]').forEach(button=>{const selected=button.dataset.stageRole===key;button.setAttribute('aria-selected',String(selected));button.tabIndex=selected?0:-1;});
 if(!reduceMotion.matches)$('#stage-panel').animate([{opacity:.25,transform:'translateY(12px)'},{opacity:1,transform:'translateY(0)'}],{duration:440,easing:'cubic-bezier(.22,.61,.36,1)'});
}
const roleTabs=[...document.querySelectorAll('[data-stage-role]')];
roleTabs.forEach((button,index)=>{button.onclick=()=>setStage(button.dataset.stageRole);button.onkeydown=event=>{let next;if(event.key==='ArrowRight'||event.key==='ArrowDown')next=(index+1)%roleTabs.length;else if(event.key==='ArrowLeft'||event.key==='ArrowUp')next=(index+roleTabs.length-1)%roleTabs.length;else if(event.key==='Home')next=0;else if(event.key==='End')next=roleTabs.length-1;else return;event.preventDefault();roleTabs[next].focus();setStage(roleTabs[next].dataset.stageRole);};});
if(!reduceMotion.matches){const hw=$('.hero-wordmark')||$('#hero-title');if(hw)hw.animate([{opacity:0,transform:'translateY(22px)'},{opacity:1,transform:'translateY(0)'}],{duration:850,easing:'cubic-bezier(.22,.61,.36,1)'});}
