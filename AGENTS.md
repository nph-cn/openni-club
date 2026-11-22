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
- Current approved website direction (confirmed 2026-11-23) is the warm-white Mobbin-inspired showcase originally in `apps/showcase/redesign/` (commit `5ec1d92`), now the root site. Preserve its near-black headings, restrained pill actions, screenshot-led stage, and gallery. The mobile app retains its own established colors; competitor research may inform its flow and hierarchy, not its theme.

- Latest user feedback: keep the website direction, remove slogans/metaphors (including 主场), use direct product labels. App visual design must show real game imagery and configurable banner placements, not contour placeholders. Avoid repeated demo badges; disclose sample data centrally and preserve honest payment/account boundaries. Beginner guidance belongs in a conventional searchable documentation layout.

- Complete flows include entering the app, login, verification, loading, empty, error, retry and success states. Capture implemented states in the gallery instead of listing only happy-path screens. Skeletons follow the content layout and actual asynchronous work; never delay responses to display them. Motion communicates navigation or feedback, respects reduced-motion settings, and must not block input. Glass belongs to navigation and floating controls; primary text, prices and input fields remain legible.
