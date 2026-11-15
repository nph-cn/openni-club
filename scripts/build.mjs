import {cp,mkdir,readdir,readFile,writeFile,access,rm} from 'node:fs/promises';
import {join,basename,resolve,relative,sep} from 'node:path';
import sharp from 'sharp';
import {buildDocs} from './lib/docs-site.mjs';
import {labels,stateGroup,sourceBaseForRef} from '../apps/showcase/gallery-model.js';

// 本地/草稿预览通过 OPENNI_SOURCE_REF 指定分支；正式构建未设置时保持 main。
const sourceBase=sourceBaseForRef(process.env.OPENNI_SOURCE_REF || 'main');
const root=process.cwd();
const warnings=[];

// 1. 站点外壳：图库首页、后台、Studio、文档、App 演示与依赖。
await rm('dist',{recursive:true,force:true});
await mkdir('dist',{recursive:true});
await cp('apps/showcase','dist',{recursive:true});
const adminRoot=resolve('apps/admin');
await cp(adminRoot,'dist/admin',{recursive:true,filter:source=>relative(adminRoot,source).split(sep)[0]!=='screenshots'});
await cp('apps/studio','dist/studio',{recursive:true});
await mkdir('dist/vendor',{recursive:true});
await cp('node_modules/fflate/esm/browser.js','dist/vendor/fflate.js');
const {count:docCount}=await buildDocs({root:process.cwd(),outDir:'dist/guide',sourceBase});
await access('apps/mobile/build/web/index.html');
await cp('apps/mobile/build/web','dist/demo',{recursive:true});
await mkdir('dist/screens',{recursive:true});

