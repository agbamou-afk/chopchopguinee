# CHOP Maps — Role Access Matrix

Legend: R = read, W = write/insert, U = update, ∅ = no access, * = via sanitized RPC / scoped policy.

| Resource | anon | client (auth) | driver/courier | merchant | field_agent | field_captain | operations_admin | finance_admin | god_admin | service_role |
|---|---|---|---|---|---|---|---|---|---|---|
| `map_service_zones` | R (active) | R | R | R | R | R | R/U | R | R/U | full |
| `map_places` (verified) | R | R | R | R | R | R | R/U | R | R/U | full |
| `map_places` (unverified) | ∅ | ∅ | ∅ | own* | own* | R | R/U | R | R/U | full |
| `map_fare_troncons` | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ | R | R | R/U | full |
| `map_driver_reports` | ∅ | ∅ | W (own) | ∅ | W (own) | R | R/U | R | R/U | full |
| `map_place_duplicate_candidates` | ∅ | ∅ | ∅ | ∅ | ∅ | R | R/U | R | R/U | full |
| `map_route_observations` | ∅ | ∅ | W (own active job)* | ∅ | ∅ | ∅ | R/U (review) | R | R/U | full |
| `driver_location_signals` | ∅ | ∅ | W (own)* | ∅ | ∅ | ∅ | R (admin map) | ∅ | R | full |
| `merchant_stores.location_*` | R (verified) | R (verified) | R (verified) | own W/U | ∅ | ∅ | R/U | R | R/U | full |
| `field_merchant_visits` | ∅ | ∅ | ∅ | ∅ | W (own) | R (assigned) | R/U | R | R/U | full |
| `field_daily_reports` | ∅ | ∅ | ∅ | ∅ | W (own) | R (assigned) | R | R | R | full |
| `/admin/map/*` pages | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ | view | view | full | n/a |

## Hard guarantees
- Anonymous traffic cannot read driver positions, route observations, or unverified places.
- A driver can only insert/update their own `driver_location_signals` and only while assigned to a ride/mission for `map_route_observations`.
- Field agents cannot mark a place as `verified` or `trusted`; that capability is admin-only.
- Merchants can only mutate their own store location; verification flips are admin-only.
- Server-only provider keys (`GOOGLE_MAPS_SERVER_KEY`, etc.) never leave Edge Functions.