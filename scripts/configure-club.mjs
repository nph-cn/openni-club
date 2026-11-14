#!/usr/bin/env node
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFile } from 'node:fs/promises';
import { PROJECT_ROOT, loadClubConfig, ConfigError } from './lib/club-config.mjs';
import { renderArtifacts, planArtifacts, applyArtifacts } from './lib/club-artifacts.mjs';
export async function configure({ configPath, root = PROJECT_ROOT, mode = 'preview', action = 'check' }) {
  const loaded = await loadClubConfig(configPath, { mode });
  if (action === 'check') return { valid: true, mode, configHash: loaded.configHash, clubId: loaded.runtime.clubId, productionVerified: false };
  const { artifacts, manifest } = await renderArtifacts(loaded); const changes = await planArtifacts(root, artifacts);
  let previous = {}; try { previous = JSON.parse(await readFile(resolve(root, 'generated/club/public.json'), 'utf8')); } catch {}
  const brandChanges = ['name', 'shortName', 'primaryColor', 'apiBaseUrl', 'mode', 'legalEntity', 'supportContact', 'wechatAppId', 'wechatMiniAppId', 'universalLink']
    .filter(key => previous[key] !== loaded.runtime[key]).map(key => ({ field: key, before: previous[key] ?? null, after: loaded.runtime[key] }));
  for (const key of ['privacyText', 'termsText']) if (previous[key] !== loaded.runtime[key]) brandChanges.push({ field: key, beforeCharacters: previous[key]?.length ?? 0, afterCharacters: loaded.runtime[key].length });
  if (action === 'apply') await applyArtifacts(root, artifacts);
  return { valid: true, mode, applied: action === 'apply', configHash: manifest.configHash, brandChanges, changes, productionVerified: false };
}
async function main() {
  let action = 'check', mode = 'preview', configPath = resolve(PROJECT_ROOT, 'config/club.json'), root = PROJECT_ROOT, asJson = false;
  const args = process.argv.slice(2);
  if (args.includes('--help')) { console.log('node scripts/configure-club.mjs --check|--plan|--apply [config/club.json] [--mode preview|production] [--json]\n--plan 只列差异；--apply 生成跨端品牌并失败回滚，不修改用户/订单数据库。'); return; }
  for (let i = 0; i < args.length; i++) {
    if (['--check', '--plan', '--apply'].includes(args[i])) action = args[i].slice(2);
    else if (args[i] === '--mode' && args[i + 1]) mode = args[++i];
    else if (args[i] === '--root' && args[i + 1]) root = resolve(args[++i]);
    else if (args[i] === '--json') asJson = true;
    else if (!args[i].startsWith('-')) configPath = resolve(args[i]);
    else throw new ConfigError(['未知参数；运行 --help 查看用法']);
  }
  const result = await configure({ configPath, root, mode, action });
  if (asJson) console.log(JSON.stringify(result, null, 2));
  else { console.log(`品牌配置${action === 'apply' ? '已生成' : '检查通过'} · ${mode} · ${result.configHash.slice(0, 12)}`);
    for (const item of result.brandChanges ?? []) console.log(`${item.field}: ${Object.hasOwn(item, 'after') ? `${JSON.stringify(item.before)} → ${JSON.stringify(item.after)}` : `${item.beforeCharacters} → ${item.afterCharacters} 字符`}`);
    for (const change of result.changes ?? []) console.log(`${change.action.padEnd(9)} ${change.path}`); console.log('配置/构建不代表真机、商户或商店审核通过。'); }
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main().catch(error => { console.error(error instanceof ConfigError ? error.issues.join('\n') : '品牌生成失败，已尝试恢复原文件；请检查磁盘与文件权限。'); process.exitCode = 1; });
