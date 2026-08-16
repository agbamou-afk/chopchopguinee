# Node 4 — Marché R2: Offer Agreement & Commitment Truth — CERTIFIED STABLE
Locked 2026-08-16 (canonical name: `node4-marche-r2-offer-agreement-commitment-truth`;
supersedes the earlier short name `node4-marche-r2-offer-agreement-truth-stable`).

## Law
- A price binds only when the party that did NOT propose it accepts. Merchant can never accept its
  own counter (`COUNTER_AWAITS_BUYER`, `NO_MERCHANT_PROPOSAL`).
- On acceptance `agreed_amount_gnf`, `agreed_by_user_id`, `agreed_at` freeze and are immutable.
- Single-counter-cycle machine: pending(buyer proposer) → merchant accept | counter once | reject;
  countered(merchant proposer) → buyer accept | reject | withdraw. accepted/rejected/withdrawn/expired
  are terminal. Expiry enforced on read/act even before sweeper; accepted never expires.
- Offer creation inherits R1.5 canonical truth (MERCHANT_STORE_REQUIRED, STORE_NOT_APPROVED,
  DEMO_SUPPLY, OUT_OF_STOCK, SELLER_NOT_ELIGIBLE) plus self-offer/amount/tender/duplicate-open guards.
- Marché payment-intent/completion consume only the frozen agreed amount; non-accepted, expired or
  agreement-less offers are refused with no finance side effects.
- Direct INSERT/UPDATE/DELETE on `marketplace_offers` revoked for anon/authenticated; anon cannot
  enumerate offers. Reads only via sanitized buyer/merchant/get/admin RPCs; `minimum_price_gnf` never leaks.

## DB objects
`marketplace_offers` (+agreed_amount_gnf, agreed_by_user_id, agreed_at, current_proposer_role, expired_at),
`marche_offer_transition_guard`, `create_marketplace_offer`, `merchant_respond_marketplace_offer`,
`buyer_respond_marketplace_offer`, `marche_offer_expire_due` (service/admin only),
`marche_offer_is_expired`, `marche_offer_set_tender`, `marche_offer_get`, `marche_offers_for_buyer`,
`marche_offers_for_merchant`, `marche_offers_admin`, `_qa_node4_marche_r2`.

## Client
`src/lib/marche/offers.ts` (sanitized RPCs, `buyerRespondOffer`, `offerActiveAmountGnf`,
`offerAwaitsBuyer/Merchant`), `ListingDetail` buyer "Accepter la contre-offre / Refuser",
`MerchantOffersSection` + `MerchantCommandesView` "En attente de l'acheteur" (no accept-own-counter).

## Verification (all green)
- `_qa_node4_marche_r2()` 82/82; Node4 R1 55/55; R1.5 38/38
- Full frozen board after last edit (Nodes 0–3 incl. Repas R1–R11 & P15.5, Slice13 runs 1–7): 0 failures / 24 suites
- tsgo exit 0, Vitest 71/71, production + PWA build OK
- Posture re-verified at lock: `marketplace_offers` has no anon/authenticated table grants;
  `has_role` EXECUTE = authenticated/service_role only (anon excluded); listings 53 total /
  48 storeless quarantined / 47 demo hidden; feature flags unchanged (marche=true, no new activation);
  0 offer rows, zero QA fixture residue; no wallet/ledger/payment/mission/courier/settlement drift.

## Accepted note
`marche_offer_transition_guard` keeps default PUBLIC EXECUTE: it is a trigger-only function and cannot
be meaningfully invoked outside trigger context.

No deployment, no flag activation, no finance-policy, rail, ledger or courier change.
