---
name: CHOP Map Phase 2F — Driver Location Signals (PROVISIONAL)
description: Driver location signal foundation + observation-ready hooks. Lifecycle wiring deferred to 2G.
type: feature
---

# chopmap-driver-location-signals-stable (PROVISIONAL)

## Scope — what IS in this phase
- `driver_location_signals` (latest-only) table + RLS (self / admin / service)
- `driver_update_location_signal` RPC — coord validation, ride/mission spoof prevention
- `driver_mark_offline_signal` RPC — clears precise speed/heading on go-offline
- `useDriverLocationSignal` hook — 60s idle / 20s on-trip / 90s save-data
- Mounted in `DriverSessionContext` alongside existing `useDriverPresence`
- `/admin/map/driver-signals` admin page — internal, 30s polling, live/recent/stale freshness
- `src/lib/maps/observations.ts` — `startRouteObservation` / `finalizeRouteObservation` helpers (admin-only target, confidence 35, never auto-trusted)

## Scope — what is explicitly NOT in this phase
- **Route observation lifecycle wiring is DEFERRED to Phase 2G.** Helpers exist but are not yet called from ride or mission state machines, so no observation rows are produced in production yet. This phase ships the foundation + observation-ready hooks, not full route-learning automation.

## Hard exits (verified at code/RLS level)
- Drivers write only their own signal; spoofed ride/mission rejected at RPC
- Public/anon blocked from `driver_location_signals`
- No customer-visible raw traces
- No pricing path touched
- No background tracking outside online or active job
