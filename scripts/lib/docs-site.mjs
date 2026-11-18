import {mkdir,readdir,readFile,writeFile} from 'node:fs/promises';
import {join,resolve,dirname} from 'node:path';
import {marked} from 'marked';

const repo='https://github.com/nph-cn/openni-club';
const sections=[
 {title:'开始使用',pages:[['index.md','项目介绍'],['01-quickstart.md','本地启动']]},
 {title:'品牌配置',pages:[['02-brand-and-config.md','品牌与资料'],['10-single-config-workflow.md','生成应用配置']]},
 {title:'第三方集成',pages:[['06-integrations.md','集成总览'],['09-wechat-adapters.md','微信登录与支付'],['11-phone-auth.md','手机号与验证码']]},
 {title:'服务器部署',pages:[['03-deployment.md','域名与服务器']]},
 {title:'应用发布',pages:[['04-mobile-release.md','iOS 与 Android'],['05-wechat-release.md','微信小程序'],['07-release-checklist.md','上线检查']]},
 {title:'工具与参考',pages:[['08-use-the-skill.md','使用教学 Skill'],['00-status.md','功能与版本状态'],['sources.md','参考资料']]},
 {title:'产品依据',pages:[['product/01-club-operations.md','经营闭环与角色范围'],['product/02-market-reality.md','真实服务目录结构']]}
];
const escape=value=>String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const text=value=>String(value).replace(/<[^>]*>/g,'').replace(/!\[([^\]]*)\]\([^)]*\)/g,'$1').replace(/\[([^\]]+)\]\([^)]*\)/g,'$1').replace(/[`*~]/g,'').replace(/&amp;/g,'&').replace(/\s+/g,' ').trim();
const url=file=>file==='index.md'?'/guide/':`/guide/${file.replace(/\.md$/,'.html')}`;
const slug=value=>text(value).toLowerCase().replace(/[^\p{L}\p{N}\s-]/gu,'').trim().replace(/\s+/g,'-')||'section';

export async function buildDocs({root=process.cwd(),outDir='dist/guide'}={}){
 const destination=resolve(root,outDir);await mkdir(destination,{recursive:true});
 const readMd=async file=>readFile(join(root,'docs',file),'utf8');
 const files=[];
 for(const entry of await readdir(join(root,'docs'),{withFileTypes:true})){
  if(entry.isDirectory()){
   for(const sub of await readdir(join(root,'docs',entry.name))){
    if(sub.endsWith('.md'))files.push(`${entry.name}/${sub}`);
   }
  }else if(entry.name.endsWith('.md'))files.push(entry.name);
 }
 files.sort();
 const contents=new Map(await Promise.all(files.map(async file=>[file,await readMd(file)])));
 const ordered=sections.flatMap(section=>section.pages).filter(([file])=>contents.has(file));
 for(const file of files)if(!ordered.some(([entry])=>entry===file))ordered.push([file,(contents.get(file).match(/^# (.+)$/m)||[])[1]||file]);
 const search=[];
 for(const [file,shortTitle] of ordered){
  const markdown=contents.get(file),title=text((markdown.match(/^# (.+)$/m)||[])[1]||shortTitle),headings=[],ids=new Map();
  const renderer=new marked.Renderer();
  renderer.heading=function({tokens,depth}){
   const html=this.parser.parseInline(tokens),plain=text(html),base=slug(plain),seen=ids.get(base)||0,id=seen?`${base}-${seen+1}`:base;ids.set(base,seen+1);
   if(depth===2||depth===3)headings.push({id,title:plain,depth});
   const anchor=depth>1?`<a class="heading-anchor" href="#${escape(id)}" aria-label="链接到${escape(plain)}">#</a>`:'';
   return `<h${depth} id="${escape(id)}">${html}${anchor}</h${depth}>\n`;
  };
  const content=marked.parse(markdown,{renderer,walkTokens(token){
   if(token.type!=='link'||!token.href||/^(?:[a-z]+:|#|\/)/i.test(token.href))return;
   const target=new URL(token.href,'https://repo.invalid/docs/');
   const local=target.pathname.slice('/docs/'.length);
   token.href=target.pathname.startsWith('/docs/')&&contents.has(local)?url(local)+target.search+target.hash:`${repo}/blob/main${target.pathname}${target.search}${target.hash}`;
  }});
  const pageNumber=ordered.findIndex(([entry])=>entry===file),previous=ordered[pageNumber-1],next=ordered[pageNumber+1];
  const group=sections.find(section=>section.pages.some(([entry])=>entry===file))?.title||'参考';
  const navigation=sections.map(section=>`<section class="nav-group"><h2>${section.title}</h2>${section.pages.filter(([entry])=>contents.has(entry)).map(([entry,label])=>`<a href="${url(entry)}"${entry===file?' aria-current="page"':''}>${escape(label)}</a>`).join('')}</section>`).join('');
  const toc=headings.map(heading=>`<a href="#${escape(heading.id)}" class="toc-link depth-${heading.depth}">${escape(heading.title)}</a>`).join('');
  const nextLink=([entry,label],direction)=>`<a href="${url(entry)}" class="page-${direction}"><span>${direction==='previous'?'上一页':'下一页'}</span><strong>${escape(label)}</strong></a>`;
  const html=`<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="theme-color" content="#f9fafb"><meta name="description" content="${escape(title)}。OpenNI 开源电竞俱乐部应用部署文档。"><title>${escape(title)} · OpenNI 文档</title><link rel="icon" href="/icon.svg"><link rel="stylesheet" href="/style.css"><script type="module" src="/guide.js"></script></head><body class="docs-page">
<a class="skip" href="#guide-content">跳到正文</a>
<header class="docs-header"><a class="docs-brand" href="/">OpenNI</a><a class="docs-label" href="/guide/" aria-current="page">文档</a><button class="search-trigger" type="button" aria-haspopup="dialog"><span>搜索文档</span><kbd>⌘ K</kbd></button><nav aria-label="文档站点导航"><a href="/">界面图库</a><a href="/studio/">品牌配置</a><a href="${repo}" target="_blank" rel="noreferrer">GitHub ↗</a></nav></header>
<div class="mobile-bar"><button id="open-doc-menu" type="button" aria-haspopup="dialog">菜单</button><details class="mobile-toc"><summary>本页目录</summary><nav aria-label="本页目录（移动端）">${toc||'<span>此页没有章节</span>'}</nav></details></div>
<div class="docs-layout"><aside class="docs-sidebar"><nav aria-label="文档章节">${navigation}</nav><a class="sidebar-version" href="/guide/00-status.html">v0.2 <span>功能与版本状态</span></a></aside>
<main class="docs-main"><div class="docs-breadcrumb"><span>${group}</span><span aria-hidden="true">/</span><span>${escape(shortTitle)}</span></div><article id="guide-content">${content}</article><div class="doc-source"><a href="${repo}/blob/main/docs/${file}" target="_blank" rel="noreferrer">在 GitHub 查看此页 ↗</a></div><nav class="page-navigation" aria-label="前后章节">${previous?nextLink(previous,'previous'):'<span></span>'}${next?nextLink(next,'next'):'<span></span>'}</nav><footer class="docs-footer"><span>OpenNI</span><a href="${repo}/blob/main/LICENSE">MIT License</a></footer></main>
<aside class="docs-toc"><nav aria-label="本页目录"><h2>本页目录</h2>${toc||'<span class="toc-empty">此页没有章节</span>'}</nav></aside></div>
<dialog id="doc-menu" aria-labelledby="doc-menu-title"><div class="menu-title"><span id="doc-menu-title">文档目录</span><button type="button" data-close-dialog="doc-menu" aria-label="关闭目录">关闭</button></div><nav aria-label="文档章节（移动端）">${navigation}</nav></dialog>
<dialog id="doc-search" aria-labelledby="search-label"><div class="search-form"><label class="sr-only" id="search-label" for="doc-search-input">搜索文档</label><input id="doc-search-input" type="search" autocomplete="off" placeholder="搜索文档、配置项或命令" aria-controls="doc-search-results"><button type="button" data-close-dialog="doc-search" aria-label="关闭搜索">Esc</button></div><div class="search-status" id="search-status" role="status">正在加载搜索索引…</div><div id="doc-search-results"></div><div class="search-footer"><span>↑ ↓ 选择</span><span>Enter 打开</span></div></dialog>
</body></html>`;
  const outFile=join(destination,file.replace(/\.md$/,'.html'));
  await mkdir(dirname(outFile),{recursive:true});
  await writeFile(outFile,html);
  const tokens=marked.lexer(markdown);let current={id:'',heading:shortTitle,parts:[]};
  const append=()=>{const body=text(current.parts.join(' '));if(body||!current.id)search.push({title:shortTitle,heading:current.heading,url:url(file)+(current.id?'#'+current.id:''),text:body});};
  let headingIndex=0;
  for(const token of tokens){if(token.type==='heading'&&(token.depth===2||token.depth===3)){append();const heading=headings[headingIndex++];current={id:heading.id,heading:heading.title,parts:[]};}else if(!(token.type==='heading'&&token.depth===1))current.parts.push(token.raw||token.text||'');}append();
 }
 await writeFile(join(destination,'search-index.json'),JSON.stringify(search));
 return {count:ordered.length,index:search.length};
}
