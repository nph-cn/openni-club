import test from 'node:test';
import assert from 'node:assert/strict';
import { createCipheriv, generateKeyPairSync, sign, verify } from 'node:crypto';
import { exchangeWechatCode, exchangeWechatAppCode, createJsapiOrder, createAppOrder, decryptWechatPayNotification,
  verifyWechatPayNotification, validateWechatPayOrder } from '../src/wechat.mjs';

const merchant = generateKeyPairSync('rsa', { modulusLength: 2048 });
const platform = generateKeyPairSync('rsa', { modulusLength: 2048 });
const privatePem = merchant.privateKey.export({ type: 'pkcs8', format: 'pem' });
const publicPem = platform.publicKey.export({ type: 'spki', format: 'pem' });
const now = Date.parse('2026-11-15T01:00:00Z');
const config = { appid: 'wxexample123', mchid: '1900000001', merchantSerial: 'ABC123', merchantPrivateKey: privatePem,
  apiV3Key: '12345678901234567890123456789012', notifyUrl: 'https://api.example.com/payments/wechat/notify',
  platformKeys: { PUB_KEY_ID_TEST: publicPem } };
const order = { id: 'order_123456', description: '俱乐部预约', totalCents: 12900, openid: 'openid_test' };
function signedHeaders(body, time = now, key = platform.privateKey) {
  const timestamp = Math.floor(time / 1000).toString(); const nonce = 'signed_nonce';
  return { 'Wechatpay-Timestamp': timestamp, 'Wechatpay-Nonce': nonce, 'Wechatpay-Serial': 'PUB_KEY_ID_TEST',
    'Wechatpay-Signature': sign('RSA-SHA256', Buffer.from(`${timestamp}\n${nonce}\n${body}\n`), key).toString('base64') };
}
function notification(overrides = {}, eventOverrides = {}) {
  const payment = { appid: config.appid, mchid: config.mchid, out_trade_no: order.id,
    transaction_id: '420000000000000000001', trade_state: 'SUCCESS', trade_type: 'JSAPI',
    amount: { total: order.totalCents, currency: 'CNY' }, payer: { openid: order.openid }, success_time: '2026-11-15T09:00:00+08:00', ...overrides };
  const nonce = '123456789012'; const associated_data = 'transaction';
  const cipher = createCipheriv('aes-256-gcm', Buffer.from(config.apiV3Key), Buffer.from(nonce));
  cipher.setAAD(Buffer.from(associated_data));
  const encrypted = Buffer.concat([cipher.update(JSON.stringify(payment), 'utf8'), cipher.final(), cipher.getAuthTag()]);
  const rawBody = JSON.stringify({ id: 'event_123', event_type: 'TRANSACTION.SUCCESS',
    resource: { algorithm: 'AEAD_AES_256_GCM', original_type: 'transaction', nonce, associated_data,
      ciphertext: encrypted.toString('base64') }, ...eventOverrides });
  return { headers: signedHeaders(rawBody), rawBody, config, expectedOrder: order, now };
}

