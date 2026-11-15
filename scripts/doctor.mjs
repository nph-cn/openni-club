#!/usr/bin/env node
import { existsSync, readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import {readSmsConfig} from '../services/api/src/sms-auth.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

export function parseEnv(text) {
  const values = {};
  const errors = [];
  text.split(/\r?\n/).forEach((line, index) => {
    const value = line.trim();
    if (!value || value.startsWith('#')) return;
    const match = /^(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=\s*(.*)$/.exec(value);
    if (!match) { errors.push(`环境文件第 ${index + 1} 行格式无效（内容已隐藏）`); return; }
    let entry = match[2].trim();
    if (entry.startsWith('"') || entry.startsWith("'")) {
      if (entry.at(-1) !== entry[0] || entry.length < 2) {
        errors.push(`环境文件第 ${index + 1} 行引号不完整（内容已隐藏）`);
        return;
      }
      entry = entry.slice(1, -1);
    } else entry = entry.replace(/\s+#.*$/, '').trim();
    values[match[1]] = entry;
  });
  return { values, errors };
}

export function inspectConfiguration(env, nodeVersion = process.versions.node) {
  const checks = [];
  const add = (status, name, message) => checks.push({ status, name, message });
  const mode = env.API_MODE || 'demo';
  add(Number(nodeVersion.split('.')[0]) >= 24 ? 'pass' : 'error', 'node', '推荐并以 Node.js 24 LTS 验证 SQLite API。');
  add(['demo', 'production'].includes(mode) ? 'pass' : 'error', 'mode', ['demo', 'production'].includes(mode) ? `运行模式：${mode}` : 'API_MODE 只能是 demo 或 production。');
  const port = env.PORT || '8787';
  add(/^\d+$/.test(port) && Number(port) >= 1 && Number(port) <= 65535 ? 'pass' : 'error', 'port', 'PORT 必须是 1—65535 的整数。');
  const token = env.ADMIN_TOKEN || '';
  const weak = /^(change|example|demo|password|replace|your[-_])/i.test(token) || new Set(token).size < 8;
  if (!token) add(mode === 'production' ? 'error' : 'warning', 'admin-token', 'ADMIN_TOKEN 未配置；管理员接口不可用。使用至少 32 字符随机值。');
  else add(/^[A-Za-z0-9_-]{24,}$/.test(token) && !weak ? 'pass' : 'error', 'admin-token', '管理员令牌使用至少24位base64url字符，建议随机32字符以上；不显示内容。');
  const origins = (env.CORS_ORIGINS || '').split(',').map(x => x.trim()).filter(Boolean);
  if (!origins.length) add(mode === 'production' ? 'error' : 'warning', 'cors', '未显式配置 CORS_ORIGINS；浏览器访问可能被默认来源策略阻止。');
  else {
    const valid = origins.every(value => {
      try { const url = new URL(value); return ['http:', 'https:'].includes(url.protocol) && !url.username && !url.password && url.origin === value && (mode !== 'production' || url.protocol === 'https:'); }
      catch { return false; }
    });
    add(valid ? 'pass' : 'error', 'cors', 'CORS 仅允许完整 origin；不能用 *、路径或凭证；正式模式需要 HTTPS。');
  }
  add(env.DATA_DIR ? 'pass' : 'warning', 'data', '为 DATA_DIR 使用固定持久化目录，并建立一致性备份；本检查不验证备份可恢复。');
  let sms;
  try {
    sms=readSmsConfig(env,mode);
    add(sms.provider==='disabled'?'warning':'pass','sms',sms.provider==='disabled'?'短信登录关闭；可在品牌配置的短信设置中选择腾讯云。':sms.provider==='test'?'仅本地验证码，不发送短信；正式环境禁止此模式。':'腾讯云短信配置形状完整；尚未验证账号权限、模板审核或手机实际收取。');
    if(sms.provider==='tencent')add('warning','sms-identity-key','SMS_HASH_SECRET 必须与数据库一起长期保管；修改会使已有手机号身份无法匹配，当前无密钥轮换迁移工具。');
  }catch{add('error','sms','短信配置无效：检查 SMS_PROVIDER、运行模式、至少43位base64url的 SMS_HASH_SECRET、完整腾讯云参数和精确代理IP。具体字段见手机号登录文档；不显示配置内容。');}
  if (mode === 'production') {
    const miniAuth = Boolean(env.WECHAT_APP_ID && env.WECHAT_APP_SECRET);
    const nativeAuth = Boolean(env.WECHAT_NATIVE_APP_ID && env.WECHAT_NATIVE_APP_SECRET);
    add(miniAuth || nativeAuth || sms?.provider==='tencent' ? 'pass' : 'error', 'production-auth', '正式登录需完整微信凭证或完整腾讯云短信配置；微信付款仍须相应渠道身份与显式账号关联。');
    for (const native of [false, true]) {
      const flag = native ? 'WECHAT_NATIVE_PAY_ENABLED' : 'WECHAT_PAY_ENABLED';
      const prefix = native ? 'WECHAT_NATIVE' : 'WECHAT';
      const label = native ? 'native-pay' : 'mini-pay';
      if (env[flag] && !['true', 'false'].includes(env[flag])) {
        add('error', label, `${flag} 只能是 true 或 false。`); continue;
      }
      if (env[flag] !== 'true') { add('warning', label, '此平台收款关闭；预约可独立验收，勿宣称支付已开通。'); continue; }
      const required = [`${prefix}_APP_ID`, `${prefix}_APP_SECRET`, 'WECHAT_PAY_MCH_ID', 'WECHAT_PAY_MERCHANT_SERIAL',
        'WECHAT_PAY_PRIVATE_KEY_PATH', 'WECHAT_PAY_API_V3_KEY', 'WECHAT_PAY_PLATFORM_KEY_ID', 'WECHAT_PAY_PLATFORM_KEY_PATH', `${prefix}_PAY_NOTIFY_URL`];
      add(required.every(key => Boolean(env[key])) ? 'pass' : 'error', `${label}-credentials`, '支付启用需对应应用身份、商户信息、私钥路径、平台公钥路径和通知 URL；不输出秘密。');
      add(Buffer.byteLength(env.WECHAT_PAY_API_V3_KEY || '') === 32 ? 'pass' : 'error', `${label}-key`, 'API v3 Key 必须正好 32 字节。');
      for (const suffix of ['PAY_NOTIFY_URL', 'PAY_REFUND_NOTIFY_URL']) {
        let valid = false;
        try { const url = new URL(env[`${prefix}_${suffix}`]); valid = url.protocol === 'https:' && !url.username && !url.password && !url.hash && !url.search; } catch {}
        add(valid ? 'pass' : 'error', `${label}-${suffix.toLowerCase()}`, '收款及全额退款通知须配置可访问的 HTTPS URL，不能带查询参数或凭证。');
      }
    }
    add('warning', 'release-evidence', '配置形状不证明真机登录、商户收退款、备份恢复或平台审核；按发布清单记录实际验收。');
  } else add('warning', 'demo-only', '当前仅适合演示和开发，不应采集真实客户数据或收款。');
  return checks;
}

function selfTest() {
  const secret = 'Fj83nRz67qLv29tM_xPa95uB4cZeH01w';
  const valid = { API_MODE: 'demo', PORT: '8787', ADMIN_TOKEN: secret, CORS_ORIGINS: 'http://localhost:8080', DATA_DIR: './data' };
  assert.equal(inspectConfiguration(valid, '24.13.0').filter(x => x.status === 'error').length, 0);
  assert.equal(JSON.stringify(inspectConfiguration(valid)).includes(secret), false, 'secret must never be included');
  assert.ok(inspectConfiguration({ ...valid, PORT: '0' }).some(x => x.name === 'port' && x.status === 'error'));
  assert.ok(inspectConfiguration({ ...valid, CORS_ORIGINS: 'https://example.com/path' }).some(x => x.name === 'cors' && x.status === 'error'));
  assert.ok(inspectConfiguration({ ...valid, CORS_ORIGINS: '*' }).some(x => x.name === 'cors' && x.status === 'error'));
  assert.ok(inspectConfiguration({ ...valid, API_MODE: 'production', CORS_ORIGINS: 'https://example.com' }).some(x => x.name === 'production-auth' && x.status === 'error'));
  assert.ok(inspectConfiguration(valid, '20.0.0').some(x => x.name === 'node' && x.status === 'error'));
  assert.deepEqual(parseEnv('PORT=8787\n# Comment\nAPI_MODE="demo"').values, { PORT: '8787', API_MODE: 'demo' });
  const broken = parseEnv(`BROKEN ${secret}\nTOKEN="unclosed`);
  assert.equal(broken.errors.length, 2);
  assert.equal(JSON.stringify(broken.errors).includes(secret), false);
  const production = { ...valid, API_MODE: 'production', CORS_ORIGINS: 'https://example.com', WECHAT_APP_ID: 'wxexample', WECHAT_APP_SECRET: secret };
  assert.equal(inspectConfiguration(production).filter(x => x.status === 'error').length, 0);
  assert.ok(inspectConfiguration({ ...production, WECHAT_PAY_ENABLED: 'true' }).some(x => x.name === 'mini-pay-credentials' && x.status === 'error'));
  assert.equal(JSON.stringify(inspectConfiguration(production)).includes(secret), false);
  const sms={...valid,API_MODE:'production',CORS_ORIGINS:'https://example.com',SMS_PROVIDER:'tencent',SMS_HASH_SECRET:'b'.repeat(43),TENCENT_SMS_SECRET_ID:'fixture-id',TENCENT_SMS_SECRET_KEY:secret,TENCENT_SMS_SDK_APP_ID:'1400000000',TENCENT_SMS_SIGN_NAME:'测试签名',TENCENT_SMS_TEMPLATE_ID:'123456',TENCENT_SMS_REGION:'ap-guangzhou'};
  assert.equal(inspectConfiguration(sms).filter(x=>x.status==='error').length,0);
  assert.equal(inspectConfiguration(sms).find(x=>x.name==='production-auth').status,'pass');
  assert.equal(JSON.stringify(inspectConfiguration(sms)).includes(secret),false);
  for(const patch of [{SMS_PROVIDER:'test'},{SMS_HASH_SECRET:''},{TENCENT_SMS_TEMPLATE_ID:''},{SMS_TRUSTED_PROXY_IPS:'*'}])assert.ok(inspectConfiguration({...sms,...patch}).some(x=>x.name==='sms'&&x.status==='error'));
  assert.equal(inspectConfiguration({...valid,SMS_PROVIDER:'test'}).filter(x=>x.status==='error').length,0);
  console.log('doctor self-test: configuration, SMS-only auth and secret redaction passed');
}

function main() {
  const args = process.argv.slice(2);
  if (args.includes('--self-test')) return selfTest();
  if (args.includes('--help')) {
    console.log('node scripts/doctor.mjs [--env PATH] [--mode demo|production] [--json]\n只读本地配置检查；不请求供应商接口、不显示密钥。--self-test 运行脱敏与配置校验测试。');
    return;
  }
  let file = resolve(root, '.env'), mode, json = false;
  for (let index = 0; index < args.length; index++) {
    if (args[index] === '--json') json = true;
    else if (args[index] === '--env' && args[index + 1] && !args[index + 1].startsWith('--')) file = resolve(args[++index]);
    else if (args[index] === '--mode' && args[index + 1] && !args[index + 1].startsWith('--')) mode = args[++index];
    else { console.error('参数无效。运行 --help 查看用法。'); process.exitCode = 2; return; }
  }
  const checks = [];
  let parsed = { values: {}, errors: [] };
  if (existsSync(file)) {
    try { parsed = parseEnv(readFileSync(file, 'utf8')); }
    catch { checks.push({ status: 'error', name: 'env-file', message: '无法读取环境文件；检查路径和权限。' }); }
  } else checks.push({ status: 'warning', name: 'env-file', message: '未找到环境文件；可复制 .env.example 为 .env。' });
  for (const message of parsed.errors) checks.push({ status: 'error', name: 'env-format', message });
  const env = { ...parsed.values };
  const keys = ['API_MODE', 'PORT', 'ADMIN_TOKEN', 'DATA_DIR', 'CORS_ORIGINS',
    'SMS_PROVIDER','SMS_HASH_SECRET','SMS_TRUSTED_PROXY_IPS','TENCENT_SMS_SECRET_ID','TENCENT_SMS_SECRET_KEY','TENCENT_SMS_SDK_APP_ID','TENCENT_SMS_SIGN_NAME','TENCENT_SMS_TEMPLATE_ID','TENCENT_SMS_REGION','TENCENT_SMS_TEMPLATE_HAS_MINUTES',
    'WECHAT_APP_ID', 'WECHAT_APP_SECRET', 'WECHAT_NATIVE_APP_ID', 'WECHAT_NATIVE_APP_SECRET',
    'WECHAT_PAY_ENABLED', 'WECHAT_NATIVE_PAY_ENABLED', 'WECHAT_PAY_MCH_ID', 'WECHAT_PAY_MERCHANT_SERIAL',
    'WECHAT_PAY_PRIVATE_KEY_PATH', 'WECHAT_PAY_API_V3_KEY', 'WECHAT_PAY_PLATFORM_KEY_ID', 'WECHAT_PAY_PLATFORM_KEY_PATH',
    'WECHAT_PAY_NOTIFY_URL', 'WECHAT_NATIVE_PAY_NOTIFY_URL', 'WECHAT_PAY_REFUND_NOTIFY_URL', 'WECHAT_NATIVE_PAY_REFUND_NOTIFY_URL'];
  for (const key of keys) if (process.env[key] !== undefined) env[key] = process.env[key];
  if (mode !== undefined) env.API_MODE = mode;
  checks.push(...inspectConfiguration(env));
  for (const relative of ['services/api/src/server.mjs', 'apps/mobile/pubspec.yaml', 'apps/miniprogram/app.json']) {
    checks.push({ status: existsSync(resolve(root, relative)) ? 'pass' : 'error', name: 'source', message: relative });
  }
  const report = { readyForLocalDemo: !checks.some(x => x.status === 'error'), productionReady: false, checks, note: '只检查本地配置形状，不验证供应商权限、真机、付款或平台审核。' };
  if (json) console.log(JSON.stringify(report, null, 2));
  else {
    console.log('OpenNI Club 配置检查');
    for (const c of checks) console.log(`${{ pass: '通过', warning: '提示', error: '阻断' }[c.status]} · ${c.name} · ${c.message}`);
    console.log(report.note);
  }
  if (checks.some(x => x.status === 'error')) process.exitCode = 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
