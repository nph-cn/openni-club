# OpenNI Club

让电竞俱乐部拥有自己的产品、品牌和数据。

一套 MIT 开源的独立俱乐部软件：Flutter iOS / Android、原生微信小程序、订单与履约 API、运营工作台、品牌向导，以及按完整流程浏览真实界面的截图网站。每家俱乐部拥有自己的品牌、服务和数据库。演示俱乐部「北岸电竞」、人物与价格均为虚构；本项目不隶属游戏发行商。

**当前为 v0.2 预览版本。** 单配置品牌生成、客户下单、运营派单、成员接单与交付、争议、分成账本已实现；包含 22 张 Flutter、15 张原生小程序和 11 张运营后台真实界面截图。微信登录、支付和退款协议适配已有模拟供应商及密码学校验测试，真实商户交易、原生真机和商店审核尚未完成。支付默认关闭，手工结算记录不等于平台自动转账。

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

运行 API 测试：`node --test services/api/test/*.test.mjs`，支付适配测试：`node --test services/integrations/test/*.test.mjs`。在 `apps/mobile` 运行 `flutter analyze`、`flutter test test/flows_test.dart` 和 `flutter build web`。生成页面截图使用 `flutter test test/screenshots_test.dart --update-goldens`。CI 只做检查，不会自动发布应用或使用你的生产密钥。

品牌生成与发布状态测试：`node --test scripts/test/*.test.mjs`。仓库展示使用 `config/demo.club.json` 的虚构北岸品牌；`club.example.json` 保留为最简客户模板。自己的公开配置与秘密配置必须分开保存。

项目代码和自编文档采用 [MIT](LICENSE)，可商用和修改，分发时保留版权与许可文本。第三方字体、依赖保留各自许可证；MIT 不授予游戏商标、肖像或第三方素材的权利。详见 [贡献说明](CONTRIBUTING.md) 和 [安全说明](SECURITY.md)。
