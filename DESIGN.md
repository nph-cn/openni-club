# OpenNI interface decisions

Avoid unnecessary secondary labels and descriptions. Let the layout do the explaining.
避免不必要的辅助标签与说明。让布局本身发挥解释作用。

OpenNI is a public open-source product website. Its primary routes are the complete screen gallery, working app demo, brand configuration, documentation, and GitHub source. It is not the club operator's dashboard. The fictional 北岸电竞 brand demonstrates the independently deployable product.

2026-11-16 用户要求官网更接近 Mobbin。主站方向更新为白底、黑色主动作、紧凑导航与大尺寸完整截图；用实际产品页面构成多屏预览，去掉巨型 OpenNI 字标占据首屏。保留角色、平台、流程、状态筛选、大图查看与源码链接。禁止为了视觉效果捏造界面内容和指标。

主站：独立俱乐部开源软件，白底与黑灰文字，内容优先，截图与可操作流程占主导。品牌拼写固定为 OpenNI，独立配置的虚构北岸电竞俱乐部不被覆盖。App 保留 Mist (#F4F5F7) 内容背景与 Graphite (#272D35) 默认强调色。减少动态时直接显示最终状态。

独立 `/delta/` 专题使用官方三角洲场景与透明人物，深色环境、浅色大字、克制的淡绿点缀。首屏分层滚动，之后依次为模式、地图、App 体验入口；不做鼠标跟随或转圈等待。视频只在可见时静音播放，有暂停和减少动态降级；点击影像再加载可控制的视频。该页参考已实际查看的 KPR 视觉结构，采用独立 CSS/浏览器动画实现，不宣称复制其 WebGL 引擎。

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
