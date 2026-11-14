# OpenNI API

Node.js 22.13+（推荐 24 LTS），内置 SQLite，无 npm 运行时依赖。每个俱乐部独立部署。基础接口见根目录 CONTRACT.md，v0.2 运营接口的实际字段见 [OPERATIONS.md](OPERATIONS.md)。

```sh
cd services/api
cp .env.example .env
# 填写自己的配置后：
node --env-file=.env src/server.mjs
npm test
```

默认只绑定本机 8787。数据库保存在 DATA_DIR；会话令牌只保存 SHA-256 哈希，24 小时过期。ADMIN_TOKEN 必须至少 24 字符，仅字母、数字、下划线及连字符，可用示例中的 base64url 生成命令。管理员令牌不得放进客户端。

## 已实现

- 公开俱乐部、服务、成员、公告；SQLite 内容持久化、管理员 CRUD、金额校验、归档与审计。
- 演示匿名登录；生产小程序微信登录和原生 APP 微信 OAuth code 交换。各 AppID 的 OpenID 隔离，只返回本系统会话，微信密钥、session_key 和 OAuth token 不下发客户端。
- 自己的预约、服务器计价、幂等提交、状态流转、取消；历史服务标题和价格独立保存。
- 微信 JSAPI / APP 预支付；签名验证的支付查询；RSA 验签、AES-GCM 解密回调；金额、交易单、应用与付款人核对。
- 管理员全额退款、签名验证的退款查询及退款回调；重试沿用同一退款单号，重复通知不回退已结算状态。
- DELETE /api/v1/account：拒绝未结预约及待确认款项，撤销全部会话、移除微信身份映射、清空历史订单联系方式及备注，保留匿名业务和财务记录。
- 成员邀请绑定、可接时段、派单防冲突、接单/拒单/履约/交付、客户确认与争议、站内通知。
- 逐单冻结价格和抽成，争议/退款冻结收益；人工结算凭据、幂等账本、CSV 导出。系统不自动转账。

## 模式与真实交易

API_MODE=demo：模拟预约不会收款，demo=true、paymentStatus=unpaid。生产环境拒绝演示登录与遗留演示会话。

API_MODE=production：登录、下单和付款还要求品牌配置 demoData=false，并填写 legalEntity、supportContact、privacyText、termsText。示例条款必须替换为自己的正式文本。这些检查只证明配置存在，不等于法律或平台审核通过。

小程序身份使用 WECHAT_APP_ID / WECHAT_APP_SECRET，原生 APP 使用 WECHAT_NATIVE_APP_ID / WECHAT_NATIVE_APP_SECRET。两套支付分别通过 WECHAT_PAY_ENABLED=true、WECHAT_NATIVE_PAY_ENABLED=true 开启，默认关闭，共用商户签名配置。只配置某一渠道即可使用该渠道。

商户私钥和可信微信平台公钥/证书通过服务器文件路径读取，不上传仓库。平台 key ID/序列号必须与受信 PEM 对应。支付回调分别配置到：

- JSAPI：/api/v1/payments/wechat/notify
- APP：/api/v1/payments/wechat-app/notify
- JSAPI 退款：/api/v1/payments/wechat/refund-notify
- APP 退款：/api/v1/payments/wechat-app/refund-notify

退款分别使用 WECHAT_PAY_REFUND_NOTIFY_URL / WECHAT_NATIVE_PAY_REFUND_NOTIFY_URL。缺少退款地址时拒绝发起退款。所有通知 URL 使用公网 HTTPS。

客户端支付 SDK 返回成功不代表已到账，只读取服务器 paymentStatus。发起支付后遇到网络错误保持 pending，由商户查询核实。取消 pending 订单先签名查询，若 NOTPAY 则关单并再次查询；仅确认 CLOSED 后才本地取消，若已付则转入退款流程。管理员 POST /admin/orders/:id/payment-sync 查询支付或已有退款；POST /admin/orders/:id/refund {reason} 发起全额退款。退款成功标记 refunded 并取消订单，PROCESSING/ABNORMAL 保持 refund_pending。退款 CLOSED 后可重新申请，生成新的退款单号。

## 单一品牌配置

默认读取仓库 generated/club/public.json，CLUB_CONFIG_PATH 可指定路径。文件存在时品牌、主体和政策以该文件为准，GET /club 返回 configManaged=true 和 configHash，后台修改这些字段返回 409 BRAND_MANAGED_BY_CONFIG。通过品牌生成器重新应用后重启 API；不能在后台另存冲突品牌。

CLUB_SEED_PATH 默认 generated/club/seed.json，仅在数据库第一次初始化时导入服务、成员、公告。以后品牌更新不会覆盖运营目录。GET /brand/logo.png 提供品牌文件同目录的 logo.png。自动测试可显式将两个路径设为 none 使用隔离种子；生产应挂载生成目录。

## 部署

从仓库根目录构建：`docker build -f services/api/Dockerfile -t openni-api .`。必须持久挂载 /app/data；服务器 PEM 文件只读挂载。Dockerfile 同时包含 services/integrations。

使用 HTTPS 反向代理。CORS_ORIGINS 是逗号分隔的精确来源，生产要求 HTTPS，不接受通配符或路径。微信原生请求没有 Origin，仍需有效会话。

下单和支付限流按认证用户（每分钟 60 次），后台结算按管理员。未认证登录按直接连接 IP 限流；在反向代理后可能共享此额度，应在边缘添加真实来源限流并按规模调整。API 不信任任意 X-Forwarded-For。

备份 SQLite 数据目录，恢复或迁移前停止写入；保护其中的联系方式，制定保留期限与访问流程。生产上线仍需真实主体、资质、商户进件、密钥配置、平台审核、真机联调、小额付款/退款/对账验收。当前测试使用本地签名夹具，没有进行真实微信交易。部分退款、自动分账打款、账单自动对账、附件托管和后台员工分级权限尚未实现。
