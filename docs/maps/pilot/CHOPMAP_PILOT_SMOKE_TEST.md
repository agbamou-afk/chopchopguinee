# CHOP Maps — Pilot Smoke Test Script

Run end-to-end before every pilot deployment. Each row must PASS.

| # | Role | Path | Action | Expected | Pass |
|---|---|---|---|---|---|
| A | admin | `/admin/map/zones` | List zones, toggle one active | Zones load; status saves | ☐ |
| B | admin | `/admin/map/places` | Open places list | List loads with verified/submitted badges | ☐ |
| C | merchant | `/merchant` → boutique | Submit store location | Submission saved, status `submitted` | ☐ |
| D | admin | `/admin/map/places` | Verify the merchant submission | Status flips to `verified` | ☐ |
| E | admin | `/admin/map/duplicates` | Run duplicate scan | Safe duplicates flagged; non-duplicates ignored | ☐ |
| F | field_agent | `/field/visit` | Submit visit online | Visit persisted to DB | ☐ |
| G | field_agent | `/field/visit` (offline) | Submit visit while offline | Draft saved locally; banner explains | ☐ |
| H | field_captain | `/field/captain` | Review visits | Recent visits visible | ☐ |
| I | driver | driver app, go online | Toggle online | Signal appears in `/admin/map/driver-signals` as live | ☐ |
| J | driver | driver app, go offline | Toggle offline | Signal stops; badge becomes stale | ☐ |
| K | client | active ride | Start ride | `RouteEstimateChip` shows distance + ETA | ☐ |
| L | driver | active mission card | Get assigned mission | `RouteEstimateChip` visible on card | ☐ |
| M | client/driver | force provider failure | Block routing provider | "Estimation approximative" banner appears | ☐ |
| N | any | force tile failure (DevTools offline) | Reload map surface | `DegradedMapPanel` renders, no blank map | ☐ |
| O | admin | `/admin/map/routing` after fallback ride | Observe queue | Route observation row appears | ☐ |
| P | anon/client | direct query of `map_route_observations` | Attempt SELECT | Denied by RLS | ☐ |
| Q | any | spot-check wallet/pricing flows | Run sandbox ride | Fares/wallet unchanged from previous lock | ☐ |
| R | dev | `bun run build` (handled by harness) | Inspect output | Clean build | ☐ |

Sign-off: ____________________  Date: __________