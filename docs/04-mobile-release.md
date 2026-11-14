# Flutter：从测试设备到应用商店

同一 Flutter 工程生成 iOS 与 Android，但签名、发布账号和审核分别完成。先处理 [发布阻断项](07-release-checklist.md)，再做正式打包。真实微信能力需使用自己的开放平台移动应用、签名和商户配置，见 [微信接入教程](09-wechat-adapters.md)。

优先使用 [单配置工作流](10-single-config-workflow.md) 的 `release-club`，它自动传入公开微信 AppID、Universal Link、版本与 API 参数。下面的原始 Flutter 命令供开发者排错时参考；直接运行时需带同样公开参数。AppSecret 不进入任何客户端构建参数。

## 原生编译验证记录

2026-11-15，[原生 CI 运行 43649484983](https://github.com/nph-cn/openni-club/actions/runs/43649484983) 已完整通过，验证提交为 [`198cb97`](https://github.com/nph-cn/openni-club/commit/198cb9725500ac9d4005baa68d1fdc8ce86e4b4c)。使用 Flutter 3.50.0 stable / Dart 3.14.0；两个独立 runner 均执行了配置生成、包名与配置指纹检查，再进行实际原生编译。

| 平台 | Runner / 命令 | 结果与 CI 产物 |
| --- | --- | --- |
| Android | Ubuntu 24.04；`flutter build apk --debug --dart-define=APP_MODE=demo` | 通过；调试 APK、编译日志、工具链和配置身份记录 |
| iOS | macOS 26、Xcode 26.6；`flutter build ios --release --no-codesign --dart-define=APP_MODE=demo` | 通过；未签名 `Runner.app` 压缩包、编译日志、工具链和配置身份记录 |

本次配置使用虚构北岸电竞，双端应用标识为 `club.openni.c5ccdaffc95`，版本 `0.2.0`、构建号 `2`，模式为 demo、API 地址为空。生成器配置指纹为 `e08f5c8bc37108bfcc0ec4445662e5530a12c5e33afb72215b00733d1ae9d980`。产物只保存在上述运行的 Actions Artifacts，保留 7 天；可手动运行 [Compile native apps](https://github.com/nph-cn/openni-club/actions/workflows/native.yml) 重新编译。

这次验证证明原生工程能够编译，**不代表真机验收、经营者签名、真实微信收退款或商店审核通过**。CI 不读取商户/开发者密钥，不上传商店，不创建原生发布版本。iOS 未签名产物不能直接交付安装；Android 调试包也不是商店发行包。

## Android

1. 安装 Android Studio / Android SDK，运行 `flutter doctor` 和 SDK 许可检查。
2. 在俱乐部 JSON 的 `distribution.androidApplicationId` 设置自己的反向域名标识，运行生成器。显示名、图标与版本随配置生成；内部 Kotlin namespace 不必为换品牌手改。
3. 在 Android Studio 创建或选择自己的上传密钥。密钥库文件、密码、`android/key.properties` 不进入 Git；备份到密码管理器或安全离线存储。
4. 本工程已接入 release signing；填写私密 `android/key.properties` 后构建。没有自己的上传签名时正式预检会阻断，不回退为 debug key。签名背景见 [Flutter Android 发布指南](https://docs.flutter.dev/deployment/android)。
5. 在 `apps/mobile` 构建：

```sh
flutter pub get
flutter analyze
flutter test test/flows_test.dart
flutter build appbundle --release --dart-define=APP_MODE=production --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

Google Play 常用产物位于 `build/app/outputs/bundle/release/`。其他 Android 商店可能要求签名 APK，可用 `flutter build apk --release` 并带同样 API 配置，具体按目标商店要求。每次发布递增版本/构建号。

6. 真机安装验收网络失败、登录、创建/取消订单、返回导航、字体放大和隐私入口。签名证书和 applicationId 后续更新必须兼容原版本。
7. 在目标商店创建应用，填写真实运营主体、服务范围、隐私和数据安全信息、截图与审核账号，再走测试轨道。

Google Play 对部分新个人开发者账号有封闭测试要求；当前官方说明为至少 12 名连续加入测试 14 天的测试者，达到后才能申请正式发布权限，不能把它当作自动通过保证。[Google Play 官方说明](https://support.google.com/googleplay/android-developer/answer/14151465)

## iOS

1. 在 macOS 上安装受支持的 Xcode 并完成首次组件安装。运行 `flutter doctor`。
2. 用自己的 Apple Developer 团队创建 App Store Connect 应用。俱乐部 JSON 的 `distribution.iosBundleId` 与 `appleTeamId` 由生成器写入工程；在 Xcode 登录对应账号并确认签名身份，不手动覆盖生成的 Bundle ID。
3. 确认显示名、应用图标、版本、所需权限说明；只申请当前功能使用的权限。
4. 在 `apps/mobile` 构建：

```sh
flutter build ipa --release --dart-define=APP_MODE=production --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

归档在 `build/ios/archive/`，导出包在 `build/ios/ipa/`；可通过 Xcode Organizer 或 Transporter 上传到 App Store Connect。`--no-codesign` 的构建用于编译检查，不是可直接交付用户的签名安装包。[Flutter iOS 发布指南](https://docs.flutter.dev/deployment/ios)

5. 先上 TestFlight，在真机验收。每次上传使用新的构建号。
6. 提交前准备可用的审核账号、完整服务说明、客服和隐私链接；后端在审核期间保持可访问。不要让审核员看到打不开的网站或占位内容。[Apple 审核说明](https://developer.apple.com/app-store/review/)

## 与俱乐部业务有关的审核点

提供用户账号时实现账号删除；开放发帖/评论/聊天时实现举报、屏蔽和内容处理。隐私说明必须与代码、SDK 和实际数据流一致。收费的游戏相关服务如何分类、是否适用应用内购买，应按真实履约方式核实 Apple / Google 的最新规则，不能仅因为用了微信支付 SDK 就认定合规。[Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

项目使用 MIT 不代表任意俱乐部模板都会自动通过审核。发布应提供该俱乐部独有的内容、运营和服务价值；游戏官方标志、角色图和真人头像要有使用依据。
