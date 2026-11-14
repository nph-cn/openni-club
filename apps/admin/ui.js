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
export const money=value=>new Intl.NumberFormat('zh-CN',{style:'currency',currency:'CNY',maximumFractionDigits:Number(value)%100?2:0}).format((Number(value)||0)/100);
export const dateTime=value=>value?new Intl.DateTimeFormat('zh-CN',{month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false,timeZone:'Asia/Shanghai'}).format(new Date(value)):'—';
export function shanghaiInput(value){return new Date(new Date(value).getTime()+8*3600000).toISOString().slice(0,16);}
export function fromShanghaiInput(value){if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value))throw Error('请填写完整时间。');return new Date(`${value}:00+08:00`).toISOString();}
export function safeImage(value){if(typeof value!=='string'||!value.trim())return '';try{const url=new URL(value,location.origin);return url.protocol==='https:'||url.origin===location.origin?url.href:'';}catch{return '';}}
export function apiAddress(value){const url=new URL(value);if(url.username||url.password||url.search||url.hash)throw Error('API 地址不能包含账号、参数或片段。');if(url.protocol!=='https:'&&!(url.protocol==='http:'&&['localhost','127.0.0.1','[::1]'].includes(url.hostname)))throw Error('请使用 HTTPS；本机调试可用 HTTP。');if(!/\/api\/v1\/?$/.test(url.pathname))throw Error('API 地址须以 /api/v1 结尾。');return url.href.replace(/\/$/,'');}
export const fulfillmentLabels={awaiting_payment:'待付款',awaiting_assignment:'待派单',awaiting_acceptance:'待接单',scheduled:'待开始',in_progress:'服务中',awaiting_confirmation:'待确认',disputed:'售后中',completed:'已完成',cancelled:'已取消'};
export const ledgerLabels={held:'冻结中',available:'待结算',settled:'已记录',reversed:'已冲回'};
export const paymentLabels={unpaid:'未付款',pending:'待确认',paid:'已付款',refunding:'退款中',refunded:'已退款',closed:'已关闭'};
