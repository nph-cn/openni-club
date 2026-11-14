# OpenNI Club — Flutter App

MIT 白标电竞俱乐部 App，iOS、Android 与 Web 预览共用业务代码。当前验证环境为 **Flutter 3.50.0 stable / Dart 3.14.0**，framework `ab2912035e`、engine `371f77202a`。此版本使用 Flutter 提取后的 `material_ui` 包。

## 配置与运行

从仓库根目录按部署指南配置 `config/club.example.json`，再执行配置生成器。`assets/brand.json` 与 `assets/catalog.json`、Logo、原生图标、Android applicationId、iOS Bundle ID、版本号和微信公开配置均为生成产物，不要手改。`config/demo.club.json` 是北岸电竞的虚构演示配置；真实经营者目录来自自己的配置与 API。

```sh
flutter pub get
flutter run -d chrome
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8787/api/v1
```

不配置 API 时，客户可浏览和创建本机模拟预约；已有订单与成员账本来自真实 API 演示流程导出的 fixture。成员接单、排班保存、交付、确认、售后和结算需连接 API，离线不会显示写入成功。远程 API 失败会显示错误，不回退虚构数据。Android 模拟器访问宿主机使用 `10.0.2.2`；真机用可访问的 LAN 地址或 HTTPS，正式构建必须 HTTPS。

## 支持的业务

- 客户：游戏/服务筛选、陪练档案、关注、服务规格、可约时段、预约核对、订单事件、微信付款、取消、交付确认、评价、售后和通知。
- 成员：邀请码绑定、待接单、拒单、开始服务、提交文字/HTTPS凭证、可接时段、收入账本、运营登记的结算凭据。
- 价格与时长由服务器按 `serviceId + variantId` 决定。120分钟72元表示套餐总价。客户端不发送价格、佣金或身份权限。当前只支持一位成员履约；多人规格明确禁用并由服务器拒绝。
- 个人中心：微信登录授权、昵称、实际运营政策与客服、二次确认注销。未结订单和退款由服务器阻止注销。

## 原生微信

通过 [fluwx 6.0.6](https://github.com/OpenFlutter/fluwx) 接入开放平台移动应用登录与 APP 支付。App Secret、证书、API v3 密钥只放后端。小程序 App ID 不能替代移动应用 App ID。

```sh
flutter run -d YOUR_DEVICE_ID \
  --dart-define=APP_MODE=production \
  --dart-define=API_BASE_URL=https://api.your-club.example/api/v1
```

公开微信 App ID 和 Universal Link 默认由生成配置读取。iOS 的 `Brand.generated.xcconfig` 已接入 URL scheme 与条件 Associated Domains；经营者需配置自己的签名团队、描述文件和域名 AASA。Android 内部 namespace 与 MainActivity 包名保持稳定，生成 applicationId 即可；在微信开放平台登记真实包名与签名 MD5。release 只读取经营者的 `android/key.properties`，不会用 debug 密钥签正式包。

正式模式要求 HTTPS、`club.demoData=false`、隐私政策、服务条款与客服信息完整。缺少配置时登录/预约/支付关闭并展示原因。登录向 `/auth/wechat-app` 交换临时 code；session 仅在内存，重启需要登录。支付 SDK 返回后重新 GET 订单，以服务端验证的付款结果为准。Web 不支持原生微信操作。

**未完成的外部验证：** 经营者真实微信账号/商户、iOS签名与Universal Link、Android签名回调、真机付款和商店审核。当前没有声称完成这些验证。本机 Android 编译曾因 NDK 下载与磁盘空间阻断；iOS 未完成原生编译。CI 原生构建结果应独立核对。

## 视觉与截图

iOS 与 Web 使用 Flutter `BackdropFilter` 形成玻璃导航/底栏/Sheet；内容保持清楚的实体排版。这不是系统原生 Liquid Glass。Android 使用实体导航。iOS Reduce Transparency 通过平台通道读取，高对比与减少动画也会关闭模糊。

```sh
flutter analyze
flutter test test/flows_test.dart test/production_test.dart test/v2_test.dart
flutter test test/screenshots_test.dart test/review_screens_test.dart
flutter build web --no-web-resources-cdn --base-href /demo/
```

22张390×844实际Widget截图和角色/流程索引在 `screenshots/`。所有截图均使用本地字体与素材，不依赖远程图片；原始图像/fixture说明见 `assets/demo/PROVENANCE.md`。仅在有意修改设计且逐张检查后，使用 `--update-goldens` 更新。跨 Flutter engine 的像素差异不能当作业务失败，也不能自动覆盖基线。

`?screen=` 支持 `screenshots/manifest.json` 的全部 id，包括 `home`、`service_120`、`checkout`、`support`、`member`、`delivery`、`availability`、`earnings`。实际路由使用 GoRouter，支持原生返回和深链。

Studio 的 `previewName`、`previewColor`、同源 `blob:` Logo 只覆盖演示展示，不能改变 API、生产身份或权限。生产模式忽略所有预览覆盖。

Noto Sans SC 使用 OFL，第三方库保留各自许可证。外部竞品截图仅用于设计研究，不打包分发。
