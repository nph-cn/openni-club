# 官方资料与核验边界

最后核查日期：2026-11-15。以下链接用于核实外部平台要求；仓库实现状态以代码和测试为准。平台界面、政策和费用会变化，发布时重新查看。

| 资料 | 用途 | 本次核查 |
| --- | --- | --- |
| [Flutter 安装](https://docs.flutter.dev/install) | 工具链安装 | 官方入口 |
| [Flutter iOS 发布](https://docs.flutter.dev/deployment/ios) | 签名、IPA、上传流程 | 已读取 |
| [Flutter Android 发布](https://docs.flutter.dev/deployment/android) | applicationId、签名、AAB/APK | 已读取 |
| [Apple 审核指南](https://developer.apple.com/app-store/review/guidelines/) | 隐私、账号删除、用户内容、支付 | 已读取 |
| [Apple 审核准备](https://developer.apple.com/app-store/review/) | 审核账号、链接和素材授权 | 已读取 |
| [Google Play 新个人账号测试](https://support.google.com/googleplay/android-developer/answer/14151465) | 封闭测试和正式发布权限 | 已读取 |
| [Cloudflare Full setup](https://developers.cloudflare.com/dns/zone-setups/full-setup/setup/) | 已注册域名接入、NS 与原 DNS 记录 | 已读取 |
| [微信公众平台](https://mp.weixin.qq.com/) | 主体、类目、备案、版本与审核 | 需账号所有者按当前后台核验 |
| [微信小程序网络](https://developers.weixin.qq.com/miniprogram/dev/framework/ability/network.html) | HTTPS 和合法域名 | 自动工具未能读取；发布前查当前页面/后台 |
| [微信开发者工具](https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html) | 下载工具 | 官方入口，需人工打开 |
| [微信支付官方 Go SDK](https://github.com/wechatpay-apiv3/wechatpay-go) | 请求/响应签名、支付通知验签与 AES-GCM | 已读取官方源码；本仓库独立 Node 实现，非该 SDK 的移植分发 |
| [官方 JSAPI 调起签名](https://github.com/wechatpay-apiv3/wechatpay-go/blob/main/services/payments/jsapi/api_jsapi_request_payment.go) | JSAPI 支付参数签名格式 | 已读取 |
| [官方 APP 调起签名](https://github.com/wechatpay-apiv3/wechatpay-go/blob/main/services/payments/app/api_app_request_payment.go) | 原生支付参数签名格式 | 已读取 |
| [微信 code2session](https://developers.weixin.qq.com/miniprogram/dev/OpenApiDoc/user-login/code2Session.html) | 小程序身份交换 | 自动工具未能读取；上线前核对官方当前要求 |
| [微信开放平台移动登录](https://developers.weixin.qq.com/doc/oplatform/Mobile_App/WeChat_Login/Development_Guide.html) | 原生 OAuth 身份交换 | 自动工具未能读取；上线前核对官方当前要求 |
| [微信支付](https://pay.weixin.qq.com/) | 商户及支付产品准入 | 需自有商户账号核实 |
| [官方退款 API 源码](https://github.com/wechatpay-apiv3/wechatpay-go/blob/main/services/refunddomestic/api_refunds.go) | 退款创建与查询路径、参数 | 已读取官方原始源码 |
| [Caddy 自动 HTTPS](https://caddyserver.com/docs/automatic-https) | DNS、80/443、证书签发与续期 | 已读取 |
| [Docker Compose 服务配置](https://docs.docker.com/reference/compose-file/services/) | env_file、网络、持久化与服务依赖 | 已读取 |
| [支付宝开放平台](https://open.alipay.com/) | 商户、应用与产品签约 | 本版本未集成；发布前核实对应产品 |
| [工信部备案系统](https://beian.miit.gov.cn/) | 域名/APP 备案事项 | 需结合主体、服务器和平台当前规则核验 |

教程没有保证 `.im` 满足中国大陆备案或微信小程序所有准入要求，也没有保证某种陪玩/游戏相关服务适用外部支付。需要结合实际服务、地区、主体和商店规则作判断。

## 输入与无障碍动效

- [Flutter 验证码自动填充](https://api.flutter.dev/flutter/services/AutofillHints/oneTimeCode-constant.html)：统一提示映射到 iOS、Android 和 Web。
- [Flutter Reduce Motion](https://api.flutter.dev/flutter/widgets/MediaQueryData/reduceMotion.html)：iOS 减弱动态效果需由自定义动画显式读取。
- [Flutter Disable Animations](https://api.flutter.dev/flutter/widgets/MediaQueryData/disableAnimations.html)：Android 移除动画与 iOS Reduce Motion 分开处理。
