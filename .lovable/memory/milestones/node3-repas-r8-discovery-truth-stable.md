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
