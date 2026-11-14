import test from 'node:test';
import assert from 'node:assert/strict';
import { createCipheriv, generateKeyPairSync, sign, verify } from 'node:crypto';
import { queryWechatOrder, closeWechatOrder, createWechatRefund, queryWechatRefund, decryptWechatRefundNotification, validateWechatRefundOrder } from '../src/wechat.mjs';

const merchant = generateKeyPairSync('rsa', { modulusLength: 2048 });
const platform = generateKeyPairSync('rsa', { modulusLength: 2048 });
const now = Date.parse('2026-11-15T01:00:00Z');
const config = { appid: 'wxrefundtest', mchid: '1900000001', merchantSerial: 'ABC123',
  merchantPrivateKey: merchant.privateKey.export({ type: 'pkcs8', format: 'pem' }),
  apiV3Key: '12345678901234567890123456789012', refundNotifyUrl: 'https://api.example.com/api/v1/payments/wechat/refund-notify',
  platformKeys: { PUB_KEY_ID_TEST: platform.publicKey.export({ type: 'spki', format: 'pem' }) } };
const order = { id: 'order_123456', transactionId: '420000000000000000001', totalCents: 12900 };
const refundId = 'refund_123456';
const payment = { appid: config.appid, mchid: config.mchid, out_trade_no: order.id, transaction_id: order.transactionId,
  trade_state: 'SUCCESS', trade_type: 'JSAPI', amount: { total: order.totalCents, currency: 'CNY' },
  payer: { openid: 'payer' }, success_time: '2026-11-15T09:00:00+08:00' };
const refund = { refund_id: '5000000000001', out_refund_no: refundId, transaction_id: order.transactionId,
  out_trade_no: order.id, status: 'PROCESSING', amount: { total: order.totalCents, refund: order.totalCents, currency: 'CNY' } };
