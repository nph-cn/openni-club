# OpenNI product and interface rules

Avoid unnecessary secondary labels and descriptions. Let the layout do the explaining.
避免不必要的辅助标签与说明。让布局本身发挥解释作用。

- Design for actual club customers, members, and dispatchers. Inspect real game-service products before choosing screen structure.
- Use clear, readable typography: mobile body text defaults to 16 logical pixels; desktop operational text defaults to 14–16 pixels. Small text is for genuinely secondary metadata only.
- Do not put an explanatory sentence below every setting, button, card, or section. Keep task-specific details at the decision point; put deployment teaching in the guide.
- Show one dominant action and a clear status. Use hierarchy, spacing, grouping, and interaction before adding more prose.
- Do not invent ratings, transaction counts, availability, testimonials, payment success, or operational statistics for visual polish.
- Preview screenshots must be captured from working screens. Review the main customer and operator screens visually before extending their pattern to all pages.
- Brand name, logo, color, and public app identities have a single generated configuration. Server secrets never belong in client bundles.
- Keep source MIT licensed. Third-party product screenshots are research references, not assets to redistribute in the application.

- The platform brand is always written **OpenNI**. Domain/package names remain lowercase; independently configured club names are not overwritten.
- 最新网站方向（2026-11-16）：OpenNI 官网采用实际查看过的 Mobbin 公开官网排布：白底、黑色主动作、大尺寸完整截图、轻量标签和清晰的流程浏览。此项覆盖旧 graphite 巨型字标首页；App 仍使用冷中性色与清晰的玻璃导航层。
- `/delta/` 是独立的三角洲行动视觉专题，参考 KPR 的分层大画面与滚动叙事。保持 OpenNI 品牌与真实 App 入口，明确非游戏官网；官方游戏美术不属于 MIT 代码授权。

- Latest user feedback: keep the website direction, remove slogans/metaphors (including 主场), use direct product labels. App visual design must show real game imagery and configurable banner placements, not contour placeholders. Avoid repeated demo badges; disclose sample data centrally and preserve honest payment/account boundaries. Beginner guidance belongs in a conventional searchable documentation layout.

- Complete flows include entering the app, login, verification, loading, empty, error, retry and success states. Capture implemented states in the gallery instead of listing only happy-path screens. Skeletons follow the content layout and actual asynchronous work; never delay responses to display them. Motion communicates navigation or feedback, respects reduced-motion settings, and must not block input. Glass belongs to navigation and floating controls; primary text, prices and input fields remain legible.
