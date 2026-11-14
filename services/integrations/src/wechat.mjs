import { createDecipheriv, createPrivateKey, createPublicKey, randomBytes, sign, verify, X509Certificate } from 'node:crypto';

// Server-only adapters. Never bundle this module or its configuration into a client.
export class IntegrationError extends Error {
  constructor(code, message) { super(message); this.name = 'IntegrationError'; this.code = code; }
}
const fail = (code, message) => { throw new IntegrationError(code, message); };
const required = (value, name, max = 256) => {
  if (typeof value !== 'string' || !value.trim() || value.length > max || /[\r\n\0]/.test(value)) {
    fail('INVALID_CONFIGURATION', `${name} is missing or invalid`);
  }
  return value;
};
const json = (text) => {
  try {
    const value = JSON.parse(text);
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error();
    return value;
  } catch { fail('INVALID_PROVIDER_RESPONSE', 'Provider returned invalid JSON object'); }
};
const timestamp = (now) => Math.floor(now / 1000).toString();
const nonce = () => randomBytes(16).toString('hex');
const header = (headers, name) => {
  const value = typeof headers?.get === 'function' ? headers.get(name)
    : Object.entries(headers ?? {}).find(([key]) => key.toLowerCase() === name.toLowerCase())?.[1];
  return typeof value === 'string' ? value : '';
};
const base64 = (value, code) => {
  if (typeof value !== 'string' || !value.length || !/^[A-Za-z0-9+/]+={0,2}$/.test(value) || value.length % 4 !== 0) {
    fail(code, 'Invalid encoded provider data');
  }
  return Buffer.from(value, 'base64');
};
async function request(fetchImpl, url, options) {
  try { return await fetchImpl(url, { ...options, redirect: 'error', signal: AbortSignal.timeout(10000) }); }
  catch { fail('PROVIDER_UNAVAILABLE', 'Provider request failed; retry safely using the same order identifier'); }
}
async function readBody(response) {
  let text;
  try { text = await response.text(); } catch { fail('PROVIDER_UNAVAILABLE', 'Provider response could not be read'); }
  if (Buffer.byteLength(text) > 256 * 1024) fail('INVALID_PROVIDER_RESPONSE', 'Provider response is too large');
  return text;
}

/** The sessionKey is server-only. Persist your own session and return only your own token to clients. */
export async function exchangeWechatCode({ appid, appSecret, code, fetchImpl = fetch }) {
  required(appid, 'appid'); required(appSecret, 'appSecret'); required(code, 'code');
  const url = new URL('https://api.weixin.qq.com/sns/jscode2session');
  url.search = new URLSearchParams({ appid, secret: appSecret, js_code: code, grant_type: 'authorization_code' }).toString();
  const response = await request(fetchImpl, url, { method: 'GET' });
  if (!response.ok) fail('PROVIDER_UNAVAILABLE', 'WeChat login service is unavailable');
  const data = json(await readBody(response));
  if (data.errcode) {
    if ([40029, 40163].includes(Number(data.errcode))) fail('INVALID_WECHAT_CODE', 'WeChat login code is invalid or expired');
    fail('WECHAT_LOGIN_FAILED', 'WeChat login failed; check server credentials and provider availability');
  }
  if (typeof data.openid !== 'string' || !data.openid || typeof data.session_key !== 'string' || !data.session_key) {
    fail('INVALID_PROVIDER_RESPONSE', 'WeChat login identity is incomplete');
  }
  return { openid: data.openid, sessionKey: data.session_key,
    ...(typeof data.unionid === 'string' && data.unionid ? { unionid: data.unionid } : {}) };
}

