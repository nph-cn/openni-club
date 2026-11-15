# OpenNI interface decisions

Avoid unnecessary secondary labels and descriptions. Let the layout do the explaining.
避免不必要的辅助标签与说明。让布局本身发挥解释作用。

OpenNI is a public open-source product website. Its primary routes are the complete screen gallery, working app demo, brand configuration, documentation, and GitHub source. It is not the club operator's dashboard. The fictional 北岸电竞 brand demonstrates the independently deployable product.

2026-11-16 用户要求官网更接近 Mobbin。主站方向更新为白底、黑色主动作、紧凑导航与大尺寸完整截图；用实际产品页面构成多屏预览，去掉巨型 OpenNI 字标占据首屏。保留角色、平台、流程、状态筛选、大图查看与源码链接。禁止为了视觉效果捏造界面内容和指标。

主站：独立俱乐部开源软件，白底与黑灰文字，内容优先，截图与可操作流程占主导。品牌拼写固定为 OpenNI，独立配置的虚构北岸电竞俱乐部不被覆盖。App 保留 Mist (#F4F5F7) 内容背景与 Graphite (#272D35) 默认强调色。减少动态时直接显示最终状态。

独立 `/delta/` 专题是「三角洲行动 · 战地档案」二创：以官方三角洲素材为底，用自研 WebGL2 着色器做调色、尘粒、扫描与噪声擦除，DOM 承载固定框架、HUD 与章节文字；滚动依次为入局、行动方式、地形情报、小队集结、部署。参考对象是实际查看并取证的 KPR 官网渲染语言（全屏画布 + DOM 文字层 + 平滑滚动 + 图像平面过渡），不是像素复刻：不复制其品牌、角色、文案与源码。移动端为独立响应式布局，并保留减少动态、无 WebGL 静态降级、影像弹层与动态开关。该页不宣称是游戏官方网站。

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

- 叙事：五章「入局 / 行动方式 / 地形情报 / 小队集结 / 部署」。小队章把 KPR 的「你是一个 keeper」转译为 OpenNI 的「一个人的枪法，四个人的战局」，接真实 App 成员页，是专题唯一的业务桥。
- 渲染：全屏 WebGL2 单 pass。图像调色（石墨阴影 + 骨白高光 + 信号绿点）、噪声擦除换场、尘粒/余烬、地图扫描线、操作员层遮罩显影；全部为自研 GLSL，不使用 KPR shader 原文。
- 框架：固定细边框、顶部章节导航、左侧进度轨、等宽 HUD（真实章节/滚动百分比/视口/本地时间/渲染状态，不编造运营指标）、纸面章节用「窗口」露出画布。
- 交互：模式与地图 tab（键盘可用）、重新扫描、官方影像弹层、暂停动态；尊重 `prefers-reduced-motion` 与 `prefers-reduced-transparency`，无 WebGL 时静态底图降级并在 HUD 标注。
- 素材：继续使用已核源的官方公开游戏素材与 App 实际截图；示例成员头像为虚构演示肖像。KPR 的素材、文案、音频一律不进入交付物。
