---
name: CHOP Map Phase 2F — Driver Location Signals (PROVISIONAL)
description: Driver location signal layer + route observation hooks. Awaiting smoke test.
type: feature
---

# chopmap-driver-location-signals-stable (PROVISIONAL)

## Scope
- `driver_location_signals` (latest-only) + RLS (self/admin/service)
- `driver_update_location_signal` RPC — validates coords, verifies ride/mission assignment, prevents spoofing
- `driver_mark_offline_signal` RPC — clears precise speed/heading on go-offline
- `useDriverLocationSignal` hook — 60s idle / 20s on-trip, paused offline/hidden/save-data
- Mounted in `DriverSessionContext` alongside `useDriverPresence`
- Admin page `/admin/map/driver-signals` — internal, polled 30s, freshness badges (live/recent/stale)
- `src/lib/maps/observations.ts` — start/finalize hooks for `map_route_observations` (admin-only, confidence 35, never trusted)

## Hard exits
- Drivers can only write their own signal; ride/mission spoofing rejected at RPC level
- Public/anon blocked
- No customer-visible raw traces
- No pricing path touched
- No background tracking outside online/active job
