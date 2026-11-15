import { spawn } from 'node:child_process';
import { readFile, writeFile, mkdir, readdir, stat } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { loadClubConfig, ConfigError, json, hash } from './club-config.mjs';
import { verifyManifest } from './club-artifacts.mjs';
import { inspectConfiguration } from '../doctor.mjs';

const exists = async path => { try { return (await stat(path)).isFile(); } catch { return false; } };
export async function releasePreflight(loaded, { root, platform, env = {}, upload = false, baseHref = '/' }) {
  const issues = []; const production = loaded.mode === 'production'; const d = loaded.source.distribution ?? {};
  if (!['web', 'android', 'ios', 'wechat'].includes(platform)) issues.push('platform 必须是 web / android / ios / wechat');
  if (!/^\/(?:[a-zA-Z0-9_-]+\/)*$/.test(baseHref)) issues.push('Web base-href 必须是 / 或 /目录/ 格式的本地路径');
  if (platform !== 'web' && baseHref !== '/') issues.push('--base-href 仅用于 Web 构建');
  if (upload && platform !== 'wechat') issues.push('--upload 仅支持微信开发者工具上传；应用商店使用生成包与平台上传工具');
  if (production && platform === 'web') issues.push('Web 仅用于预览，原生微信登录请构建 iOS/Android');
  if (production) {
    if (env.API_MODE !== 'production') issues.push('正式构建需要独立服务端配置 API_MODE=production；不要把正式客户端连接到演示身份系统');
    issues.push(...inspectConfiguration({ ...env, API_MODE: 'production' }).filter(check => check.status === 'error').map(check => check.message));
    const native = platform === 'android' || platform === 'ios';
    const appId = native ? d.wechatNativeAppId : d.wechatMiniAppId;
    const prefix = native ? 'WECHAT_NATIVE' : 'WECHAT';
    if (!appId) issues.push(`正式构建需要 ${native ? '移动微信' : '小程序'} AppID`);
    if (!env[`${prefix}_APP_SECRET`] || env[`${prefix}_APP_ID`] !== appId) issues.push('独立服务器秘密配置缺少匹配的微信 AppID/AppSecret；内容不会传给客户端构建进程');
    if (platform === 'android') {
      if (!d.androidApplicationId || /(^|\.)example(\.|$)/.test(d.androidApplicationId)) issues.push('正式 Android 需要自己的固定 applicationId');
      let text = ''; try { text = await readFile(join(root, 'apps/mobile/android/key.properties'), 'utf8'); } catch {}
      const props = Object.fromEntries(text.split(/\r?\n/).filter(line => /^\w+=/.test(line)).map(line => { const i = line.indexOf('='); return [line.slice(0, i), line.slice(i + 1)]; }));
      if (!['storeFile', 'storePassword', 'keyAlias', 'keyPassword'].every(key => Boolean(props[key]))) issues.push('Android 上传签名未配置完整 key.properties');
      else if (/debug\.keystore$/i.test(props.storeFile) || !await exists(resolve(root, 'apps/mobile/android/app', props.storeFile))) issues.push('Android 上传签名文件不可用或仍是 debug keystore');
    }
    if (platform === 'ios' && (!d.iosBundleId || !d.appleTeamId || !d.universalLink || /(^|\.)example(\.|$)/.test(d.iosBundleId))) issues.push('正式 iOS 需要固定 Bundle ID、Apple Team ID 和 Universal Link；Xcode 将进一步验证签名身份');
    const enabled = env[native ? 'WECHAT_NATIVE_PAY_ENABLED' : 'WECHAT_PAY_ENABLED'];
    if (enabled && !['true', 'false'].includes(enabled)) issues.push('支付开关必须为 true / false');
    if (enabled === 'true') {
      for (const key of ['WECHAT_PAY_MCH_ID', 'WECHAT_PAY_MERCHANT_SERIAL', 'WECHAT_PAY_API_V3_KEY', 'WECHAT_PAY_PLATFORM_KEY_ID', 'WECHAT_PAY_PRIVATE_KEY_PATH', 'WECHAT_PAY_PLATFORM_KEY_PATH', `${prefix}_PAY_NOTIFY_URL`, `${prefix}_PAY_REFUND_NOTIFY_URL`]) if (!env[key]) issues.push(`已开启收款但缺少 ${key}`);
      if (Buffer.byteLength(env.WECHAT_PAY_API_V3_KEY || '') !== 32) issues.push('支付 API v3 Key 长度必须为32字节');
    }
  }
  if (platform === 'wechat' && !env.WECHAT_DEVTOOLS_CLI) issues.push('需要 WECHAT_DEVTOOLS_CLI 指向微信开发者工具 cli，并先登录自己的开发者账号');
  return issues;
}