function signedHeaders(rawBody) {
  const time = Math.floor(now / 1000).toString(); const nonce = 'refund_nonce';
  return { 'Wechatpay-Timestamp': time, 'Wechatpay-Nonce': nonce, 'Wechatpay-Serial': 'PUB_KEY_ID_TEST',
    'Wechatpay-Signature': sign('RSA-SHA256', Buffer.from(`${time}\n${nonce}\n${rawBody}\n`), platform.privateKey).toString('base64') };
}
const response = data => { const body = JSON.stringify(data); return new Response(body, { headers: signedHeaders(body) }); };
function verifyRequest(url, options) {
  const fields = Object.fromEntries([...options.headers.Authorization.matchAll(/(\w+)="([^"]*)"/g)].map(x => [x[1], x[2]]));
  const parsed = new URL(url);
  assert.ok(verify('RSA-SHA256', Buffer.from(`${options.method}\n${parsed.pathname}${parsed.search}\n${fields.timestamp}\n${fields.nonce_str}\n${options.body ?? ''}\n`),
    merchant.publicKey, Buffer.from(fields.signature, 'base64')));
}
function callback(overrides = {}) {
  const payload = { ...refund, mchid: config.mchid, refund_status: 'SUCCESS', success_time: '2026-11-15T09:00:00+08:00',
    amount: { total: order.totalCents, refund: order.totalCents }, ...overrides };
  delete payload.status;
  const nonce = '123456789012'; const associated_data = 'refund';
  const cipher = createCipheriv('aes-256-gcm', Buffer.from(config.apiV3Key), Buffer.from(nonce));
  cipher.setAAD(Buffer.from(associated_data));
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(payload)), cipher.final(), cipher.getAuthTag()]).toString('base64');
  const rawBody = JSON.stringify({ id: 'refund_event', event_type: `REFUND.${payload.refund_status}`,
    resource: { algorithm: 'AEAD_AES_256_GCM', original_type: 'refund', nonce, associated_data, ciphertext } });
  return { headers: signedHeaders(rawBody), rawBody, config, now };
}
test('payment query signs full query path and verifies returned merchant and order', async () => {
  const result = await queryWechatOrder({ config, orderId: order.id, now, fetchImpl: async (url, options) => {
    verifyRequest(url, options); assert.equal(options.method, 'GET');
    assert.equal(new URL(url).searchParams.get('mchid'), config.mchid);
    return response(payment);
  } });
  assert.equal(result.state, 'SUCCESS'); assert.equal(result.totalCents, order.totalCents);
  for (const mismatch of [{ appid: 'attacker' }, { mchid: '999' }, { out_trade_no: 'wrong_order' }, { trade_type: 'APP' }]) {
    await assert.rejects(queryWechatOrder({ config, orderId: order.id, now, fetchImpl: async () => response({ ...payment, ...mismatch }) }), { code: 'PAYMENT_MISMATCH' });
  }
});
test('close requires signed empty 204 and does not claim confirmed local cancellation', async () => {
  const result = await closeWechatOrder({ config, orderId: order.id, now, fetchImpl: async (url, options) => {
    verifyRequest(url, options); assert.ok(url.endsWith(`/${order.id}/close`));
    assert.deepEqual(JSON.parse(options.body), { mchid: config.mchid });
    return new Response(null, { status: 204, headers: signedHeaders('') });
  } });
  assert.deepEqual(result, { accepted: true, orderId: order.id });
  await assert.rejects(closeWechatOrder({ config, orderId: order.id, now, fetchImpl: async () => new Response(null, { status: 204 }) }), { code: 'INVALID_SIGNATURE' });
  await assert.rejects(closeWechatOrder({ config, orderId: order.id, now, fetchImpl: async () => response({ closed: true }) }), { code: 'INVALID_PROVIDER_RESPONSE' });
});
test('unpaid and closed order queries allow optional trade_type, but paid queries require it',async()=>{
  for(const state of ['NOTPAY','CLOSED']){
    const payload={...payment,trade_state:state};delete payload.trade_type;delete payload.payer;delete payload.transaction_id;delete payload.success_time;
    assert.equal((await queryWechatOrder({config,orderId:order.id,now,fetchImpl:async()=>response(payload)})).state,state);
  }
  const missing={...payment};delete missing.trade_type;
  await assert.rejects(queryWechatOrder({config,orderId:order.id,now,fetchImpl:async()=>response(missing)}),{code:'INVALID_PROVIDER_RESPONSE'});
});
test('full refund uses fixed retry identifier and signs verified integer total', async () => {
  const requests = [];
  const fetchImpl = async (url, options) => {
    verifyRequest(url, options); assert.equal(new URL(url).pathname, '/v3/refund/domestic/refunds');
    const body = JSON.parse(options.body); requests.push(body);
    assert.deepEqual(body.amount, { total: order.totalCents, refund: order.totalCents, currency: 'CNY' });
    assert.equal(body.transaction_id, order.transactionId);
    return response(refund);
  };
  for (let index = 0; index < 2; index++) {
    const result = await createWechatRefund({ config, order, refundId, now, fetchImpl });
    assert.equal(result.status, 'PROCESSING'); assert.equal(result.refundId, refundId);
  }
  assert.equal(requests[0].out_refund_no, requests[1].out_refund_no);
});
test('refund request rejects invalid amount and wrong upstream identity', async () => {
  await assert.rejects(createWechatRefund({ config, order: { ...order, totalCents: -1 }, refundId, now,
    fetchImpl: async () => assert.fail('Invalid refund must not reach provider') }), { code: 'INVALID_ORDER' });
  await assert.rejects(createWechatRefund({ config, order, refundId, now,
    fetchImpl: async () => response({ ...refund, transaction_id: 'wrong_transaction' }) }), { code: 'REFUND_MISMATCH' });
  await assert.rejects(createWechatRefund({ config, order, refundId, now,
    fetchImpl: async () => response({ ...refund, amount: { total: order.totalCents, refund: 1, currency: 'CNY' } }) }), { code: 'REFUND_MISMATCH' });
});
test('refund query verifies response and caller can anchor it to saved payment', async () => {
  const result = await queryWechatRefund({ config, refundId, now, fetchImpl: async (url, options) => {
    verifyRequest(url, options); assert.ok(url.endsWith(refundId)); return response(refund);
  } });
  assert.equal(validateWechatRefundOrder(result, order, refundId).status, 'PROCESSING');
  await assert.rejects(queryWechatRefund({ config, refundId, now, fetchImpl: async () => response({ ...refund, out_refund_no: 'wrong_refund' }) }), { code: 'REFUND_MISMATCH' });
});
test('refund callback authenticates/decrypts and matches original full payment', () => {
  const result = decryptWechatRefundNotification(callback());
  assert.equal(result.status, 'SUCCESS'); assert.equal(result.mchid, config.mchid);
  assert.equal(validateWechatRefundOrder(result, order, refundId).providerRefundId, refund.refund_id);
  for (const mismatch of [{ totalCents: 1 }, { id: 'another_order' }, { transactionId: 'another_tx' }]) {
    assert.throws(() => validateWechatRefundOrder(result, { ...order, ...mismatch }, refundId), { code: 'REFUND_MISMATCH' });
  }
  assert.throws(() => validateWechatRefundOrder(result, order, 'another_refund'), { code: 'REFUND_MISMATCH' });
  assert.throws(() => decryptWechatRefundNotification(callback({ mchid: 'wrong' })), { code: 'REFUND_MISMATCH' });
});
test('refund callback rejects tampering and decrypt failures; abnormal status is not success', () => {
  const input = callback();
  assert.throws(() => decryptWechatRefundNotification({ ...input, rawBody: `${input.rawBody} ` }), { code: 'INVALID_SIGNATURE' });
  assert.throws(() => decryptWechatRefundNotification({ ...input, config: { ...config, apiV3Key: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' } }), { code: 'INVALID_REFUND_EVENT' });
  assert.equal(decryptWechatRefundNotification(callback({ refund_status: 'ABNORMAL', success_time: undefined })).status, 'ABNORMAL');
});
