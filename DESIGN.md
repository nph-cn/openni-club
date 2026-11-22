# OpenNI interface decisions

Avoid unnecessary secondary labels and descriptions. Let the layout do the explaining.
避免不必要的辅助标签与说明。让布局本身发挥解释作用。

OpenNI is a public open-source product website. Its primary routes are the complete screen gallery, working app demo, brand configuration, documentation, and GitHub source. It is not the club operator's dashboard. The fictional 北岸电竞 brand demonstrates the independently deployable product.

The current website direction, confirmed by the user on 2026-11-23, is the warm-white Mobbin-inspired showcase from commit `5ec1d92`. It uses near-black headings, black pill actions, a centered hero, and an interactive stage that changes between actual customer, member and operator screens. The gallery has complete runtime captures, role/platform/flow filters, a large viewer and source links. Do not fabricate screen content or metrics for visual polish. The earlier graphite site is historical, not the current homepage.

Design read: independent club software · restrained warm-white site · screenshot-led product stage · CSS/WAAPI product-state transition. Motion reveals the typography and switches real product roles; reduced motion displays the final static state. Brand casing is OpenNI, distinct from the independently configurable fictional 北岸电竞 demo club. The site uses the palette and type tokens in `apps/showcase/library.css`; the default configurable club accent remains Graphite (#272D35). Do not import a competitor's theme into the mobile app.

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
