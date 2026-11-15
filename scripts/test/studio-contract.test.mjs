import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { PROJECT_ROOT, loadClubConfig } from '../lib/club-config.mjs';
import { parseEnv } from '../doctor.mjs';

test('Studio exported public config is accepted by generator and secrets stay in server.env', async t => {
  const text = await readFile(join(PROJECT_ROOT, 'apps/studio/studio.js'), 'utf8');
  const configFunction = text.match(/function configuration\(\)\{[^\n]+/)[0];
  const envFunction = text.match(/function serverEnv\(config\)\{[\s\S]+?\n\}/)[0];
  const secretFieldsDeclaration = text.match(/const secretFields=\[[^\n]+/)[0];
  const fields = { brandName: '青岚俱乐部', shortName: '青岚', primaryColor: '#137B57', clubId: 'qinglan',
    legalEntity: '青岚互动有限公司', supportContact: 'support@qinglan.invalid', privacyText: '我们收集订单联系方式用于履约。', termsText: '按双方预约的服务履约。',
    androidApplicationId: 'cn.qinglan.club', iosBundleId: 'cn.qinglan.club', appleTeamId: 'ABC1234567',
    wechatMiniAppId: 'wx1234567890abcdef', wechatNativeAppId: 'wxabcdef1234567890', apiBaseUrl: 'https://api.qinglan.invalid/api/v1', siteUrl: 'https://qinglan.invalid',
    universalLink: 'https://qinglan.invalid/wechat/', WECHAT_APP_SECRET: 'MINI_SECRET_MUST_NOT_ENTER_PUBLIC', WECHAT_NATIVE_APP_SECRET: 'NATIVE_SECRET_MUST_NOT_ENTER_PUBLIC',
    TENCENT_SMS_SECRET_ID: 'SMS_ID_MUST_NOT_ENTER_PUBLIC', TENCENT_SMS_SECRET_KEY: 'SMS_SECRET_MUST_NOT_ENTER_PUBLIC',
    TENCENT_SMS_SIGN_NAME: '青岚俱乐部', TENCENT_SMS_TEMPLATE_ID: '123456', SMS_HASH_SECRET: 'ExistingPhoneIdentityKeyMustStayTheSame123456789' };
  const context = vm.createContext({ URL, logoExtension: 'svg', value: key => fields[key] || '', compact: object => Object.fromEntries(Object.entries(object).filter(([, v]) => v !== '' && v !== undefined)),
    randomAdminToken: () => 'OnlyTestBase64urlToken1234567890' });
  vm.runInContext(`${secretFieldsDeclaration}\n${configFunction}\n${envFunction}\nthis.result=configuration();this.envText=serverEnv(this.result);`, context);
  assert.equal(JSON.stringify(context.result).includes('SECRET'), false);
  const env = parseEnv(context.envText); assert.equal(env.errors.length, 0);
  assert.equal(env.values.WECHAT_APP_SECRET, fields.WECHAT_APP_SECRET);
  assert.equal(env.values.TENCENT_SMS_SECRET_KEY, fields.TENCENT_SMS_SECRET_KEY);
  assert.equal(env.values.TENCENT_SMS_SIGN_NAME, fields.TENCENT_SMS_SIGN_NAME);
  assert.equal(env.values.SMS_HASH_SECRET, fields.SMS_HASH_SECRET);
  assert.equal(env.values.SMS_PROVIDER, 'disabled');
  assert.equal(env.values.TENCENT_SMS_REGION, 'ap-guangzhou');
  assert.equal(JSON.stringify(context.result).includes(fields.SMS_HASH_SECRET), false);
  assert.equal(env.values.WECHAT_PAY_NOTIFY_URL, 'https://api.qinglan.invalid/api/v1/payments/wechat/notify');
  const root = await mkdtemp(join(tmpdir(), 'openni-studio-')); t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(join(root, 'assets/brand'), { recursive: true }); await writeFile(join(root, 'assets/brand/logo.svg'), await readFile(join(PROJECT_ROOT, 'config/assets/brand/logo.svg')));
  const path = join(root, 'club.json'); await writeFile(path, JSON.stringify(context.result));
  const loaded = await loadClubConfig(path, { mode: 'production' }); assert.equal(loaded.runtime.name, fields.brandName); assert.equal(loaded.runtime.wechatAppId, fields.wechatNativeAppId);
});
