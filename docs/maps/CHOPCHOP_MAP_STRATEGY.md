# CHOPCHOP Map Strategy

_Status: living document — updated as the map stack evolves._

## Why this exists

CHOPCHOP runs ride-hailing, food, market, deliveries, and wallet flows on top
of one map surface. The current engine is **Mapbox GL JS** via `react-map-gl`,
wrapped by `ChopMap`. Before we evaluate any engine swap, we must guarantee
two things:

1. **Live location is real.** The map never pretends a fallback center
   (Conakry / Kaloum) is the user's position.
2. **Fallback is honest.** When GPS is denied, unavailable, or stale, the UI
   labels the map as a Conakry fallback and offers an explicit "Activer ma
   position" CTA — never a silent lie.

These rules are enforced by `src/lib/location/useLiveUserLocation.ts`. See
the hook for the canonical contract.

## Current stack (Stage 1)

- **Tiles & rendering:** Mapbox GL JS via `react-map-gl` (`ChopMap.tsx`).
- **Routing:** pluggable via `RoutingService` — providers under
  `src/lib/maps/providers/` (Google, OSRM, GraphHopper).
- **External navigation fallback:** Google / Apple Maps deep links
  (`src/lib/maps/external.ts`).
- **Map config:** `maps-config` edge function returns Mapbox public token,
  style URL, default center (Conakry), and provider flags.
- **Live driver positions:** `useDriverLocation` + `DriverMarker`.
- **Customer discovery layer:** `VendorDiscoveryLayer` — capped at 50 pins,
  vendor-only, never exposes customers/couriers/private sellers.
- **Low-data mode:** `chop-map-fallback` skin replaces tile rendering with a
  static branded surface.

## Stage 2 — local intelligence

Before we touch the engine, build CHOPCHOP-specific spatial data:

- Gazetteer of Conakry neighborhoods, landmarks, KM markers
- Merchant public pins (already partially shipped via `VendorDiscoveryLayer`)
- Pickup / dropoff corrections submitted by drivers and customers
- Support-issue geography (wrong address, GPS failure, route failure zones)
- Aggregated district-level demand signals

See `CHOPCHOP_URBAN_INTELLIGENCE_LAYER.md` for the data model and privacy
rules.

## Stage 3 — aggregate operational signals

Once we have the data above, we can power:

- District demand heatmaps (aggregate, not individual trails)
- Driver supply gaps by hour / district
- Wrong-address hotspots
- Route-failure zones
- Delivery-friction maps

These views go into the Command Center, never into customer-facing surfaces.

## Stage 4 — engine evolution (not now)

Possible directions, evaluated only after Stages 1–3 are stable:

- **Continue Mapbox.** Lowest risk; we keep building on top.
- **MapLibre + self-hosted vector tiles.** Removes the Mapbox bill and the
  third-party dependency, but adds ops cost (tile pipeline, style maintenance).
- **OSM-based self-hosted tiles.** Same as above but starting from OSM data
  directly.
- **Hybrid routing.** Keep Mapbox for rendering, swap routing per region or
  vehicle type (Google for cars in dense Conakry, OSRM for motos elsewhere).
- **CHOPCHOP spatial data layer.** Our own overlay (KM markers, gazetteer,
  corrections) sitting on top of whatever base map we use.

**Do not switch engines prematurely.** Engine choice should follow data
maturity, not the other way around.

## Performance guardrails

These apply regardless of engine:

- Memoize markers; never recreate marker arrays on every render.
- Cap vendor pins (50 is the current ceiling).
- Throttle geolocation updates (max one update per ~5 s for passive screens).
- Avoid remounting `ChopMap` on parent re-renders.
- Lazy-load map-heavy screens (`React.lazy` + `Suspense`).
- Prefer the low-data static skin where full interactivity is not needed.
- Cluster driver pins for any view with more than ~30 visible drivers.

## Rules of engagement

- Never label a fallback as the user's location.
- Never bias "near you" copy when we are showing a fallback.
- Never let a driver go online without a real location fix (enforced per
  surface — pending).
- Never expose raw user or driver location trails to non-admin clients.