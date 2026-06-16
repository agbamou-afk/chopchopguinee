---
name: chopmap-routing-eta-foundation-stable
description: Map Phase 2E — routing/ETA abstraction with haversine fallback, internal tronçon compare, admin diagnostics, and map_route_observations learning table
type: feature
---
Locked 2026-06-16. Map Phase 2E delivered foundation infrastructure only — no customer pricing, no live tracking.

## Provider abstraction
`src/lib/maps/routing.ts` exports `getRouteEstimate({origin,destination,mode,providerPreference,timeOfDay,bypassCache})` returning `{distance_meters, duration_seconds, polyline_geojson, provider, confidence (high|medium|fallback), fallback_used, warning, mode}`.
- Wraps existing `RoutingService` (google/osrm/graphhopper); on any provider error it returns `fallbackEstimate()` with provider `"chop_fallback"`, confidence `"fallback"`, and warning "Estimation approximative — trajet à confirmer".
- 60s in-memory memoization keyed by 5-decimal coords + mode; <50 m straight-line short-circuits to fallback.

## Fallback model
Road factor moto×1.35 / car×1.45 / walking×1.10. Speeds (km/h): moto day 22 / night 28, car 18/24, walking 4.5/4.5. `timeOfDayNow()` splits at 06:00/19:00. Polyline is a 2-point LineString between endpoints.

## Tronçon comparison (internal only)
`compareRouteToObservedTroncons({originName,destinationName,timeOfDay})` — exact lowercase match on `map_fare_troncons` (bidirectional aware). Returns `{price_gnf, troncon_id, verification_status, label}` with label "Tarif local observé — Non officiel — À vérifier" or `null`. Never used for wallet/fare mutations.

## Route observation learning table
`public.map_route_observations` (source_module ride|mission|repas|marche|manual, source_id, driver_user_id, origin/destination lat/lng, observed_distance_meters, observed_duration_seconds, observed_polyline_geojson, simplified_polyline_geojson, provider_used, fallback_used, confidence_score=35, verification_status submitted|field_checked|admin_verified|trusted|needs_review, status recorded|reviewed|rejected|promoted, notes).
RLS: admins SELECT+UPDATE, drivers INSERT only their own, no public/anon. Helpers: `recordRouteObservation`, `listRouteObservations`, `updateRouteObservationStatus`. Collection hooks not yet wired into ride/mission lifecycles — caller responsibility.

## Admin diagnostics
`/admin/map/routing` (`MapRoutingAdmin.tsx`) — provider vs fallback test, tronçon exact-match test, observation list with mark-reviewed / trust / reject actions. Linked in AdminSidebar under Carte.

## Hard exit criteria met
- route estimate works ✓
- fallback works without provider ✓
- map crash-safe (try/catch around provider) ✓
- ETA labeled approximate when fallback ✓
- tronçon tariffs stay internal/non-official ✓
- wallet/fare pricing untouched (no integration with Moto/Repas/Marché yet) ✓
- admin diagnostics exists ✓
- build clean ✓

## Files
- supabase/migrations/..._map_route_observations.sql (new table + RLS + grants)
- src/lib/maps/routing.ts (new)
- src/pages/admin/MapRoutingAdmin.tsx (new)
- src/App.tsx (route)
- src/components/admin/AdminSidebar.tsx (nav entry)
