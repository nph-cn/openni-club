import {cp,mkdir,readdir,readFile,writeFile,access,rm} from 'node:fs/promises';
import {join,basename,resolve,relative,sep} from 'node:path';
import sharp from 'sharp';
import {buildDocs} from './lib/docs-site.mjs';
import {stateGroup,sourceBaseForRef} from '../apps/showcase/gallery-model.js';
// 本地/草稿预览通过 OPENNI_SOURCE_REF 指定分支；正式构建未设置时保持 main。
const sourceBase=sourceBaseForRef(process.env.OPENNI_SOURCE_REF || 'main');
const root=process.cwd();await rm('dist',{recursive:true,force:true});await mkdir('dist',{recursive:true});await cp('apps/showcase','dist',{recursive:true});
const adminRoot=resolve('apps/admin');
await cp(adminRoot,'dist/admin',{recursive:true,filter:source=>relative(adminRoot,source).split(sep)[0]!=='screenshots'});
await cp('apps/studio','dist/studio',{recursive:true});
await mkdir('dist/vendor',{recursive:true});await cp('node_modules/fflate/esm/browser.js','dist/vendor/fflate.js');
const {count:docCount}=await buildDocs({root:process.cwd(),outDir:'dist/guide',sourceBase});
await access('apps/mobile/build/web/index.html');await cp('apps/mobile/build/web','dist/demo',{recursive:true});
await mkdir('dist/screens',{recursive:true});const files=await readdir('apps/mobile/screenshots');for(const f of files.filter(f=>f.endsWith('.png')))await cp(join('apps/mobile/screenshots',f),join('dist/screens',f));
const required=['home','services','service','players','player','booking','orders','order','profile','announcements','settings'];for(const id of required)await access(`dist/screens/${id}.png`);
const baseCatalog=JSON.parse(await readFile('apps/showcase/catalog.json','utf8'));
const adminTitles={orders:['全部订单','fulfillment'],overview:['今日待办','fulfillment'],dispatch:['派单工作台','fulfillment'],order:['订单详情','fulfillment'],disputes:['售后处理','fulfillment'],settlements:['收入与结算','member'],club:['品牌与发布','account'],brand:['品牌与发布','account'],services:['服务目录','discover'],players:['成员与排班','member'],members:['成员与排班','member'],announcements:['俱乐部公告','account'],connection:['连接与集成','account']};
const gallery=[],seenIds=new Set(),seenFiles=new Set();
for(const [platform,dir] of [['flutter','apps/mobile/screenshots'],['mini','apps/miniprogram/screenshots'],['admin','apps/admin/screenshots']]){
 let images=[];try{images=(await readdir(dir)).filter(f=>/\.(png|jpe?g)$/.test(f));}catch{continue;}
 let manifest;try{manifest=JSON.parse(await readFile(join(dir,'manifest.json'),'utf8'));}catch(error){if(error.code!=='ENOENT')throw new Error(`Cannot read screenshot manifest: ${dir}/manifest.json`,{cause:error});}
 if(manifest!==undefined&&!Array.isArray(manifest))throw Error(`${dir}/manifest.json must be an array`);
 let items=manifest??images.map(file=>({id:file.replace(/\.(png|jpe?g)$/,''),file}));
 for(const item of items){
  const file=item.file|| (item.image?basename(item.image):images.find(f=>f.replace(/\.(png|jpe?g)$/,'')===item.id));
  if(!file||basename(file)!==file||!images.includes(file))throw Error(`Missing screenshot for ${platform}/${item.id}`);
  if(seenIds.has(item.id)||seenFiles.has(file))throw Error(`Duplicate screenshot id or file: ${platform}/${item.id}`);
  seenIds.add(item.id);seenFiles.add(file);
  const shortId=item.id.replace(/^(mini-|admin-)/,''),original=baseCatalog.find(s=>s.id===shortId)||{};
  const meta=adminTitles[shortId];if(platform==='admin'&&!manifest&&!meta)continue;
  const info=await sharp(join(dir,file)).metadata();
  const title=item.title||meta?.[0]||original.title||shortId;
  const flow=item.flow||meta?.[1]||original.flow||'account';
  await cp(join(dir,file),join('dist/screens',file));
  const screen={...original,...item,id:item.id,platform,title,flow,role:item.role||(platform==='admin'?'operator':original.role||'customer'),description:item.description||original.description||title,image:`/screens/${file}`,width:info.width,height:info.height,source:item.source||(platform==='admin'?'apps/admin/operations.js':platform==='mini'?`apps/miniprogram/pages/${shortId}/${shortId}.wxml`:'apps/mobile/lib/screens.dart')};
  await access(screen.source);screen.sourceBase=sourceBase;screen.stateGroup=stateGroup(screen);gallery.push(screen);
 }
}
await writeFile('dist/screens.json',JSON.stringify(gallery));
await writeFile('dist/extra-screens.json',JSON.stringify(gallery.filter(s=>s.platform!=='flutter')));
await writeFile('dist/robots.txt','User-agent: *\nAllow: /\nDisallow: /admin/\n');
await writeFile('dist/_headers','/*\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n  Permissions-Policy: camera=(), microphone=(), geolocation=()\n');
console.log(`Built showcase, ${docCount} guides, admin, Flutter demo, ${gallery.length} real screenshots.`);
