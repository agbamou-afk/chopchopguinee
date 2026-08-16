# Node 4 — Marché R2: Offer Agreement & Commitment Truth — CERTIFIED STABLE

## Law
- Every offer amount that binds money is the frozen `agreed_amount_gnf`, set only by mutual consent.
- No actor can accept its own proposal (`COUNTER_AWAITS_BUYER`, `NO_MERCHANT_PROPOSAL`).
- Terminal states (accepted/rejected/withdrawn/expired) are locked; agreement fields immutable.
- Offer creation inherits R1.5 canonical listing truth (MERCHANT_STORE_REQUIRED, STORE_NOT_APPROVED, DEMO_SUPPLY, OUT_OF_STOCK, SELLER_NOT_ELIGIBLE).
- Direct table INSERT/UPDATE/DELETE revoked for anon/authenticated; anon cannot read offers.
- Reads go through sanitized RPCs (buyer / merchant / admin); floor price never exposed.

## Client
`src/lib/marche/offers.ts` uses `marche_offers_for_buyer|_for_merchant|_admin`, adds `buyerRespondOffer`,
`offerActiveAmountGnf`, `offerAwaitsBuyer/Merchant`. Buyer counter accept/reject in `ListingDetail`;
"awaiting buyer" state in merchant offer surfaces.

## Verification (all green)
- `_qa_node4_marche_r2()` 82/82
- Node4 R1 55/55, R1.5 38/38
- Full frozen board (Nodes 0–3, Slice 13): 0 failures across 24 suites
- tsgo exit 0, Vitest 71/71, production/PWA build OK

No deployment, no flag activation, no finance-policy or courier change.
