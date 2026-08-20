---
name: Node 4 Marché R13 — Conakry Hardening (certified)
description: Offline basket drafts without economic authority, server revalidation before commitment, landmark destinations, repeated-tap safety and lost-response recovery for Marché
type: feature
---

# Node 4 — Marché R13: Conakry Hardening — CERTIFIED / LOCKED / FROZEN

## Core product law

**NO OFFLINE ECONOMIC AUTHORITY.** A draft composed without network is an intention only:
store, listing ids, quantities and destination words. Any cached price is drift evidence,
never a total, never a promise. Money, stock, availability and location quality are decided
by the server at revalidation and frozen at commitment.

## Server

- `marche_orders` gains `destination_label`, `destination_landmark`, `destination_instructions`
  and the server-derived `destination_quality`
  (`gps_verified` / `manually_placed` / `landmark_assisted` / `approximate` / `unverifiable`).
- `_marche_destination_quality(...)` — private derivation helper; not client-callable.
  A landmark alone never becomes a GPS claim.
- `marche_order_commit` accepts landmark intent, refuses `CLIENT_LOCATION_QUALITY_NOT_ALLOWED`,
  `INVALID_LOCATION_SOURCE`, `DESTINATION_TEXT_TOO_LONG`. Its idempotency fingerprint adds the
  destination extras **only when present**, so pre-R13 durable keys keep replaying to the same order.
- `marche_basket_revalidate(jsonb)` — STABLE, authenticated-only, read-only. Reserves no stock,
  touches no money rail, refuses a client subtotal, and reports per-line
  `ok / price_changed / quantity_unavailable / unavailable / review_required / not_found`
  with R12 refusals (`LISTING_QUARANTINED`, `STORE_SUSPENDED`) honoured.
- `marche_order_recover(text)` — STABLE, buyer-scoped lookup by `client_request_id` for a lost
  response. Cannot create a second order; other users and the merchant see nothing.

## Client

- `src/lib/net/boundedPoll.ts` — bounded attempts, jittered backoff, deadline, abort; always
  resolves. `isLostResponseError` separates a lost response from a definitive refusal.
- `src/lib/marche/basketDraft.ts` — durable, normalised, hostile-input-clamped offline draft.
- `src/lib/marche/orders.ts` — `revalidateMarcheBasket`, `recoverMarcheOrder`,
  `commitMarcheOrderResilient` (never blind-replays a mutation), `destinationQualityLabel`.
- `MarcheOrderReview` — offline-aware, revalidates before commit, landmark + instruction inputs,
  honest "le prix a changé" gate, recovery-aware confirmation.

## Certification

| Gate | Result |
| --- | --- |
| `_qa_node4_marche_r13` | 105 / 0 failed |
| Full machine-derived board (43 suites) | **4,400 executed / 0 failed** |
| tsgo | exit 0 |
| Vitest | 19 files / 155 tests passed |
| Non-drift | wallets, ledger, payables, payouts, profiles, auth users, orders, listings, stores, ops cases — all zero |

**NODE 4 · MARCHÉ R13 — CERTIFIED / LOCKED / FROZEN**
