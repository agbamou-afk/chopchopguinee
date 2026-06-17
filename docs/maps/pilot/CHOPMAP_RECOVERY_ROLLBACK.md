# CHOP Maps — Recovery & Rollback Notes

Use these procedures if a pilot incident degrades the map layer. None of
them require code rollback — most are runtime toggles.

## 1. Disable optional map layers
- `/admin/settings` → toggle "Driver signals layer", "Route observations layer".
- Pages keep rendering; layers hide.

## 2. List-only mode
- If tiles fail repeatedly across the fleet, set `feature_flags.map_list_only = true`.
- `ChopMap` callers should already accept `degradedFallback`. Surfaces
  fall back to the rich `DegradedMapPanel` with pickup/dropoff/ETA.

## 3. Keep field visits going if tiles fail
- Agents continue using `/field/visit` — coordinate capture uses raw
  GPS, not the tile layer.
- Offline drafts persist; agents resend when back online.

## 4. Force fallback routing
- Disable the provider key in the `maps-route` Edge Function secrets, or
  set `map_provider_settings.routing_enabled = false`.
- Frontend will show "Estimation approximative" but flows continue.

## 5. Pause driver signal display without disabling driver app
- Remove SELECT on `driver_location_signals` for the admin role
  temporarily (or hide the route in `AdminSidebar`).
- Drivers keep publishing; only the admin view is paused.

## 6. Identify RLS / access issues
- Run `supabase--linter`.
- Check Edge Function logs for `42501` permission errors.
- Verify `GRANT` statements exist on every public map table.

## 7. Keep ride/mission flow running without maps
- The ride/mission lifecycle does not depend on tiles loading.
- If `RouteEstimateChip` errors, it self-hides. Lifecycle continues.

## 8. Full rollback (last resort)
- Re-deploy the previous frontend build from the publish history.
- Backend migrations are additive; no destructive rollback needed.
- Communicate to pilot operators via the broadcast channel.