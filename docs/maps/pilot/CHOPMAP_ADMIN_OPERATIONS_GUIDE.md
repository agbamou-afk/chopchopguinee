# CHOP Maps — Admin Operations Guide

## 1. Reviewing merchant location submissions
- Path: `/admin/map/places` → filter status = `submitted`.
- Confirm coordinates vs. submitted address.
- Click **Vérifier** to flip to `admin_verified`. Reject with reason otherwise.

## 2. Verifying map_places
- Same page. A place becomes `trusted` after admin verification + 1 corroborating field visit.
- Never auto-trust observation data.

## 3. Merging duplicates
- Path: `/admin/map/duplicates`.
- Compare candidates side by side, check distance + name similarity.
- Pick the canonical one, merge the other; references update automatically.
- When unsure: leave as `pending`, escalate to god_admin.

## 4. Reviewing field reports
- Path: `/admin/field-pilots` → daily reports per agent.
- Check coverage, flag missing zones.

## 5. Driver signal freshness
- Path: `/admin/map/driver-signals`.
- Badge meanings: **live** (< 60 s), **recent** (< 5 min), **stale** (> 5 min).
- Stale-only fleet = signal pipeline issue; check `driver-location-publish` logs.

## 6. Routing diagnostics
- Path: `/admin/map/routing`.
- Shows provider success vs fallback ratio. Spike in fallback → provider key or quota issue.

## 7. Route observations
- Path: `/admin/map/routing` → observations tab.
- Mark rows **reviewed**, **trusted**, or **rejected**.
- ⚠️ **Observed routes must NOT be used for pricing.** Pricing remains on the locked tronçon table.

## 8. Degraded map state
- If tiles fail across many users: switch banner via `/admin/settings` → "Map degraded mode".
- Field/admin workflows continue via list views.

## 9. Known safe fallbacks
- Tile down → `DegradedMapPanel` with pickup/dropoff/ETA still works.
- Routing down → `fallbackEstimate` returns a haversine-based ETA, chip flags "Estimation approximative".
- DB realtime down → driver signals show last known timestamp; do not panic.