import { readFile, stat } from 'node:fs/promises';
import { dirname, resolve, isAbsolute, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import sharp from 'sharp';
export const PROJECT_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
export const GENERATOR_VERSION = '1.0.0';
export const hash = bytes => createHash('sha256').update(bytes).digest('hex');
export const stable = value => value && typeof value === 'object' ? Array.isArray(value) ? value.map(stable) : Object.fromEntries(Object.keys(value).sort().map(key => [key, stable(value[key])])) : value;
export const json = value => JSON.stringify(stable(value), null, 2) + '\n';
export class ConfigError extends Error { constructor(issues) { super('俱乐部配置校验失败'); this.issues = issues; } }

function validate(value, schema, path, issues) {
  if (schema.const !== undefined && value !== schema.const) issues.push(`${path} 必须为 ${schema.const}`);
  if (schema.type === 'object') {
    if (!value || typeof value !== 'object' || Array.isArray(value)) { issues.push(`${path} 必须是对象`); return; }
    for (const key of schema.required ?? []) if (!Object.hasOwn(value, key)) issues.push(`${path}.${key} 必填`);
    for (const [key, child] of Object.entries(value)) {
      if (Object.hasOwn(schema.properties ?? {}, key)) validate(child, schema.properties[key], `${path}.${key}`, issues);
      else if (schema.additionalProperties === false) issues.push(`${path} 包含不支持的字段（字段内容已隐藏）`);
    }
  } else if (schema.type === 'string') {
    if (typeof value !== 'string') { issues.push(`${path} 必须是文本`); return; }
    if (/[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(value)) issues.push(`${path} 含控制字符`);
    if (schema.minLength && value.trim().length < schema.minLength) issues.push(`${path} 不能为空`);
    if (schema.maxLength && value.length > schema.maxLength) issues.push(`${path} 超出长度限制`);
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) issues.push(`${path} 格式无效`);
  } else if (schema.type === 'integer' && (!Number.isSafeInteger(value) || value < schema.minimum || value > schema.maximum)) issues.push(`${path} 必须是规定范围内的整数`);
  else if (schema.type === 'array' && (!Array.isArray(value) || value.length > schema.maxItems)) issues.push(`${path} 必须是最多 ${schema.maxItems} 项的数组`);
}
function rejectSecrets(value, issues) {
  if (Array.isArray(value)) { value.forEach(item => rejectSecrets(item, issues)); return; }
  if (!value || typeof value !== 'object') return;
  for (const [key, entry] of Object.entries(value)) {
    if (/secret|token|password|private.?key|api.?v3.?key|access.?key|admin.?credential/i.test(key)) issues.push('公开配置含疑似秘密字段；请移到独立服务器秘密配置（字段和值已隐藏）');
    if (typeof entry === 'string' && /-----BEGIN (?:RSA |EC |ENCRYPTED )?PRIVATE KEY-----/.test(entry)) issues.push('公开配置不能包含私钥');
    rejectSecrets(entry, issues);
  }
}
function urlValid(value, production) {
  if (!value) return true;
  try { const u = new URL(value); return (production ? u.protocol === 'https:' : ['http:', 'https:'].includes(u.protocol)) && !u.username && !u.password && !u.search && !u.hash; } catch { return false; }
}
function validateCatalog(catalog, issues) {
  const ids = new Set();
  for (const [type, rows] of Object.entries(catalog ?? {})) {
    if (!Array.isArray(rows)) continue;
    for (const row of rows) {
      if (!row || typeof row !== 'object' || Array.isArray(row) || typeof row.id !== 'string' || !/^[a-zA-Z0-9_-]{1,64}$/.test(row.id) || ids.has(`${type}:${row.id}`)) { issues.push(`initialCatalog.${type} 含无效或重复 ID`); continue; }
      ids.add(`${type}:${row.id}`);
      for(const key of ['coverUrl','gameIconUrl','bannerUrl','imageUrl','avatarUrl'])if(row[key]){try{const u=new URL(row[key]);if(u.protocol!=='https:'||u.username||u.password||row[key].length>2048)throw Error();}catch{issues.push(`initialCatalog.${type}.${key} 必须是有效 HTTPS 图片地址`);}}
      if(type==='banners'&&((typeof row.title!=='string'||!row.title.trim())||!row.imageUrl||(!row.serviceId&&!row.game)||!Number.isInteger(row.sortOrder??0)||(row.sortOrder??0)<0||(row.sortOrder??0)>1000))issues.push('initialCatalog.banners 需要标题、图片、目标服务或游戏及有效排序');
      if(type==='banners'&&row.serviceId&&!catalog.services?.some(s=>s.id===row.serviceId))issues.push('initialCatalog.banners 目标服务不存在');
      if (type === 'services' && (typeof row.title !== 'string' || !row.title.trim() || !Number.isSafeInteger(row.priceCents) || row.priceCents <= 0 || !Number.isSafeInteger(row.durationMinutes) || row.durationMinutes < 15)) issues.push('initialCatalog.services 需要名称、正整数分价格和至少15分钟时长');
      if (type === 'players' && (typeof row.name !== 'string' || !row.name.trim() || !Array.isArray(row.games))) issues.push('initialCatalog.players 需要名称及游戏列表');
      if (type === 'announcements' && (typeof row.title !== 'string' || typeof row.body !== 'string')) issues.push('initialCatalog.announcements 需要标题和正文');
    }
  }
}
export async function loadClubConfig(configPath, { mode = 'preview' } = {}) {
  if (!['preview', 'production'].includes(mode)) throw new ConfigError(['mode 必须是 preview 或 production']);
  let source;
  try { source = JSON.parse(await readFile(configPath, 'utf8')); } catch { throw new ConfigError(['无法读取有效的俱乐部 JSON；内容已隐藏']); }
  const schema = JSON.parse(await readFile(join(PROJECT_ROOT, 'config/club.schema.json'), 'utf8'));
  const issues = []; rejectSecrets(source, issues); validate(source, schema, 'club', issues);
  if (issues.length) throw new ConfigError(issues);
  const production = mode === 'production';
  const brand = source.brand, d = source.distribution ?? {}, operator = source.operator ?? {}, legal = source.legal ?? {}, endpoints = source.endpoints ?? {};
  if (/[\r\n\\]|\$\(|\/\//.test(brand.name) || /[\r\n]/.test(brand.shortName ?? '')) issues.push('品牌名称不能包含换行、反斜杠或原生构建控制语法');
  for (const value of [endpoints.apiBaseUrl, endpoints.siteUrl, d.universalLink]) if (!urlValid(value, production)) issues.push('公开 URL 格式无效；不可包含凭证、查询参数或片段，正式环境必须 HTTPS');
  if (production) {
    for (const [name, value] of Object.entries({ legalEntity: operator.legalEntity, supportContact: operator.supportContact, privacyText: legal.privacyText, termsText: legal.termsText, apiBaseUrl: endpoints.apiBaseUrl, siteUrl: endpoints.siteUrl })) if (!value?.trim()) issues.push(`正式发布需要 ${name}`);
    if ([brand.name, operator.legalEntity, operator.supportContact].some(value => /你的|示例|example|占位/i.test(value ?? ''))) issues.push('正式配置需替换示例名称、经营主体与联系方式');
    if (!d.clubId) issues.push('正式发布需要固定 distribution.clubId；发布后不要更改');
  }
  validateCatalog(source.initialCatalog, issues);
  if (issues.length) throw new ConfigError(issues);
  if (isAbsolute(brand.logo) || /^\w+:/.test(brand.logo) || brand.logo.split(/[\\/]/).includes('..')) throw new ConfigError(['Logo 必须位于配置目录内，使用相对图片路径']);
  const logoPath = resolve(dirname(configPath), brand.logo);
  let logo;
  try { const info = await stat(logoPath); if (!info.isFile() || info.size > 5 * 1024 * 1024) throw new Error(); logo = await readFile(logoPath); } catch { throw new ConfigError(['Logo 不存在或超过5MB；请放入配置包的 assets/brand/ 目录']); }
  if (/\.svg$/i.test(logoPath) && /<script|<foreignObject|<!DOCTYPE|<!ENTITY|(?:href\s*=\s*["']\s*(?:https?:|file:|data:))|url\(/i.test(logo.toString('utf8'))) throw new ConfigError(['SVG Logo 不能引用外部资源或包含脚本']);
  let image;
  try { image = await sharp(logo, { limitInputPixels: 40000000 }).metadata(); } catch { throw new ConfigError(['Logo 不是可读取的 PNG/JPEG/WebP/SVG 图片']); }
  if (!['png', 'jpeg', 'webp', 'svg'].includes(image.format)) throw new ConfigError(['Logo 仅支持 PNG/JPEG/WebP/SVG']);
  if (production && image.format !== 'svg' && Math.min(image.width, image.height) < 512) throw new ConfigError(['正式图标原图短边至少512像素，推荐1024像素']);
  const clubId = d.clubId ?? `club-${hash(brand.name).slice(0, 10)}`;
  const configHash = hash(json({ source, logoHash: hash(logo), mode, generatorVersion: GENERATOR_VERSION }));
  const runtime = { schemaVersion: 1, clubId, id: clubId, name: brand.name.trim(), shortName: brand.shortName?.trim() || [...brand.name.trim()].slice(0, 4).join(''),
    tagline: brand.tagline || '和同频队友，一起上场', description: brand.description || `${brand.name.trim()}的俱乐部服务、成员与预约入口。`,
    city: operator.city || '线上俱乐部', notice: brand.notice || (production ? '预约前请阅读服务说明与退款规则。' : '预览环境 · 示例服务与成员，不收款。'),
    primaryColor: brand.primaryColor || '#2455E7', logoAsset: 'assets/brand/logo.png', logoUrl: endpoints.apiBaseUrl ? `${endpoints.apiBaseUrl.replace(/\/$/, '')}/brand/logo.png` : '', legalEntity: operator.legalEntity || '',
    supportContact: operator.supportContact || '', privacyText: legal.privacyText || '', termsText: legal.termsText || '', demoData: !production,
    apiBaseUrl: endpoints.apiBaseUrl || '', mode: production ? 'production' : 'demo', wechatAppId: d.wechatNativeAppId || '',
    wechatMiniAppId: d.wechatMiniAppId || '', universalLink: d.universalLink || '', configHash };
  return { source, runtime, logo, configHash, mode, distribution: { androidApplicationId: d.androidApplicationId || `club.openni.c${hash(clubId).slice(0, 10)}`,
    iosBundleId: d.iosBundleId || `club.openni.c${hash(clubId).slice(0, 10)}`, version: d.version || '0.1.0', buildNumber: d.buildNumber || 1, appleTeamId: d.appleTeamId || '', ...d } };
}
export const escapeHtml = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');
export function policyHtml(club, kind) {
  const title = kind === 'privacy' ? '隐私说明' : '服务条款'; const content = kind === 'privacy' ? club.privacyText : club.termsText;
  const paragraphs = (content || '预览占位：经营者尚未填写正式内容。此页面不能作为正式政策提交。').split(/\r?\n/).filter(Boolean).map(line => `<p>${escapeHtml(line)}</p>`).join('\n');
  return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(club.name)} · ${title}</title><style>body{max-width:760px;margin:60px auto;padding:0 24px;font-family:system-ui,sans-serif;line-height:1.8;color:#16213a}h1{line-height:1.3}footer{border-top:1px solid #ddd;margin-top:40px;padding-top:20px}p{white-space:pre-wrap;overflow-wrap:anywhere}</style></head><body><h1>${escapeHtml(club.name)} · ${title}</h1>${paragraphs}<footer><p>经营主体：${escapeHtml(club.legalEntity || '尚未填写')}</p><p>联系方式：${escapeHtml(club.supportContact || '尚未填写')}</p></footer></body></html>\n`;
}
