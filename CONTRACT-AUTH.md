# Authentication UI contract

Base `/api/v1`. JSON request/response. Implementations: API `src/sms-auth.mjs`, Tencent adapter `services/integrations/src/tencent-sms.mjs`. Secrets remain server-only. Phone scope in this version: mainland China mobile, `1[3-9]` plus 9 digits, optionally prefixed by `+86`; surrounding spaces trimmed, no other characters.

## Capabilities (no session required)

`GET /auth/capabilities` → 200:

```json
{"mode":"demo","demo":{"enabled":true},"wechatMini":{"enabled":false},"wechatApp":{"enabled":false},"sms":{"enabled":true,"provider":"test","testMode":true,"codeLength":6,"expiresInSeconds":300,"retryAfterSeconds":60,"reasonCode":null}}
```

SMS provider is `disabled`, `test`, or `tencent`. Default is disabled. `SMS_PROVIDER=test` is explicitly enabled only in API_MODE=demo, never sends a message. In production, complete Tencent configuration AND club legal readiness are required. Disabled SMS reason is `SMS_NOT_CONFIGURED` or `CLUB_NOT_READY`. WeChat enabled booleans reflect production credentials + legal readiness. Demo enabled does not mean WeChat works.

Challenges, phone identities, resend state and send budgets persist their verification source. Test and Tencent records stay separate even when a database and `SMS_HASH_SECRET` are reused across mode changes. A test code cannot create a production session, and test accounts/roles never become production accounts. Verification IP budgets remain shared conservatively.

## Request code

`POST /auth/sms/challenges` with `{ "phone": "13800138000" }` → 201:

```json
{"challengeId":"opaque-random-id","phoneMasked":"138****8000","expiresInSeconds":300,"retryAfterSeconds":60,"delivery":"test","testCode":"123456"}
```

- Real provider returns `delivery:"accepted"`, with NO `testCode`. Accepted means the SMS provider accepted the request; delivery to a handset has not been verified.
- Test provider returns a newly generated 6 digit `testCode`. Label it “本地验证码，未发送短信”. Do not say an SMS was sent. Frontend fixtures may use `123456`; live test code is random and comes from this response.
- A successful resend creates a new `challengeId` and supersedes prior unconsumed codes for that phone. If a provider send fails, the previous valid challenge remains valid. Cooldown/rate limit still apply to failed send attempts.
- Persist phone/form intent locally only as needed for this flow; do not log codes. Code entry may paste all six digits and submit once, disable while pending. Countdown uses response `retryAfterSeconds` (not the phone clock's assumptions).

## Verify

`POST /auth/sms/verify` with `{ "challengeId":"...", "code":"123456" }` → 200:

```json
{"token":"opaque-bearer","user":{"id":"uuid","name":"手机用户"},"role":"customer","playerId":null,"demo":true,"expiresIn":86400}
```

Save as the existing session; use `GET /me` to refresh user/role. New accounts are customers. No client role or user ID is accepted. Existing explicitly invited members retain their role; SMS does not grant a role. A phone already registered is indistinguishable until a valid OTP proves possession. Verification consumes the challenge atomically; no second session from replay.

All errors use `{ "error": { "code":"...", "message":"...", "retryAfterSeconds":60, "attemptsRemaining":4 } }`. Last two fields only when relevant. `Retry-After` HTTP header also accompanies retryAfterSeconds.

| HTTP | Code | UI action |
|---|---|---|
| 400 | PHONE_INVALID | Inline phone format error |
| 400 | OTP_FORMAT_INVALID | Require exactly six ASCII digits |
| 401 | OTP_INVALID | Stay on code screen; show attemptsRemaining |
| 410 | OTP_EXPIRED | Request another code |
| 410 | OTP_SUPERSEDED | Use newest challenge/code |
| 410 | OTP_USED | Code already consumed; request another if session was lost |
| 429 | OTP_ATTEMPTS_EXCEEDED | Challenge is locked; wait retryAfterSeconds, then request another |
| 429 | SMS_COOLDOWN | Countdown from retryAfterSeconds |
| 429 | SMS_RATE_LIMIT | Wait retryAfterSeconds; do not retry automatically |
| 503 | SMS_NOT_CONFIGURED | Disable SMS entry and offer available method |
| 409 | CLUB_NOT_READY | Explain club setup is incomplete |
| 409 | SMS_IDENTITY_REVIEW_REQUIRED | Show “此手机号需要联系客服核实后登录”; do not switch accounts or retry automatically |
| 502 | SMS_DELIVERY_FAILED | Do not claim sent; retain phone and expose timed retry |

Unknown challenge IDs return OTP_INVALID with the same general failure text; no phone/account lookup result is returned. Wrong attempts count even when malformed code is supplied to a known challenge. Five failed attempts lock a challenge. Limits: phone 5/hour, 10/day; IP 20/hour, 100/day; verify IP 60/10 minutes. Proxy headers are ignored unless the immediate proxy is explicitly trusted.

Upgrades from databases without verification-source metadata invalidate their outstanding challenges and revoke sessions for those phone accounts. Existing accounts, roles, identities and orders remain stored, but no old phone mapping is assumed to be real SMS verification. After a valid production OTP matches an unclassified old mapping, return `SMS_IDENTITY_REVIEW_REQUIRED` rather than inherit that account or silently create a second one. Recovery needs operator verification; no automatic identity migration is provided. Test or unclassified phone mappings alone do not reserve a production member binding.

## Explicit WeChat link before payment

Phone login does not invent an OpenID or merge accounts. If a phone session requests real payment without a suitable WeChat identity, API returns 409 `WECHAT_LINK_REQUIRED`. The client should clearly offer “关联微信并继续支付”. Only after the user chooses this action:

- Mini obtains a fresh `wx.login()` code; `POST /auth/wechat/link` with current Bearer + `{code}`.
- Native app obtains a fresh WeChat OAuth code; `POST /auth/wechat-app/link` with current Bearer + `{code}`.
- Success returns the same token/user shape as login, for the SAME user and role, with a new appropriate WeChat session. Save it, then retry payment on the SAME order. Pending payment attempts are never reassigned to a different app.
- `409 WECHAT_IDENTITY_IN_USE`: this WeChat identity belongs to another account. Do not merge, switch account silently, or discard the current order; offer customer support or explicit account switch.
- `409 WECHAT_ACCOUNT_ALREADY_LINKED`: this account already has another identity for that WeChat application. Do not overwrite it.
- `401 WECHAT_LOGIN_FAILED`, `503 AUTH_PROVIDER_NOT_CONFIGURED`, `409 CLUB_NOT_READY`: same handling as regular WeChat login.

Separate WeChat applications may be linked to the same verified phone account, each with its own appid/openid mapping. No UnionID auto-merge. Account deletion revokes sessions, phone mapping and all WeChat identities; outstanding-order protections remain.
