# CHOP CHOP Mapping System

A production-grade map layer built on **Mapbox GL JS** for rendering and **Google Directions/Distance Matrix** (proxied via edge functions) for routing and ETA — wrapped in a provider abstraction so we can swap to GraphHopper or OSRM later without touching the UI.

## What gets built

### 1. Secrets & config
- `MAPBOX_PUBLIC_TOKEN` — Mapbox public token (pk.*). Safe in frontend, but stored as a runtime secret and exposed via a tiny `map-config` edge function so we can rotate it without redeploying the SPA.
- `GOOGLE_MAPS_SERVER_KEY` — restricted server key, never sent to the browser.
- New table `map_provider_settings` for default provider, style URL, default zoom/center, and feature flags (heatmaps, clustering, surge).

### 2. Routing provider abstraction (`src/lib/maps/`)
```text
src/lib/maps/
  providers/
    types.ts          ← RouteProvider interface (route, eta, matrix, snap)
    googleProvider.ts ← calls our edge proxy
    osrmProvider.ts   ← stub, ready
    graphhopperProvider.ts ← stub, ready
  RoutingService.ts   ← picks provider via env/flag, caches, retries
  geo.ts              ← haversine, bbox, decode polyline, bearing
  zones.ts            ← Conakry quartiers/communes lookup
  markerIcons.ts      ← SVG factory for moto/toktok/food/wallet/marche/pin
```

The `RouteProvider` interface returns a normalized `Route { polyline, distanceM, durationS, steps[], bbox }` so callers never care which engine produced it.

### 3. Edge functions (Google key stays server-side)
- `maps-route` — POST `{origin, destination, mode, waypoints?}` → calls Google Directions, returns normalized route. Per-user rate limit, audit log row in `ai_request_log`-style table `maps_request_log`.
- `maps-eta` — POST `{origins[], destinations[]}` → Distance Matrix, normalized.
- `maps-config` — GET → returns Mapbox public token + style URL + active feature flags. Cached 5 min.
- `driver-location-publish` — POST `{lat,lng,heading,speed,status}` → upserts into `driver_locations` (admin/auth-only, driver writes own row).

### 4. Realtime driver tracking
- Table `driver_locations(user_id pk, lat, lng, heading, speed, status, updated_at)` with RLS: driver writes own row, admins read all, clients read only the driver assigned to their active ride.
- Realtime publication enabled.
- Hook `useDriverLocation(driverId)` subscribes via supabase realtime channel.
- Smooth interpolation: client keeps `{from, to, t0}` and on each animation frame lerps marker position + bearing → markers glide instead of teleport. Re-target on each new event.

### 5. Map components (`src/components/map/`)
- `<ChopMap />` — Mapbox container, applies CHOP CHOP theme, exposes imperative ref for fitBounds/flyTo.
- `<MapMarker />` — SVG marker with variants: `moto`, `toktok`, `food`, `wallet`, `marche`, `pickup`, `dropoff`. Props: `state` (online/offline/busy), `pulse`, `rotation`, `selected`.
- `<DriverMarker />` — wraps MapMarker + interpolation hook.
- `<DriverCluster />` — Mapbox GL clustering at low zoom, expands at high zoom.
- `<RoutePolyline />` — animated draw-on with gradient stroke (primary → primary-glow), updates live when re-routed.
- `<PinSet />` — pickup/dropoff with pulse on the active leg.
- `<HeatmapLayer />` (scaffolded, hidden behind `flag:heatmap`).
- `<SurgeZonesLayer />` (scaffolded, hidden behind `flag:surge`).

### 6. CHOP CHOP map theme
- Custom Mapbox style URL (set via `maps-config`); fallback uses `mapbox://styles/mapbox/light-v11` overridden at runtime: muted roads, hidden POI labels, emerald water, sand land, and our service-marker palette layered above.

### 7. Wire into existing flows
- `RideBooking` — replace static route preview with `<ChopMap>` + `RoutingService.route()` for ETA and polyline; pickup/dropoff pins; nearby driver cluster.
- `Activity` (active ride) — live driver marker with smooth glide, ETA refreshing every 20 s.
- `UserHome` — small map preview showing nearby moto/toktok markers (read from `driver_locations` filtered to ~3 km radius).
- `Marche`, `Repas` — pickup pin + ETA badge on listing detail.
- `AgentTopup` map of nearby wallet agents.

### 8. Future-proof (scaffolded, off by default)
- Heatmap layer driven by `analytics_events` aggregations.
- Surge zones layer driven by ride demand RPC.
- Geofence helpers in `lib/maps/geofence.ts`.
- Dispatch hooks (`useDispatchCandidates`) returning ranked drivers — stub today.
- Delivery batching helper (`batchByCorridor`) — stub today.

## Technical details

- Mapbox SDK: `mapbox-gl` + `react-map-gl` v7 (uses Mapbox GL under the hood, idiomatic React).
- Realtime: Supabase Realtime channel `driver-locations` per zone for fanout efficiency.
- Interpolation: requestAnimationFrame loop; clamp to 1 s window so a stalled feed doesn't drag markers across the city.
- Caching: in-memory LRU for routes keyed by `origin|dest|mode`, 60 s TTL. Distance Matrix cached 30 s.
- Rate limits: 60 route calls/user/min, 120 ETA/min, enforced in edge functions via existing `ai_rate_limits`-style pattern (new `maps_rate_limits` table).
- Audit: every server route/ETA call inserts into `maps_request_log` (admin-only RLS).
- Bundle: Mapbox is heavy (~700 KB gz). Lazy-load `<ChopMap>` via `React.lazy` so initial home stays fast.
- Accessibility: markers have aria-labels; the map view has a "list view" toggle for screen-reader users.

## What I need from you before building

1. **Mapbox public token** (`pk.*`) — get one free at mapbox.com/account → tokens. I'll store it as a runtime secret.
2. **Google Maps server key** with Directions API + Distance Matrix API enabled, restricted by IP/referrer to Lovable Cloud functions only.
3. (Optional) A custom Mapbox **style URL** if you already have one; otherwise I'll ship a tuned default.

Once those are in place I'll build in this order: secrets + edge proxies → provider abstraction → `<ChopMap>` + theme → markers + interpolation → driver_locations table + realtime → wire into RideBooking and Activity → scaffold heatmap/surge/dispatch placeholders.
