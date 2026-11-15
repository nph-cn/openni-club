# 微信登录与支付：把真实账号接进代码

本仓库已实现小程序 `code2session`、移动应用 OAuth code 换身份、微信支付 v3 JSAPI / APP 预支付、客户端参数签名，以及支付响应/通知的 RSA 验签和 AES-GCM 解密。模拟测试覆盖正常支付、伪造签名、过期通知、错误金额/订单/付款人/商户和不同支付类型。它们证明代码按测试协议工作，不证明你的商户已经开通，也不证明真机支付成功。

## 1. 分清三个账号

| 账号 | 在哪里办理 | 这份工程用到什么 |
| --- | --- | --- |
| 微信小程序 | 微信公众平台 | 小程序 AppID / AppSecret；JSAPI 支付绑定 |
| 微信开放平台移动应用 | 微信开放平台 | 独立移动应用 AppID / AppSecret；Android 包名及签名、iOS Bundle ID / Universal Link；APP 支付绑定 |
| 微信支付商户 | 微信支付商户平台 | 商户号、已开通支付产品、证书序列号、商户私钥、API v3 Key、可信微信支付平台公钥/证书 |

小程序 AppID 和移动应用 AppID 不要混用。商户须分别绑定要收款的应用，业务类目应与实际服务一致。此处不代替平台对主体或类目的审核；先确认服务允许接入再投入真金白银。

## 2. 只在服务器填写秘密配置

从仓库根目录的 `.env.example` 复制为 `.env`。正式环境使用部署平台秘密变量或仅服务账号可读的文件；不要把 `.env` 提交到 Git。下面列变量名而不填入真实值：

| 变量 | 作用 | 是否可以放客户端 |
| --- | --- | --- |
| `WECHAT_APP_ID` / `WECHAT_APP_SECRET` | 小程序真实登录 | 只有 AppID 可以 |
| `WECHAT_NATIVE_APP_ID` / `WECHAT_NATIVE_APP_SECRET` | 原生 App 真实登录 | 只有 AppID 可以 |
| `WECHAT_PAY_MCH_ID` | 商户号 | 返回合法支付参数时可以 |
| `WECHAT_PAY_MERCHANT_SERIAL` | 商户签名证书序列号 | 无需客户端保存 |
| `WECHAT_PAY_PRIVATE_KEY_PATH` | 商户私钥 PEM 的服务器绝对路径 | 不可以 |
| `WECHAT_PAY_API_V3_KEY` | 解密通知的 32 字节 API v3 Key | 不可以 |
| `WECHAT_PAY_PLATFORM_KEY_ID` | 可信平台公钥 ID 或证书序列号 | 服务端配置 |
| `WECHAT_PAY_PLATFORM_KEY_PATH` | 对应平台公钥/证书 PEM 的服务器绝对路径 | 服务端配置 |
| `WECHAT_PAY_NOTIFY_URL` | `https://你的API域名/api/v1/payments/wechat/notify` | 可公开，但仅服务端设置 |
| `WECHAT_NATIVE_PAY_NOTIFY_URL` | `https://你的API域名/api/v1/payments/wechat-app/notify` | 可公开，但仅服务端设置 |
| `WECHAT_PAY_REFUND_NOTIFY_URL` | `https://你的API域名/api/v1/payments/wechat/refund-notify` | 服务端设置 |
| `WECHAT_NATIVE_PAY_REFUND_NOTIFY_URL` | `https://你的API域名/api/v1/payments/wechat-app/refund-notify` | 服务端设置 |

平台公钥与商户私钥不是同一份东西。公钥/证书从已认证的微信商户后台取得；不要信任回调请求自带的公钥。公钥 ID 要与文件对应，平台轮换时及时更新；证书模式还需关注有效期。当前环境配置一次装载一份平台公钥，轮换窗口请提前规划；适配器内部支持多个可信 key ID。

API 的 `DATA_DIR` 必须在持久化磁盘上，`ADMIN_TOKEN` 使用强随机值，`CORS_ORIGINS` 写实际后台网站的 HTTPS origin。运行 `node scripts/doctor.mjs --mode production` 查看缺项，输出不会显示密钥值。检查通过仅代表形状正确，剩余发布验收仍需完成。

## 3. 先验收登录，再启用收款

