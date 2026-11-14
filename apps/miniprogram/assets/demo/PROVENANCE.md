# Demo assets

`player-yu.png` and `player-bei.png` are original AI-generated portraits of fictional adults. Generated with the built-in imagegen tool, 2026-11-15. They are only fallback assets when the runtime is explicitly in demo mode. Production members use their own authorized `avatarUrl` or an initial; no fabricated identity, rating or online state is shown.

Prompts:

- Male portrait: premium natural editorial photo of a fictional Chinese male esports coach, age 27, textured dark hair, subtle silver glasses, charcoal unbranded crewneck, relaxed three-quarter pose, warm grey studio with out-of-focus gaming desk and daylight, muted olive-grey and ivory palette, realistic skin and photographic grain, chest-up 4:5. No text, logos, badges, ratings, watermark, game artwork or recognizable real person.
- Female portrait: premium natural editorial photo of a fictional Chinese woman esports coach, age 26, shoulder-length dark hair, sage-green unbranded technical jersey, relaxed expression, warm pale-stone studio and soft daylight, realistic skin and photographic grain, chest-up 4:5. No text, logos, badges, ratings, watermark, game artwork, sexualization or recognizable real person.

`order-in-progress.json` is copied from `services/api/test/fixtures/order-in-progress.json`, produced through actual HTTP actions: customer creates demo order; owner assigns p1; p1 accepts; p1 starts. The screenshot fixture preserves the server-produced events and state. It contains no customer session token. See the API fixture README for the generating sequence. This fixture is used by screenshot tests, not silently loaded as a live customer order.
