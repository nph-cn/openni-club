// 仅通过隔离的演示 HTTP API 推进状态；不改数据库或手写服务金额、流水。
import {mkdir, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {createApp, readConfig} from '../../../services/api/src/app.mjs';

const localDate = new Date(Date.now()+8*3600000).toISOString().slice(0,10);
let clock = Date.parse(localDate+'T19:45:00+08:00');
if (clock < Date.now()+60000) clock += 86400000;
const startAt = new Date(clock+15*60000).toISOString();
const owner = 'isolated-mobile-fixture-owner-123456';
const app = createApp({...readConfig({API_MODE:'demo', ADMIN_TOKEN:owner}), dataDir:':memory:', now:()=>clock});
await new Promise(resolve=>app.listen(0,'127.0.0.1',resolve));
const base = `http://127.0.0.1:${app.address().port}/api/v1`;
async function call(path, token, method='GET', body) {
  const response = await fetch(base+path, {method, headers:{'content-type':'application/json', ...(token?{authorization:`Bearer ${token}`}:{})}, body:body===undefined?undefined:JSON.stringify(body)});
  const result = await response.json();
  if (!response.ok) throw Error(`${method} ${path}: ${JSON.stringify(result)}`);
  return result;
}
try {
  const customer = (await call('/auth/demo',null,'POST',{name:'林同学'})).token;
  const member = (await call('/auth/demo',null,'POST',{role:'member',playerId:'p1',name:'阿屿'})).token;
  const teammate = (await call('/auth/demo',null,'POST',{role:'member',playerId:'p2',name:'Echo'})).token;
  for (const id of ['p1','p2']) await call(`/admin/players/${id}/availability`,owner,'PUT',{slots:[{startAt:new Date(clock+5*60000).toISOString(),endAt:new Date(clock+225*60000).toISOString()}]});
  async function create(id, at, key) {
    const service = await call('/services/'+id);
    return call('/orders',customer,'POST',{serviceId:id, variantId:service.variants?.[0]?.id, scheduledAt:at, contact:'demo-contact-only',note:'重点练习报点和队内沟通。',idempotencyKey:key});
  }
  async function assign(order,id) { return call(`/admin/orders/${order.id}/assign`,owner,'POST',{playerId:id,commissionBps:2000,reason:'按游戏与可接时段安排。'}); }
  async function act(order,token,action,body={}) { return call(`/member/orders/${order.id}/${action}`,token,'POST',body); }
  const first=await create('s1',startAt,'mobile-completion');
  const second=await create('s2',startAt,'mobile-support');
  const later=await create('s1',new Date(Date.parse(startAt)+120*60000).toISOString(),'mobile-pending');
  const assigned=await assign(first,'p1');
  await assign(second,'p2');
  const pending=await assign(later,'p1');
  const scheduled=await act(first,member,'accept');
  await act(second,teammate,'accept');
  clock=Date.parse(startAt);
  const running=await act(first,member,'start');
  await act(second,teammate,'start');
  clock+=60*60*1000;
  const delivery={summary:'完成了三场报点与路线沟通练习，复盘了两次关键决策，并整理了下次练习重点。', evidenceUrl:'https://example.com/demo-delivery'};
  const awaitingConfirmation=await act(first,member,'submit',delivery);
  const supportReady=await act(second,teammate,'submit',{summary:'已完成对局回看，整理了地图选择与关键报点。'});
  const notificationsUnread=await call('/notifications',customer);
  await call(`/notifications/${notificationsUnread[0].id}/read`,customer,'PATCH',{});
  const notificationsRead=await call('/notifications',customer);
  const review={rating:5,comment:'沟通清楚，复盘建议很具体。'};
  const completed=await call(`/orders/${first.id}/confirm`,customer,'POST',review);
  const dispute={reason:'服务未按约定完成',details:'第二场复盘记录缺少关键时间点，希望补充说明。'};
  const disputed=await call(`/orders/${second.id}/dispute`,customer,'POST',dispute);
  const snapshot={
    source:'隔离演示API真实HTTP响应；固定测试时钟；无真实付款；不含会话凭据',
    generatedAt:new Date(clock).toISOString(),
    services:await call('/services'),players:await call('/players'),club:await call('/club'),
    customer:await call('/me',customer),member:await call('/me',member),
    orders:{assigned,scheduled,running,pending,awaitingConfirmation,supportReady,completed,disputed},
    memberEarnings:await call('/member/earnings',member),
    notifications:{unread:notificationsUnread,read:notificationsRead},
    actions:{delivery,review,dispute},
  };
  const destination=fileURLToPath(new URL('../test/fixtures/product-flow.json',import.meta.url));
  await mkdir(fileURLToPath(new URL('../test/fixtures/',import.meta.url)),{recursive:true});
  await writeFile(destination,JSON.stringify(snapshot,null,2)+'\n');
  console.log(JSON.stringify({destination,states:Object.keys(snapshot.orders),notifications:notificationsUnread.length}));
} finally {
  await new Promise(resolve=>{app.closeAllConnections();app.close(resolve);});
}
