---
name: Node 4 — Marché R6 ChopChop Staples Catalog (Stable)
description: Second commerce rail — ChopChop-managed normalized essentials catalog (category → commodity → variant → purchase option), sanitized public discovery, admin-only mutation. Certified 157/157, board 0 failures. LOCKED.
type: feature
---

# Node 4 — Marché R6: ChopChop Staples Catalog — LOCKED

## Scope
Separate ChopChop-managed reference rail. Never uses `marketplace_listings`, never invents stores/sellers.
No ordering, cart, procurement, shopper, payment, mission, price intelligence, rating, ranking, economics,
flag activation or deploy. Identity + unit truth only.

## Schema
- `marche_staple_categories` (11 seeded)
- `marche_staple_commodities` (20 seeded)
- `marche_staple_variants` (21)
- `marche_staple_purchase_options` (29)
Hierarchy: category → commodity → variant → purchase option. Active-state cascades downward.

## Normalization law
- `exact` — physical conversion knowable (sac 25 kg → 25 kg; bidon 5 L → 5 L)
- `unit_native` — sold per local unit (pièce)
- `non_comparable` — bunch / tas / undefined sack: never fabricated into kg

## Access posture
- Direct table grants to `anon`/`authenticated`: 0
- Mutation: admin-only SECURITY DEFINER RPCs, `search_path=public` pinned, `marche_staples_admin()` authenticated-admin only
- Read: `marche_staples_discover`, `marche_staple_get`, `marche_staple_categories_public` (sanitized: no price, no audit metadata)
- `has_role` remains non-executable by `anon` (Repas R8 invariant P15.5 preserved)

## Client
- `src/lib/marche/staples.ts` — typed read-only wrapper + honest `normalizationLabel`
- `src/components/marche/StaplesView.tsx` — read-only discovery UI
- `src/components/views/MarketView.tsx` — "Essentiels" tab (presentation only)

## Certification
- `_qa_node4_marche_r6()` → 157/157 PASS (deterministic across reruns)
- Frozen board (31 runnable suites): 2800 assertions, 0 failures
- Vitest 99/99, tsgo clean, prod build + PWA (134 precache entries) OK

## Known pre-existing (not R6)
`_qa_node3_repas_r7_semantics`, `_qa_node3_repas_r7_readtruth`, `_qa_node3_repas_r7_ext` raise
`RESTAURANT_NOT_PUBLISHED` standalone — legacy pre-R8 fixtures superseded by R8 publication truth.
Reproduces identically without R6 changes; out of R6 scope, frozen Repas harnesses untouched.

Status: LOCKED.
