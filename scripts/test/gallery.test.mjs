import test from 'node:test';
import assert from 'node:assert/strict';
import {matchScreens, groupFlows, stateGroup, gallerySearch, parseLocation} from '../../apps/showcase/gallery-model.js';

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
