# Mobile interface direction

This is a club booking and fulfillment app. The platform is OpenNI; the club name, logo, primary color, banners and service catalog come from one generated configuration and the club API. Current sample identity is 北岸电竞.

The latest user correction replaces the abstract, image-poor catalog with real game imagery. Home contains a compact club header and search, configurable game banner placements, a visible active-order shortcut, game icons, image-led service choices and player roster. Banners open a configured service or filter the actual catalog; they have no invented offers or counts. Service detail uses real game art above the title, variants, maps and rules. Player detail pairs the person's image with their game and useful service facts. Orders use game thumbnails and the server's actual status, costs, assignee and event sequence.

Official game images are loaded from their recorded HTTPS catalog URLs. They retain third-party ownership and are not claimed as MIT assets. Missing media falls back to the game name, never fabricated art. The screenshot cache downloads those same URLs into ignored `.dart_tool/catalog-media`; it does not alter runtime data or bundle third-party bitmap files. On web, image loading can fall back to an HTML image when a publisher CDN omits CORS headers.

Surfaces use cool white `#F4F5F7`, ink `#171B21`, muted `#636B78`, separators `#DDE1E7` and the configured club primary (default graphite `#272D35`). Images provide the game-specific color. Titles/prices use weight 600; body 400 at 16px; secondary facts 13–14px. Copy directly names the service, action or state. No invented ratings, online indicators, sales, skills or outcomes.

Keep sample-data disclosure in settings/about and once at checkout. Do not put mode badges on each page. Original fictional member portraits remain documented there; production uses supplied member images or initials. Production payment and identity paths still fail closed without verified configuration. Offline member actions remain disabled rather than reporting fake write success.

iOS/web use localized glass for navigation, transaction bars and sheets, with content visible beneath. Android uses solid Material surfaces. Accessibility preferences disable transparency. Flutter glass is not represented as Apple's native Liquid Glass.

Review the actual 390×844 home/service/player/order captures before the full 22-page gallery. Preserve all booking, variant, authentication, payment and fulfillment tests.
