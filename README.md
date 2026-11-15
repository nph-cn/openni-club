# OpenNI Club

Flutter App、微信小程序和运营后台。

一套 MIT 开源的独立俱乐部软件：Flutter iOS / Android、原生微信小程序、订单与履约 API、运营工作台、品牌向导，以及按完整流程浏览真实界面的截图网站。每家俱乐部拥有自己的品牌、服务和数据库。演示俱乐部「北岸电竞」、人物与价格均为虚构；本项目不隶属游戏发行商。

**当前为 v0.2 预览版本。** 单配置品牌生成、客户下单、运营派单、成员接单与交付、争议、分成账本已实现；图库包含 Flutter、小程序、运营后台，以及登录、验证码、骨架加载、错误和空状态的实际运行截图。微信和腾讯云短信登录、支付及退款适配已有自动化测试，真实短信送达、商户交易、真机与商店审核尚未完成。生产短信和支付默认关闭。

## 最近验收 · 2026-11-16

- App 预览增加 iPhone 时间、灵动岛和手势条，Cupertino 导航图标、搜索框、分组设置与玻璃弹层统一；设备外观仅用于预览，真机继续使用系统状态栏。玻璃材质由 Flutter 绘制，不是系统原生 Apple Liquid Glass。
- 官网按实际查看过的 Mobbin 公开官网重排：白底、大尺寸完整截图、轻标签、角色多屏预览及完整流程浏览。App 图库扩展为 64 张 780×1688 运行截图，包含 28 个真实交互状态；另保留 12 张后台 JPG 和 24 张上一版小程序图，全站共 100 张。小程序截图尚未同步最新 UI。
- `/delta/` 新增参考 KPR 构图与滚动叙事的三角洲专题：官方高清场景与人物分层、模式和地图切换、可控制的视频、App 预约入口。素材逐项记录出处，不属于代码的 MIT 授权；该页为非官方设计预览。
- 找服务与找陪练支持独立搜索和筛选；关注入口可点击；预约保留服务、规格和陪练，支持当天未过期的时段；接口订单再次预约保留原规格。当前代码的本机测试与浏览器验收结果详见下方记录。上一提交的 Android debug、iOS 未签名构建已成功，不代表这次代码已完成真机验收。
- 本轮新增成员订单状态分组、冻结规格展示、交付/评价结果、通知日期与未读状态；小满与 North 的示例头像已补全。新增回归发现并修复弹层退场时输入控制器过早释放的问题。最终测试及浏览器证据见下方验收记录。

详见[功能与上线状态](docs/00-status.md)、[功能回归记录](docs/qa/2026-11-16-api-integration-review.md)和[最新官网与 App 验收记录](docs/qa/2026-11-16-gallery-delta-review.md)。

## 先做成自己的俱乐部

1. 在品牌向导填写名称、上传 Logo，下载配置包；或从 [最简配置](config/club.example.json) 开始。
2. 将 `club.json` 和 `assets/` 放进仓库 `config/`；秘密文件 `server.env` 单独保管，放到服务端 `.env`，不能放进客户端或公开网站。
3. 在仓库根目录生成三端品牌：

```sh
npm install
node scripts/configure-club.mjs --check config/club.json
node scripts/configure-club.mjs --plan config/club.json
node scripts/configure-club.mjs --apply config/club.json
```

名称、Logo、主题、原生图标、包标识与政策页由同一公开配置生成，不需要改 Dart/JavaScript。名称和 Logo 足够预览；正式发布再补真实经营信息、公开 AppID、应用标识及独立服务端密钥。真实账户资质、签名、真机和平台审核仍需逐项核验。[完整操作教程](docs/10-single-config-workflow.md)

## 从这里开始

| 想做什么 | 阅读 |
| --- | --- |
| 完全不懂技术，先跑起来 | [零基础本地启动](docs/01-quickstart.md) |
| 看清这一版能做什么 | [功能与上线状态](docs/00-status.md) |
| 换成自己的俱乐部 | [品牌与配置](docs/02-brand-and-config.md) |
| 名称+Logo 生成三端，实际构建 | [单配置工作流](docs/10-single-config-workflow.md) |
| 域名接 Cloudflare / 发布 API | [域名与服务器部署](docs/03-deployment.md) |
| 苹果、安卓和微信上架 | [移动端发布](docs/04-mobile-release.md)、[小程序发布](docs/05-wechat-release.md) |
| 理清账号、密钥、支付 | [第三方集成](docs/06-integrations.md) |
| 配置已实现的微信接口 | [微信登录与支付接入](docs/09-wechat-adapters.md) |
| 上线前逐项验收 | [发布验收](docs/07-release-checklist.md) |
| 请 AI 带着做 | [Skill 使用教程](docs/08-use-the-skill.md)、[OpenNI Launch Skill](skills/openni-launch/SKILL.md) |

## 最短本地路径

安装 Node.js 24 LTS 和 Flutter stable；先运行 `flutter doctor`。在仓库根目录：

```sh
cp .env.example .env
node scripts/doctor.mjs
node --env-file=.env services/api/src/server.mjs
```

另开一个终端：

```sh
cd apps/mobile
flutter pub get
flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://localhost:8787/api/v1
```

未配置 `API_BASE_URL` 的 Flutter App 使用本地演示数据。连接 API 后，各客户端的数据保存在同一台服务器的 SQLite 数据库中；两种模式不能混为真实线上业务。详细步骤与常见错误见启动教程。

## 目录

```text
apps/mobile/         Flutter App、测试和真实界面截图
apps/miniprogram/    微信原生小程序
apps/showcase/       截图目录与项目网站
apps/admin/          订单运营后台
services/api/        单俱乐部 Node.js + SQLite API
services/integrations/ 微信身份和支付签名/验签适配器
config/              品牌资料模板
generated/club/      公开品牌、首启目录、政策与校验清单
docs/                中文部署和发布教程
skills/openni-launch/可复用的 AI 部署教学 Skill
scripts/doctor.mjs   不输出密钥的环境检查
```

每个俱乐部独立部署一套服务和数据库。当前没有多租户市场、储值钱包、自动代付或游戏厂商 API；价格由服务器确定，分成账本与实际转账分开记录。API 约定见 [CONTRACT.md](CONTRACT.md)。

## 开发与许可

运行 API 测试：`node --test services/api/test/*.test.mjs`，支付适配测试：`node --test services/integrations/test/*.test.mjs`。在 `apps/mobile` 运行 `flutter analyze`、`flutter test` 和 `flutter build web --base-href /demo/ --no-web-resources-cdn`。更新完整截图使用 `flutter test test/review_screens_test.dart test/screenshots_test.dart test/auth_screens_test.dart test/journey_screens_test.dart --update-goldens`，逐张检查新图后再提交。CI 只做检查，不会自动发布应用或使用你的生产密钥。

品牌生成与发布状态测试：`node --test scripts/test/*.test.mjs`。仓库展示使用 `config/demo.club.json` 的虚构北岸品牌；`club.example.json` 保留为最简客户模板。自己的公开配置与秘密配置必须分开保存。

项目代码和自编文档采用 [MIT](LICENSE)，可商用和修改，分发时保留版权与许可文本。第三方字体、依赖保留各自许可证；MIT 不授予游戏商标、肖像或第三方素材的权利。官方游戏图的来源、授权边界与替换方法见 [游戏媒体说明](third_party/GAME_MEDIA.md)，这些图片不适用 MIT。详见 [贡献说明](CONTRIBUTING.md) 和 [安全说明](SECURITY.md)。
