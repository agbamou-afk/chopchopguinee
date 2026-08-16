---
name: Node 4 Marché R1.5 — Approved Merchant Supply Doctrine
description: Marché supply law — only approved, active merchant stores may originate orderable listings; storeless/community supply refused with MERCHANT_STORE_REQUIRED
type: feature
---
# Node 4 — Marché R1.5 (LOCKED)

Marché is not classifieds. Only an approved (`onboarding_status='approved'`), active
(`status='active'`) merchant store owned by the seller may originate production-orderable supply.

## Canonical law
- `v_marche_listing_truth`: first refusal is `MERCHANT_STORE_REQUIRED` when `store_id IS NULL`
  or `kind <> 'merchant'`. Then removed/sold/paused/private/banned/store-not-approved/demo/stock/price.
- `marche_publication_guard`: storeless or non-merchant rows are forced `visibility='private'`,
  `status='paused'`.
- `marche_listing_create`: raises `MERCHANT_STORE_REQUIRED` without a store, `NOT_STORE_OWNER`
  for a store the caller does not own; always forces `kind='merchant'`.
- `marche_listing_publish`: raises `MERCHANT_STORE_REQUIRED` for storeless listings.
- Legacy/community/demo rows are quarantined (paused + private), never deleted.

## Client
- `getSellerEligibility()` in `src/lib/marche/stores.ts` is the single client gate.
- `MarketView` FAB shows "Devenir marchand" → `/merchant/onboarding` unless the store is approved.
- `SellFlow` refuses to open the wizard without an approved active store.

## Evidence at lock
- `_qa_node4_marche_r15()` 38/38, `_qa_node4_marche_r1()` 55/55.
- Full frozen board 2006 checks / 0 failures (Nodes 0–4 + Slice 13 507).
- Vitest 71/71, tsgo exit 0, production + PWA build OK.
- Supply: 53 listings preserved, 48 storeless quarantined, 47 demo quarantined,
  5 orderable — all in approved active stores. `anon` still cannot execute `has_role`.

No feature activation, no deployment, no finance/mission/payment change.