/** Native OAuth credentials and returned tokens stay on the server. Client supplies only its short-lived SDK code. */
export async function exchangeWechatAppCode({ appid, appSecret, code, fetchImpl = fetch }) {
  required(appid, 'appid'); required(appSecret, 'appSecret'); required(code, 'code');
  const url = new URL('https://api.weixin.qq.com/sns/oauth2/access_token');
  url.search = new URLSearchParams({ appid, secret: appSecret, code, grant_type: 'authorization_code' }).toString();
  const response = await request(fetchImpl, url, { method: 'GET' });
  if (!response.ok) fail('PROVIDER_UNAVAILABLE', 'WeChat native login service is unavailable');
  const data = json(await readBody(response));
  if (data.errcode) {
    if ([40029, 40163].includes(Number(data.errcode))) fail('INVALID_WECHAT_CODE', 'WeChat login code is invalid or expired');
    fail('WECHAT_LOGIN_FAILED', 'WeChat native login failed; check server credentials and provider availability');
  }
  if (typeof data.openid !== 'string' || !data.openid || typeof data.access_token !== 'string' || !data.access_token
    || typeof data.refresh_token !== 'string' || !data.refresh_token || !Number.isSafeInteger(data.expires_in) || data.expires_in <= 0) {
    fail('INVALID_PROVIDER_RESPONSE', 'WeChat native identity is incomplete');
  }
  return { openid: data.openid, accessToken: data.access_token, refreshToken: data.refresh_token, expiresIn: data.expires_in,
    ...(typeof data.unionid === 'string' && data.unionid ? { unionid: data.unionid } : {}) };
}

function payIdentity(config) {
  required(config?.appid, 'appid'); required(config?.mchid, 'mchid');
  if (!/^[A-Za-z0-9_-]+$/.test(config.appid) || !/^\d+$/.test(config.mchid)) {
    fail('INVALID_CONFIGURATION', 'Invalid payment merchant identity');
  }
}
function privateKey(config) {
  required(config.merchantSerial, 'merchantSerial');
  if (!/^[A-Za-z0-9_-]+$/.test(config.merchantSerial)) fail('INVALID_CONFIGURATION', 'Invalid merchant certificate serial');
  try {
    const key = createPrivateKey(config.merchantPrivateKey);
    if (key.asymmetricKeyType !== 'rsa' || key.asymmetricKeyDetails.modulusLength < 2048) throw new Error();
    return key;
  } catch { fail('INVALID_CONFIGURATION', 'Merchant private key must be a valid RSA key of at least 2048 bits'); }
}
function platformKey(config, serial, now) {
  if (!serial || !Object.hasOwn(config.platformKeys ?? {}, serial)) {
    fail('UNKNOWN_PLATFORM_KEY', 'No trusted WeChat platform key matches this signature');
  }
  try {
    const pem = config.platformKeys[serial];
    let key;
    if (typeof pem === 'string' && pem.includes('BEGIN CERTIFICATE')) {
      const cert = new X509Certificate(pem);
      if (now < Date.parse(cert.validFrom) || now > Date.parse(cert.validTo)) throw new Error();
      if (cert.serialNumber.toUpperCase() !== serial.toUpperCase()) throw new Error();
      key = cert.publicKey;
    } else key = createPublicKey(pem);
    if (key.asymmetricKeyType !== 'rsa' || key.asymmetricKeyDetails.modulusLength < 2048) throw new Error();
    return key;
  } catch { fail('INVALID_PLATFORM_KEY', 'Trusted WeChat platform key is invalid or expired'); }
}

/** Verify exact bytes before parsing. Trust keys provisioned from the merchant console, never callback-supplied keys. */
export function verifyWechatPaySignature({ headers, rawBody, config, now = Date.now() }) {
  if (typeof rawBody !== 'string' || Buffer.byteLength(rawBody) > 256 * 1024) {
    fail('INVALID_SIGNATURE', 'Payment message body is invalid');
  }
  const time = header(headers, 'Wechatpay-Timestamp');
  const random = header(headers, 'Wechatpay-Nonce');
  const serial = header(headers, 'Wechatpay-Serial');
  const signature = header(headers, 'Wechatpay-Signature');
  if (!/^\d{10,12}$/.test(time) || Math.abs(now / 1000 - Number(time)) > 300 || !random || random.length > 128 || /[\r\n]/.test(random)) {
    fail('INVALID_SIGNATURE', 'Payment signature timestamp or nonce is invalid');
  }
  const key = platformKey(config, serial, now);
  const bytes = base64(signature, 'INVALID_SIGNATURE');
  if (!verify('RSA-SHA256', Buffer.from(`${time}\n${random}\n${rawBody}\n`), key, bytes)) {
    fail('INVALID_SIGNATURE', 'Payment signature verification failed');
  }
  return true;
}

export const createJsapiOrder = (options) => createPaymentOrder({ ...options, tradeType: 'JSAPI' });
export const createAppOrder = (options) => createPaymentOrder({ ...options, tradeType: 'APP' });

