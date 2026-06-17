# CHOP Maps — Pilot Launch Checklist

Status: Phase 2L — Pilot Launch Readiness.
Scope: deploy CHOP Maps as a field-survivable pilot tool. No new features.

## 1. Pre-deployment
- [ ] All Phase 2A–2H milestones locked (see `.lovable/memory/index.md`).
- [ ] Build clean (no TypeScript / lint errors blocking deploy).
- [ ] `.env` contains only `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `VITE_SUPABASE_PROJECT_ID`.
- [ ] No server-only map keys present in `src/` (`rg -n "GOOGLE_MAPS|MAPBOX_SECRET|ORS_API|GRAPHHOPPER|SERVER_KEY" src/` returns empty).
- [ ] Edge function `maps-config` deployed and returns publishable map config only.
- [ ] Edge function `maps-route` deployed; provider key stored as runtime secret.
- [ ] `map_provider_settings` row exists and points at chosen provider.

## 2. Database / RLS
- [ ] `supabase--linter` shows no new ERROR/WARN regressions on map tables.
- [ ] `driver_location_signals` blocked for anon (admin / owner-only).
- [ ] `map_route_observations` blocked for anon and customers.
- [ ] `map_places` public read limited to verified rows only.
- [ ] `map_driver_reports` writable by drivers, readable by admins.
- [ ] `merchant_stores` location columns writable only by store owner / admin.

## 3. Smoke pass (see PILOT_SMOKE_TEST.md)
- [ ] Sections A–R all PASS.
- [ ] Pricing/wallet untouched (cross-checked against last wallet milestone).

## 4. Field readiness
- [ ] Field operator guide distributed to pilot agents.
- [ ] Admin operations guide reviewed by ops lead.
- [ ] Known limitations acknowledged by pilot owner.
- [ ] Recovery / rollback notes accessible offline (printed or PDF).

## 5. Post-deploy verification
- [ ] Open `/admin/map/zones` — zones load.
- [ ] Open `/admin/map/places` — list loads, verified count > 0.
- [ ] Open `/admin/map/driver-signals` — live/recent/stale badges render.
- [ ] Open `/admin/map/routing` — diagnostics render.
- [ ] Customer ride flow — pickup/dropoff selectable, estimate chip visible.
- [ ] Driver mission card — estimate chip visible when assigned.
- [ ] Simulate offline (DevTools) — `DegradedMapPanel` appears, never blank.

## 6. Rollback triggers
- Tile provider outage > 30 min → operate via list views (admin docs).
- Driver signal privacy regression → disable `/admin/map/driver-signals` route.
- Route observation leak → revoke `map_route_observations` SELECT.
- Any wallet/pricing drift → halt rollout, escalate to ChopWallet agent.