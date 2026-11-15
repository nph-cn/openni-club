import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

// 执行产品页实际角色切换函数，防止清单换格式后仍请求旧的 PNG 路径。
async function stageFixture(screens){
 const source=await readFile(new URL('../../apps/showcase/app.js',import.meta.url),'utf8');
 const start=source.indexOf('const stageRoles='),end=source.indexOf('const roleTabs=',start);
 assert.ok(start>=0&&end>start,'产品角色切换入口必须存在');
 const elements=new Map(),loaded=[],opened=[];
 const element=()=>({dataset:{},attributes:{},children:[],setAttribute(key,value){this.attributes[key]=value;},replaceChildren(...children){this.children=children;},append(...children){this.children.push(...children);},animate(){}});
 const lookup=selector=>{if(!elements.has(selector))elements.set(selector,element());return elements.get(selector);};
 const tabs=['customer','member','operator'].map(role=>Object.assign(element(),{dataset:{stageRole:role}}));
 const context=vm.createContext({screens,$:lookup,node:(tag,text)=>Object.assign(element(),{tag,text}),screenImage:screen=>({src:screen.image}),openStageScreen:screen=>opened.push(screen.id),reduceMotion:{matches:true},document:{querySelectorAll:()=>tabs},Image:class{async decode(){loaded.push(this.src);}}});
 vm.runInContext(source.slice(start,end)+'\nglobalThis.switchStage=setStage;',context);
 return{switchStage:context.switchStage,lookup,loaded,tabs,opened};
}

test('角色预览使用清单真实图片格式，后台 JPG 不退回旧 PNG',async()=>{
 const fixture=await stageFixture([{id:'home',image:'/screens/home.webp'},{id:'member',image:'/screens/member.avif'},{id:'admin-dispatch',image:'/screens/admin-dispatch.jpg'}]);
 for(const key of ['customer','member','operator'])await fixture.switchStage(key);
 assert.deepEqual(fixture.loaded,['/screens/home.webp','/screens/member.avif','/screens/admin-dispatch.jpg']);
 assert.equal(fixture.lookup('#stage-image').src,'/screens/admin-dispatch.jpg');
 assert.equal(fixture.lookup('#product-stage').dataset.role,'operator');
 assert.equal(fixture.lookup('#stage-launch').href,'/admin/');
 assert.equal(fixture.tabs[2].attributes['aria-selected'],'true');
});

test('清单缺少角色图片时保留现有预览，不发送猜测路径',async()=>{
 const fixture=await stageFixture([]);fixture.lookup('#stage-image').src='/screens/existing.png';
 await fixture.switchStage('operator');
 assert.equal(fixture.loaded.length,0);assert.equal(fixture.lookup('#stage-image').src,'/screens/existing.png');
});

test('多屏预览仅使用实际清单，每张图都打开自身流程',async()=>{
 const fixture=await stageFixture([
  {id:'home',title:'首页',image:'/screens/home.png'},
  {id:'services',title:'服务目录',image:'/screens/services.webp'},
  {id:'player',title:'陪练详情',image:'/screens/player.png'},
 ]);
 await fixture.switchStage('customer');
 const extra=fixture.lookup('#stage-extra').children;
 assert.equal(extra.length,2,'缺少booking时不可制造图片路径');
 assert.deepEqual(extra.map(button=>button.children[0].src),['/screens/services.webp','/screens/player.png']);
 fixture.lookup('#stage-open').onclick();for(const button of extra)button.onclick();
 assert.deepEqual(fixture.opened,['home','services','player']);
 assert.equal(fixture.lookup('#stage-launch').href,'/demo/?device=iphone');
});

test('新首页保留全部实际脚本入口，提供专题与设备预览链接',async()=>{
 const html=await readFile(new URL('../../apps/showcase/index.html',import.meta.url),'utf8');
 const script=await readFile(new URL('../../apps/showcase/app.js',import.meta.url),'utf8');
 const ids=[...html.matchAll(/\bid="([^"]+)"/g)].map(match=>match[1]);
 assert.equal(new Set(ids).size,ids.length,'页面id不能重复');
 for(const [,id] of script.matchAll(/\$\(['"]#([\w-]+)/g))assert.ok(ids.includes(id),`脚本入口#${id}必须存在`);
 assert.match(html,/href="\/delta\/"/);
 for(const [,href] of html.matchAll(/href="(\/demo\/[^"\s]*)"/g))assert.equal(new URL(href,'https://openni.local').searchParams.get('device'),'iphone');
 assert.match(html,/<h1 id="hero-title">[\s\S]*?开源系统[\s\S]*?<\/h1>/);
});
