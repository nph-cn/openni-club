import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {labels,browseSequence,stateGroup,appPreviewUrl,screenPreview,sourceHref} from '../../apps/showcase/gallery-model.js';

// 执行真实详情与翻页函数，验证界面上的页码、缩略图、边界按钮一致。
async function fixture(){
  const source=await readFile(new URL('../../apps/showcase/app.js',import.meta.url),'utf8');
  const show=source.slice(source.indexOf('function show('),source.indexOf('function renderSidebar('));
  const next=source.slice(source.indexOf('function next('),source.indexOf("$('#close-detail').onclick="));
  const screens=[
    {id:'phone',title:'手机号',platform:'flutter',flow:'auth',source:'auth.dart',image:'/phone.png'},
    {id:'code',title:'验证码',platform:'flutter',flow:'auth',source:'auth.dart',image:'/code.png'},
    {id:'home',title:'首页',platform:'flutter',flow:'discover',source:'discover.dart',image:'/home.png'},
  ];
  const element=(tag,text)=>({tag,textContent:text,children:[],attributes:{},dataset:{},scrollLeft:0,offsetLeft:0,offsetWidth:70,clientWidth:200,
    classList:{toggle(){},remove(){}},append(...children){this.children.push(...children);},replaceChildren(...children){this.children=children;},
    setAttribute(key,value){this.attributes[key]=value;},contains(){return false;},
    querySelectorAll(){return this.children;},querySelector(){return this.children.find(child=>child.attributes['aria-current']==='true');},focus(){},
  });
  const elements=new Map(),lookup=selector=>{if(!elements.has(selector))elements.set(selector,element('div'));return elements.get(selector);};
  const dialog=element('dialog');dialog.open=true;
  const browseMode=element('div');browseMode.children=['flow','results'].map(scope=>Object.assign(element('button'),{dataset:{browseScope:scope}}));
  const context=vm.createContext({screens,$:lookup,node:element,screenImage:()=>element('img'),names:labels,stateGroup,appPreviewUrl,screenPreview,sourceHref,browseSequence,captureInfo:element('p'),
    document:{activeElement:{}},dialog,browseMode,matched:()=>screens,writeLocation(){},
  });
  vm.runInContext(`let currentId='',detailScope='results'; const detailList=()=>browseSequence(matched(),currentId,detailScope);${show}\n${next}\n globalThis.viewer={show,next,get id(){return currentId;}};`,context);
  return{screens,viewer:context.viewer,lookup};
}

test('本流程翻到末页即停止，切换筛选范围后可继续到下一流程',async()=>{
  const {screens,viewer,lookup}=await fixture();
  viewer.show(screens[0],{scope:'flow'});
  assert.equal(lookup('#detail-position').textContent,'本流程 1 / 2');
  assert.equal(lookup('#previous-screen').disabled,true);
  assert.equal(lookup('#detail-sequence').children.length,2);
  viewer.next(1);
  assert.equal(viewer.id,'code');assert.equal(lookup('#next-screen').disabled,true);
  viewer.next(1);assert.equal(viewer.id,'code');
  assert.equal(lookup('#detail-sequence').children[1].attributes['aria-current'],'true');
  assert.equal(lookup('#detail-demo').href,'/demo/?screen=code&device=iphone');
  viewer.show(screens[1],{scope:'results'});
  assert.equal(lookup('#detail-position').textContent,'筛选结果 2 / 3');
  assert.equal(lookup('#detail-sequence').children.length,3);
  viewer.next(1);assert.equal(viewer.id,'home');assert.equal(lookup('#next-screen').disabled,true);
});
