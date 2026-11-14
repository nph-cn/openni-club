# v0.2 club operations contract

Work in progress; v0.1 payment/security adapters remain. No production data currently exists in this repository.

Keep existing public catalog/auth/payment API compatible. Extend Order with `fulfillmentStatus`, `assignedPlayerId`, `commissionBps`, `memberCents`, `clubCents`, `events`, `review`, `dispute`. Existing `status` remains pending/confirmed/completed/cancelled for compatibility; all v2 UI renders fulfillmentStatus.

Fulfillment status: `awaiting_payment`, `awaiting_assignment`, `awaiting_acceptance`, `scheduled`, `in_progress`, `awaiting_confirmation`, `disputed`, `completed`, `cancelled`. Demo orders enter awaiting_assignment without real payment. Production payment callback moves awaiting_payment to awaiting_assignment. Confirmation/fulfillment transitions must enforce authorized actor and prior state on server.

## Customer

- GET /me → {user:{id,name},role:'customer'|'member',playerId?}; PATCH /me {name}
- GET /orders/:id includes events, payment/refund and fulfillment fields.
- POST /orders/:id/confirm {rating:1..5,comment?} creates a single completed event/earnings entry.
- POST /orders/:id/dispute {reason,details?} freezes fulfillment/settlement; cannot be called for someone else's order.
- GET /notifications; PATCH /notifications/:id/read.
- GET /players/:id/availability?date=YYYY-MM-DD → slots with available/busy, timezone Asia/Shanghai; validate interval overlap on assignment, not just UI.

## Member

Member is a server-bound player identity. Owner generates expiring single-use invitation; accepting it binds an authenticated account to a player. Demo role switching must be restricted to API_MODE=demo and visibly marked.

- POST /member/invitation/accept {code}; GET /member/me
- GET /member/orders; POST /member/orders/:id/accept; POST /member/orders/:id/decline {reason}
- POST /member/orders/:id/start; POST /member/orders/:id/submit {summary,evidenceUrl?}. Evidence URL HTTPS only; never server-fetch arbitrary URLs. Only the assigned member can act.
- GET/PUT /member/availability {slots:[{startAt,endAt}]} with future interval validation and conflict protection.
- GET /member/earnings → ledger plus totals: held/available/settled. No fake withdrawal API.

## Owner/operations

Existing ADMIN_TOKEN authenticates owner. Extend safely with staff roles only if complete and tested; do not expose owner token to member/customer apps.

- GET /admin/overview → computed queue counts and actual order totals; demo explicitly marked.
- POST /admin/players/:id/invitation → one-time code + expiry (no secrets in audit output).
- POST /admin/orders/:id/assign {playerId,commissionBps,reason?}; freeze commission for the assignment, reserve duration, reject conflicting occupied intervals. Default commission from club config (e.g. 2000bps); member sees memberCents before accept.
- GET /admin/disputes; POST /admin/orders/:id/resolve {outcome:'resume'|'refund',reason}. Refund delegates verified existing refund flow. Resolution recorded.
- GET /admin/settlements → ledger; POST /admin/settlements {entryIds,paymentReference,note?} atomically marks eligible items settled and records reference. Does not send money. Export CSV using safe cell escaping.

Use transactional updates / idempotency and immutable events for finance. Price and rate are never accepted from customer. Expired/unpaid upstream payment must be closed safely before local cancellation. Server may derive timed-out acceptance in reads/writes with tested transitions; no long polling daemon required for first version.

## Public branding

`config/club.json` + generated public JSON is the brand/distribution source, private `.env` separate. Agent writing generator owns its schema; coordinate before consuming. Runtime catalog/availability/order data remains in DB. Hardcoded 北岸 strings, one shared following bool, or fake online/count/rating numbers must not survive production configuration.
