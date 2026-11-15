import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

// 执行产品页实际角色切换函数，防止清单换格式后仍请求旧的 PNG 路径。
async function stageFixture(screens){
 const source=await readFile(new URL('../../apps/showcase/app.js',import.meta.url),'utf8');
 const start=source.indexOf('const stageRoles='),end=source.indexOf('const roleTabs=',start);
 assert.ok(start>=0&&end>start,'产品角色切换入口必须存在');
 const elements=new Map(),loaded=[];
 const element=()=>({dataset:{},attributes:{},setAttribute(key,value){this.attributes[key]=value;},replaceChildren(...children){this.children=children;},animate(){}});
 const lookup=selector=>{if(!elements.has(selector))elements.set(selector,element());return elements.get(selector);};
 const tabs=['customer','member','operator'].map(role=>Object.assign(element(),{dataset:{stageRole:role}}));
 const context=vm.createContext({screens,$:lookup,node:(tag,text)=>({tag,text}),reduceMotion:{matches:true},document:{querySelectorAll:()=>tabs},Image:class{async decode(){loaded.push(this.src);}}});
 vm.runInContext(source.slice(start,end)+'\nglobalThis.switchStage=setStage;',context);
 return{switchStage:context.switchStage,lookup,loaded,tabs};
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
