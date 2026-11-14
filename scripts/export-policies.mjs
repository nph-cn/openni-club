#!/usr/bin/env node
import { mkdir, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { policyHtml, ConfigError } from './lib/club-config.mjs';
export async function exportPolicies(apiBaseUrl, outputDir, fetchImpl = fetch) {
  let url; try { url = new URL(apiBaseUrl); } catch { throw new ConfigError(['请输入有效 API URL']); }
  if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new ConfigError(['API URL 不得携带凭证/查询参数']);
  const response = await fetchImpl(`${url.href.replace(/\/$/, '')}/club`, { redirect: 'error', signal: AbortSignal.timeout(10000) });
  if (!response.ok) throw new ConfigError(['公开俱乐部 API 请求失败']);
  const club = await response.json();
  if (club.demoData || !['name', 'privacyText', 'termsText', 'legalEntity', 'supportContact'].every(key => typeof club[key] === 'string' && club[key].trim())) throw new ConfigError(['俱乐部仍为演示或经营信息/政策不完整，不能导出为正式政策']);
  await mkdir(outputDir, { recursive: true });
  for (const kind of ['privacy', 'terms']) await writeFile(join(outputDir, `${kind}.html`), policyHtml(club, kind));
  return ['privacy.html', 'terms.html'];
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length !== 4) { console.error('用法：node scripts/export-policies.mjs https://api.example.com/api/v1 ./policies'); process.exitCode = 1; }
  else exportPolicies(process.argv[2], resolve(process.argv[3])).then(files => console.log(`已导出 ${files.join('、')}；请部署到自己的 HTTPS 网站并核对内容。`)).catch(error => { console.error(error instanceof ConfigError ? error.issues.join('\n') : '政策导出失败，未输出秘密或接口详情'); process.exitCode = 1; });
}
