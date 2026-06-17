---
name: Map Phase 2L — Pilot Launch Readiness (Stable)
description: CHOP Maps documentation, role matrix, smoke script, recovery notes — pilot deployable
type: feature
---

# chopmap-pilot-launch-readiness-stable

Locked 2026-06-17. Packages the entire CHOP Maps stack (Phases 2A–2H)
into a pilot-deployable bundle. No new features, no pricing/wallet
changes, no privacy regression.

## Deliverables
- `docs/maps/pilot/CHOPMAP_PILOT_LAUNCH_CHECKLIST.md`
- `docs/maps/pilot/CHOPMAP_ROLE_ACCESS_MATRIX.md`
- `docs/maps/pilot/CHOPMAP_DEPLOYMENT_ENV.md`
- `docs/maps/pilot/CHOPMAP_PILOT_SMOKE_TEST.md`
- `docs/maps/pilot/CHOPMAP_FIELD_OPERATOR_GUIDE.md`
- `docs/maps/pilot/CHOPMAP_ADMIN_OPERATIONS_GUIDE.md`
- `docs/maps/pilot/CHOPMAP_KNOWN_LIMITATIONS.md`
- `docs/maps/pilot/CHOPMAP_RECOVERY_ROLLBACK.md`

## Audit summary
- Surfaces: client map, ride active map, mission card, driver signal,
  merchant location submission, field visit, field captain review, and
  all `/admin/map/*` pages confirmed present and routed.
- Frontend secret audit: `rg "GOOGLE_MAPS|MAPBOX_SECRET|ORS_API|GRAPHHOPPER|SERVER_KEY" src/` → no matches.
- RLS posture: driver signals and route observations remain admin/owner
  only; merchant submissions scoped to owner; field reports scoped to
  agent/captain.
- Degraded UX: `DegradedMapPanel` wired into `ActiveTripMap` and
  `ActiveMissionCard` via the `degradedFallback` render prop on `ChopMap`.
- Offline: `cc:field_visit_drafts:v1` persists field drafts; manual
  resend only.

## Hard guarantees
- No pricing, wallet, or fare mutation.
- No route observation trust changes.
- No public exposure of driver signals or route observations.
- No server-only provider keys in `src/`.
- Build clean.

## Deferred (post-pilot)
- Service worker background sync for field drafts.
- Offline tile cache.
- Offline media/photo queue.
- Lightweight pilot health panel (documentation-only for now; a real
  dashboard would risk scope creep beyond 2L).