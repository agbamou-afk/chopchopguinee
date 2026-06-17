---
name: chopmap-service-integration-route-observation-stable
description: Map Phase 2G — trusted merchant location resolver, service-flow route estimate wrapper with opt-in observation start, and idempotent route observation finalize wired into ride completion + mission delivery
type: feature
---
Locked candidate 2026-06-17 pending live smoke test. Phase 2G wires CHOP Maps into service flows WITHOUT touching pricing, fares, or wallet logic.

## Scope (delivered)
- `src/lib/maps/serviceLocations.ts` — `resolveTrustedMerchantLocation({merchant_store_id, restaurant_id, listing_id})` returns `{lat,lng,source,verification_status,confidence_score,warning}` with preference order: trusted_map_place → admin_verified_map_place → submitted_map_place → merchant_store_coordinates → restaurant_coordinates → listing_coordinates → missing. Never blocks orders; submitted/legacy sources carry an "À confirmer" warning.
- `src/lib/maps/serviceRouting.ts` — `getEstimateForActiveJob()` wraps `getRouteEstimate()` and, when an `activeJob` context is supplied and the provider fell back, opportunistically calls `startObservationIfEligible()`. `useServiceRouteEstimate()` hook for service flows. `zoneContext()` returns origin/destination commune labels and an `out_of_zone` flag for internal display only.
- `src/lib/maps/observationLifecycle.ts` — idempotent `startObservationIfEligible()` (keys on `source_module + source_id`, skips if a row already exists) and `finalizeObservationForSource()` (no-op when no observation; sets `verification_status='needs_review'` when caller passes `needsReview: true`). Fire-and-forget — every error path is swallowed.
- Wired finalize calls (fire-and-forget, never blocks):
  - `src/lib/missions/missions.ts` → `confirmDropoff` after `logEvent("delivered")`.
  - `src/hooks/useRideLifecycleNotifications.ts` → on `status === "completed"` and `status === "cancelled"` (driver role only); cancellations finalize as `needs_review`.

## Hard guarantees preserved
- No wallet hold / release path touched.
- No Moto fare, Repas pricing, or Marché pricing touched.
- Observations remain admin-only (`map_route_observations` RLS unchanged: admin SELECT/UPDATE, driver self INSERT, no anon).
- Observations never auto-trusted (`confidence_score=35`, `verification_status='submitted'`).
- Observations never customer-visible.
- Observation insert only fires when (a) caller provides `activeJob` context, AND (b) provider fell back. No browsing/search/admin diagnostic observations.
- Driver location signal failures don't affect service flows (independent layer).
- Routing failure does not block ride/mission completion (try/catch + fallback).

## Not in this phase
- UI surface changes inside RideBooking / LiveTracking / FoodCheckout / Marché are still consumer responsibility — `useServiceRouteEstimate` is available but not yet imported into those views. Adoption can ship incrementally without re-locking.
- Polyline collection from `driver_location_signals` not yet aggregated into `simplified_polyline_geojson` — finalize currently records summary-only.
- Repas/Marché observation start is supported by the API (`source_module: 'repas' | 'marche'`) but only triggers when a caller wires `getEstimateForActiveJob` with that context.

## QA expectations
A–O per phase brief; key invariants — Moto/Repas/Marché wallet amounts unchanged (M), public/customer access to `map_route_observations` blocked (K), build clean (O), service flows continue if routing fails (N).

## Files
- src/lib/maps/serviceLocations.ts (new)
- src/lib/maps/serviceRouting.ts (new)
- src/lib/maps/observationLifecycle.ts (new)
- src/lib/missions/missions.ts (finalize hook)
- src/hooks/useRideLifecycleNotifications.ts (finalize hook)