# 一个配置包，生成自己的俱乐部

先准备名称和一张自己的 Logo；不必打开 Dart、JavaScript、Gradle 或 Xcode 源码改品牌。生成器负责把同一配置应用到 Flutter、微信小程序、后端品牌、原生图标和政策页面。真正的上架仍需要你的发布账号、签名、经营资质和审核结果。

## 第一步：准备配置包

网页品牌向导可以导出 `club.json` 与 `assets/brand/logo.png`。也可以复制仓库 `config/club.example.json`，把自己的 Logo 放进同目录下 `assets/brand/`，修改两个必需字段：

```json
{
  "schemaVersion": 1,
  "brand": {
    "name": "银河电竞",
    "logo": "assets/brand/logo.png"
  }
}
```

Logo 路径相对这份 JSON。支持 PNG、JPEG、WebP、SVG，最大5MB；正式图标原图短边至少512像素，推荐1024像素。SVG 不得引用外部文件或包含脚本。图标按比例缩放并留出安全边距，不重画、不拉伸；iOS 图标生成不透明背景，可用 `brand.iconBackground` 指定背景色。

`brand.primaryColor` 是六位十六进制色值。省略时采用默认主题；`shortName`、介绍和标语都可选。预览模式自动提供明确标记为示例的服务与成员。所有字段见 [Schema](../config/club.schema.json)。

## 第二步：检查、看差异、生成

在仓库根目录安装依赖，假设配置包放在 `config/club.json`：

```sh
npm install
node scripts/configure-club.mjs --check config/club.json
node scripts/configure-club.mjs --plan config/club.json
node scripts/configure-club.mjs --apply config/club.json
```

`--check` 校验资料和 Logo；`--plan` 列出将创建、更新或保持不变的文件，不写入；`--apply` 先暂存全部内容，再提交，普通文件错误会回滚。不会删除或改写用户、订单数据库。输出文件由配置生成，不要手工编辑，否则发布时 hash 检查会阻断。

主要产物：`generated/club/public.json` 是公开运行配置，`seed.json` 只供首次初始化，`manifest.json` 记录配置及文件 hash；Flutter 的 `assets/brand.json` 与小程序 `utils/brand.generated.js` 使用同一品牌。Flutter `assets/catalog.json` 保存同一配置的服务、成员和公告供离线预览，连接后端后读取 API 目录。Android/iOS 的显示名、包标识、版本和图标也一并生成。

生成不是跨整个文件系统的一条原子指令。若电脑断电或进程被强制终止，可能留下 `generated/.configure.lock` 和 `.configure-*` 暂存/备份目录。先确认没有生成进程并检查备份，再恢复或重新生成；不能靠忽略 manifest 检查发布混合版本。

## 第三步：运行品牌预览

```sh
cd apps/mobile
flutter pub get
flutter run -d chrome
```

Flutter 默认读取生成配置；不设置 API 地址时可以看内置演示。小程序用微信开发者工具导入 `apps/miniprogram`，生成的 AppID 为空时是工具允许的游客预览。连接 API 需要可达的后端地址；手机上的 localhost 不是电脑。

将 `endpoints.apiBaseUrl` 填为自己的 API 地址并重新生成。API 读取 `generated/club/public.json` 的品牌，首次数据库读取 seed；日常目录和订单在数据库。品牌配置不会每次启动重置运营数据。详见 [服务器部署](03-deployment.md)。

## 第四步：集中补齐正式配置

正式配置至少需要 `operator.legalEntity`、`operator.supportContact`、`legal.privacyText`、`legal.termsText`、HTTPS API/网站地址，以及固定的 `distribution.clubId`。不同平台再补自己的 Android applicationId、iOS Bundle ID/Apple Team ID、微信小程序或移动应用 AppID、Universal Link。

服务器秘密放在独立 `.env` 或托管平台秘密配置，不放在 `club.json`。生成器拒绝包含 secret、token、password、privateKey 等秘密字段的公开配置。AppSecret、商户私钥、API v3 Key 不会传给 Flutter 编译进程。微信接入步骤见 [微信教程](09-wechat-adapters.md)。

正式服务端配置使用 `API_MODE=production`、强随机管理员令牌和精确 HTTPS CORS 来源；浏览器向导初始导出的 `API_MODE=demo` 需要在准备好正式环境后调整。发布预检会指出这项，不能把正式客户端连到演示身份服务。

```sh
node scripts/configure-club.mjs --check config/club.json --mode production
node scripts/configure-club.mjs --apply config/club.json --mode production
```

正式生成不会自动创建虚构收费服务或成员；已有数据库保留，首次安装可用 `initialCatalog` 或后台填写真实目录。换品牌不能自动改变已发布应用身份；商店更新必须沿用原包标识和签名。

## 第五步：用真实工具链构建

先看计划，不执行工具：

```sh
node scripts/release-club.mjs --config config/club.json --platform android --mode production --env .env --plan
```

去掉 `--plan` 后，脚本核对生成文件 hash，依次运行 Flutter 依赖、分析、流程测试与实际构建。Android 正式生成 AAB，要求自己的 `key.properties` 和上传密钥；iOS 正式生成 IPA，要求 macOS/Xcode、自己的开发者团队和有效签名。预览 Android 使用 debug APK，预览 iOS 编译不签名，不是可上架包。

`--platform web --mode preview` 可以验证完整的 Web 预览构建。放在网站子目录时加 `--base-href /demo/`；默认部署路径为 `/`。通过 `FLUTTER_BIN` 指定非 PATH 中的 Flutter 可执行文件。发布记录写入 `releases/<clubId>-<version>-<buildNumber>/<platform>/manifest.json`，含每个阶段的开始/结束、返回码、实际产物路径与校验和。失败即停止，工具返回0但没有产物也算失败。

微信用独立 `WECHAT_DEVTOOLS_CLI` 指向开发者工具 cli，先在工具中登录自己的账号。`--platform wechat` 调用官方 CLI 生成体验二维码；加 `--upload` 才会上传代码。即使上传成功，报告仍写“等待审核”，不会写“已发布”。本机 CLI 参数已经通过 `--help` 核对；微信工具的新版本如改参数，按官方当前帮助更新。

Android/iOS 的商店上传按 [移动端发布教程](04-mobile-release.md) 进行，微信版本提交按 [小程序教程](05-wechat-release.md) 进行。构建、真机、商户、上传、审核、正式发布分别留证。

## 公开政策与持续维护

生成的 `generated/club/legal/privacy.html` / `terms.html` 可部署到自己的 HTTPS 网站。也可在后端资料完成后运行 `node scripts/export-policies.mjs https://api.example.com/api/v1 ./policies`；演示或不完整资料会被拒绝。页面只整理你提供的内容，不保证法律条款本身正确。

每次改配置，先看差异，再生成并构建。相同配置、Logo 与工具版本产生相同品牌产物；版本号/构建号由配置统一管理。把公开配置和许可证一起保存，秘密配置单独备份。测试命令：`node --test scripts/test/branding.test.mjs`。
