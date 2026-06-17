# CHOP Maps — Deployment Environment Checklist

## Frontend (`.env`, shipped to client)
Only the standard Lovable Cloud bootstrap values:
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `VITE_SUPABASE_PROJECT_ID`

No map provider keys. The map style URL and any publishable token come
from the `maps-config` Edge Function at runtime.

## Backend (Edge Function secrets, runtime-only)
Configured via `secrets--add_secret`, never committed:
- `MAPBOX_PUBLIC_TOKEN` — public token used by `maps-config` (publishable).
- `GOOGLE_MAPS_SERVER_KEY` — server-side routing/geocoding (if Google provider enabled).
- Optional: `ORS_API_KEY`, `GRAPHHOPPER_KEY` — alternative providers.

Auto-managed (do not rotate manually):
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` — injected into Edge Functions.

## Edge Functions to deploy
- `maps-config` — returns publishable style + token; rate-limited.
- `maps-route` — routing proxy with provider fallback.
- `maps-eta`, `maps-search` — optional helpers.
- `driver-location-publish` — driver signal RPC entry point.

## Frontend secret audit (run before deploy)
```bash
rg -n "GOOGLE_MAPS|MAPBOX_SECRET|ORS_API|GRAPHHOPPER|SERVER_KEY" src/
```
Expected: no matches. Any match is a launch blocker.

## Provider-down behavior
- `maps-route` returns `{ fallback_used: true }` → frontend `RouteEstimateChip`
  shows "Estimation approximative". App keeps working.
- `maps-config` failure → `ChopMap` renders `DegradedMapPanel` (or
  `MapFallbackCard` when no degraded fallback prop is provided).

## PWA / offline
- Service worker registered via `src/lib/pwa/registerPwa.ts`.
- Field visit drafts persist in `localStorage` (`cc:field_visit_drafts:v1`).
- No offline tile cache. No offline media queue. These are deferred.