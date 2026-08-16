---
name: Node 4 Marché R1 — Listing Publication Truth (certified stable)
description: Locked 2026-08-16 — canonical Marché listing truth, unified publication guard, server-authoritative mutation RPCs, discovery read model, demo quarantine, media privacy, 55/55 QA
type: feature
---
# node4-marche-r1-listing-publication-truth — CERTIFIED STABLE (2026-08-16)

Frozen. Do not modify Marché R1 primitives without a new R-pass.

## Canonical primitives
- `v_marche_listing_truth`, `marche_listing_truth(uuid)` — derives `is_orderable` + refusal reason
  (`DEMO_SUPPLY`, `STORE_NOT_APPROVED`, `SELLER_NOT_ELIGIBLE`, `LISTING_PAUSED`, `OUT_OF_STOCK`, `NO_PHOTO`).
- `marche_publication_guard()` — single trigger replacing `enforce_listing_visibility` +
  `marche_enforce_pending_merchant_privacy`; covers community (`store_id IS NULL`) listings.
- Mutation RPCs (SECURITY DEFINER, only write path): `marche_listing_create`, `_update`,
  `_set_stock`, `_adjust_stock`, `_set_availability`, `_publish`, `_unpublish`, `_archive`.
- Discovery read model: `marche_listings_discover`, `marche_listing_public`,
  `marche_store_listing_previews`.
- Direct INSERT/UPDATE/DELETE on `marketplace_listings` REVOKED from anon+authenticated
  (SELECT only). `prevent_seller_protected_columns` honours the RPC path via `marche.rpc`.

## RLS contract (final)
- `merchant_stores` public read is SPLIT BY ROLE:
  - `Anon read approved stores` (TO anon): `status='active' AND onboarding_status='approved'` only.
  - `Auth read stores` (TO authenticated): approved OR owner OR admin OR onboarding_specialist.
  Reason: `has_role` is NOT granted to anon (granting it broke frozen Repas R8 invariant P15.5).
  Any anon-reachable policy must therefore never call `has_role`.
- `marketplace_listings` / `listing_images` admin policies are `TO authenticated` only;
  anon paths contain no role-helper calls. `listing_images` public read gated on
  `marche_listing_is_public()`.

## Demo quarantine
47 seeded 2026-05-14 listings are non-orderable and hidden from discovery; 0 rows deleted.

## Certification (2026-08-16, after final policy edit)
Node 4 R1 `_qa_node4_marche_r1()` 55/55. Frozen board all 0 failures: Course 34, Bonbonna 78,
Taxi 97, Repas R1–R4 148, Pickup 64, R5 runtime 91, R6 171, R7 203, R8 202, R9 68, R10 134,
R11 116, Slice 13 runs 1–7 = 507. Vitest 71/71, tsgo clean, production+PWA build OK.
No feature-flag, finance, ledger, mission, or courier change.
