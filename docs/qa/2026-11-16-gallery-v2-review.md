# 图库首页 Mobbin 级改版与全量截图接入验收

日期：2026-11-16。范围：`apps/showcase` 首页（`index.html` / `app.js` / `gallery-model.js` / `catalog.json` / `library.css` / `gallery-refinement.css`）、`scripts/build.mjs`、`docs/00-status.md` 图库相关行。未改 `apps/showcase/delta/`、`apps/mobile/`（由其它任务负责）、README/DESIGN/AGENTS；未提交 git。

结论：首页从「营销 Hero + 角色预览 + 界面网格」重构为 Mobbin 式 App 展示页（App 介绍 + 平台切换 + 按业务流程分组的大尺寸运行截图 + 详情查看器）。构建自动纳入 Flutter/小程序/后台全部截图，清单缺失时按目录兜底并对未登记截图告警。本轮在 App 侧扩图完成前的 100 张截图（Flutter 64 / 小程序 24 / 后台 12）上完成结构改造与浏览器验收；App 侧扩图后的最终数量见文末「最终接入数量」。

## 1. 用户要求与落地对照

| 用户要求 | 落地 |
| --- | --- |
| 像 Mobbin 一样的 App 展示页，一个 App 全页面截图很多、完整度高、清晰大气 | 首页主体是单个 App（OpenNI/北岸电竞演示俱乐部）的完整界面库；默认按业务流程分组；卡片按截图原始 780×1688 比例完整显示、不裁切，桌面 4–5 列大图，手机单列 |
| 顶部 App 介绍区：名称、定位一句话、平台/流程/截图数量真实统计、主色标签 | 头部含 OpenNI 图标与名称、`h1` 定位、四项真实统计（运行截图/业务流程/客户端/交互状态，全部来自构建产物）、品牌色与 App 主色色卡、平台标签与许可证 |
| 平台切换（iOS / Android / 微信小程序 / 运营后台） | 平台切换为 iOS / Android（合并）· 微信小程序 · 运营后台，每项显示真实张数；iOS 与 Android 共用同一套 Flutter 界面，合并避免同一批图重复出现，另含 `home_android` Android 主题变体并在卡片上标注 |
| 按业务流程分组的大尺寸 3:8 手机截图卡片 | 6 条真实流程分组（登录与验证、发现与选人、预约与下单、订单与履约、成员工作台、资料与设置），每组有编号、界面数量、说明和「顺序浏览」；手机截图按原始比例完整展示（后台宽屏截图单独 2 列布局） |
| 搜索、流程筛选、状态筛选、收藏 | 搜索框（`/` 聚焦、Esc 清空）、流程 chips、状态下拉、收藏（localStorage 持久化）与「只看收藏」，筛选状态写入 URL 可分享 |
| 大图详情逐屏浏览（上一张/下一张、全屏、原图下载） | 详情对话框：大图、标题/说明/流程/状态/范围/源码、打开演示、下载原图、上一张/下一张（方向键）、全屏模式、放大到原图像素、流程/筛选结果缩略图条、复制链接 |
| 显示真实数量 | 首屏统计、平台计数、流程计数、结果计数、详情范围计数都从 `/screens.json` 计算，页面不写死数字 |
| 白底、轻标签、紧凑导航、大图优先、留白讲究；移动端单列；懒加载；键盘可操作 | 白底 + 细线分隔 + 浅灰标签；64px 紧凑导航；卡片 `loading=lazy` + `decoding=async`；手机 390 宽单列；详情弹窗为原生 `<dialog>`，Tab 焦点、方向键翻页、`f` 全屏、Esc 关闭 |
| 不编造截图内容或指标 | 标题、流程、说明取自 `apps/*/screenshots/manifest.json`；缺失时用 `catalog.json` 公共兜底或文件名，并向构建日志告警，不伪造文案与数字 |

## 2. 页面结构