生产 API 使用 `API_MODE=production`。小程序以 `wx.login` 的一次性 code 请求 `POST /api/v1/auth/wechat`；原生 SDK 的 OAuth code 请求 `POST /api/v1/auth/wechat-app`。客户端只得到 OpenNI 自己的会话，微信 session_key、access_token、refresh_token 留在服务器一侧。登录失败不回退成 demo 身份。

让两个不同测试账号各自登录、建单，确认互相看不到订单。关闭再打开客户端，确认会话及错误处理合理；到期会话应要求重新登录。微信返回的 code 只能及时使用，不能把同一 code 复制到教程里长期复用。

若用户通过手机号登录，必须明确选择关联微信后，携带当前会话和新的微信 code 请求 `/auth/wechat/link`（小程序）或 `/auth/wechat-app/link`（原生）。它保留原账号和订单；身份冲突时拒绝关联，不自动合并。保存返回的新会话后继续支付同一订单。见 [手机号登录教程](11-phone-auth.md)。

收款默认关闭：`WECHAT_PAY_ENABLED=false` 和 `WECHAT_NATIVE_PAY_ENABLED=false`。分别设置为 `true` 才开启小程序或原生支付；还必须处于生产模式、补齐对应配置，并把真实俱乐部内容替换掉示例内容（`demoData=false`）。`POST /api/v1/orders/:id/pay` 根据已认证会话返回对应 SDK 的 `paymentParams`；金额来自数据库中的订单，不接受客户端任意报价。

小程序调用 `wx.requestPayment`；原生由 Flutter 微信 SDK 调起。iOS Universal Link、Bundle ID、Android applicationId 和签名指纹需要与微信开放平台一致。具体 SDK 配置跟随 `apps/mobile` 的实际说明，不能仅填服务器密钥就跳过原生工程配置。

## 4. 确认钱和订单真的一致

支付前核对商户、商品描述和金额。按供应商规则在隔离测试环境进行一次受控验收，保留脱敏的订单号、微信交易号、回调和数据库状态；不要在公共演示环境收真实款。

客户端“成功”回调只触发刷新。订单变成已支付必须由服务端通知通过签名、商户/AppID、订单号、整数金额、币种和付款人核对后提交。网络延迟时页面应显示待确认，不能先显示到账。通知重复送达不会重复记账；签名错误、未知订单、错误金额不能返回业务成功。

管理员可用订单里的支付同步操作查询微信真实状态，或发起全额退款。退款号在数据库中固定，失败重试沿用同一号码；提交成功显示“处理中”，只有有效退款回调或主动退款查询确认 `SUCCESS` 才记为退款成功。`ABNORMAL` / `CLOSED` 需要运营人员核实，不能改标签假装成功。尚无部分退款、自动定时查单或账单下载任务；每日在商户后台核对交易和退款记录。

退款通知协议没有 AppID 字段，因此通过已保存的原支付订单、支付渠道、商户、微信交易号、退款号与全额金额交叉核对；不会把配置中的 AppID 伪装成微信已回传的字段。测试应包含重复退款请求、退款通知重复、错误金额和断网后同步。未经实际验收不向公众开放收款。

## 5. 排错时只看脱敏信息

`INVALID_WECHAT_CODE`：重新从客户端发起登录，检查是否重复使用 code。`UNKNOWN_PLATFORM_KEY`：检查平台 key ID 与可信文件、轮换情况。`INVALID_SIGNATURE`：检查服务器时钟、原始请求体是否被中间件改写、平台 key 是否正确。`PAYMENT_MISMATCH`：检查应用、商户、支付类型和数据库订单，不能关闭校验来“修好”。`PROVIDER_UNAVAILABLE`：检查出站网络；支付请求超时重试必须沿用相同商户订单号。

正式验收证据还包括账号注销、退款与对账、iOS/Android/小程序真机、服务履约和商店审核。教程帮助完成配置与验证，不提供平台自动放行保证。

## 6. 提供自己的经营信息与隐私条款

后台填写真实经营主体、客服联系方式、隐私说明与服务条款，再从公开 `/club` 数据生成可公开访问的页面。在仓库根目录执行 `node scripts/export-policies.mjs https://api.example.com/api/v1 ./policies`，将输出的 `privacy.html` 和 `terms.html` 部署到自己的 HTTPS 网站，填入商店与微信后台。生成页面不会代写或保证内容准确；俱乐部需按实际 SDK、数据用途、保存期限和服务履约规则填写。原生正式模式在这些必需内容为空时拒绝继续登录/预约/付款。
