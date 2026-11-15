import {zipSync,strToU8} from '/vendor/fflate.js';
const $=selector=>document.querySelector(selector), form=$('#studio-form');
let step=0,logoFile=null,logoObjectUrl='',logoExtension='png';
const value=name=>form.elements.namedItem(name)?.value.trim()||'';
const htmlElement=(tag,text,className)=>{const el=document.createElement(tag);if(text!==undefined)el.textContent=text;if(className)el.className=className;return el;};
function compact(object){return Object.fromEntries(Object.entries(object).filter(([,v])=>v!==''&&v!==undefined));}
function configuration(){return {schemaVersion:1,brand:compact({name:value('brandName'),logo:`assets/brand/logo.${logoExtension}`,shortName:value('shortName'),tagline:value('tagline'),description:value('description'),primaryColor:value('primaryColor'),iconBackground:'#ffffff'}),operator:compact({legalEntity:value('legalEntity'),supportContact:value('supportContact'),city:value('city')}),legal:compact({privacyText:value('privacyText'),termsText:value('termsText')}),distribution:compact({clubId:value('clubId'),androidApplicationId:value('androidApplicationId'),iosBundleId:value('iosBundleId'),appleTeamId:value('appleTeamId'),wechatMiniAppId:value('wechatMiniAppId'),wechatNativeAppId:value('wechatNativeAppId'),universalLink:value('universalLink'),version:'1.0.0',buildNumber:1}),endpoints:compact({apiBaseUrl:value('apiBaseUrl'),siteUrl:value('siteUrl')})};}
function brandReady(){return Boolean(value('brandName')&&logoFile);}
function policyReady(){return ['legalEntity','supportContact','privacyText','termsText'].every(name=>value(name));}
function checkCurrent(){
 if(step===0&&!brandReady()){$('#logo-error').textContent=!logoFile?'请先选择 Logo 文件。':'请填写俱乐部名称。';if(!value('brandName'))form.elements.brandName.reportValidity();return false;}
 for(const field of document.querySelector(`[data-panel="${step}"]`).querySelectorAll('input:not([type=file]),textarea'))if(field.value&&!field.checkValidity()){field.reportValidity();return false;}
 return true;
}
function showStep(next){
 if(next>step&&!checkCurrent())return;
 step=Math.max(0,Math.min(3,next));
 document.querySelectorAll('[data-panel]').forEach(panel=>panel.hidden=Number(panel.dataset.panel)!==step);
 document.querySelectorAll('[data-step]').forEach(button=>{button.classList.toggle('selected',Number(button.dataset.step)===step);button.setAttribute('aria-current',Number(button.dataset.step)===step?'step':'false');});
 $('#previous-step').hidden=step===0;$('#next-step').hidden=step===3;$('#step-caption').textContent=`${step+1} / 4`;
 if(step===3)renderReadiness();window.scrollTo({top:0,behavior:'smooth'});
}
function updateBrand(){
 const name=value('brandName')||'你的俱乐部';$('#preview-brand strong').textContent=name;$('#preview-brand small').textContent=value('tagline')||'';$('#color-hex').textContent=value('primaryColor').toUpperCase();
 document.querySelectorAll('[data-color]').forEach(button=>button.classList.toggle('selected',button.dataset.color===value('primaryColor')));
 if(step===3)renderReadiness();
}
function refreshPreview(){const url=new URL('/demo/',location.origin);url.searchParams.set('previewName',value('brandName')||'你的俱乐部');url.searchParams.set('previewColor',value('primaryColor'));if(logoObjectUrl)url.searchParams.set('previewLogo',logoObjectUrl);$('#app-preview').src=url.href;updateBrand();}
$('#logo-file').onchange=async event=>{
 const file=event.target.files[0];if(!file)return;
 $('#logo-error').textContent='';
 try{
  if(file.size>5*1024*1024)throw Error('Logo 最大支持 5 MB，请选择较小的源文件。');
  const bytes=new Uint8Array(await file.arrayBuffer());
  const isPng=bytes.slice(0,8).every((b,i)=>b===[137,80,78,71,13,10,26,10][i])&&bytes.length>8;
  const text=isPng?'':new TextDecoder().decode(bytes);
  if(!isPng&&(!/<svg[\s>]/i.test(text)||/<(?:script|foreignObject)\b|<!DOCTYPE|<!ENTITY|url\(/i.test(text)||/(?:href|xlink:href)\s*=\s*["']\s*(?:https?:|file:|data:|\/\/)/i.test(text)))throw Error('请选择有效 PNG，或不含脚本、实体和外部引用的 SVG。');
  const nextUrl=URL.createObjectURL(file);const image=new Image();image.src=nextUrl;
  try{await image.decode();}catch{URL.revokeObjectURL(nextUrl);throw Error('无法读取这张 Logo，请换一个 PNG 或 SVG 文件。');}
  if(logoObjectUrl)URL.revokeObjectURL(logoObjectUrl);logoFile=file;logoExtension=isPng?'png':'svg';logoObjectUrl=nextUrl;
  $('#logo-preview').src=nextUrl;$('#logo-preview').hidden=false;$('#logo-placeholder').hidden=true;$('#logo-filename').textContent=file.name;$('#preview-brand img').src=nextUrl;refreshPreview();
 }catch(error){$('#logo-error').textContent=error.message;event.target.value='';}
};
form.addEventListener('input',updateBrand);form.addEventListener('change',event=>{if(['brandName','primaryColor'].includes(event.target.name))refreshPreview();});form.addEventListener('submit',event=>event.preventDefault());
document.querySelectorAll('[data-color]').forEach(button=>button.onclick=()=>{form.elements.primaryColor.value=button.dataset.color;updateBrand();refreshPreview();});
document.querySelectorAll('[data-step]').forEach(button=>button.onclick=()=>showStep(Number(button.dataset.step)));
$('#next-step').onclick=()=>{if(step===0&&checkCurrent())refreshPreview();showStep(step+1);};$('#previous-step').onclick=()=>showStep(step-1);$('#refresh-preview').onclick=refreshPreview;
function renderReadiness(){
 const rows=[
  ['品牌预览',brandReady(),brandReady()?'名称与 Logo 已准备好，可生成三端品牌。':'先填写名称，并选择 Logo。','可生成'],
  ['经营与政策',policyReady(),policyReady()?'已填写经营主体、客服联系与政策正文，仍需核实内容。':'正式运营前填写经营主体、客服、隐私政策与服务协议。','已填写'],
  ['服务端与域名',!!value('apiBaseUrl')&&!!value('siteUrl'),'需要部署 API、配置 HTTPS，再用 doctor 检查连接。','已填写'],
  ['微信应用身份',!!value('wechatMiniAppId')||!!value('wechatNativeAppId'),'小程序与原生 App 使用不同 AppID，发布时分别校验。','已填写'],
  ['设备、商户与上架',false,'签名、真机登录、真实商户支付/退款联调与平台审核尚未在这里执行。','未验证']
 ];
 $('#readiness').replaceChildren();for(const [title,ready,description,status]of rows){const row=htmlElement('div',undefined,'readiness-row'+(ready?' ready':''));const icon=htmlElement('span',ready?'✓':'·','readiness-icon'),text=htmlElement('div');text.append(htmlElement('h3',title));row.append(icon,text,htmlElement('span',ready?status:'待完成'));$('#readiness').append(row);}
 $('#export-name').textContent=value('brandName')||'俱乐部配置';$('#export-config').disabled=!brandReady();
}
function randomAdminToken(){const bytes=crypto.getRandomValues(new Uint8Array(32));return btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');}
const secretFields=['WECHAT_APP_SECRET','WECHAT_NATIVE_APP_SECRET','WECHAT_PAY_MCH_ID','WECHAT_PAY_MERCHANT_SERIAL','WECHAT_PAY_API_V3_KEY','WECHAT_PAY_PRIVATE_KEY_PATH','WECHAT_PAY_PLATFORM_KEY_ID','WECHAT_PAY_PLATFORM_KEY_PATH','TENCENT_SMS_SECRET_ID','TENCENT_SMS_SECRET_KEY','TENCENT_SMS_SDK_APP_ID','TENCENT_SMS_SIGN_NAME','TENCENT_SMS_TEMPLATE_ID'];
function serverEnv(config){
 const origins=['http://localhost:4173','http://localhost:8080'];if(config.endpoints.siteUrl)origins.push(new URL(config.endpoints.siteUrl).origin);
 const api=config.endpoints.apiBaseUrl||'';const line=(key,text)=>{if(/[\r\n\0]/.test(text))throw Error(`${key} 不可包含换行。`);return `${key}=${JSON.stringify(text)}`;};
 return ['# OpenNI server-only configuration. Keep this file private.','# Payment remains disabled until verified merchant testing.','API_MODE=demo','HOST=127.0.0.1','PORT=8787','DATA_DIR=./data',line('ADMIN_TOKEN',randomAdminToken()),line('CORS_ORIGINS',origins.join(',')),line('WECHAT_APP_ID',config.distribution.wechatMiniAppId||''),line('WECHAT_NATIVE_APP_ID',config.distribution.wechatNativeAppId||''),'WECHAT_PAY_ENABLED=false','WECHAT_NATIVE_PAY_ENABLED=false',...secretFields.map(key=>line(key,value(key))),'# Keep SMS_HASH_SECRET with the existing database; do not replace it on redeploy.','SMS_PROVIDER=disabled',line('SMS_HASH_SECRET',value('SMS_HASH_SECRET')||randomAdminToken()),line('TENCENT_SMS_REGION',value('TENCENT_SMS_REGION')||'ap-guangzhou'),line('TENCENT_SMS_TEMPLATE_HAS_MINUTES',value('TENCENT_SMS_TEMPLATE_HAS_MINUTES')||'false'),line('WECHAT_PAY_NOTIFY_URL',api?`${api.replace(/\/$/,'')}/payments/wechat/notify`:''),line('WECHAT_NATIVE_PAY_NOTIFY_URL',api?`${api.replace(/\/$/,'')}/payments/wechat-app/notify`:''),line('WECHAT_PAY_REFUND_NOTIFY_URL',api?`${api.replace(/\/$/,'')}/payments/wechat/refund-notify`:''),line('WECHAT_NATIVE_PAY_REFUND_NOTIFY_URL',api?`${api.replace(/\/$/,'')}/payments/wechat-app/refund-notify`:'')].join('\n')+'\n';
}
$('#export-config').onclick=async()=>{
 const button=$('#export-config');button.disabled=true;$('#export-status').textContent='';
 try{
  if(!brandReady())throw Error('请先填写名称并上传 Logo。');
  const config=configuration();
  if(config.brand.name.length>40||/[\r\n]/.test(config.brand.name))throw Error('俱乐部名称最多40字符，不能包含换行。');
  const patterns={clubId:/^[a-z][a-z0-9-]{2,39}$/,androidApplicationId:/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){2,}$/,iosBundleId:/^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*){2,}$/,appleTeamId:/^[A-Z0-9]{10}$/,wechatMiniAppId:/^wx[0-9A-Za-z]{16}$/,wechatNativeAppId:/^wx[0-9A-Za-z]{16}$/};
  for(const [key,pattern]of Object.entries(patterns))if(config.distribution[key]&&!pattern.test(config.distribution[key]))throw Error(`${key} 格式无效，请核对账号中的公开标识。`);
  const urls={...config.endpoints,...(config.distribution.universalLink?{universalLink:config.distribution.universalLink}:{})};
  for(const [key,url]of Object.entries(urls)){const parsed=new URL(url);if(parsed.protocol!=='https:')throw Error(`${key} 请使用 HTTPS 地址；预览时可以留空。`);if(parsed.username||parsed.password||parsed.hash||parsed.search)throw Error(`${key} 不应包含凭证、查询参数或片段。`);}
  const instructions=`# ${config.brand.name} · OpenNI 配置包\n\n1. 获取 https://github.com/nph-cn/openni-club 的源代码。\n2. 将本配置包解压到源代码的 config 目录。\n3. 在仓库根目录执行：\n\n   npm install\n   node scripts/configure-club.mjs --check config/club.json\n   node scripts/configure-club.mjs --plan config/club.json\n   node scripts/configure-club.mjs --apply config/club.json\n\n4. server.env 是秘密文件，移动到项目根目录并重命名 .env，或存入部署平台的秘密配置。不要提交 Git 或放进公开网站目录。\n5. 初始 API_MODE=demo、支付关闭，先完成演示。正式发布先执行 configure-club --apply config/club.json --mode production，再执行 node scripts/release-club.mjs --config config/club.json --platform android --mode production --env .env --plan。去掉 --plan 才会运行真实工具链；iOS/微信请替换对应平台参数。详细操作见 docs/10-single-config-workflow.md。短信配置仅保存在 server.env，按 docs/11-phone-auth.md 配置生产环境后显式启用；已有数据库必须保留原 SMS_HASH_SECRET。\n\n本配置包含填写结果，不是连接成功、真机通过或商店审核通过的证明。正式经营服务和成员资料在工作台添加，不使用虚构人物。\n`;
  const zip=zipSync({'club.json':strToU8(JSON.stringify(config,null,2)+'\n'),[`assets/brand/logo.${logoExtension}`]:new Uint8Array(await logoFile.arrayBuffer()),'server.env':strToU8(serverEnv(config)),'README.md':strToU8(instructions)},{level:6});
  const url=URL.createObjectURL(new Blob([zip],{type:'application/zip'})),link=htmlElement('a');link.href=url;link.download=`${value('clubId')||'openni-club'}-config.zip`;document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),30000);
  $('#export-status').style.color='#35855a';$('#export-status').textContent='配置包已生成。server.env 含秘密凭证，请妥善保管。';
 }catch(error){$('#export-status').style.color='';$('#export-status').textContent=error.message;}
 finally{button.disabled=!brandReady();}
};
window.addEventListener('beforeunload',()=>{if(logoObjectUrl)URL.revokeObjectURL(logoObjectUrl);});
