---
name: Node 4 — Marché R3.5 Basket & Fulfillment Intelligence Foundation (Stable)
description: Locked R3.5 — immutable basket/distance profiles, append-only fulfillment milestones, derived-only observations, descriptive P50/P75/P90 cohorts. No money, no ETA, no prediction, no dispatch effect.
type: feature
---
# node4-marche-r35-basket-fulfillment-intelligence-foundation — LOCKED

## Product law (enforced, not aspirational)
1. OBSERVE BEFORE PREDICT — history only, never an estimate or promise.
2. Basket dimensions are server-derived at commit and immutable thereafter.
3. Distance integrity: `distance_method = 'geodesic'` only; road and geodesic are never mixed.
4. Fulfillment mode is explicit; unknown is stored as `unspecified`, never guessed.
5. Milestones are append-only (`ORDER_COMMITTED` … `DELIVERED`), idempotent on `(order_id, event_type, source_key)`.
6. Observations exist only when both endpoints exist; they are derived-only and immutable.
7. Cohort output is descriptive statistics (P50/P75/P90, sample_count, confidence, freshness) — thin samples return `insufficient_data`, never an invented number.
8. No money, no ETA, no PII in this layer.

## DB surface
- Tables: `marche_fulfillment_profiles`, `marche_fulfillment_events`, `marche_fulfillment_observations`; `category_snapshot` added to `marche_order_items`.
- Functions: `marche_fulfillment_profile_create`, `marche_fulfillment_event_append`, `marche_fulfillment_recompute_observations`, `marche_fulfillment_cohort_stats`.
- Admin reads: `marche_fulfillment_profile_admin`, `marche_fulfillment_events_admin`, `marche_fulfillment_observations_admin`, `marche_fulfillment_cohorts_admin`.
- `marche_order_commit` atomically writes the profile + `ORDER_COMMITTED` event.
- Direct table CRUD revoked from `anon` and `authenticated`; every definer function pins `search_path = public`.
- Observation guard: one-shot, row-bound internal token (`marche.fulfillment_derive_token`) + trigger covering INSERT/UPDATE/DELETE → `FULFILLMENT_OBSERVATION_DERIVED_ONLY`.

## Wiring state (deliberate)
- Only `ORDER_COMMITTED` is production-wired. All other milestones are reserved vocabulary awaiting real merchant/courier events.
- Fulfillment mode at commit is `unspecified`.
- No customer-facing surface. Client module `src/lib/marche/fulfillmentIntelligence.ts` is admin/internal read + descriptive labelling only and suppresses insufficient cohorts.

## Certification at lock
- `_qa_node4_marche_r35()` 198/198 · `_qa_node4_marche_r3()` 136/136 · R2 82/82 · R1.5 38/38 · R1 55/55.
- Full frozen board: 29 suites, 2837 assertions, 0 failures (Course, Bonbonna, Taxi, Repas R1–R11, Pickup, Slice13, Marché).
- Client gates: tsgo clean, Vitest 99/99 (incl. `src/test/node4-marche-r35-measurement.test.ts`), production build clean.