export function releaseCommands(loaded, { root, platform, env = {}, outputDir, upload = false, baseHref = '/' }) {
  const mobile = join(root, 'apps/mobile'), d = loaded.distribution, r = loaded.runtime;
  const define = [`--dart-define=APP_MODE=${r.mode}`, `--dart-define=API_BASE_URL=${r.apiBaseUrl}`, `--dart-define=WECHAT_APP_ID=${r.wechatAppId}`, `--dart-define=WECHAT_UNIVERSAL_LINK=${r.universalLink}`];
  if (platform === 'wechat') {
    const cli = env.WECHAT_DEVTOOLS_CLI || 'WECHAT_DEVTOOLS_CLI';
    const steps = [{ name: 'wechat-preview', command: cli, args: ['preview', '--project', join(root, 'apps/miniprogram'), '--qr-format', 'image', '--qr-output', join(outputDir, 'wechat-preview.png'), '--info-output', join(outputDir, 'wechat-preview-info.json')], cwd: root }];
    if (upload) steps.push({ name: 'wechat-upload', command: cli, args: ['upload', '--project', join(root, 'apps/miniprogram'), '--version', d.version, '--desc', `${r.name} ${d.version}`, '--info-output', join(outputDir, 'wechat-upload-info.json')], cwd: root });
    return steps;
  }
  const command = env.FLUTTER_BIN || 'flutter';
  const build = platform === 'android' ? loaded.mode === 'production' ? ['build', 'appbundle', '--release'] : ['build', 'apk', '--debug'] : platform === 'ios' ? loaded.mode === 'production' ? ['build', 'ipa', '--release'] : ['build', 'ios', '--debug', '--no-codesign'] : ['build', 'web', '--release', '--no-web-resources-cdn'];
  return [{ name: 'dependencies', command, args: ['pub', 'get'], cwd: mobile }, { name: 'analysis', command, args: ['analyze'], cwd: mobile },
    { name: 'flows', command, args: ['test', 'test/flows_test.dart', 'test/production_test.dart', 'test/v2_test.dart', 'test/catalog_test.dart'], cwd: mobile },
    { name: 'build', command, args: [...build, ...(platform === 'web' ? [`--base-href=${baseHref}`] : []), `--build-name=${d.version}`, `--build-number=${d.buildNumber}`, ...define], cwd: mobile }];
}
const childEnvironment = () => Object.fromEntries(['PATH', 'HOME', 'TMPDIR', 'JAVA_HOME', 'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'FLUTTER_ROOT', 'LANG', 'LC_ALL', 'PUB_CACHE', 'GRADLE_USER_HOME', 'HTTPS_PROXY', 'HTTP_PROXY', 'NO_PROXY'].filter(key => process.env[key]).map(key => [key, process.env[key]]));
export async function runStep(step) {
  return new Promise(resolveStep => {
    const processHandle = spawn(step.command, step.args, { cwd: step.cwd, env: childEnvironment(), shell: false, stdio: ['ignore', 'pipe', 'pipe'] });
    // Do not persist raw tool output: SDK tools may print credentials or account data.
    processHandle.stdout.on('data', () => {}); processHandle.stderr.on('data', () => {});
    processHandle.on('error', () => resolveStep({ exitCode: null, error: '无法启动工具；检查安装路径和权限' }));
    processHandle.on('close', code => resolveStep({ exitCode: code, ...(code ? { error: '工具执行失败；请在本地工具中查看诊断，检查网络、磁盘、SDK与签名' } : {}) }));
  });
}
async function collect(directory) {
  const result = [];
  async function walk(path) { for (const entry of await readdir(path, { withFileTypes: true })) { const p = join(path, entry.name); if (entry.isDirectory()) await walk(p); else if (entry.isFile()) { const bytes = await readFile(p); result.push({ path: p, bytes: bytes.length, sha256: hash(bytes) }); } } }
  try { await walk(directory); } catch { return []; } return result;
}
export async function releaseClub({ root, configPath, mode = 'preview', platform, env = {}, plan = false, upload = false, baseHref = '/', runner = runStep, onStage = () => {} }) {
  const loaded = await loadClubConfig(configPath, { mode });
  const outputDir = join(root, 'releases', `${loaded.runtime.clubId}-${loaded.distribution.version}-${loaded.distribution.buildNumber}`, platform);
  const issues = await releasePreflight(loaded, { root, platform, env, upload, baseHref });
  const commands = releaseCommands(loaded, { root, platform, env, outputDir, upload, baseHref });
  if (plan) return { status: issues.length ? 'blocked' : 'planned', issues, configHash: loaded.configHash, commands, published: false };
  if (issues.length) throw new ConfigError(issues);
  const manifest = await verifyManifest(root);
  if (manifest.configHash !== loaded.configHash) throw new ConfigError(['当前配置与生成文件不一致；先用同一 mode 运行 configure-club --apply']);
  await mkdir(outputDir, { recursive: true });
  const report = { schemaVersion: 1, configHash: loaded.configHash, clubId: loaded.runtime.clubId, platform, mode, ...(platform === 'web' ? { baseHref } : {}), version: loaded.distribution.version,
    buildNumber: loaded.distribution.buildNumber, status: 'running', published: false, startedAt: new Date().toISOString(), stages: [], artifacts: [],
    pendingEvidence: ['真实设备登录与履约流程', '真实商户收退款（如启用）', '平台审核结果', '正式发布状态'] };
  const reportPath = join(outputDir, 'manifest.json');
  const save = () => writeFile(reportPath, json(report));
  await save();
  for (const step of commands) {
    const stage = { name: step.name, startedAt: new Date().toISOString(), status: 'running' }; report.stages.push(stage); await save(); onStage(step.name);
    let result; try { result = await runner(step); } catch { result = { exitCode: null, error: '构建工具异常退出' }; }
    Object.assign(stage, { status: result.exitCode === 0 ? 'passed' : 'failed', exitCode: result.exitCode, finishedAt: new Date().toISOString(), ...(result.error ? { error: result.error } : {}) });
    if (result.exitCode !== 0) { report.status = 'failed'; report.finishedAt = new Date().toISOString(); await save(); return { ...report, reportPath }; }
    await save();
  }
  const artifactDir = platform === 'web' ? join(root, 'apps/mobile/build/web') : platform === 'android' ? join(root, mode === 'production' ? 'apps/mobile/build/app/outputs/bundle/release' : 'apps/mobile/build/app/outputs/flutter-apk') : platform === 'ios' ? join(root, mode === 'production' ? 'apps/mobile/build/ios/ipa' : 'apps/mobile/build/ios/iphoneos') : outputDir;
  report.artifacts = (await collect(artifactDir)).filter(item => item.path !== reportPath);
  if (!report.artifacts.length) { report.status = 'failed'; report.stages.push({ name: 'artifact-check', status: 'failed', error: '工具返回成功但找不到产物，不能标记构建成功' }); }
  else report.status = upload ? 'uploaded-awaiting-review' : 'built-awaiting-device-validation';
  report.finishedAt = new Date().toISOString(); await save(); return { ...report, reportPath };
}