test('login exchanges one-time code at the fixed official endpoint and keeps redirect disabled', async () => {
  const result = await exchangeWechatCode({ appid: config.appid, appSecret: 'server_secret', code: 'one_time_code',
    fetchImpl: async (url, options) => {
      assert.equal(url.origin, 'https://api.weixin.qq.com');
      assert.equal(url.pathname, '/sns/jscode2session');
      assert.equal(url.searchParams.get('secret'), 'server_secret');
      assert.equal(url.searchParams.get('js_code'), 'one_time_code');
      assert.equal(url.searchParams.get('grant_type'), 'authorization_code');
      assert.equal(options.redirect, 'error');
      return new Response(JSON.stringify({ openid: 'user', session_key: 'private_key', unionid: 'union' }));
    } });
  assert.deepEqual(result, { openid: 'user', sessionKey: 'private_key', unionid: 'union' });
});
test('login rejects expired codes and never exposes provider diagnostics or credentials', async () => {
  await assert.rejects(exchangeWechatCode({ appid: 'wx123', appSecret: 'do_not_echo', code: 'expired',
    fetchImpl: async () => new Response(JSON.stringify({ errcode: 40029, errmsg: 'do_not_echo internal details' })) }),
  error => error.code === 'INVALID_WECHAT_CODE' && !error.message.includes('do_not_echo'));
  await assert.rejects(exchangeWechatCode({ appid: 'wx123', appSecret: 'do_not_echo', code: 'valid',
    fetchImpl: async () => { throw new Error('URL includes do_not_echo'); } }),
  error => error.code === 'PROVIDER_UNAVAILABLE' && !error.message.includes('do_not_echo'));
});
test('login rejects incomplete and non-object responses', async () => {
  for (const data of [{ openid: 'user' }, null, []]) {
    await assert.rejects(exchangeWechatCode({ appid: 'wx123', appSecret: 'secret', code: 'code',
      fetchImpl: async () => new Response(JSON.stringify(data)) }), { code: 'INVALID_PROVIDER_RESPONSE' });
  }
});
test('native login exchanges SDK code and rejects invalid provider credentials without leaking details', async () => {
  const result = await exchangeWechatAppCode({ appid: 'wxnative', appSecret: 'secret', code: 'nativecode',
    fetchImpl: async (url) => {
      assert.equal(url.origin + url.pathname, 'https://api.weixin.qq.com/sns/oauth2/access_token');
      assert.equal(url.searchParams.get('code'), 'nativecode');
      return new Response(JSON.stringify({ openid: 'native_user', access_token: 'private_access', refresh_token: 'private_refresh', expires_in: 7200 }));
    } });
  assert.equal(result.openid, 'native_user'); assert.equal(result.expiresIn, 7200);
  await assert.rejects(exchangeWechatAppCode({ appid: 'wxnative', appSecret: 'secret', code: 'bad',
    fetchImpl: async () => new Response(JSON.stringify({ errcode: 40029, errmsg: 'secret' })) }), { code: 'INVALID_WECHAT_CODE' });
  await assert.rejects(exchangeWechatAppCode({ appid: 'wxnative', appSecret: 'secret', code: 'bad',
    fetchImpl: async () => new Response(JSON.stringify({ openid: 'missing_token' })) }), { code: 'INVALID_PROVIDER_RESPONSE' });
});
test('JSAPI authenticates request and provider response, and produces verifiable client pay parameters', async () => {
  const result = await createJsapiOrder({ config, order, now, fetchImpl: async (url, options) => {
    assert.equal(url, 'https://api.mch.weixin.qq.com/v3/pay/transactions/jsapi');
    assert.equal(options.redirect, 'error');
    const fields = Object.fromEntries([...options.headers.Authorization.matchAll(/(\w+)="([^"]*)"/g)].map(match => [match[1], match[2]]));
    assert.equal(fields.mchid, config.mchid);
    assert.equal(fields.serial_no, config.merchantSerial);
    assert.ok(verify('RSA-SHA256', Buffer.from(`POST\n/v3/pay/transactions/jsapi\n${fields.timestamp}\n${fields.nonce_str}\n${options.body}\n`),
      merchant.publicKey, Buffer.from(fields.signature, 'base64')));
    assert.deepEqual(JSON.parse(options.body).amount, { total: order.totalCents, currency: 'CNY' });
    const responseBody = JSON.stringify({ prepay_id: 'wx_prepay_test' });
    return new Response(responseBody, { headers: signedHeaders(responseBody) });
  } });
  assert.equal(result.prepayId, 'wx_prepay_test');
  const p = result.paymentParams;
  assert.equal(p.signType, 'RSA');
  assert.ok(verify('RSA-SHA256', Buffer.from(`${p.appId}\n${p.timeStamp}\n${p.nonceStr}\n${p.package}\n`),
    merchant.publicKey, Buffer.from(p.paySign, 'base64')));
});
test('JSAPI rejects unsigned responses and invalid order amounts before requesting payment', async () => {
  await assert.rejects(createJsapiOrder({ config, order, now,
    fetchImpl: async () => new Response(JSON.stringify({ prepay_id: 'forged' })) }), { code: 'INVALID_SIGNATURE' });
  for (const totalCents of [-1, 0, 1.5, '12900', Number.MAX_SAFE_INTEGER + 1]) {
    await assert.rejects(createJsapiOrder({ config, order: { ...order, totalCents }, now,
      fetchImpl: async () => assert.fail('Invalid amount must not reach provider') }), { code: 'INVALID_ORDER' });
  }
  await assert.rejects(createJsapiOrder({ config: { ...config, platformKeys: {} }, order, now,
    fetchImpl: async () => assert.fail('Untrusted configuration must not reach provider') }), { code: 'INVALID_CONFIGURATION' });
});
test('APP orders omit JSAPI payer and sign the native SDK canonical message', async () => {
  const result = await createAppOrder({ config, order: { ...order, openid: undefined }, now, fetchImpl: async (url, options) => {
    assert.equal(url, 'https://api.mch.weixin.qq.com/v3/pay/transactions/app');
    assert.equal(Object.hasOwn(JSON.parse(options.body), 'payer'), false);
    const responseBody = JSON.stringify({ prepay_id: 'app_prepay' });
    return new Response(responseBody, { headers: signedHeaders(responseBody) });
  } });
  const p = result.paymentParams;
  assert.equal(p.package, 'Sign=WXPay'); assert.equal(p.partnerId, config.mchid);
  assert.ok(verify('RSA-SHA256', Buffer.from(`${p.appId}\n${p.timeStamp}\n${p.nonceStr}\n${p.prepayId}\n`),
    merchant.publicKey, Buffer.from(p.sign, 'base64')));
});
test('APP callback is accepted only with explicit expected APP trade type', () => {
  const input = notification({ trade_type: 'APP' });
  assert.throws(() => verifyWechatPayNotification(input), { code: 'PAYMENT_MISMATCH' });
  assert.equal(verifyWechatPayNotification({ ...input, config: { ...config, tradeType: 'APP' } }).tradeType, 'APP');
});
test('signed and authenticated callback matches persisted amount, identity and merchant', () => {
  const result = verifyWechatPayNotification(notification());
  assert.equal(result.transactionId, '420000000000000000001');
  assert.equal(result.orderId, order.id);
  assert.equal(result.totalCents, order.totalCents);
  assert.equal(result.openid, order.openid);
  assert.equal(result.notificationId, 'event_123');
  assert.deepEqual(validateWechatPayOrder(decryptWechatPayNotification(notification()), order), result);
});
test('callback rejects signature tampering, unknown trust root, replay age and malicious signatures', () => {
  const valid = notification();
  assert.throws(() => verifyWechatPayNotification({ ...valid, rawBody: `${valid.rawBody} ` }), { code: 'INVALID_SIGNATURE' });
  assert.throws(() => verifyWechatPayNotification({ ...valid, headers: { ...valid.headers, 'Wechatpay-Serial': 'attacker' } }), { code: 'UNKNOWN_PLATFORM_KEY' });
  assert.throws(() => verifyWechatPayNotification({ ...valid, now: now + 301000 }), { code: 'INVALID_SIGNATURE' });
  assert.throws(() => verifyWechatPayNotification({ ...valid, headers: { ...valid.headers, 'Wechatpay-Signature': 'WECHATPAY/SIGNTEST/invalid' } }), { code: 'INVALID_SIGNATURE' });
  assert.throws(() => verifyWechatPayNotification({ ...valid, headers: signedHeaders(valid.rawBody, now, merchant.privateKey) }), { code: 'INVALID_SIGNATURE' });
});
test('callback rejects wrong APIv3 key and resource authentication tag', () => {
  const valid = notification();
  assert.throws(() => verifyWechatPayNotification({ ...valid, config: { ...config, apiV3Key: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' } }), { code: 'INVALID_PAYMENT_EVENT' });
  const body = JSON.parse(valid.rawBody); body.resource.ciphertext = `${body.resource.ciphertext.slice(0, -4)}AAAA`;
  const rawBody = JSON.stringify(body);
  assert.throws(() => verifyWechatPayNotification({ ...valid, rawBody, headers: signedHeaders(rawBody) }), { code: 'INVALID_PAYMENT_EVENT' });
});
test('callback rejects mismatched amount/order/payer/merchant/currency and unsuccessful transactions', () => {
  for (const mismatch of [{ amount: { total: 1, currency: 'CNY' } }, { out_trade_no: 'other_order' },
    { payer: { openid: 'other_user' } }, { appid: 'wxother' }, { mchid: '99999999' },
    { amount: { total: 12900, currency: 'USD' } }, { trade_state: 'CLOSED' }, { trade_type: 'APP' }]) {
    assert.throws(() => verifyWechatPayNotification(notification(mismatch)), { code: 'PAYMENT_MISMATCH' });
  }
  assert.throws(() => verifyWechatPayNotification({ ...notification(), expectedOrder: undefined }), { code: 'PAYMENT_MISMATCH' });
  assert.throws(() => verifyWechatPayNotification(notification({}, { event_type: 'REFUND.SUCCESS' })), { code: 'INVALID_PAYMENT_EVENT' });
});
