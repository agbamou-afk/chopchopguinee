---
name: Map Phase 2H — Offline / Low-data Map Hardening (Stable)
description: Connectivity state bus, degraded map panel, lightweight TTL cache, field visit offline drafts, routing defensive guards
type: feature
---

# chopmap-offline-lowdata-map-hardening-stable

Locked 2026-06-17. Adds graceful degradation across CHOP Maps for slow
networks, tile failures, low-data mode, GPS denial, and brief offline
periods. No pricing/wallet logic, no route observation trust changes,
no realtime polling.

## Surfaces

### Connectivity bus — `src/lib/maps/connectivity.ts`
- `useMapConnectivityState()` returns `{ isOnline, isLowDataMode, tileStatus, routingStatus, geolocationStatus, userMessage }`.
- Event-driven (no polling). Listens to `online`/`offline`, custom map events, `cc:lowdata`, and Permissions API.
- `reportTileStatus`, `reportRoutingStatus`, `reportGeolocationStatus` — emitters used by ChopMap and routing.

### ChopMap signals — `src/components/map/ChopMap.tsx`
- Emits `ready` on map load, `failed` on tile error / config error, `degraded` in low-data mode.

### Routing hardening — `src/lib/maps/routing.ts`
- Rejects invalid lat/lng (`NaN`, out-of-range) with safe fallback (no crash).
- Short-circuits to fallback when `navigator.onLine === false`.
- Emits `routingStatus: ready | fallback | failed` for the connectivity bus.
- Caching + provider fallback behavior preserved from Phase 2E.

### Degraded panel — `src/components/map/DegradedMapPanel.tsx`
- Calm fallback surface: pickup/dropoff, distance/ETA, zone label, nearby places, retry + continue actions.
- Drop-in replacement for ChopMap when callers need richer fallback than `MapFallbackCard`.

### Lightweight client cache — `src/lib/maps/clientCache.ts`
- TTL'd `localStorage` cache for safe reference data: service zones, verified places, route estimates, merchant locations, admin filters.
- Explicitly never used for driver traces, route observations, secrets, or provider keys.

### Field visit offline drafts — `src/lib/maps/fieldDrafts.ts` + `src/pages/field/FieldVisit.tsx`
- Offline submissions persist locally as drafts (`draft` / `pending_retry` / `failed`).
- Drafts list shown in the field UI with explicit Renvoyer / Supprimer controls — no silent auto-submit.
- Photos/media explicitly NOT queued offline — text/coordinates only.

## Hard guarantees
- No pricing, wallet, or fare mutation.
- No route observation trust changes (still learning data only).
- No driver signal exposure outside admin.
- No new realtime channels, no polling timers, no heavy dependencies.
- No provider key exposure (routing stays through existing abstractions).
- Map tile/routing failures never block ride / mission / field / merchant submission flows.

## Deferred
- Offline media queue for field photos.
- IndexedDB migration if localStorage limits become a problem.
- Background sync via service worker (PWA scope).