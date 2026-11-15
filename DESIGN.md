# OpenNI interface decisions

Avoid unnecessary secondary labels and descriptions. Let the layout do the explaining.
避免不必要的辅助标签与说明。让布局本身发挥解释作用。

OpenNI is a public open-source product website. Its primary routes are the complete screen gallery, working app demo, brand configuration, documentation, and GitHub source. It is not the club operator's dashboard. The fictional 北岸电竞 brand demonstrates the independently deployable product.

2026-11-16 用户要求官网更接近 Mobbin。主站方向更新为白底、黑色主动作、紧凑导航与大尺寸完整截图；用实际产品页面构成多屏预览，去掉巨型 OpenNI 字标占据首屏。保留角色、平台、流程、状态筛选、大图查看与源码链接。禁止为了视觉效果捏造界面内容和指标。

主站：独立俱乐部开源软件，白底与黑灰文字，内容优先，截图与可操作流程占主导。品牌拼写固定为 OpenNI，独立配置的虚构北岸电竞俱乐部不被覆盖。App 保留 Mist (#F4F5F7) 内容背景与 Graphite (#272D35) 默认强调色。减少动态时直接显示最终状态。

独立 `/delta/` 专题是「三角洲行动 · 战地档案」Three.js 3D 二创：以官方三角洲素材为底，在 Three.js r160 透视相机中分层布置场景、干员与循环视频，配合预加载声音门、逐字标题、章节菜单、自定义光标、HOLD 交互、3D 拾取与自研 post-processing；DOM 承载固定框架、HUD 与章节文字。滚动依次为入局、行动方式、干员档案、地形情报、小队集结、部署，固定 HUD 只展示真实数据。参考对象是实际查看并取证的 KPR 官网渲染语言（全屏画布 + DOM 文字层 + 平滑滚动 + 图像平面过渡），不是像素复刻：不复制其品牌、角色、文案与源码。移动端为独立响应式布局，并保留减少动态、无 WebGL 静态降级、影像弹层与动态开关。该页不宣称是游戏官方网站。

Typography is readable rather than decorative: 16px body copy, 14–16px operational text, larger headings. Secondary metadata can be 11–12px when it is truly secondary. Chinese UI uses the system Chinese sans; Manrope is locally hosted for Latin text with its license. No repeated explanatory subtitle under each action. Configuration learning belongs in the guide; contextual errors stay beside the relevant input.

For mobile, customer ordering, member fulfillment and operator dispatch are different tasks. Service choices need device/platform, service type, selected specification, price/unit and the agreed fulfillment rules. In-progress service is visible before promotional material. The API freezes the selected service specification on the order. Unsupported business paths must not be presented as working.

The iOS visual direction uses a glass-inspired functional layer for navigation and floating controls. Content, prices, names, and order facts stay clear. Android shares the domain and screen logic while using platform-appropriate behavior and surfaces. Flutter blur is not claimed as the native Apple Liquid Glass implementation. Respect transparency/contrast accessibility settings where the platform exposes them.

References inspected: official Bixin App Store promotional screenshots for hierarchy (game choice, person/service facts and price); public club service menus for specifications; Apple's Materials HIG for glass hierarchy. The official 东东电竞 App Store images inspected mainly show community and esports content, not the complete ordering flow. Mobbin searches returned connector errors; no unseen Mobbin result is cited or claimed as inspected. Third-party research images are not bundled in the MIT product.

All demonstration people, orders and balances are fictional. Original generated demo portraits are labeled as such. Never fabricate availability, ratings, transaction volume, successful payments or store approvals to decorate a screen.

Reference update: actual Grok logged-out UI, x.ai/grok and Heron AI website were viewed. Codrops Heron (2026-10-12) and bleibtgleich26 (2026-09-23) articles informed meaningful product interaction and restrained composition; no third-party assets are redistributed.

## 2026-11-15 user correction

Website direction retained; ornamental marketing copy removed. Use literal labels: 电竞俱乐部开源应用、用户端、成员端、管理后台、配置俱乐部、文档. No 主场 metaphor or explanatory lines beside every function.

App design is being replaced with image-led real game content: official game covers/icons, configurable club banners, image-supported service cards and member profiles. Abstract contour artwork is not an acceptable substitute for game imagery. Game artwork provenance and third-party rights stay separate from the MIT code license. Keep sample-data disclosure in application information and transaction decisions rather than every navigation bar. Never claim a real paid order or identity that did not occur.

Documentation is a Read surface: grouped left navigation, searchable content, article table of contents, copyable commands, numbered actions and previous/next links. It is not a marketing landing page.

## Full-flow refinement

The next pass includes authentication and transient states as product surfaces: welcome, login method, phone input, one-time code, verification failure, submission, empty and unavailable content. Public browsing stays available; protected actions return to their original intent after authentication. The server owns OTP expiry and resend cooldown. Test codes are explicitly marked as local tests; unconfigured production providers never display successful delivery.

Motion uses a short transition for navigation and a restrained response to controls. Loading uses layout-shaped placeholders only while asynchronous work is pending. Reduced motion renders static skeletons. Floating navigation and actions carry the glass treatment with soft offset shadows; text and prices remain on clear surfaces.

The gallery groups every manifest entry by its actual flow, including new states, and supports state filters, direct page links, full-screen fitting and optional zoom. No curated ID list may silently hide a new page from flow browsing. Mobbin authentication searches on 2026-11-15 again returned internal errors; no new Mobbin image was available for review.

## 2026-11-16 三角洲二创改版

用户反馈上一版「学 KPR 做得差、没有二创感」。本轮按 lixiaolin94/skills 的 web-shader-extractor 方法对 KPR 做了目标锁定与证据记录（固定画布 + DOM 文字层 + GSAP ScrollSmoother + 遮罩/模糊材质 + 相机指针微环绕；证据在 `work/kpr-shader-study/`），随后改用自有叙事与自研着色器重建三角洲专题：

- 叙事：六章「入局 / 行动方式 / 干员档案 / 地形情报 / 小队集结 / 部署」。干员档案章用 6 张官方公开透明角色立绘组成滚动驱动的 3D 横向画廊，当前干员提亮并同步代号/定位/语录；章节节奏参考 KPR 的 270vh 三屏窗口与 mask 擦场。小队章把 KPR 的「你是一个 keeper」转译为 OpenNI 的「一个人的枪法，四个人的战局」，接真实 App 成员页，是专题唯一的业务桥。
- 渲染：Three.js r160 透视相机 + 分层图像平面 + 视频纹理 + 自定义 post-processing（调色、颗粒、暗角、色差、扫描线）；章节切换用相机运动、遮罩显影与透明度过场；全部为本项目自有实现，不使用 KPR shader 原文与素材。
- 框架：固定细边框、顶部章节导航、左侧进度轨、等宽 HUD（真实章节/滚动百分比/视口/本地时间/渲染状态，不编造运营指标）、纸面章节用「窗口」露出画布。
- 交互：模式与地图 tab（键盘可用）、重新扫描、官方影像弹层、暂停动态；尊重 `prefers-reduced-motion` 与 `prefers-reduced-transparency`，无 WebGL 时静态底图降级并在 HUD 标注。
- 素材：继续使用已核源的官方公开游戏素材与 App 实际截图；示例成员头像为虚构演示肖像。KPR 的素材、文案、音频一律不进入交付物。


## 2026-11-16 App 会员体系与俱乐部能力

App 演示目录新增 8 个游戏类目（三角洲行动、无畏契约、英雄联盟、CS2、永劫无间、绝地求生、Apex 英雄、守望先锋）、四级打手分级（新锐/进阶/精英/王牌）与 8 项俱乐部可开通能力（打手分级、认证打手、试听、多游戏类目、语音房、发票、会员卡、上分车队）。分级依据接单量、评分与认证状态，展示权益、分成与认证流程；能力页明确示例配置，未开通项显示为可开通。运营后台可新增/编辑/停用打手、设置分级与认证、启停游戏类目与能力。所有游戏封面来自官方公开商店/CDN，角色头像来自官方公开角色美术并标注为非真人；示例数据不等于真实签约、评分或支付。
