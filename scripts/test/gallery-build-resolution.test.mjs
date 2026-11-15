// 运行真实构建脚本，但所有输入与输出均留在隔离临时目录。
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,readFile,writeFile,rm,access} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import sharp from 'sharp';

const buildScript=fileURLToPath(new URL('../build.mjs',import.meta.url));
const required=['home','services','service','players','player','booking','orders','order','profile','announcements','settings'];
async function fixture(t){
 const root=await mkdtemp(join(tmpdir(),'openni-gallery-build-'));
 t.after(()=>rm(root,{recursive:true,force:true}));
 async function write(path,content){const target=join(root,path);await mkdir(dirname(target),{recursive:true});await writeFile(target,content);}
 const portrait=await sharp({create:{width:780,height:1688,channels:3,background:'#202020'}}).png().toBuffer();
 const desktop=await sharp({create:{width:2880,height:1960,channels:3,background:'#303030'}}).png().toBuffer();
 const entries=required.map(id=>({id,file:id+'.png',title:id,flow:'discover',role:'customer',width:390,height:844,source:'apps/mobile/lib/screens.dart'}));
 for(const item of entries)await write('apps/mobile/screenshots/'+item.file,portrait);
 await write('apps/mobile/screenshots/manifest.json',JSON.stringify(entries));
 await write('apps/mobile/lib/screens.dart','// 仅用于构建测试的来源占位文件。\n');
 await write('apps/mobile/build/web/index.html','<!doctype html><title>隔离测试</title>');
 await write('apps/showcase/index.html','<!doctype html><title>隔离测试</title>');
 await write('apps/showcase/catalog.json',JSON.stringify(entries));
 await write('apps/admin/index.html','<!doctype html><title>隔离测试</title>');
 await write('apps/admin/operations.js','// 隔离构建测试。\n');
 await write('apps/admin/screenshots/admin-overview.png',desktop);
 await write('apps/admin/screenshots/manifest.json',JSON.stringify([{id:'admin-overview',file:'admin-overview.png',title:'后台测试',flow:'fulfillment',source:'apps/admin/operations.js'}]));
 await write('apps/studio/index.html','<!doctype html><title>隔离测试</title>');
 await write('node_modules/fflate/esm/browser.js','// 构建只复制，不执行。\n');
 await write('docs/index.md','# 隔离构建测试\n');
 return {root,portrait,desktop,write};
}
function build(root,env={}){return spawnSync(process.execPath,[buildScript],{cwd:root,env:{...process.env,OPENNI_SOURCE_REF:'',...env},encoding:'utf8',windowsHide:true,timeout:15000});}

test('构建保留2倍原图，输出实际像素，并仅在screens目录发布后台截图',async t=>{
 const f=await fixture(t),result=build(f.root);assert.equal(result.status,0,result.stderr||String(result.error));
 const screens=JSON.parse(await readFile(join(f.root,'dist/screens.json'),'utf8'));
 assert.equal(screens.length,required.length+1);
 const home=screens.find(screen=>screen.id==='home');assert.equal(home.width,780);assert.equal(home.height,1688);
 assert.equal(home.sourceBase,'https://github.com/nph-cn/openni-club/blob/main/');
 const admin=screens.find(screen=>screen.id==='admin-overview');assert.equal(admin.width,2880);assert.equal(admin.height,1960);
 assert.deepEqual(await readFile(join(f.root,'dist/screens/home.png')),f.portrait);
 assert.deepEqual(await readFile(join(f.root,'dist/screens/admin-overview.png')),f.desktop);
 await assert.rejects(access(join(f.root,'dist/admin/screenshots')),{code:'ENOENT'});
 await access(join(f.root,'dist/admin/index.html'));
});

test('草稿构建把同一明确分支写入全部界面的源码来源',async t=>{
 const f=await fixture(t),result=build(f.root,{OPENNI_SOURCE_REF:'codex/openni-ui-20261116'});
 assert.equal(result.status,0,result.stderr||String(result.error));
 const screens=JSON.parse(await readFile(join(f.root,'dist/screens.json'),'utf8'));
 assert.ok(screens.length>0);
 for(const screen of screens)assert.equal(screen.sourceBase,'https://github.com/nph-cn/openni-club/blob/codex/openni-ui-20261116/',screen.id);
});

test('损坏或非数组截图清单必须阻止构建，不静默改用文件名',async t=>{
 const f=await fixture(t);
 for(const content of ['{invalid-json','null','{}']){
  await f.write('apps/mobile/screenshots/manifest.json',content);
  const result=build(f.root);assert.notEqual(result.status,0,content);assert.match(result.stderr,/manifest\.json/);
 }
});

test('没有可选截图清单仍可生成目录，但缺少真实Flutter构建必须失败',async t=>{
 const f=await fixture(t);
 await rm(join(f.root,'apps/mobile/screenshots/manifest.json'));
 const withoutManifest=build(f.root);assert.equal(withoutManifest.status,0,withoutManifest.stderr);
 const screens=JSON.parse(await readFile(join(f.root,'dist/screens.json'),'utf8'));assert.equal(screens.find(screen=>screen.id==='home').width,780);
 await rm(join(f.root,'apps/mobile/build/web/index.html'));
 const missingApp=build(f.root);assert.notEqual(missingApp.status,0);assert.match(missingApp.stderr,/index\.html/);
});
