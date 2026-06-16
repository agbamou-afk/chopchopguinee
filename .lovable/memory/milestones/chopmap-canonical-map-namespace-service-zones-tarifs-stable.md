---
name: CHOP Maps Canonical Namespace & Service Zones — Stable
description: Milestone locked 2026-06-16. Canonical map_* namespace, service zones v0.2, place verification UI, driver reports (light), 40 seeded moto tronçons.
type: feature
---
Locked 2026-06-16.

**Canonical tables (do not duplicate, do not rename):**
- `map_service_zones` — operational zones (name, commune, district, center/radius or boundary_geojson, status, priority, services_enabled jsonb, verification, confidence, ops/driver/merchant/coverage notes)
- `map_places` — canonical place intelligence (name, aliases, category, commune, neighborhood, lat/lng, verification, confidence, duplicate_of, pickup/entrance/landmark/operational notes)
- `map_driver_reports` — field signals (admin + reporter visibility only; no anon)
- `map_fare_troncons` — field-observed Conakry moto fares (admin-only; not public; not official customer pricing)

**Shared vocabulary:** enum `map_verification_status` = unverified | submitted | field_checked | admin_verified | trusted | needs_review | duplicate | closed. Default confidence ladder 20/35/60/80/95/30/10/0 lives in `map_default_confidence()` and frontend `DEFAULT_CONFIDENCE`.

**Admin surfaces:**
- `/admin/map/zones` → `MapZonesAdmin`
- `/admin/map/places` → `MapPlacesAdmin`
- `/admin/map/tarifs` → `MapTariffsAdmin`
- Sidebar group "Carte" — module `zones`.
- Legacy `/admin/zones` (district_hubs) intact and untouched.

**Driver-report trigger contract:** a new report sets `last_reported_at`; only downgrades verification_status to `needs_review` when the place is currently unverified / submitted / field_checked. Trusted and admin_verified places are flagged but never auto-downgraded.

**Rules going forward:**
- Never grant anon read on `map_driver_reports` or `map_fare_troncons`.
- Never expose `map_fare_troncons` prices as official customer pricing without an explicit phase upgrade.
- Never destructively delete places/zones/tronçons from the UI — use status changes (`closed`, `duplicate`, `needs_review`) or `active=false`.
- `estimateMotoFareByTroncon()` in `src/lib/maps/canonical.ts` is internal-only; returns null when there is no exact (or bidirectional) match.
- All 40 seeded tronçons start as `submitted` / confidence 60 / `is_bidirectional=true` / `is_active=true`, with both place_ids null ("À géocoder"). Reseed is idempotent via the unique index on `lower(raw_*)`.

**Out of scope at lock time (do not silently expand):** routing/ETA, live driver tracking, merchant self-location submission, full driver-report admin queue, customer-facing fare prices, migration of `district_hubs` into `map_service_zones`.