async function createPaymentOrder({ config, order, fetchImpl = fetch, now = Date.now(), tradeType }) {
  payIdentity(config);
  const key = privateKey(config);
  required(order?.id, 'order.id'); required(order?.description, 'order.description', 127);
  if (tradeType === 'JSAPI') required(order?.openid, 'order.openid');
  if (!/^[A-Za-z0-9_-]{6,32}$/.test(order.id) || !Number.isSafeInteger(order.totalCents) || order.totalCents <= 0) {
    fail('INVALID_ORDER', 'Order identifier and integer amount are required');
  }
  let notifyUrl;
  try { notifyUrl = new URL(config.notifyUrl); } catch { fail('INVALID_CONFIGURATION', 'Payment notification URL is required'); }
  if (notifyUrl.protocol !== 'https:' || notifyUrl.username || notifyUrl.password || notifyUrl.hash) {
    fail('INVALID_CONFIGURATION', 'Payment notification URL must use HTTPS without credentials or fragment');
  }
  // Require a trust root before making a real charge-capable upstream request.
  if (!Object.keys(config.platformKeys ?? {}).length) fail('INVALID_CONFIGURATION', 'A trusted WeChat platform public key is required');
  const path = `/v3/pay/transactions/${tradeType.toLowerCase()}`;
  const body = JSON.stringify({ appid: config.appid, mchid: config.mchid, description: order.description,
    out_trade_no: order.id, notify_url: notifyUrl.href, amount: { total: order.totalCents, currency: 'CNY' },
    ...(tradeType === 'JSAPI' ? { payer: { openid: order.openid } } : {}) });
  const time = timestamp(now); const random = nonce();
  const signature = sign('RSA-SHA256', Buffer.from(`POST\n${path}\n${time}\n${random}\n${body}\n`), key).toString('base64');
  const authorization = `WECHATPAY2-SHA256-RSA2048 mchid="${config.mchid}",nonce_str="${random}",signature="${signature}",timestamp="${time}",serial_no="${config.merchantSerial}"`;
  const response = await request(fetchImpl, `https://api.mch.weixin.qq.com${path}`, { method: 'POST', body,
    headers: { Authorization: authorization, Accept: 'application/json', 'Content-Type': 'application/json', 'User-Agent': 'OpenNI/0.1' } });
  const responseBody = await readBody(response);
  if (!response.ok) fail('PAYMENT_ORDER_FAILED', 'WeChat did not accept this payment order; inspect the merchant console');
  verifyWechatPaySignature({ headers: response.headers, rawBody: responseBody, config, now });
  const result = json(responseBody);
  if (typeof result.prepay_id !== 'string' || !/^[A-Za-z0-9_=-]{1,128}$/.test(result.prepay_id)) {
    fail('INVALID_PROVIDER_RESPONSE', 'WeChat prepayment identifier is missing or invalid');
  }
  const clientNonce = nonce();
  if (tradeType === 'APP') {
    const clientSign = sign('RSA-SHA256', Buffer.from(`${config.appid}\n${time}\n${clientNonce}\n${result.prepay_id}\n`), key).toString('base64');
    return { prepayId: result.prepay_id, paymentParams: { appId: config.appid, partnerId: config.mchid, prepayId: result.prepay_id,
      package: 'Sign=WXPay', nonceStr: clientNonce, timeStamp: time, sign: clientSign } };
  }
  const paymentPackage = `prepay_id=${result.prepay_id}`;
  const paySign = sign('RSA-SHA256', Buffer.from(`${config.appid}\n${time}\n${clientNonce}\n${paymentPackage}\n`), key).toString('base64');
  return { prepayId: result.prepay_id, paymentParams: { appId: config.appid, timeStamp: time,
    nonceStr: clientNonce, package: paymentPackage, signType: 'RSA', paySign } };
}

