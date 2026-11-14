import {contentManager} from './content.js';
const $ = selector => document.querySelector(selector);
let base = '', token = '', orders = [], status = 'all', search = '', refundOrder = null;
const labels = {pending:'待确认',confirmed:'已确认',completed:'已完成',cancelled:'已取消'};
const paymentLabels = {unpaid:'未付款',pending:'等待付款',paid:'已付款',refunded:'已退款',refund_pending:'退款处理中'};
const element = (tag,text,className) => {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  if (className) node.className = className;
  return node;
};
async function request(path, options = {}) {
  const response = await fetch(base + path, {...options,headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`,...options.headers},signal:AbortSignal.timeout(12000)});
  const data = await response.json();
  if (!response.ok) throw new Error(data.error?.message || `请求失败 ${response.status}`);
  return data;
}
function notice(message,error = false) {
  $('#connection-status').textContent = message;
  $('#connection-status').classList.toggle('error',error);
}
async function refreshConfig() {
  const config = await request('/admin/config/status');
  const names = {mode:'运行模式',authProvider:'登录方式',paymentProvider:'支付方式',wechatLoginReady:'小程序登录',wechatAppLoginReady:'App 登录',wechatPayReady:'微信支付',catalogReady:'经营资料已就绪'};
  $('#integrations').replaceChildren();
  for (const [key,value] of Object.entries(config)) {
    if (typeof value === 'boolean' || typeof value === 'string') $('#integrations').append(element('span',`${names[key] || key}：${typeof value === 'boolean' ? (value ? '已配置' : '未就绪') : value}`));
  }
}
async function refresh() { orders = await request('/admin/orders'); render(); }
const content = contentManager(request,()=>!!token,refreshConfig);
function disconnect() {
  token = ''; orders = [];
  $('#refresh').disabled = true; $('#disconnect').hidden = true;
  $('#mode-label').textContent = '未连接后端';
  $('#integrations').replaceChildren(element('p','连接后端后读取能力状态。'));
  content.clear(); $('#refund-dialog').close(); refundOrder = null; render();
}
$('#connect').onsubmit = async event => {
  event.preventDefault();
  let url;
  try {
    url = new URL($('#base').value);
    if (url.username || url.password || url.search || url.hash) throw new Error();
    if (url.protocol !== 'https:' && !(['localhost','127.0.0.1'].includes(url.hostname) && url.protocol === 'http:')) throw new Error();
  } catch { notice('生产 API 必须使用 HTTPS，本地演示可使用 localhost 或 127.0.0.1。',true); return; }
  base = url.href.replace(/\/$/,''); token = $('#token').value;
  notice('正在连接…');
  const button = $('#connect button[type=submit]'); button.disabled = true;
  try {
    await refresh(); await refreshConfig(); await content.reload();
    $('#mode-label').textContent = '已连接独立后端';
    $('#refresh').disabled = false; $('#disconnect').hidden = false; $('#token').value = '';
    notice('连接成功。当前令牌仅在页面内存中。');
  } catch (error) { disconnect(); notice(error.message,true); }
  finally { button.disabled = false; }
};
$('#disconnect').onclick = () => { disconnect(); notice('已断开连接。'); };
$('#refresh').onclick = () => refresh().then(()=>notice('已刷新订单。')).catch(error=>notice(error.message,true));
function render() {
  const list = $('#order-list'); list.replaceChildren();
  const filtered = orders.filter(order=>(status === 'all' || order.status === status) && `${order.id} ${order.serviceTitle} ${order.contact}`.toLowerCase().includes(search.toLowerCase()));
  if (!filtered.length) {
    const empty = element('div',undefined,'empty');
    empty.append(element('h3',token ? '暂无匹配的订单' : '先连接你的俱乐部后端'),element('p',token ? '新预约会在这里出现。' : '请使用自己的后端地址和管理员令牌。'));
    list.append(empty); return;
  }
  for (const order of filtered) {
    const row = element('article',undefined,'order');
    const info = element('div');
    const payment = paymentLabels[order.paymentStatus] || '未收款';
    info.append(element('h3',order.serviceTitle),element('span',order.id,'order-id'),element('p',`金额 ¥${(order.priceCents/100).toFixed(2)} · ${payment}`));
    const context = element('div');
    context.append(element('p',new Date(order.scheduledAt).toLocaleString('zh-CN')),element('p',`联系：${order.contact}`),element('p',order.note || '无备注'));
    const actions = element('div',undefined,'order-actions');
    actions.append(element('span',labels[order.status] || order.status,`status ${order.status}`));
    const next = order.status === 'pending' ? [['confirmed','确认接单']] : order.status === 'confirmed' && (order.demo || order.paymentStatus === 'paid') ? [['completed','完成服务']] : [];
    if (['pending','confirmed'].includes(order.status) && order.paymentStatus === 'unpaid') next.push(['cancelled','取消']);
    for (const [state,label] of next) {
      const button = element('button',label,'button outline compact');
      button.onclick = async () => {
        if (state === 'cancelled' && !confirm(`取消订单 ${order.id}？此操作会改变订单状态。`)) return;
        button.disabled = true;
        try { await request(`/admin/orders/${encodeURIComponent(order.id)}`,{method:'PATCH',body:JSON.stringify({status:state})}); await refresh(); notice('订单状态已更新。'); }
        catch (error) { notice(error.message,true); button.disabled = false; }
      };
      actions.append(button);
    }
    if (!order.demo && order.paymentStatus !== 'refunded') {
      const sync = element('button','同步付款状态','button outline compact');
      sync.onclick = async () => {
        sync.disabled = true;
        try { await request(`/admin/orders/${encodeURIComponent(order.id)}/payment-sync`,{method:'POST',body:'{}'}); await refresh(); notice('支付状态已向微信核对。'); }
        catch (error) { notice(error.message,true); sync.disabled = false; }
      };
      actions.append(sync);
    }
    if (['paid','refund_pending'].includes(order.paymentStatus)) {
      const refund = element('button',order.paymentStatus === 'refund_pending' ? '重试退款请求' : '全额退款','button outline compact');
      refund.onclick = () => {
        refundOrder = order;
        $('#refund-form').reset(); $('#refund-error').textContent = '';
        $('#refund-summary').textContent = `${order.serviceTitle} · 订单 ${order.id} · 退款金额 ¥${(order.priceCents/100).toFixed(2)}`;
        $('#refund-dialog').showModal();
      };
      actions.append(refund);
    }
    row.append(info,context,actions); list.append(row);
  }
}
 document.querySelectorAll('[data-status]').forEach(button=>button.onclick=()=>{
  status = button.dataset.status;
  document.querySelectorAll('[data-status]').forEach(other=>other.classList.toggle('selected',other===button)); render();
});
$('#search-orders').oninput = event => { search = event.target.value.trim(); render(); };
$('#close-refund').onclick = () => $('#refund-dialog').close();
$('#refund-form').onsubmit = async event => {
  event.preventDefault();
  if (!refundOrder) return;
  const button = event.target.querySelector('[type=submit]'); button.disabled = true;
  try {
    await request(`/admin/orders/${encodeURIComponent(refundOrder.id)}/refund`,{method:'POST',body:JSON.stringify({reason:event.target.elements.reason.value.trim()})});
    $('#refund-dialog').close(); await refresh(); notice('退款申请已提交，请查看状态并按需同步。');
  } catch (error) { $('#refund-error').textContent = error.message; }
  finally { button.disabled = false; }
};
