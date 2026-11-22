# OpenNI 文档

OpenNI 是一套 MIT 开源的电竞俱乐部应用，包含 Flutter App、微信小程序、运营后台和订单 API。这份文档从获取代码开始，逐步完成品牌配置、服务部署和应用发布。

## 第一次使用

按下面的顺序操作。每完成一步，再进入下一步。

1. [本地启动](01-quickstart.md)：安装工具，在电脑上打开 App 并提交一笔测试订单。
2. [品牌与资料](02-brand-and-config.md)：准备俱乐部名称、Logo、客服和经营资料。
3. [生成应用配置](10-single-config-workflow.md)：用同一份配置生成 App、小程序、图标和应用标识。
4. [域名与服务器](03-deployment.md)：部署 API、设置 HTTPS，并让客户端连接自己的服务器。
5. [微信登录与支付](09-wechat-adapters.md)：接入自己的账号与商户，在设备上完成联调。
6. [手机号与验证码](11-phone-auth.md)：按需接入腾讯云短信，验证登录与账号关联。
7. [上线检查](07-release-checklist.md)：核对签名、真机、支付与资料，再提交平台审核。

只想先查看界面，可以打开 [App](https://openni.im/demo/)、[运营后台](https://openni.im/admin/) 或 [品牌配置](https://openni.im/studio/)。这些公开页面使用示例数据，不处理真实付款。

## 需要准备什么

| 阶段 | 必需材料 |
| --- | --- |
| 本地运行 | 电脑、Node.js 24、Flutter stable、Chrome |
| 更换品牌 | 俱乐部名称、自己的 Logo |
| 服务器部署 | 域名、支持 Node.js 24 和持久化磁盘的服务器 |
| 微信登录与支付 | 对应平台的 AppID、服务端密钥；收款还需自己的微信商户配置 |
| 手机号登录 | 腾讯云短信应用、已审核签名和验证码模板、服务端密钥 |
| Android 发布 | 固定包名、上传签名、目标商店账号 |
| iOS 发布 | macOS、Xcode、Apple 开发者账号和签名 |
| 小程序发布 | 微信小程序账号、开发者工具、合法服务器域名 |

名称和 Logo 足够生成本地品牌预览。正式发布所需的账号、签名和审核由各俱乐部持有并完成。

## 项目由哪些部分组成

| 部分 | 仓库位置 | 用途 |
| --- | --- | --- |
| App | `apps/mobile/` | iOS、Android 共用的 Flutter 工程 |
| 小程序 | `apps/miniprogram/` | 微信原生小程序 |
| 运营后台 | `apps/admin/` | 服务目录、成员、派单、售后和结算记录 |
| API | `services/api/` | 保存俱乐部、订单、排班和账本数据 |
| 品牌配置 | `config/` | 公开的名称、Logo、平台身份和地址 |
| 教学 Skill | `skills/openni-launch/` | 让 AI 按项目实际状态协助部署 |

每家俱乐部独立部署，数据库和第三方账号由自己管理。App 与小程序共用 API，小程序不是 Flutter 的构建产物。

## 遇到问题

产品流程与界面的设计依据见[俱乐部经营闭环](product/01-club-operations.md)、[服务目录研究](product/02-market-reality.md)和[手机竞品流程走查](product/03-mobile-competitor-walkthrough.md)。

先查看对应页面的操作结果和常见错误，再检查 [功能与版本状态](00-status.md)。需要 AI 协助时，使用 [教学 Skill](08-use-the-skill.md)，让它读取仓库并检查当前配置。

代码、构建或文档问题可在 [GitHub Issues](https://github.com/nph-cn/openni-club/issues) 提交。附上操作步骤和错误信息即可，不要附上密钥、管理员令牌或客户资料。
