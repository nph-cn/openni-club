# Demo assets

## 2026-11-16 新增原创虚构人物

`player-xiaoman.webp`（小满，成年女性）与 `player-north.webp`（North，成年男性）是通过内置 `image_gen.imagegen` 分别生成的原创虚构演示人物，不来自第三方头像，也不代表真实陪练、签约人员或客户身份。两图已人工视检，未使用游戏标志、猫耳或既有角色 IP。

生成方形原件只做等比缩小和 WebP 格式转换，最终均为 768×768；没有修改人物或背景内容。完整提示词、生成方式、原件与成品尺寸和 SHA-256 保存在同目录 `GENERATED-2026-11-16.json`。原始 PNG 工作备份位于本任务工作区 `work/openni-generated-avatars/`。这两项是演示人物素材，和官方游戏美术来源分开记录；真实运营中的成员头像须由成员提供或授权。

`player-yu.png` and `player-bei.png` are original AI-generated portraits of fictional adults. Generated with the built-in imagegen tool, 2026-11-15. They are only fallback assets when the runtime is explicitly in demo mode. Production members use their own authorized `avatarUrl` or an initial; no fabricated identity, rating or online state is shown.

Prompts:

- Male portrait: premium natural editorial photo of a fictional Chinese male esports coach, age 27, textured dark hair, subtle silver glasses, charcoal unbranded crewneck, relaxed three-quarter pose, warm grey studio with out-of-focus gaming desk and daylight, muted olive-grey and ivory palette, realistic skin and photographic grain, chest-up 4:5. No text, logos, badges, ratings, watermark, game artwork or recognizable real person.
- Female portrait: premium natural editorial photo of a fictional Chinese woman esports coach, age 26, shoulder-length dark hair, sage-green unbranded technical jersey, relaxed expression, warm pale-stone studio and soft daylight, realistic skin and photographic grain, chest-up 4:5. No text, logos, badges, ratings, watermark, game artwork, sexualization or recognizable real person.

`service-desk.png` is an original AI-generated still life of unbranded headphones, keyboard and mouse on a pale stone desk, with an ivory/olive palette and natural light. It is a generic service illustration, not a game screenshot or licensed game asset.

`order-in-progress.json` is copied from `services/api/test/fixtures/order-in-progress.json`, produced through actual HTTP actions: customer creates demo order; owner assigns p1; p1 accepts; p1 starts. The fixture preserves the server-produced events and state. It contains no customer session token. It is loaded only in the explicitly labeled offline demo and screenshot tests, never production.

`member-preview.json` contains actual p1 responses from authenticated `/me`, `/member/orders`, `/member/earnings`, `/member/availability`, and `/notifications`. The generating script creates, assigns, accepts, starts, submits, confirms and records a manual settlement; it also creates separate in-progress and awaiting-acceptance orders. Availability is set through the API to 18:00–23:30. Offline member operations are read-only. See `services/api/scripts/generate-demo-snapshot.mjs` and the fixture README. The app never rewrites fixture status, ledger amounts or event timestamps for visual effect.


## 2026-11-16 新增：打手分级演示头像

`avatar-nyx.webp`、`avatar-gale.webp`、`avatar-abyss.webp`、`avatar-wing.webp` 是从三角洲行动官方公开角色美术（元数据见 `apps/showcase/delta/assets-manifest.json`）裁切的方形演示头像，用于打手分级与更多类目的示例成员；不是真实人物照片，也不代表真实陪练、签约人员或客户身份。生产环境成员必须使用本人授权上传的头像或默认首字母，不使用官方游戏角色美术作为真人头像。

游戏封面与图标来源见同仓库 `assets/games/PROVENANCE.md`。