1. **紧凑导航**：OpenNI 字标、图库/流程/三角洲专题/文档、GitHub、打开 App。移动端两行布局，导航可横向滚动。
2. **App 介绍区**：App 图标 + `OpenNI · MIT 开源 · 可白标部署`、`h1 电竞俱乐部开源应用`、一句定位说明、四项真实统计、主色色卡（品牌色 `#263C2E`、App 主色 `#272D35`，来自 `apps/showcase/icon.svg` 与 `apps/mobile/lib/ui.dart` 主题令牌）、平台/许可证标签、各端真实张数摘要。
3. **角色预览**：用户端 / 成员端 / 管理后台三个真实运行截图预览，点击直接进入对应界面详情，全部图片取自清单，缺图不猜测路径。
4. **图库工具条**：标题与当前结果数、搜索框、平台切换（带张数）、分组/全部视图、只看收藏、流程 chips、状态筛选、当前筛选摘要与清除。
5. **截图分组**：每条业务流程一个章节；卡片显示完整运行截图、界面标题、状态标签、交互状态/成员端/Android 变体/流程标签与收藏按钮；「顺序浏览」从该流程第一张开始逐屏查看。
6. **详情查看器**：大图默认完整适配，工具栏提供放大（原图像素）、全屏、复制链接、关闭；信息栏含标题、说明、流程、状态、浏览范围、源码链接、打开演示、下载原图、流程/筛选缩略图；底部上一张/下一张与当前位置。
7. **状态与兜底**：加载骨架、无结果空状态、清单加载失败可重试；`prefers-reduced-motion` / `prefers-contrast` / `prefers-reduced-transparency` 均有降级。
8. **专题与页脚**：保留 `/delta/` 专题入口与文档/状态/GitHub/MIT 页脚链接。

## 3. 数据与构建

- 数据链路：`apps/{mobile,miniprogram,admin}/screenshots/manifest.json` → `scripts/build.mjs` → `dist/screens.json` + `dist/screens/`（原图字节）→ 首页渲染。图片实际像素由 `sharp` 读取（手机 780×1688、后台 1266×712 等），不使用清单里的旧逻辑尺寸。
- **自动纳入**：清单已登记条目全部纳入；清单存在时，目录里未登记的新图片也会合并进图库（按同名文件去重、PNG/JPG 同 stem 不重复），并输出 `警告：…未在 manifest 中登记…`。清单缺失时按目录文件名兜底并告警，不静默隐藏。
- **元数据兜底**：`apps/showcase/catalog.json` 扩展为 65 条公共说明（当前 64 张 App 截图 + 小程序独有页），提供 id/标题/流程/说明/角色的最后兜底；构建仍优先使用 manifest 字段。
- **关键屏幕校验**：构建要求 home、services、service、players、player、booking、orders、order、profile、announcements、settings 都在图库数据里且图片已发布；任一平台目录存在却没有任何截图会直接报错；清单损坏/非数组仍阻断构建。
- **源码链接**：构建校验源码路径，缺失时告警并在详情中隐藏链接，不阻断整站构建（避免 App 侧重构期间误码路径导致全站构建失败）。
- **不破坏其它构建产物**：`dist/delta`、`dist/guide`（14 篇）、`dist/admin`（不含 screenshots 目录）、`dist/studio`、`dist/demo` 仍正常生成；`/`、`/delta/`、`/guide/`、`/guide/00-status.html`、`/admin/`、`/studio/`、`/demo/` 均返回 200。
- **URL 状态**：`platform/role/flow/state/view/q/screen` 参数沿用原有可分享格式；默认视图改为按流程分组（`view=flows`），`view=screens` 为全部平铺；`?screen=<id>` 可直接打开详情。

## 4. 自动化验证

