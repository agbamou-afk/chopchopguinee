## CHOP Driver/Courier Operational Layer — Foundation Sprint

Lay the groundwork so drivers become unified fulfillment agents (rides + Repas + Marché + colis) without breaking the existing ride lifecycle.

### 1. Database — additive only

New migration:

- `driver_profiles.capabilities text[]` default `ARRAY['rides_moto']` — values from `rides_moto | rides_toktok | repas_delivery | marche_delivery | package_delivery`.
- New enum `mission_type`: `ride | food_delivery | marketplace_delivery | package_delivery`.
- New enum `mission_state`: `assigned | heading_to_pickup | arrived_pickup | picked_up | heading_to_dropoff | arrived_dropoff | delivered | failed`.
- New table `missions`:
  - `type mission_type`, `state mission_state default 'assigned'`
  - `courier_id uuid` (driver), `customer_id uuid`, `merchant_id uuid null`
  - `pickup_address text`, `pickup_lat/lng`, `dropoff_address text`, `dropoff_lat/lng`
  - `payload_summary text`, `estimated_earning_gnf bigint`, `estimated_distance_m int`, `estimated_duration_s int`
  - `ref_ride_id`, `ref_food_order_id`, `ref_market_order_id` (nullable links to legacy systems — compatibility layer, not replacement)
  - `pickup_confirmed_at`, `pickup_confirmed_by`, `dropoff_confirmed_at`, `dropoff_confirmed_by`
  - `issue_reason text`, timestamps
- RLS:
  - courier reads/updates own missions
  - customer reads own missions
  - merchant (restaurant owner / listing seller) reads missions where they are merchant
  - admins manage all
- `mission_events` table (event log) feeding ActivityTimeline:
  - `mission_id`, `event` (`accepted | en_route_pickup | arrived_pickup | picked_up | en_route_dropoff | delivered | issue`), `actor_id`, `note`, `created_at`. RLS mirrors `missions`.

Existing `rides` table is untouched.

### 2. Domain layer

`src/lib/missions/types.ts` — TS types + French labels:
```
assigned: "Mission attribuée"
heading_to_pickup: "En route vers le retrait"
arrived_pickup: "Arrivé au point de retrait"
picked_up: "Colis récupéré"
heading_to_dropoff: "En route vers le client"
arrived_dropoff: "Arrivé chez le client"
delivered: "Livré"
failed: "Problème signalé"
```

`src/lib/missions/missions.ts` — `listMyMissions`, `advanceMission(id, nextState)`, `confirmPickup`, `confirmDropoff`, `reportIssue`. All writes also insert into `mission_events`.

`src/lib/missions/capabilities.ts` — helper for capability checks and labels (`Moto`, `TokTok`, `Livraison Repas`, `Livraison Marché`, `Colis`).

### 3. Driver UI (lightweight, no new bottom tabs)

Rework the existing **Courses** tab into a "Mission hub":

- `src/components/driver/MissionRequestCard.tsx` — incoming card variant supporting all mission types (badge per type, pickup/dropoff lines, payload summary, earning, distance/time).
- `src/components/driver/ActiveMissionCard.tsx` — current mission with the state-machine CTA: "Je pars vers le retrait" → "Arrivé" → "Récupéré (confirmation manuelle)" → "En route client" → "Arrivé" → "Livré" + a discreet "Signaler un problème" link.
- Extend `src/components/driver/LiveRidesPanel.tsx` to also fetch from `missions` (alongside `rides`) and render mission cards. Existing ride rows keep working.
- Capability picker in driver profile/settings area (chips toggling `driver_profiles.capabilities`).

No bottom nav changes. No fake "courier ETA" copy when no courier is assigned.

### 4. Confirmation architecture (manual now, QR/PIN/photo-ready)

`confirmPickup(mission_id, method='manual')` and `confirmDropoff(...)` accept a `method` enum stored in `mission_events.note` so we can later swap in QR/PIN/photo without a schema break. UI shows only "Confirmer le retrait" / "Confirmer la livraison" buttons in this sprint.

### 5. ActivityTimeline integration

Extend `src/lib/activity/useActivityFeed.ts` to map `mission_events` for the current user (as customer or courier) into `ActivityItem` with kinds reused from existing `food_order` / `market_order` plus a generic `ride` for package. Subtitle uses the French state label. No new `ActivityKind` values needed yet — keeps the timeline calm.

### 6. Compatibility (no rewrites)

- Repas: existing `food_orders` flow unchanged. A later sprint can call `createMissionFromFoodOrder` when a restaurant confirms a delivery order. We expose the helper but do **not** auto-dispatch in this sprint.
- Marché: same — `createMissionFromMarketOrder` helper exists, not wired into checkout.
- Rides: legacy `rides` table + RPCs remain authoritative.

### 7. Out of scope (explicitly)

- No enterprise dispatch / auto-assignment
- No insurance, no escrow
- No QR/PIN/photo capture implementation
- No bottom-nav changes
- No fake courier promises in customer UI (Repas/Marché checkout copy unchanged)

### Acceptance check

- Migration applies cleanly; types regenerate.
- Driver `Courses` tab shows existing rides **and** any seeded missions.
- A test mission can move through every state via the UI.
- `ActivityTimeline` shows mission events for the customer.
- Existing ride accept/complete flow is byte-identical.
- Build clean at 390×844.
