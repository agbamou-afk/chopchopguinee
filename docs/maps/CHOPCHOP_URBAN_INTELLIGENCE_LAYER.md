# CHOPCHOP Urban Intelligence Layer

_Status: architecture intent — implemented incrementally, privacy-first._

> **Individual privacy protected. Collective urban patterns understood.**

## What this is

CHOPCHOP is not only a ride / food / market / wallet / delivery app. The
long-term ambition is for CHOPCHOP to become a **privacy-preserving digital
brain for Conakry**: a district-aware urban operating layer that understands
movement patterns, density zones, merchant clusters, delivery friction,
address ambiguity, and operational demand — without surveilling individuals.

This document defines the architecture, privacy rules, event taxonomy, and
staged implementation plan for that layer.

## Privacy-first principles (non-negotiable)

- Individual privacy is protected. Collective patterns are understood.
- Collect the minimum data needed for the operational signal.
- Prefer aggregation over raw trails. Persist raw points only when an active
  operation (mission, delivery, support case) requires it.
- Never store continuous personal traces "just in case".
- Never expose raw location trails to normal admins. Sensitive geography is
  role-gated and aggregated by default.
- Separate operational data (live mission state) from planning analytics
  (aggregated, district-level views).
- Retention rules are written into the table definition and reviewed annually.

## Event taxonomy

Events are grouped into families. Not all are implemented — this is the
target shape we grow into.

### A. Mobility
- `ride_requested`, `pickup_selected`, `pickup_confirmed`,
  `dropoff_completed`, `trip_cancelled`, `trip_failed`

### B. Delivery
- `delivery_requested`, `courier_assigned`, `pickup_arrived`,
  `pickup_confirmed`, `dropoff_arrived`, `delivery_completed`,
  `delivery_failed`

### C. Location quality
- `gps_denied`, `gps_unavailable`, `gps_stale`, `route_unavailable`,
  `location_corrected`, `wrong_address_reported`, `map_recentered`,
  `external_navigation_opened`

### D. Merchant
- `restaurant_order_created`, `merchant_not_ready`, `item_unavailable`,
  `merchant_location_confirmed`, `public_location_missing`

### E. Support geography
- `support_issue_created` (issue_type, severity, district, related ids)

### F. Driver / courier supply
- `driver_online`, `driver_offline`, `driver_idle_zone`, `driver_busy_zone`,
  `mission_declined`, `mission_accepted`

## Data shape (future)

Proposed table: `urban_mobility_events`

| Field | Notes |
|---|---|
| `id` | uuid pk |
| `event_type` | enum from the families above |
| `actor_role` | client / courier / driver / merchant / admin / system |
| `actor_id_hash` | salted hash; raw user_id only when operationally required |
| `related_mission_id` | nullable |
| `related_order_id` | nullable |
| `related_payment_intent_id` | nullable |
| `district` | snapped to known Conakry districts |
| `commune` | nullable |
| `latitude` / `longitude` | optional; precision controlled |
| `location_precision` | `exact` / `approximate` / `district_only` |
| `confidence` | 0–1 |
| `service_type` | moto / toktok / repas / marche / envoyer / wallet / support |
| `source` | gps / user_selected / gazetteer / merchant / courier / admin / fallback |
| `metadata` | jsonb — small, no PII |
| `created_at` | timestamptz |

**Access rules:**
- RLS: writers are service role / authenticated event producers only.
- Readers: admins with explicit analytics permission. Aggregate views
  (below) are preferred over raw SELECTs.
- Raw lat/lng is omitted in default admin views; only aggregated tiles are
  shown.

## Aggregation-first views

Before any raw dashboard, build these aggregate views:

- `district_activity_hourly`
- `pickup_density_by_district`
- `dropoff_density_by_district`
- `merchant_demand_by_zone`
- `route_failure_zones`
- `wrong_address_hotspots`
- `support_issues_by_district`
- `driver_idle_density`
- `delivery_failure_density`
- `gps_failure_density`

These power planning dashboards. They never expose individual trails.

## Immediate low-risk wiring

For now, wire only signals we already collect:

- `navigation_events`
- `location_search_events`
- `support_issues` (district / type / severity)
- `missions` (district / type / status)
- `merchant public locations`
- `route_unavailable` events
- `gps_unavailable` events
- `wrong_address` support issues

No new continuous tracking. The immediate goal is to **structure what we
already collect**.

## Live location comes first

Before any of this analytics layer ships:

- Live GPS must be real and labeled.
- The Conakry fallback must be labeled as a fallback in the UI.
- No "near you" copy without a real fix.
- Driver cannot go online without the required location fix (per surface).
- Pickup must never default to Kaloum unless the user actively selects it.

See `CHOPCHOP_MAP_STRATEGY.md` and
`src/lib/location/useLiveUserLocation.ts`.

## Future driver-trace collection (requires consent + governance)

Driver traces could eventually power road speed estimates, informal corridor
mapping, and delivery time prediction. Before we collect them we need:

- Explicit consent at driver onboarding (terms update).
- Precision minimized when full precision is not required.
- Hard retention limits (e.g. 30 / 90 days for raw; aggregates retained
  longer).
- Role-based access; raw traces never exposed to standard admins.
- No public exposure under any circumstance.

Not implemented now.

## Command Center evolution

The Command Center will eventually surface aggregate city signals (demand by
district, support friction, supply gaps, route failure zones, peak windows).

**Today** it only shows real operational data already in the system. No
fake heatmaps, no placeholder gauges. See the Command Center spec in
`docs/pilot/`.