- `node --test scripts/test/*.test.mjs`：43/43 通过（含图库模型、构建隔离测试、流程翻页、角色预览、首页入口、预览服务）。
- `node scripts/build.mjs`：`100 real screenshots (flutter 64, mini 24, admin 12), 0 warnings`（本轮 App 扩图完成后重跑，见文末）。
- 追加的临时构建回归（不入库）：清单存在但目录新增未登记图片时，图库张数 +2 且保留未登记项；清单条目缺标题/说明时回退 catalog 并告警；构建退出码 0。

## 5. 浏览器验证

环境：本机 `node scripts/serve.mjs`（WEB_PORT=8793，127.0.0.1）；Playwright（`createRequire` 指向 codex runtime node_modules）`chromium.launch({channel:'msedge', headless:true})`；桌面 `1440×900`，手机 `390×844`（isMobile + hasTouch + deviceScaleFactor 2）。

脚本与截图：`C:\Users\guanyipingshisb\Documents\Codex\2026-11-15\wo\work\gallery-check\`（`verify-gallery.cjs`、`verify-extra.cjs`、`verify-report.json`、`verify-extra-report.json`、`01-desktop-hero.png` 等 13 张截图与下载得到的原图）。

主验收 `verify-gallery.cjs` 30/30 通过：

1. 100 张截图资源全部 200，无 404；首屏统计 = 100 / 6 / 3 / 28（与清单一致）。
2. 桌面首屏与整页无横向溢出；平台切换显示 64 / 24 / 12；默认 6 组流程、64 张卡片。
3. 卡片图片自然尺寸 780×1688，桌面单卡约 318×687（4 列），完整原图不裁切；懒加载首屏卡片已加载。
4. 搜索「验证码」得到 3 张，与图库模型计算一致；流程筛选「登录与验证」得到 7 张且只剩 1 组；状态筛选「错误」得到 5 张且标签全部为错误。
5. 收藏计数与「只看收藏」联动正确。
6. 详情打开欢迎页：本流程 1/7、上一张禁用、缩略图 7 张；下一张与 ← 方向键可往返；全屏模式宽度 1440 且按钮变「退出全屏」；放大模式可查看原图像素；原图下载得到 `welcome.png`（824,621 字节）；关闭后恢复页面。
7. 运营后台 12 张、宽屏 2 列布局；键盘 `/` 聚焦搜索、Esc 清空。
8. 手机首屏与整页无横向溢出；图库单列 64 张；手机详情可读（原生图宽 780）且可翻页。
9. 控制台 error 0、页面脚本异常 0、失败请求（4xx/5xx）0。

补充验收 `verify-extra.cjs` 8/8 通过：全部平铺视图 64 张且每卡带流程标签；小程序 24 张与说明；深链接 `?screen=code_error` 直接打开「验证码错误」；手机搜索/状态筛选可用；无 console error、无脚本异常、无失败请求。

## 6. 边界与说明

- 截图来自 Flutter golden 控件渲染（2 倍分辨率）与微信开发者工具运行画面，设备外观仅为 iPhone 预览壳，**不是真机照片**；详情里沿用清单的采集说明。
- iOS 与 Android 共用一套 Flutter 界面，平台切换合并为「iOS / Android」；目前 Android 形态只有 `home_android` 一张主题变体，卡片会标注 Android。
- 手机截图原始比例为 780×1688（≈390×844，接近 3:6.5），页面按原始比例完整展示；「3:8 手机截图卡片」按“手机竖屏卡片”理解，不裁切也不拉伸。
- 搜索匹配的是清单标题/说明/流程/状态文本，不是截图 OCR。
- 小程序 24 张仍是旧版 UI 运行图（App 侧本轮不同步小程序），图库如实标注为微信小程序截图，未宣称最新。
- 首页需要 `/screens.json` 与 `/screens/` 由构建产出；直接打开 `apps/showcase/index.html` 时无数据会显示「界面目录未能加载」并可重试。

## 7. 最终接入数量（App 侧扩图后更新）

见下节补记。