/** Authenticates provider + merchant, but caller MUST still match a persisted order using validateWechatPayOrder. */
export function decryptWechatPayNotification({ headers, rawBody, config, now = Date.now() }) {
  payIdentity(config);
  verifyWechatPaySignature({ headers, rawBody, config, now });
  const event = json(rawBody); const resource = event.resource;
  if (event.event_type !== 'TRANSACTION.SUCCESS' || !resource || resource.algorithm !== 'AEAD_AES_256_GCM'
    || resource.original_type !== 'transaction' || typeof event.id !== 'string' || !event.id) {
    fail('INVALID_PAYMENT_EVENT', 'Unsupported payment notification');
  }
  if (typeof config.apiV3Key !== 'string' || Buffer.byteLength(config.apiV3Key) !== 32) {
    fail('INVALID_CONFIGURATION', 'WeChat API v3 key must contain exactly 32 bytes');
  }
  if (typeof resource.nonce !== 'string' || Buffer.byteLength(resource.nonce) !== 12
    || typeof resource.associated_data !== 'string') fail('INVALID_PAYMENT_EVENT', 'Invalid encrypted payment resource');
  const encrypted = base64(resource.ciphertext, 'INVALID_PAYMENT_EVENT');
  if (encrypted.length <= 16) fail('INVALID_PAYMENT_EVENT', 'Encrypted payment resource is incomplete');
  let plaintext;
  try {
    const decipher = createDecipheriv('aes-256-gcm', Buffer.from(config.apiV3Key), Buffer.from(resource.nonce));
    decipher.setAuthTag(encrypted.subarray(-16)); decipher.setAAD(Buffer.from(resource.associated_data));
    plaintext = Buffer.concat([decipher.update(encrypted.subarray(0, -16)), decipher.final()]).toString('utf8');
  } catch { fail('INVALID_PAYMENT_EVENT', 'Payment resource authentication failed'); }
  const payment = json(plaintext);
  if (payment.appid !== config.appid || payment.mchid !== config.mchid || payment.trade_state !== 'SUCCESS'
    || !['JSAPI', 'APP'].includes(config.tradeType ?? 'JSAPI') || payment.trade_type !== (config.tradeType ?? 'JSAPI')
    || payment.amount?.currency !== 'CNY' || !Number.isSafeInteger(payment.amount?.total)
    || payment.amount.total <= 0 || typeof payment.out_trade_no !== 'string' || !payment.out_trade_no
    || typeof payment.transaction_id !== 'string' || !payment.transaction_id || typeof payment.payer?.openid !== 'string'
    || !payment.payer.openid || typeof payment.success_time !== 'string' || Number.isNaN(Date.parse(payment.success_time))) {
    fail('PAYMENT_MISMATCH', 'Payment notification does not match this merchant or a successful CNY payment of the expected type');
  }
  return { notificationId: event.id, transactionId: payment.transaction_id, orderId: payment.out_trade_no,
    appid: payment.appid, mchid: payment.mchid, totalCents: payment.amount.total, currency: payment.amount.currency,
    openid: payment.payer.openid, paidAt: payment.success_time, tradeType: payment.trade_type };
}

export function validateWechatPayOrder(notification, expectedOrder) {
  if (!expectedOrder || notification.orderId !== expectedOrder.id || notification.totalCents !== expectedOrder.totalCents
    || notification.currency !== 'CNY' || (expectedOrder.openid && notification.openid !== expectedOrder.openid)) {
    fail('PAYMENT_MISMATCH', 'Payment does not match the persisted order, amount, or payer');
  }
  return notification;
}

export function verifyWechatPayNotification(options) {
  return validateWechatPayOrder(decryptWechatPayNotification(options), options.expectedOrder);
}

async function merchantRequest({ config, method, path, payload, fetchImpl = fetch, now = Date.now(), emptyResponse = false }) {
  payIdentity(config);
  const key = privateKey(config);
  if (!Object.keys(config.platformKeys ?? {}).length) fail('INVALID_CONFIGURATION', 'A trusted WeChat platform public key is required');
  const body = payload === undefined ? '' : JSON.stringify(payload);
  const time = timestamp(now); const random = nonce();
  const signature = sign('RSA-SHA256', Buffer.from(`${method}\n${path}\n${time}\n${random}\n${body}\n`), key).toString('base64');
  const response = await request(fetchImpl, `https://api.mch.weixin.qq.com${path}`, { method, ...(body ? { body } : {}),
    headers: { Authorization: `WECHATPAY2-SHA256-RSA2048 mchid="${config.mchid}",nonce_str="${random}",signature="${signature}",timestamp="${time}",serial_no="${config.merchantSerial}"`,
      Accept: 'application/json', 'Content-Type': 'application/json', 'User-Agent': 'OpenNI/0.1' } });
  const rawBody = await readBody(response);
  if (!response.ok) fail('PAYMENT_REQUEST_FAILED', 'WeChat did not accept this request; check merchant records before retrying');
  verifyWechatPaySignature({ headers: response.headers, rawBody, config, now });
  if (emptyResponse) {
    if (response.status !== 204 || rawBody !== '') fail('INVALID_PROVIDER_RESPONSE', 'Expected an empty signed close-order response');
    return { accepted: true };
  }
  return json(rawBody);
}
const merchantId = (value) => {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{6,64}$/.test(value)) fail('INVALID_ORDER', 'Invalid merchant order or refund identifier');
  return value;
};

