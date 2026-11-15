export function el(tag,attrs={},...children){
  const node=document.createElement(tag);
  for(const [key,value] of Object.entries(attrs)){
    if(key.startsWith('on')&&typeof value==='function')node.addEventListener(key.slice(2),value);
    else if(key==='class')node.className=value;
    else if(['disabled','hidden','checked','required','multiple'].includes(key))node[key]=Boolean(value);
    else if(value!==null&&value!==undefined)node.setAttribute(key,String(value));
  }
  for(const child of children.flat(Infinity))if(child!==null&&child!==undefined)node.append(child instanceof Node?child:document.createTextNode(String(child)));
  return node;
}
// 自绘统一线性图标；仅作装饰，按钮名称由可见文案或 aria-label 提供。
const iconPaths={
 overview:'M4 4h6v6H4z M14 4h6v6h-6z M4 14h6v6H4z M14 14h6v6h-6z',
 dispatch:'M5 19 19 5 M8 5h11v11',
 orders:'M7 3h10a2 2 0 0 1 2 2v16l-4-2-3 2-3-2-4 2V5a2 2 0 0 1 2-2z M9 8h6 M9 12h6',
 members:'M16 20v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2 M10 10a3 3 0 1 0 0-6 3 3 0 0 0 0 6 M17 5a3 3 0 0 1 0 6 M20 20v-2a4 4 0 0 0-2-3.5',
 settlements:'M4 6h16v14H4z M4 6V4h13 M15 11h5v5h-5z',
 disputes:'M12 8v5 M12 16v.01 M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0',
 services:'M4 5h16v14H4z M4 10h16 M10 10v9',
 banners:'M4 4h16v16H4z M4 16l5-5 4 4 3-3 4 4 M15 8h.01',
 announcements:'M4 10v5h4l9 4V5l-9 5H4z M8 15l2 5 M20 9v6',
 brand:'M12 3 3 12l9 9 9-9-9-9z M8 12l4 4 4-4-4-4-4 4',
 connection:'M8 3v5 M16 3v5 M6 8h12v4a6 6 0 0 1-12 0V8z M12 18v3',
 clock:'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0 M12 7v5l3 2',
 play:'M9 5 19 12 9 19V5z',
 check:'M5 12l4 4L19 6',
 empty:'M5 5h14l3 10v5H2v-5L5 5z M2 15h6l2 3h4l2-3h6',
 refresh:'M20 7v5h-5 M20 12a8 8 0 1 0-2 5 M20 7l-3-3',
 menu:'M4 6h16 M4 12h16 M4 18h16',
 close:'M6 6l12 12 M18 6 6 18'
};
export function icon(name){
 const ns='http://www.w3.org/2000/svg',svg=document.createElementNS(ns,'svg');
 for(const [key,value] of Object.entries({viewBox:'0 0 24 24',fill:'none',stroke:'currentColor','stroke-width':'1.65','stroke-linecap':'round','stroke-linejoin':'round','aria-hidden':'true',focusable:'false',class:'ui-icon'}))svg.setAttribute(key,value);
 const path=document.createElementNS(ns,'path');path.setAttribute('d',iconPaths[name]||iconPaths.empty);svg.append(path);return svg;
}
export const money=value=>new Intl.NumberFormat('zh-CN',{style:'currency',currency:'CNY',maximumFractionDigits:Number(value)%100?2:0}).format((Number(value)||0)/100);
export const dateTime=value=>value?new Intl.DateTimeFormat('zh-CN',{month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false,timeZone:'Asia/Shanghai'}).format(new Date(value)):'—';
export function shanghaiInput(value){return new Date(new Date(value).getTime()+8*3600000).toISOString().slice(0,16);}
export function fromShanghaiInput(value){if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value))throw Error('请填写完整时间。');return new Date(`${value}:00+08:00`).toISOString();}
export function safeImage(value){if(typeof value!=='string'||!value.trim())return '';try{const url=new URL(value,location.origin);return url.protocol==='https:'||url.origin===location.origin?url.href:'';}catch{return '';}}
export function apiAddress(value){const url=new URL(value);if(url.username||url.password||url.search||url.hash)throw Error('API 地址不能包含账号、参数或片段。');if(url.protocol!=='https:'&&!(url.protocol==='http:'&&['localhost','127.0.0.1','[::1]'].includes(url.hostname)))throw Error('请使用 HTTPS；本机调试可用 HTTP。');if(!/\/api\/v1\/?$/.test(url.pathname))throw Error('API 地址须以 /api/v1 结尾。');return url.href.replace(/\/$/,'');}
export const fulfillmentLabels={awaiting_payment:'待付款',awaiting_assignment:'待派单',awaiting_acceptance:'待接单',scheduled:'待开始',in_progress:'服务中',awaiting_confirmation:'待确认',disputed:'售后中',completed:'已完成',cancelled:'已取消'};
export const ledgerLabels={held:'冻结中',available:'待结算',settled:'已记录',reversed:'已冲回'};
export const paymentLabels={unpaid:'未付款',pending:'待确认',paid:'已付款',refunding:'退款中',refunded:'已退款',closed:'已关闭'};
