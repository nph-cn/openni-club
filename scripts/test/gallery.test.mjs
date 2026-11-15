import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {matchScreens, groupFlows, stateGroup, gallerySearch, parseLocation, browseSequence, galleryCounts, appPreviewUrl, screenPreview, sourceBaseForRef, sourceHref} from '../../apps/showcase/gallery-model.js';

const screens = [
  {id:'home',platform:'flutter',role:'customer',flow:'discover',state:'catalog',title:'首页'},
  {id:'code_error',platform:'flutter',role:'customer',flow:'auth',state:'code_error',title:'验证码错误'},
  {id:'code',platform:'flutter',role:'customer',flow:'auth',state:'verification',title:'验证码'},
  {id:'home_loading',platform:'flutter',role:'customer',flow:'discover',state:'skeleton',title:'首页加载'},
  {id:'orders_empty',platform:'flutter',role:'customer',flow:'fulfillment',state:'empty',title:'暂无订单'},
  {id:'mini-code',platform:'mini',role:'customer',flow:'auth',state:'verification',title:'验证码'},
  {id:'future',platform:'flutter',role:'member',flow:'new-flow',state:'ready',title:'新增页面'}
];
test('gallery can find auth failures independently from normal and verification screens',()=>{
  assert.deepEqual(matchScreens(screens,{platform:'flutter',flow:'auth',state:'error'}).map(x=>x.id),['code_error']);
  assert.deepEqual(matchScreens(screens,{platform:'mini',query:'验证码 验证'}).map(x=>x.id),['mini-code']);
  assert.deepEqual(matchScreens(screens,{platform:'flutter',state:'loading'}).map(x=>x.id),['home_loading']);
  assert.equal(stateGroup(screens[0]),'ready');
  assert.deepEqual(matchScreens(screens,{favoriteOnly:true},new Set(['orders_empty'])).map(x=>x.id),['orders_empty']);
});
test('flow view never drops new screens or new flow categories',()=>{
  const groups=groupFlows(screens),ids=groups.flatMap(group=>group.screens.map(screen=>screen.id));
  assert.equal(groups[0].key,'auth');
  assert.equal(new Set(ids).size,screens.length);
  assert.deepEqual([...ids].sort(),screens.map(screen=>screen.id).sort());
});
test('shareable filters and screen links preserve Chinese text and reject unknown filter values',()=>{
  const value={platform:'mini',role:'customer',flow:'auth',state:'error',view:'flows',query:'验证码 & 重发'};
  assert.deepEqual(parseLocation(gallerySearch(value,'mini-code')), {...value,screenId:'mini-code'});
  assert.equal(parseLocation('?platform=anything&role=owner&state=unknown').platform,'flutter');
  assert.equal(parseLocation('?state=unknown').state,'all');
  assert.equal(gallerySearch({platform:'flutter'},'code'),'?screen=code');
});

test('流程序列保留清单顺序和筛选范围，不混入其他端或其他流程',()=>{
  const shown=matchScreens(screens,{platform:'flutter'});
  assert.deepEqual(browseSequence(shown,'code_error','flow').map(screen=>screen.id),['code_error','code']);
  assert.deepEqual(browseSequence(shown,'code_error','results'),shown);
  assert.deepEqual(browseSequence(matchScreens(screens,{state:'error'}),'code_error','flow').map(screen=>screen.id),['code_error']);
  assert.deepEqual(browseSequence(shown,'removed','flow'),[]);
  assert.deepEqual(browseSequence(shown,'future','flow').map(screen=>screen.id),['future']);
});

test('图库计数区分当前结果、各端和全站，旧收藏不计入可用页面',()=>{
  const counts=galleryCounts(screens,matchScreens(screens,{flow:'auth'}),new Set(['code','removed','mini-code']));
  assert.deepEqual(counts,{total:7,shown:2,platforms:{flutter:6,mini:1,admin:0},favorites:2});
});

test('App入口带iPhone设备预览并保留页面参数，其他入口不变',()=>{
  assert.equal(appPreviewUrl('/demo/'),'/demo/?device=iphone');
  assert.equal(appPreviewUrl('/demo/?screen=member&device=other#orders'),'/demo/?screen=member&device=iphone#orders');
  assert.equal(appPreviewUrl('/admin/'),'/admin/');
  assert.equal(appPreviewUrl('/guide/05-wechat-release.html'),'/guide/05-wechat-release.html');
  assert.equal(appPreviewUrl('https://example.com/demo/'),'https://example.com/demo/');
});

test('流程用清单顺序值排序，未编号的未来页面仍保留',()=>{
  const pages=[
    {id:'later',platform:'flutter',flow:'auth',flowOrder:3},
    {id:'future',platform:'flutter',flow:'auth'},
    {id:'first',platform:'flutter',flow:'auth',flowOrder:1},
    {id:'second',platform:'flutter',flow:'auth',flowOrder:2},
  ];
  const expected=['first','second','later','future'];
  assert.deepEqual(groupFlows(pages)[0].screens.map(screen=>screen.id),expected);
  assert.deepEqual(browseSequence(pages,'second','flow').map(screen=>screen.id),expected);
  assert.equal(pages[0].id,'later');
});

test('真实清单的交互截图回到已实现流程起点，不把截图名当路由',async()=>{
  const manifest=JSON.parse(await readFile(new URL('../../apps/mobile/screenshots/manifest.json',import.meta.url),'utf8'));
  const routes=new Set(manifest.filter(screen=>screen.captureKind==='route').map(screen=>screen.id));
  const interactions=manifest.filter(screen=>screen.captureKind==='interaction');
  assert.ok(interactions.length>0);
  for(const screen of manifest){
    const preview=screenPreview({...screen,platform:'flutter'}),url=new URL(preview.href,'https://openni.local');
    assert.equal(url.searchParams.get('screen'),screen.previewScreen??screen.id,screen.id);
    assert.equal(url.searchParams.get('device'),'iphone');
    assert.equal(preview.label,screen.captureKind==='interaction'?'打开流程起点 ↗':'打开此页 ↗');
  }
  for(const screen of interactions)assert.ok(routes.has(screen.previewScreen),`${screen.id} 必须指向真实路由`);
});

test('源码链接使用构建指定分支，旧清单默认main且不接受外部来源地址',()=>{
  const source='apps/mobile/lib/discover.dart';
  const draft=sourceBaseForRef('codex/openni-ui-20261116');
  assert.equal(draft,'https://github.com/nph-cn/openni-club/blob/codex/openni-ui-20261116/');
  assert.equal(sourceHref({source,sourceBase:draft}),draft+source);
  assert.equal(sourceHref({source}),sourceBaseForRef('main')+source);
  assert.equal(sourceHref({source,sourceBase:'https://example.com/blob/draft/'}),sourceBaseForRef('main')+source);
  assert.equal(sourceHref({source:'apps/中文 文件.dart',sourceBase:draft}),draft+'apps/'+encodeURIComponent('中文 文件.dart'));
  assert.throws(()=>sourceBaseForRef('../main'),/源码分支/);
});