/** A signed 204 acknowledges the request. Query CLOSED before changing the local order. */
export async function closeWechatOrder({ config, orderId, fetchImpl = fetch, now = Date.now() }) {
  merchantId(orderId);
  await merchantRequest({ config, method: 'POST', path: `/v3/pay/transactions/out-trade-no/${encodeURIComponent(orderId)}/close`,
    payload: { mchid: config.mchid }, fetchImpl, now, emptyResponse: true });
  return { accepted: true, orderId };
}

/** Signed provider query. Caller must still match saved amount/payer and persist atomically. */
export async function queryWechatOrder({ config, orderId, fetchImpl = fetch, now = Date.now() }) {
  merchantId(orderId);
  const payment = await merchantRequest({ config, method: 'GET',
    path: `/v3/pay/transactions/out-trade-no/${encodeURIComponent(orderId)}?mchid=${encodeURIComponent(config.mchid)}`, fetchImpl, now });
  if (payment.appid !== config.appid || payment.mchid !== config.mchid || payment.out_trade_no !== orderId
    || !['SUCCESS', 'REFUND', 'NOTPAY', 'CLOSED', 'REVOKED', 'USERPAYING', 'PAYERROR'].includes(payment.trade_state)
    || !['JSAPI', 'APP'].includes(config.tradeType ?? 'JSAPI') || (payment.trade_type !== undefined && payment.trade_type !== (config.tradeType ?? 'JSAPI'))
    || !Number.isSafeInteger(payment.amount?.total) || payment.amount.total <= 0 || payment.amount.currency !== 'CNY') {
    fail('PAYMENT_MISMATCH', 'Queried payment does not match the configured merchant or order');
  }
  if (['SUCCESS', 'REFUND'].includes(payment.trade_state) && (payment.trade_type !== (config.tradeType ?? 'JSAPI') || typeof payment.transaction_id !== 'string' || !payment.transaction_id
    || typeof payment.payer?.openid !== 'string' || !payment.payer.openid || Number.isNaN(Date.parse(payment.success_time ?? '')))) {
    fail('INVALID_PROVIDER_RESPONSE', 'Successful payment query is incomplete');
  }
  return { state: payment.trade_state, orderId: payment.out_trade_no, transactionId: payment.transaction_id,
    totalCents: payment.amount.total, currency: payment.amount.currency, appid: payment.appid, mchid: payment.mchid,
    openid: payment.payer?.openid, paidAt: payment.success_time, tradeType: payment.trade_type };
}

function refundResult(data, { callback = false } = {}) {
  const status = callback ? data.refund_status : data.status;
  if (!['SUCCESS', 'CLOSED', 'PROCESSING', 'ABNORMAL'].includes(status)
    || typeof data.refund_id !== 'string' || !data.refund_id || typeof data.out_refund_no !== 'string' || !data.out_refund_no
    || typeof data.transaction_id !== 'string' || !data.transaction_id || typeof data.out_trade_no !== 'string' || !data.out_trade_no
    || !Number.isSafeInteger(data.amount?.total) || data.amount.total <= 0
    || !Number.isSafeInteger(data.amount?.refund) || data.amount.refund <= 0 || data.amount.refund > data.amount.total
    || (data.amount.currency !== undefined && data.amount.currency !== 'CNY')
    || (status === 'SUCCESS' && Number.isNaN(Date.parse(data.success_time ?? '')))) {
    fail('REFUND_MISMATCH', 'Refund response has invalid identity, amount or status');
  }
  return { refundId: data.out_refund_no, providerRefundId: data.refund_id, status, orderId: data.out_trade_no,
    transactionId: data.transaction_id, totalCents: data.amount.total, refundCents: data.amount.refund,
    ...(data.success_time ? { successTime: data.success_time } : {}) };
}

