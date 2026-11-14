# Shared API contract v0.1

Base `/api/v1`. JSON requests and responses. Success direct JSON, errors `{error: {code, message}}`. Club deployment single-tenant. Public GET /club, /services, /players, /announcements. GET /services/:id and /players/:id. GET /health at server root.

Club `{id,name,tagline,description,city,notice}`. Service `{id,title,game,category,description,priceCents,durationMinutes,tags}`. Player `{id,name,role,bio,games,tags,initials,color}`. Announcement `{id,title,body,publishedAt}`.

POST /auth/demo `{name?}` => `{token,user:{id,name}}`, available ONLY demo mode. Authorization `Bearer token` for own orders. POST /orders `{serviceId,playerId?,scheduledAt,contact,note?,idempotencyKey}` => order. Client never supplies price. GET /orders => array. PATCH /orders/:id/cancel => order. Order `{id,serviceId,serviceTitle,playerId,scheduledAt,contact,note,priceCents,status,createdAt}`. Status pending/confirmed/completed/cancelled. Demo orders are simulated/unpaid, never payment success. Production auth requires a real provider and must fail closed rather than accept demo tokens.

Admin `Authorization: Bearer ADMIN_TOKEN`: GET /admin/orders => array; PATCH /admin/orders/:id `{status}` transition pending->confirmed->completed, pending/confirmed->cancelled. GET /admin/config/status => safe booleans only. No secrets in response or mobile bundles. Environment PORT=8787; API_MODE=demo or production; ADMIN_TOKEN only server; DATA_DIR default ./data. Demo seed deterministic.

API response collections are arrays, not `{data:...}`. Clients may use explicit local seeded demo mode but must label it. Cross-port local web uses API_BASE_URL=http://localhost:8787/api/v1. Flutter --dart-define=API_BASE_URL=...; mini program utils/config.js. Static showcase root `apps/showcase`, admin `apps/admin`.