// 2. 截图元数据：manifest 优先，缺失时按目录兜底；catalog.json 是公共兜底说明。
const baseCatalog=JSON.parse(await readFile('apps/showcase/catalog.json','utf8'));
if(!Array.isArray(baseCatalog))throw Error('apps/showcase/catalog.json must be an array');
const catalogById=new Map(baseCatalog.map(item=>[item.id,item]));
const catalogFor=id=>catalogById.get(id)||catalogById.get(String(id).replaceAll('-','_'));
// 后台没有 manifest 时的已知页面标题与流程（截图文件名为 admin-<id>.png/jpg）。
const adminTitles={orders:['全部订单','fulfillment'],overview:['今日待办','fulfillment'],dispatch:['派单工作台','fulfillment'],order:['订单详情','fulfillment'],disputes:['售后处理','fulfillment'],settlements:['收入与结算','member'],club:['品牌与发布','account'],brand:['品牌与发布','account'],services:['服务目录','discover'],players:['成员与排班','member'],members:['成员与排班','member'],announcements:['俱乐部公告','account'],connection:['连接与集成','account'],banners:['首页横幅','account']};
const imagePattern=/\.(png|jpe?g|webp|avif)$/i;
const platforms=[
 {key:'flutter',dir:'apps/mobile/screenshots',zh:'App',defaultSource:'apps/mobile/lib/screens.dart'},
 {key:'mini',dir:'apps/miniprogram/screenshots',zh:'微信小程序',defaultSource:'apps/miniprogram/pages/home/home.wxml'},
 {key:'admin',dir:'apps/admin/screenshots',zh:'运营后台',defaultSource:'apps/admin/operations.js'}
];
const gallery=[],seenIds=new Set(),seenStems=new Set();
function stemOf(file){return file.replace(imagePattern,'');}
function humanize(id){return String(id).replace(/[_-]+/g,' ').trim();}
function inferSource(platform,shortId,item){
 if(item.source)return item.source;
 if(platform.key==='mini')return `apps/miniprogram/pages/${shortId}/${shortId}.wxml`;
 if(platform.key==='admin')return 'apps/admin/operations.js';
 return platform.defaultSource;
}
for(const platform of platforms){
 let files=[];
 try{
  files=(await readdir(platform.dir,{withFileTypes:true})).filter(entry=>entry.isFile()&&imagePattern.test(entry.name)).map(entry=>entry.name);
 }catch(error){
  if(error.code==='ENOENT')continue;
  throw error;
 }
 if(!files.length)throw Error(`${platform.dir} 中没有可用的运行截图`);
 let manifest;
 try{
  manifest=JSON.parse(await readFile(join(platform.dir,'manifest.json'),'utf8'));
 }catch(error){
  if(error.code!=='ENOENT')throw new Error(`Cannot read screenshot manifest: ${platform.dir}/manifest.json`,{cause:error});
 }
 if(manifest!==undefined&&!Array.isArray(manifest))throw Error(`${platform.dir}/manifest.json must be an array`);
 const items=[];
 if(manifest===undefined){
  warnings.push(`${platform.dir}/manifest.json 缺失：已按目录文件名兜底纳入 ${files.length} 张截图，标题、流程与说明需要补充。`);
  for(const file of files)items.push({id:stemOf(file),file,unlisted:true});
 }else{
  for(const entry of manifest)items.push({...entry});
  // 清单漏登记的新截图也纳入图库，只按同名文件去重，不静默隐藏。
  const listedStems=new Set(items.map(item=>item.file?stemOf(item.file):stemOf(String(item.id))));
  for(const file of files){
   const stem=stemOf(file);
   if(listedStems.has(stem)||seenStems.has(stem))continue;
   listedStems.add(stem);
   warnings.push(`${platform.dir}/${file} 未在 manifest 中登记：已按目录纳入，请在 manifest 或 catalog.json 补充标题/流程/说明。`);
   items.push({id:stem,file,unlisted:true});
  }
 }
 for(const item of items){
  const file=typeof item.file==='string'
   ? item.file
   : item.image
    ? basename(String(item.image))
    : files.find(candidate=>stemOf(candidate)===String(item.id))||'';
  if(!file||basename(file)!==file||!files.includes(file))throw Error(`Missing screenshot for ${platform.key}/${item.id}`);
  const stem=stemOf(file),rawId=String(item.id||stem).trim();
  if(!rawId)throw Error(`Screenshot id is empty: ${platform.dir}/${file}`);
  if(seenIds.has(rawId))throw Error(`Duplicate screenshot id or file: ${platform.key}/${rawId}`);
  seenIds.add(rawId);
  if(seenStems.has(stem))throw Error(`Duplicate screenshot file: ${platform.key}/${file}`);
  seenStems.add(stem);
  const shortId=rawId.replace(/^(mini-|admin-)/,'');
  const original=catalogFor(shortId);
  const adminMeta=platform.key==='admin'?(adminTitles[shortId]||adminTitles[shortId.replaceAll('-','_')]):undefined;
  const title=item.title||adminMeta?.[0]||original?.title;
  const flow=item.flow||adminMeta?.[1]||original?.flow;
  const description=item.description||(platform.key==='flutter'?original?.description:undefined)||(title?`${title}（${platform.zh}运行界面）。`:'');
  if(platform.key==='flutter'){
   const missing=[];
   if(!title)missing.push('标题');
   if(!flow)missing.push('流程');
   if(!item.description&&!original?.description)missing.push('说明');
   if(missing.length)warnings.push(`${platform.dir}/${file} 缺少${missing.join('、')}：已用文件名或通用描述兜底，请补充 manifest 或 catalog.json。`);
  }
  const source=inferSource(platform,shortId,item);
  let sourcePath=source;
  try{await access(source);}catch{
   sourcePath=null;
   warnings.push(`${platform.dir}/${file} 的源码路径不存在：${source}（详情页将不显示源码链接）。`);
  }
  const info=await sharp(join(platform.dir,file)).metadata();
  if(!info.width||!info.height)throw Error(`Cannot read screenshot dimensions: ${platform.dir}/${file}`);
  await cp(join(platform.dir,file),join('dist/screens',file));
  const screen={...original,...item,id:rawId,platform:platform.key,title:title||humanize(shortId),flow:flow||'unknown',role:item.role||(platform.key==='admin'?'operator':original?.role||'customer'),description:description||humanize(shortId),image:`/screens/${file}`,width:info.width,height:info.height,source:sourcePath,sourceBase};
  screen.capturePlatform=item.platform||(/android/i.test(item.device||'')?'android':'ios');
  screen.stateGroup=stateGroup(screen);
  gallery.push(screen);
 }
}

// 3. 关键屏幕校验：真实构建必须有首页与核心流程页面，避免空图库被当成成功。
const required=['home','services','service','players','player','booking','orders','order','profile','announcements','settings'];
for(const id of required){
 const screen=gallery.find(item=>item.id===id);
 if(!screen)throw Error(`Critical screenshot is missing from gallery data: ${id}`);
 await access(`dist/screens/${basename(screen.image)}`);
}
for(const platform of platforms){
 try{
  await access(platform.dir);
 }catch{
  continue;
 }
 if(!gallery.some(screen=>screen.platform===platform.key))throw Error(`No screenshots included for ${platform.dir}`);
}

await writeFile('dist/screens.json',JSON.stringify(gallery));
await writeFile('dist/extra-screens.json',JSON.stringify(gallery.filter(screen=>screen.platform!=='flutter')));
await writeFile('dist/robots.txt','User-agent: *\nAllow: /\nDisallow: /admin/\n');
await writeFile('dist/_headers','/*\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n  Permissions-Policy: camera=(), microphone=(), geolocation=()\n');
const counts=Object.fromEntries(Object.keys(labels.platform).map(key=>[key,gallery.filter(screen=>screen.platform===key).length]));
for(const warning of warnings)console.warn(`警告：${warning}`);
console.log(`Built showcase, ${docCount} guides, admin, Flutter demo, ${gallery.length} real screenshots (${Object.entries(counts).map(([key,count])=>`${key} ${count}`).join(', ')}), ${warnings.length} warnings.`);