export function validateWechatRefundOrder(refund, expectedOrder, expectedRefundId) {
  if (!expectedOrder || refund.orderId !== expectedOrder.id || refund.transactionId !== expectedOrder.transactionId
    || refund.totalCents !== expectedOrder.totalCents || refund.refundCents !== expectedOrder.totalCents
    || !expectedRefundId || refund.refundId !== expectedRefundId) {
    fail('REFUND_MISMATCH', 'Refund does not match the persisted payment and full refund request');
  }
  return refund;
}

/** Reuse refundId for every retry. Only full refunds are supported by this first adapter. */
export async function createWechatRefund({ config, order, refundId, reason = '俱乐部订单退款', fetchImpl = fetch, now = Date.now() }) {
  merchantId(order?.id); merchantId(refundId); required(order?.transactionId, 'transactionId'); required(reason, 'reason', 80);
  if (!Number.isSafeInteger(order.totalCents) || order.totalCents <= 0) fail('INVALID_ORDER', 'Refund requires a persisted integer payment amount');
  let notify;
  try { notify = new URL(config.refundNotifyUrl); } catch { fail('INVALID_CONFIGURATION', 'Refund notification URL is required'); }
  if (notify.protocol !== 'https:' || notify.username || notify.password || notify.search || notify.hash) {
    fail('INVALID_CONFIGURATION', 'Refund notification URL must use HTTPS without query or credentials');
  }
  const data = await merchantRequest({ config, method: 'POST', path: '/v3/refund/domestic/refunds', fetchImpl, now,
    payload: { transaction_id: order.transactionId, out_refund_no: refundId, reason, notify_url: notify.href,
      amount: { total: order.totalCents, refund: order.totalCents, currency: 'CNY' } } });
  return validateWechatRefundOrder(refundResult(data), order, refundId);
}

export async function queryWechatRefund({ config, refundId, fetchImpl = fetch, now = Date.now() }) {
  merchantId(refundId);
  const data = await merchantRequest({ config, method: 'GET', path: `/v3/refund/domestic/refunds/${encodeURIComponent(refundId)}`, fetchImpl, now });
  const result = refundResult(data);
  if (result.refundId !== refundId) fail('REFUND_MISMATCH', 'Queried refund identifier does not match');
  return result;
}

/** Refund notifications do not contain appid. Caller anchors channel/app identity to the original saved payment. */
export function decryptWechatRefundNotification({ headers, rawBody, config, now = Date.now() }) {
  payIdentity(config); verifyWechatPaySignature({ headers, rawBody, config, now });
  const event = json(rawBody); const resource = event.resource;
  if (!['REFUND.SUCCESS', 'REFUND.ABNORMAL', 'REFUND.CLOSED'].includes(event.event_type) || !resource
    || resource.algorithm !== 'AEAD_AES_256_GCM' || resource.original_type !== 'refund' || typeof event.id !== 'string' || !event.id) {
    fail('INVALID_REFUND_EVENT', 'Unsupported refund notification');
  }
  if (typeof config.apiV3Key !== 'string' || Buffer.byteLength(config.apiV3Key) !== 32) fail('INVALID_CONFIGURATION', 'WeChat API v3 key must contain exactly 32 bytes');
  if (typeof resource.nonce !== 'string' || Buffer.byteLength(resource.nonce) !== 12 || typeof resource.associated_data !== 'string') {
    fail('INVALID_REFUND_EVENT', 'Invalid encrypted refund resource');
  }
  const encrypted = base64(resource.ciphertext, 'INVALID_REFUND_EVENT');
  if (encrypted.length <= 16) fail('INVALID_REFUND_EVENT', 'Encrypted refund resource is incomplete');
  let plaintext;
  try {
    const decipher = createDecipheriv('aes-256-gcm', Buffer.from(config.apiV3Key), Buffer.from(resource.nonce));
    decipher.setAuthTag(encrypted.subarray(-16)); decipher.setAAD(Buffer.from(resource.associated_data));
    plaintext = Buffer.concat([decipher.update(encrypted.subarray(0, -16)), decipher.final()]).toString('utf8');
  } catch { fail('INVALID_REFUND_EVENT', 'Refund resource authentication failed'); }
  const data = json(plaintext);
  if (data.mchid !== config.mchid || event.event_type !== `REFUND.${data.refund_status}`) {
    fail('REFUND_MISMATCH', 'Refund notification merchant or event status does not match');
  }
  return { ...refundResult(data, { callback: true }), notificationId: event.id, mchid: data.mchid };
}
