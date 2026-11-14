# OpenNI Club

<!-- impeccable:product-schema 1 -->

## Platform
adaptive

## Stack
Flutter iOS/Android and native WeChat mini program share a portable Node.js SQLite REST API. A browser Studio configures a club; an operator console manages daily work; a public screenshot gallery documents the actual interfaces. Each club self-hosts an isolated deployment. One public brand configuration feeds all clients; secrets remain server-side.

## Users
Esports club operators who need an independent app without a development team; club members and customers booking gaming sessions.

## Product Purpose
MIT open-source software for independent club operations: acquire customers, schedule and assign members, deliver sessions, handle disputes and refunds, and account for member earnings. Name and logo should be enough for a useful branded preview. Production adds the operator's legal information, platform identities, signing and verified integrations through a guided workflow.

## Capabilities and Constraints
The original generic booking prototype was rejected by the user. The v0.2 working scope and research evidence are in docs/product/01-club-operations.md. Customer, member and operator roles must form one complete booking → assignment → acceptance → delivery → confirmation → earnings-record flow, with conflicts, refusal, expiry, disputes and refunds handled explicitly. Operations API tests and the brand generator exist; redesigned client interfaces and end-to-end product validation are ongoing. Do not call unfinished screens complete.

The generator produces public runtime configuration, native app icons/identity settings, mini-program project settings, first-start catalog and legal pages. It does not reset live users or orders. Real WeChat authentication and payment/refund protocol adapters exist and use mocked-provider cryptographic tests; no real merchant transaction or app-store approval has been verified. Demo Northshore/北岸 club, people and prices are fictional and labeled. No fabricated ratings or sales are allowed.

## Open decisions
Actual club brand, merchant account, production hosting region and app-store developer accounts come from each adopter. SMS/IM/RTC are not currently integrated. Manual settlement records are bookkeeping evidence, not automated transfers or a wallet. Native signing, real devices, merchant settlement and platform review remain separate verification stages. No game-publisher affiliation is implied.

## Principles
Each club owns its deployment and data. Demo works without paid services. Production mode fails closed when integrations are missing. Screenshots depict implemented product states. Application review remains a real prerequisite.
