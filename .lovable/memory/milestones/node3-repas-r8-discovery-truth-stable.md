---
name: Node 3 Repas R8 — Discovery Truth
description: Server-authoritative Repas publication/discovery model; staff-only publication; no fake restaurants, ratings, ETA or distance
type: feature
---

# Node 3 Repas R8 — Discovery Truth (LOCKED)

## Contract
- Three distinct concepts, all server-derived: **visible** (published supply only),
  **open** (`is_open`), **orderable now** (`orderable_now` + `blocked_reason`).
- Publication signal = `food_restaurants.verification_state`
  (`none`=brouillon, `verified`=publié, `suspended`, `rejected`).

## Server
- `repas_restaurants_discover(text,int)` — published supply only, excludes zero-menu
  restaurants, no rating/ETA/distance dimension, never exposes `owner_user_id`.
- `repas_restaurant_public(uuid)` — participant-scoped detail; owner/staff may see drafts.
- `repas_restaurant_menu_public(uuid)` — real menu of published restaurants only.
- `repas_admin_set_publication(uuid,text,text)` — staff only, audited in `audit_logs`.
- `_food_restaurant_guard` trigger — owners cannot self-publish, self-enable Chop Pay,
  change `status`, reassign owner or link a merchant store.
- RLS on `food_restaurants` / `food_menu_items`: public SELECT requires
  `status='active' AND verification_state='verified'` (owner/staff bypass).

## Client
- `src/lib/repas/discovery.ts` is the only customer-facing discovery seam.
- `FoodView`, `RestaurantCard`, `UserHome` rail and `RepasRestaurantDetail` render server
  truth only; the fake restaurant catalogue and fake LiveStrip claims were deleted.
- Merchant onboarding no longer sends privileged columns; Chop Pay is staff-activated.
- `/admin/repas` exposes Publier / Retirer / Suspendre / Refuser.

## Certification
- `public._qa_node3_repas_r8_discovery()` — **89/89 PASS**.
- Typecheck exit 0, Vitest 46/46 PASS.

## Post-landing closeout (2026-08-14 19:0x UTC)
- Merchant onboarding no longer submits `status` / `choppay_enabled` / `owner_user_id`
  on update (`createOrUpdateRestaurant`), and `listOpenRestaurants` was deleted —
  customer discovery has exactly one seam.
- `/admin/repas` now has the publication queue (Publier / Retirer / Suspendre / Refuser),
  a real menu-item count per restaurant, and a "Publiés" stat. Publishing is disabled
  when the restaurant has zero menu items.
- Guard fallout fixed: `_qa_node3_repas_r5_runtime` is now a thin wrapper that sets
  `app.repas_publication_ctx` before delegating to `_qa_node3_repas_r5_runtime_core`
  (its fixture seeds a suspended restaurant). Guard itself was NOT weakened.

## Verified board
- R8 89/89, R7 203/203, R6 171/171, R5 71/71, R5 runtime 91/91, Pickup 64/64,
  R1–R4 148/148, Node 0 34/34, Node 1 78/78, Node 2 97/97 — all PASS.
- Slice 13 finance: parts 1/2/3/6 PASS (18, 32, 54, 87) via the QA runner.
  Parts 4/5/7 use `SET ROLE` and can only be executed by a direct privileged
  postgres session — not reachable through the edge runner. Pre-existing limitation,
  unchanged by R8.
- Typecheck exit 0, Vitest 46/46, production build PASS (134 precache entries).
