// Derive every fixture through the HTTP API. No direct database writes or invented balances.
import {mkdir,writeFile} from 'node:fs/promises';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createApp,readConfig} from '../src/app.mjs';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const owner='fixture-only-owner-credential-123456';
const localDate=new Date(Date.now()+8*3600000).toISOString().slice(0,10);
let clock=Date.parse(localDate+'T19:45:00+08:00');if(clock<Date.now()+60000)clock+=86400000;
const serviceStart=clock+15*60000;
let scheduledAt=new Date(serviceStart).toISOString();
const server=createApp({...readConfig({API_MODE:'demo',ADMIN_TOKEN:owner}),dataDir:':memory:',now:()=>clock});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const base=`http://127.0.0.1:${server.address().port}/api/v1`;
async function call(path,token,method='GET',body){
  const response=await fetch(base+path,{method,headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body)});
  const result=await response.json();if(!response.ok)throw Error(`${method} ${path}: ${JSON.stringify(result)}`);return result;
}
try{
  const customer=(await call('/auth/demo',null,'POST',{name:'林'})).token;
  const members={};for(const playerId of ['p1','p2','p3','p4'])members[playerId]=(await call('/auth/demo',null,'POST',{role:'member',playerId,name:({p1:'阿屿',p2:'Echo',p3:'小满',p4:'North'})[playerId]})).token;
  const eveningSlots=Array.from({length:14},(_,day)=>({startAt:new Date(Math.max(serviceStart-2*3600000+day*86400000,Date.now()+60000)).toISOString(),endAt:new Date(serviceStart+3.5*3600000+day*86400000).toISOString()}));
  for(const playerId of Object.keys(members))await call(`/admin/players/${playerId}/availability`,owner,'PUT',{slots:eveningSlots});
  let index=0;
  async function create(serviceId='s1',note='希望练习信息沟通与小队配合。'){
    const service=await call('/services/'+serviceId),variantId=service.variants?.[0]?.id;
    return call('/orders',customer,'POST',{serviceId,variantId,scheduledAt,contact:'demo-contact-only',note,idempotencyKey:'documented-fixture-'+(++index)});
  }
  async function assign(order,playerId){return call(`/admin/orders/${order.id}/assign`,owner,'POST',{playerId,commissionBps:2000,reason:'根据开放时段与游戏匹配安排。'});}
  async function accept(order,playerId){return call(`/member/orders/${order.id}/accept`,members[playerId],'POST',{});}
  async function start(order,playerId){return call(`/member/orders/${order.id}/start`,members[playerId],'POST',{});}
  async function submit(order,playerId){return call(`/member/orders/${order.id}/submit`,members[playerId],'POST',{summary:'已按约定完成小队沟通练习，并一起复盘关键报点。无游戏账号密码交换。'});}

  const completed=await create();await assign(completed,'p1');await accept(completed,'p1');
  const disputed=await create('s2','希望重点复盘地图选择。');await assign(disputed,'p2');await accept(disputed,'p2');
  const confirmation=await create('s1','服务已结束，等待客户核对。');await assign(confirmation,'p4');await accept(confirmation,'p4');
  clock=serviceStart;
  await start(completed,'p1');await start(disputed,'p2');await start(confirmation,'p4');
  clock+=60*60000;
  await submit(completed,'p1');await submit(disputed,'p2');await submit(confirmation,'p4');
  await call(`/orders/${completed.id}/confirm`,customer,'POST',{rating:5,comment:'演示评价：沟通清楚，服务记录完整。'});
  const earned=(await call('/member/earnings',members.p1)).entries;
  await call('/admin/settlements',owner,'POST',{entryIds:[earned[0].id],paymentReference:'DEMO-RECEIPT-NO-TRANSFER',note:'只读演示凭据，没有真实打款。'});

  await call(`/orders/${disputed.id}/dispute`,customer,'POST',{reason:'复盘记录需要补充',details:'演示问题：希望补充第二场对局的复盘说明。'});
  clock+=5*60000;scheduledAt=new Date(clock+10*60000).toISOString();
  const running=await create('s1','正在进行的小队服务。');await assign(running,'p1');await accept(running,'p1');clock=Date.parse(scheduledAt);const inProgress=await start(running,'p1');
  scheduledAt=new Date(clock+15*60000).toISOString();
  const acceptance=await create('s3','成员尚未确认接单。');await assign(acceptance,'p3');
  await create('s2','新预约，等待运营安排成员。');
  scheduledAt=new Date(clock+75*60000).toISOString();
  const memberPending=await create('s1','稍晚的预约，等待成员接单。');await assign(memberPending,'p1');

  const snapshot={generatedAt:new Date(clock).toISOString(),source:'api-fixture',demo:true};
  for(const [key,path]of Object.entries({overview:'/admin/overview',orders:'/admin/orders',players:'/admin/players',services:'/admin/services',announcements:'/admin/announcements',banners:'/banners',club:'/club',settlements:'/admin/settlements',disputes:'/admin/disputes'}))snapshot[key]=await call(path,owner);
  const destination=resolve(root,'apps/admin/demo-snapshot.json'),mobile=resolve(root,'services/api/test/fixtures/order-in-progress.json');
  await mkdir(dirname(destination),{recursive:true});await mkdir(dirname(mobile),{recursive:true});
  await writeFile(destination,JSON.stringify(snapshot,null,2)+'\n');await writeFile(mobile,JSON.stringify(inProgress,null,2)+'\n');
  const memberPreview={generatedAt:new Date(clock).toISOString(),source:'api-fixture',demo:true,readOnly:true};
  for(const [key,path]of Object.entries({me:'/member/me',orders:'/member/orders',earnings:'/member/earnings',availability:'/member/availability',notifications:'/notifications'}))memberPreview[key]=await call(path,members.p1);
  await writeFile(resolve(root,'services/api/test/fixtures/member-preview.json'),JSON.stringify(memberPreview,null,2)+'\n');
  await writeFile(resolve(root,'services/api/test/fixtures/README.md'),'# API-derived demo fixtures\n\nRun `node services/api/scripts/generate-demo-snapshot.mjs` from the repository root. The script creates an isolated in-memory demo API, customer and four member sessions, then uses authenticated HTTP calls to create, assign, accept, start, submit, confirm, dispute and record a demo settlement. All returned states, events, totals and amounts come from server responses. An injected clock runs the workflow at evening service hours (19:45 through 21:15, Asia/Shanghai); availability is published as 18:00–23:30 windows. It writes the operator snapshot, mobile in-progress order and member-preview responses from the same run. Ledger timestamps use the same injected clock. No database state or balance is injected. All identities are fictional; no real payment or bank transfer occurs. Tokens are omitted.\n');
  console.log(JSON.stringify({snapshot:destination,orders:snapshot.orders.length,states:snapshot.orders.map(order=>order.fulfillmentStatus),mobileFixture:mobile}));
}finally{await new Promise(resolve=>{server.closeAllConnections();server.close(resolve);});}
