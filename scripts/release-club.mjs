#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROJECT_ROOT, ConfigError } from './lib/club-config.mjs';
import { parseEnv } from './doctor.mjs';
import { releaseClub } from './lib/club-release.mjs';
async function main() {
  const options = { root: PROJECT_ROOT, configPath: resolve(PROJECT_ROOT, 'config/club.json'), mode: 'preview', platform: 'web' };
  let envPath = resolve(PROJECT_ROOT, '.env'); const args = process.argv.slice(2);
  if (args.includes('--help')) { console.log('node scripts/release-club.mjs --config club.json --platform web|android|ios|wechat --mode preview|production [--base-href /demo/] [--env .env] [--plan] [--upload]\n默认真实执行构建；--plan 仅检查并列步骤。--upload 仅明确上传微信代码，不代表审核/发布。'); return; }
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--config' && args[i + 1]) options.configPath = resolve(args[++i]);
    else if (args[i] === '--platform' && args[i + 1]) options.platform = args[++i];
    else if (args[i] === '--mode' && args[i + 1]) options.mode = args[++i];
    else if (args[i] === '--base-href' && args[i + 1]) options.baseHref = args[++i];
    else if (args[i] === '--env' && args[i + 1]) envPath = resolve(args[++i]);
    else if (args[i] === '--plan') options.plan = true;
    else if (args[i] === '--upload') options.upload = true;
    else throw new ConfigError(['未知或不完整参数；使用 --help']);
  }
  let parsed = { values: {}, errors: [] }; try { parsed = parseEnv(await readFile(envPath, 'utf8')); } catch {}
  if (parsed.errors.length) throw new ConfigError(parsed.errors);
  const result = await releaseClub({ ...options, env: { ...parsed.values, ...process.env }, onStage: name => console.log(`正在执行 ${name}…`) });
  console.log(JSON.stringify(result, null, 2)); if (['failed', 'blocked'].includes(result.status)) process.exitCode = 1;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main().catch(error => { console.error(error instanceof ConfigError ? error.issues.join('\n') : '发布流程失败；未标记为上架。请检查本地环境。'); process.exitCode = 1; });
