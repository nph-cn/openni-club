import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire } from 'node:module';
import sharp from 'sharp';
import { configure } from '../configure-club.mjs';
import { loadClubConfig, ConfigError, policyHtml, hash } from '../lib/club-config.mjs';
import { renderArtifacts, applyArtifacts, verifyManifest } from '../lib/club-artifacts.mjs';
import { releaseClub, releasePreflight, releaseCommands } from '../lib/club-release.mjs';
import { exportPolicies } from '../export-policies.mjs';
const require = createRequire(import.meta.url);
async function fixture(t, name = '银河俱乐部', color = '#2345AB') {
  const root = await mkdtemp(join(tmpdir(), 'openni-brand-')); t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(join(root, 'config/assets'), { recursive: true });
  await writeFile(join(root, 'config/assets/logo.svg'), `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024"><rect width="1024" height="1024" fill="${color}"/><circle cx="512" cy="512" r="180" fill="white"/></svg>`);
  const source = { schemaVersion: 1, brand: { name, logo: 'assets/logo.svg', primaryColor: color } };
  const configPath = join(root, 'config/club.json'); await writeFile(configPath, JSON.stringify(source));
  return { root, configPath, source };
}
test('name and logo generate two isolated brands across Flutter, mini, backend and native icons', async t => {
  const a = await fixture(t), b = await fixture(t, '赤焰电竞', '#BA3412');
  for (const f of [a, b]) {
    await configure({ ...f, action: 'apply' });
    const flutter = JSON.parse(await readFile(join(f.root, 'apps/mobile/assets/brand.json'), 'utf8'));
    const api = JSON.parse(await readFile(join(f.root, 'generated/club/public.json'), 'utf8'));
    const mini = require(join(f.root, 'apps/miniprogram/utils/brand.generated.js'));
    assert.equal(flutter.name, f.source.brand.name); assert.equal(mini.name, flutter.name); assert.deepEqual(api, flutter);
    assert.equal(flutter.primaryColor, f.source.brand.primaryColor); assert.equal(flutter.demoData, true);
    const seed = JSON.parse(await readFile(join(f.root, 'generated/club/seed.json'), 'utf8'));
    assert.equal(seed.club.name, flutter.name); assert.ok(seed.services.length); assert.ok(seed.announcements[0].title.includes(flutter.name));
    assert.equal(JSON.stringify(seed).includes('北岸'), false);
    const localCatalog = JSON.parse(await readFile(join(f.root, 'apps/mobile/assets/catalog.json'), 'utf8'));
    assert.deepEqual(localCatalog, { services: seed.services, players: seed.players, announcements: seed.announcements });
    const contents = JSON.parse(await readFile(join(f.root, 'apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json'), 'utf8'));
    const icon = contents.images.find(x => x.idiom === 'ios-marketing');
    const metadata = await sharp(join(f.root, 'apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset', icon.filename)).metadata();
    assert.equal(metadata.width, 1024); assert.equal(metadata.height, 1024); assert.equal(metadata.hasAlpha, false);
    await verifyManifest(f.root);
  }
  const left = JSON.parse(await readFile(join(a.root, 'generated/club/manifest.json'), 'utf8'));
  const right = JSON.parse(await readFile(join(b.root, 'generated/club/manifest.json'), 'utf8'));
  assert.notEqual(left.configHash, right.configHash); assert.notEqual(left.distribution.androidApplicationId, right.distribution.androidApplicationId);
});
test('plans are deterministic and read-only; applying does not touch existing business data', async t => {
  const f = await fixture(t); await mkdir(join(f.root, 'data')); await writeFile(join(f.root, 'data/orders.sqlite'), 'existing order records');
  const first = await configure({ ...f, action: 'plan' }); assert.ok(first.changes.every(c => c.action === 'create'));
  await assert.rejects(readFile(join(f.root, 'generated/club/public.json')), { code: 'ENOENT' });
  await configure({ ...f, action: 'apply' });
  const second = await configure({ ...f, action: 'plan' }); assert.ok(second.changes.every(c => c.action === 'unchanged'));
  assert.equal(await readFile(join(f.root, 'data/orders.sqlite'), 'utf8'), 'existing order records');
  await writeFile(join(f.root, 'apps/mobile/assets/brand.json'), '{}');
  await assert.rejects(verifyManifest(f.root), error => error instanceof ConfigError && error.issues.some(x => x.includes('brand.json')));
});
test('mid-commit failure restores previous generated files and manifest', async t => {
  const f = await fixture(t); const loaded = await loadClubConfig(f.configPath); const { artifacts } = await renderArtifacts(loaded);
  await applyArtifacts(f.root, artifacts); const before = await readFile(join(f.root, 'generated/club/public.json'));
  const changed = new Map([...artifacts].map(([path, content]) => [path, path.endsWith('public.json') ? Buffer.from('{"changed":true}') : content]));
  await assert.rejects(applyArtifacts(f.root, changed, { beforeCommit: (_, index) => { if (index === 3) throw new Error('simulated disk error'); } }));
  assert.equal(hash(await readFile(join(f.root, 'generated/club/public.json'))), hash(before)); await verifyManifest(f.root);
});
test('public configuration rejects nested secrets without echoing their values', async t => {
  const f = await fixture(t); const secret = 'never-output-this-private-value';
  for (const mutate of [s => { s.brand.appSecret = secret; }, s => { s.initialCatalog = { players: [{ id: 'p1', name: 'x', games: [], credentials: { accessToken: secret } }] }; }, s => { s.brand.description = '-----BEGIN PRIVATE KEY-----'; }]) {
    const source = structuredClone(f.source); mutate(source); await writeFile(f.configPath, JSON.stringify(source));
    await assert.rejects(loadClubConfig(f.configPath), error => error instanceof ConfigError && !JSON.stringify(error.issues).includes(secret));
  }
});
test('generator refuses path escapes, hostile SVG and symlink output targets', async t => {
  const f = await fixture(t); await writeFile(f.configPath, JSON.stringify({ ...f.source, brand: { ...f.source.brand, logo: '../secret.png' } }));
  await assert.rejects(loadClubConfig(f.configPath), ConfigError);
  await writeFile(f.configPath, JSON.stringify(f.source)); await writeFile(join(f.root, 'config/assets/logo.svg'), '<svg xmlns="http://www.w3.org/2000/svg"><image href="https://remote.invalid/image"/></svg>');
  await assert.rejects(loadClubConfig(f.configPath), ConfigError);
  await mkdir(join(f.root, 'apps')); await symlink(join(f.root, 'config'), join(f.root, 'apps/mobile'));
  await assert.rejects(applyArtifacts(f.root, new Map([['apps/mobile/file', Buffer.from('bad')]])), ConfigError);
});
test('production requires legal facts and explicit platform identity/signing; no secrets enter commands', async t => {
  const f = await fixture(t); await assert.rejects(loadClubConfig(f.configPath, { mode: 'production' }), ConfigError);
  const source = { ...f.source, operator: { legalEntity: '银河互动有限公司', supportContact: '客服 400-123-4567' }, legal: { privacyText: '实际收集说明', termsText: '实际服务约定' },
    distribution: { clubId: 'galaxy', wechatNativeAppId: 'wx1234567890abcdef' }, endpoints: { apiBaseUrl: 'https://api.galaxy.invalid/api/v1', siteUrl: 'https://galaxy.invalid' } };
  await writeFile(f.configPath, JSON.stringify(source)); const loaded = await loadClubConfig(f.configPath, { mode: 'production' });
  const env = { WECHAT_NATIVE_APP_ID: source.distribution.wechatNativeAppId, WECHAT_NATIVE_APP_SECRET: 'server-secret-only' };
  const issues = await releasePreflight(loaded, { root: f.root, platform: 'android', env });
  assert.ok(issues.some(x => x.includes('applicationId'))); assert.ok(issues.some(x => x.includes('key.properties')));
  assert.equal(JSON.stringify(releaseCommands(loaded, { root: f.root, platform: 'android', env })).includes('server-secret-only'), false);
});
test('failed builds stop remaining stages and never claim uploaded or published', async t => {
  const f = await fixture(t); await configure({ ...f, action: 'apply' }); let calls = 0;
  const result = await releaseClub({ ...f, platform: 'web', runner: async () => ({ exitCode: ++calls === 2 ? 1 : 0 }) });
  assert.equal(calls, 2); assert.equal(result.status, 'failed'); assert.equal(result.published, false);
  const saved = JSON.parse(await readFile(result.reportPath, 'utf8')); assert.equal(saved.stages.at(-1).status, 'failed');
});
test('Web preview supports a subdirectory and rejects external or ambiguous base paths', async t => {
  const f = await fixture(t); const loaded = await loadClubConfig(f.configPath);
  const commands = releaseCommands(loaded, { root: f.root, platform: 'web', baseHref: '/demo/' });
  assert.ok(commands.at(-1).args.includes('--base-href=/demo/'));
  for (const baseHref of ['https://example.com/', '//example/', '/../', '/demo?token=abc/']) {
    assert.ok((await releasePreflight(loaded, { root: f.root, platform: 'web', baseHref })).length);
  }
});
test('successful tool exits still require artifacts and evidence remains separate', async t => {
  const f = await fixture(t); await configure({ ...f, action: 'apply' });
  let result = await releaseClub({ ...f, platform: 'web', runner: async () => ({ exitCode: 0 }) }); assert.equal(result.status, 'failed');
  await mkdir(join(f.root, 'apps/mobile/build/web'), { recursive: true }); await writeFile(join(f.root, 'apps/mobile/build/web/index.html'), '<html>Preview</html>');
  result = await releaseClub({ ...f, platform: 'web', runner: async () => ({ exitCode: 0 }) });
  assert.equal(result.status, 'built-awaiting-device-validation'); assert.equal(result.published, false); assert.ok(result.artifacts[0].sha256);
});
test('policy pages escape user content and reject incomplete demo policies', async t => {
  const f = await fixture(t); const club = { name: '<script>bad()</script>', privacyText: '用户数据说明', termsText: '履约约定', supportContact: 'contact', legalEntity: 'operator', demoData: false };
  assert.equal(policyHtml(club, 'privacy').includes('<script>'), false);
  const files = await exportPolicies('https://api.example.com/api/v1', join(f.root, 'policies'), async () => new Response(JSON.stringify(club)));
  assert.deepEqual(files, ['privacy.html', 'terms.html']);
  await assert.rejects(exportPolicies('https://api.example.com/api/v1', join(f.root, 'policies'), async () => new Response(JSON.stringify({ ...club, demoData: true }))), ConfigError);
});
