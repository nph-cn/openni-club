# 单一品牌配置与发布流程

状态：生成器、运行时公开配置、原生图标/品牌配置、政策页和发布包装脚本已实现，并有双品牌、确定性、回滚与失败状态测试。各客户端消费及业务体验的验收以对应测试为准；实际真机、商户和商店审核未由生成器证明。使用说明见 [单配置教程](../docs/10-single-config-workflow.md)。

## 经营者实际要做的事

第一次用向导输入俱乐部名称、Logo、自己的经营信息，选择俱乐部服务模板，连接已有第三方账号。向导提供可用默认主题和页面，不要求经营者编辑 Dart、JavaScript、Android 或 Xcode 源文件。真正必需的账号、签名、类目和法律信息由经营者补齐，不能伪造或跳过。

向导导出公开 `club.json` 和独立秘密配置。预览可仅有名称和 Logo；正式发布预检再校验域名、签名文件、微信配置和经营信息。CLI 记录每个实际工具阶段；第三方账号和平台审核结果须另外核验。

## 配置边界

`config/club.json` 是品牌和发布配置的唯一来源，含：

- `schemaVersion`：显式配置迁移版本。
- `brand`：名称、简称、Logo 相对路径、介绍、标语、主色和图标背景。
- `operator`：经营主体、客服联系、所在地。
- `legal`：真实隐私政策与服务条款正文。
- `distribution`：稳定 clubId、iOS Bundle ID、Android applicationId、版本号、构建号、小程序 AppID、移动微信 AppID、Apple Team ID、Universal Link。
- `endpoints`：公开 API/网站域名。
- `initialCatalog`：首次建库的服务模板和待完善目录；不含虚构真实成员，不会反复覆盖运营数据库。

`.env` / 平台 secret store 是秘密来源，含 AppSecret、商户私钥路径、API v3 Key 和后台凭证。Schema 拒绝公开 JSON 中的 `secret`、`privateKey`、`token`、密码字段。校验和日志只输出配置键名，不输出秘密值。

运营数据（订单、成员排班、价格调整）仍由数据库保存；它们不是安装时品牌配置。`/club` 的品牌/经营信息直接读取已加载的公共配置，后台的同类字段不再另存一个可能冲突的副本。后台品牌编辑导出新的配置版本，预览差异后部署；服务与人员目录继续走 CRUD。App 内远程品牌文案可随配置更新，安装图标/系统显示名/包标识变更必须重新签名构建。

## 生成与发布契约

`node scripts/configure-club.mjs --check config/club.json`：离线 Schema、Logo 文件和公开 URL 校验，检查秘密误放及包标识格式，输出缺项。

`node scripts/configure-club.mjs --plan config/club.json`：列出将生成的文件、摘要、旧新差异；不写业务数据。

`node scripts/configure-club.mjs --apply config/club.json`：先生成暂存文件，再提交产物，manifest 最后写入；普通文件异常会回滚已提交文件。多目录更新不是单次操作系统原子操作：进程被强杀/机器断电可能留下锁和暂存目录，需先检查恢复，不能直接发布；release 会核对全部文件 hash。相同配置、Logo 和生成器版本得到相同输出。

生成产物包括 Flutter `assets/brand.json` 和 `assets/catalog.json`、各原生平台图标与品牌配置、小程序公开配置、后端首次初始化 seed、法律页面与可选 Universal Link 文件。`catalog.json` 只含 services、players、announcements，与首次初始化目录一致；远程运行时目录由 API 提供。原生包名等通过受控模板生成；不对业务源码做全局替换。

`node scripts/release-club.mjs --platform android|ios|wechat --mode preview|production`：读取同一 manifest，自动传入公开构建参数，检查配置 hash 一致和对应签名条件，调用真实工具链，输出产物/校验和/版本/测试证据。不承诺自动通过商店审核；上传、审核结果与正式发布是分开的状态。

生产后端初次启动才导入 initialCatalog。已有数据库更新品牌文件前做迁移检查和备份，不清库、不重置用户、不覆写历史订单金额。发布者必须保持已发布应用的包标识与签名；脚本不会读取商店账号来自动锁定应用身份。

## 验收顺序

1. Schema、默认模板、检查器、生成 manifest；两套完全不同俱乐部配置的测试均不出现原型品牌残留。
2. Flutter/小程序/后端消费同一公开配置；禁用重复品牌来源，验证改名跨端同步。
3. Logo 原图确定性缩放生成各尺寸图标；iOS 不允许透明的目标使用明确背景。生成后肉眼检查，不用拉伸图片充数。
4. 网页安装向导和运营后台完成配置编辑、秘密位置指引、差异预览、发布进度。
5. Android/iOS/微信构建包装与外部审核交接；真机、商户与签名凭证齐备时再记录通过。

验收重点：经营者不改源代码；错误配置一次性说明；同一输入可复现；无密钥进入客户端或构建日志；现有订单不受换品牌影响；生成失败不会留下跨端混用两版品牌的半成品。
