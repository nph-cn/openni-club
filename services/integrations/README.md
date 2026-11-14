# Server-only WeChat adapters

Independent Node.js implementation with no runtime dependencies. This module is never imported by clients. The project API owns sessions, authorization, persistent orders and transaction idempotency.

| Export | Input | Result |
| --- | --- | --- |
| `exchangeWechatCode` | appid, appSecret, one-time code | openid, optional unionid, server-only sessionKey |
| `exchangeWechatAppCode` | native appid, appSecret, SDK code | openid, optional unionid, server-only OAuth tokens |
| `createJsapiOrder` | config, persisted order | prepayId and mini-program paymentParams |
| `createAppOrder` | config, persisted order | prepayId and native SDK paymentParams |
| `decryptWechatPayNotification` | headers, exact rawBody, config | verified merchant transaction for DB lookup |
| `validateWechatPayOrder` | verified transaction, persisted expected order | matching transaction or throws |
| `verifyWechatPayNotification` | callback inputs plus expectedOrder | both verification stages in one call |
| `queryWechatOrder` | config, merchant orderId | signed provider state and amount for reconciliation |
| `closeWechatOrder` | config, merchant orderId | signed empty 204 acknowledgement; query CLOSED before local cancellation |
| `createWechatRefund` | config, persisted paid order, stable refundId | verified full refund state |
| `queryWechatRefund` | config, refundId | signed provider refund state |
| `decryptWechatRefundNotification` | headers, rawBody, config | authenticated refund event for DB lookup |
| `validateWechatRefundOrder` | refund, original paid order, refundId | full-amount/transaction/order match |

Payment config: `appid`, `mchid`, `merchantSerial`, `merchantPrivateKey` (PEM), `apiV3Key` (32 bytes), `notifyUrl`, `platformKeys` (trusted serial/public-key-ID → PEM), and callback `tradeType` (`JSAPI` default or `APP`). Order: `id` (6–32 safe characters), `description`, positive integer `totalCents`; JSAPI also requires `openid`. Use a stable mapping from business order IDs to merchant IDs; do not generate a new merchant order on every retry.

Both outbound requests and client payment parameters are RSA-SHA256 signed. Successful upstream responses and callbacks require a known platform key and a timestamp within five minutes. Callbacks are authenticated before AES-256-GCM decryption. Merchant, appid, trade type, currency and successful state are checked; the second stage matches stored order ID, amount and payer. Provision trusted keys from the merchant console and maintain rotation; no arbitrary network trust-key discovery is performed.

The API must commit payment changes atomically, reject unknown orders, preserve transaction uniqueness and acknowledge valid duplicates without double fulfilment. Do not use `decryptWechatPayNotification` alone to mark an order paid. Do not use a client SDK success event as payment proof. Never expose sessionKey, OAuth tokens, PEM keys or API-v3 keys to the client or logs.

Refund config adds `refundNotifyUrl`. Only full refunds are supported. Store one refundId before the first upstream request and reuse it after timeouts. Both queries and refund responses are signature-verified. Refund notifications include merchant identity but no appid; the caller must anchor their channel/app to the original stored payment and validate all order, transaction and refund IDs plus amounts before any state change.

Unpaid/closed queries may omit the optional `trade_type`; when supplied it must match the configured channel. Successful/refunded queries and payment callbacks require the expected type. A close acknowledgement alone does not establish local cancellation: query the provider and require `CLOSED`. See the [official order query](https://pay.wechatpay.cn/doc/v3/merchant/4012791859) and [close API](https://pay.wechatpay.cn/doc/v3/merchant/4012791860).

Run `npm test` and `npm run check` here. Tests generate local RSA keys, encrypt fake callbacks and mock HTTP; no real merchant API calls or financial transactions occur. Provider eligibility, live credentials, actual mobile SDK flow and external payment rules still need operator verification. Partial refunds, automatic bill downloading and certificate downloading are not implemented.

Configuration walkthrough: [中文教程](../../docs/09-wechat-adapters.md). Protocol reference: [WeChat Pay official SDK](https://github.com/wechatpay-apiv3/wechatpay-go), [official notification handler](https://github.com/wechatpay-apiv3/wechatpay-go/blob/main/core/notify/notify.go).
