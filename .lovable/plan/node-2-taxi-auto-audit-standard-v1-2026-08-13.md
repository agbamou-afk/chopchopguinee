# Node 2 — Taxi (`auto`) Audit, Standard v1

Audit only. No code, DB, flag, policy or data change was made.

## A. Current state (evidence)

Discovery / labels
- Customer service grid `src/components/views/ServicesView.tsx` offers exactly two ride products: `moto` and `toktok`. No Taxi entry.
- `src/components/ride/RideBooking.tsx:41` types the product as `"moto" | "toktok"`; product copy map covers only those two; routing profile is `two_wheeler` for moto else `driving`.
- `src/lib/rides/rideModeLabel.ts` has no `auto` label, subtitle or product model; `rideServiceTitle` would return the raw value.
- Driver signup `src/pages/DriverApply.tsx` shows only Moto and Bonbonna; its parser accepts only `moto | toktok | livraison`.
- `src/lib/missions/capabilities.ts` capability union has no taxi entry; `src/lib/analytics/eventTaxonomy.ts` has moto/toktok event families only.

Enums / schema
- `ride_mode` = `moto, toktok, food` (queried). `driver_vehicle_type` includes `auto` (and `livraison`).
- `ride_offers.ride_mode`, `rides.mode` and all ride RPC params are typed on `ride_mode`, so `auto` is unusable end-to-end until the enum gains a value.
- Generated `src/integrations/supabase/types.ts` mirrors the enum; every ride RPC signature is bound to it.

Runtime / finance (shared spine, verified server-authoritative)
- `ride_request_create` / `ride_get_quote` / `ride_reservation_amount_gnf` / `ride_cancel` / `_cancellation_compute` / `ride_complete` / `_ride_expire_unfulfilled_internal` contain no hardcoded mode strings — they are mode-agnostic and would carry Taxi for free once the enum, fare row and policy key exist.
- `ride_compute_quote_gnf` looks up `fare_settings WHERE ride_type = p_mode::text` and **raises** `no_fare_settings_for_mode` when absent. No silent moto fallback here. Good.
- `fare_settings` currently has exactly two rows: `moto` (500 + 1000/km) and `toktok` (1000 + 1500/km). No `auto` row.

Silent fallbacks that WOULD mislabel Taxi
- `ride_dispatch`: `v_vehicle := CASE mode WHEN 'moto' … WHEN 'toktok' … ELSE 'moto' END`. An `auto` ride would dispatch to **moto** drivers.
- `driver_offer_accept`: `v_required := CASE mode WHEN 'toktok' … WHEN 'moto' … ELSE NULL END`, and the check is skipped when NULL — so an `auto` ride would accept **any approved vehicle type**. This is the Node 1 hardening not being extended.
- `_ride_mission_type(mode)`: `WHEN 'toktok' THEN 'bonbonna' ELSE 'ride'`. `auto` silently inherits the Moto/`ride` commission policy and mission economics.

Supply
- `driver_profiles` today: 4 approved moto, 2 suspended moto. **Zero `auto` drivers of any status, zero `toktok` drivers.** No approved Taxi supply exists.
- `get_nearby_available_drivers` takes a text `p_vehicle_type` filter and is mode-agnostic (no hardcode) — reusable.

Recovery / ops
- No-driver autonomous sweep (`ride_sweep_unfulfilled` via pg_cron), zero-fee expiry, hold release, reconnect restore and `NoDriverRecoverySheet` are mode-agnostic — but recovery copy and the "switch service" affordance are written for Moto/Bonbonna only.

Map / tariffs
- `map_fare_troncons` has no vehicle/mode column (day/night price per corridor only) — corridor tariffs are currently mode-blind and cannot express a Taxi premium.
- `map_service_zones` / `finance_policies` expose no per-mode service key column beyond `services_enabled` jsonb.

QA
- Harnesses: `_qa_node0_course` (Moto), `_qa_node1_bonbonna*` (Bonbonna), `_qa_s13_run1..7`. **No Taxi coverage of any kind.** The `qa-node-harness` edge function allowlist has no Node 2 entry.

## B. Gap register

| ID | Severity | Gap |
|---|---|---|
| TAX-G1 | P0 | `ride_mode` enum has no `auto`; Taxi cannot be requested, quoted, offered or reported anywhere. |
| TAX-G2 | P0 | Zero approved `auto` drivers. No supply → launch-blocking regardless of code. |
| TAX-G3 | P0 | `ride_dispatch` silently maps unknown mode to `moto` drivers — a Taxi request would be served by a motorbike. |
| TAX-G4 | P0 | `driver_offer_accept` skips vehicle revalidation when the mode is unmapped — any vehicle could accept a Taxi. |
| TAX-G5 | P0 | No `fare_settings` row for `auto`; quote raises, and no Taxi price structure exists. |
| TAX-G6 | P1 | `_ride_mission_type` silently folds `auto` into the `ride` (Moto) commission/economics policy; no `taxi` policy key. |
| TAX-G7 | P1 | No customer discovery surface: ServicesView, RideBooking union/product copy, QuickActions, icons. |
| TAX-G8 | P1 | `rideModeLabel` / `rideServiceTitle` / `RIDE_MODE_PRODUCT` lack `auto`; receipts, activity feed, wallet rows and emails would show a raw `auto`. |
| TAX-G9 | P1 | Driver onboarding (`DriverApply`) and admin approval surfaces do not offer or filter `auto`. |
| TAX-G10 | P1 | Driver offer popup / active-trip mode truth not extended to Taxi labels or icons. |
| TAX-G11 | P1 | No Node 2 QA harness; no allowlist entry; regression evidence would be manufactured otherwise. |
| TAX-G12 | P2 | Analytics taxonomy, capability union, notification/SMS templates and support/ops filters have no Taxi family. |
| TAX-G13 | P2 | Corridor tariffs (`map_fare_troncons`) are mode-blind; a Taxi premium cannot be expressed per corridor. |
| TAX-G14 | YELLOW | Routing profile for Taxi is `driving` by default, unvalidated against Conakry car traffic; ETA quality unproven. |
| TAX-G15 | YELLOW | Gate 14 (two-actor live device run) cannot be executed in this environment, as with Node 0/1. |

## C. Remediation slices (dependency order)

1. **T1 — Enum + type spine.** Add `auto` to `ride_mode`; regenerate types. Nothing else changes behaviourally. (TAX-G1)
2. **T2 — Fare + policy truth.** Insert the `auto` `fare_settings` row and a `taxi` finance policy key; extend `_ride_mission_type` to map `auto → taxi`. Requires founder pricing decision (F1/F2). (TAX-G5, TAX-G6)
3. **T3 — Dispatch + acceptance eligibility.** Make `ride_dispatch` map `auto → auto` and **fail closed** on unknown modes instead of defaulting to moto; make `driver_offer_accept` fail closed when the required vehicle cannot be resolved. This also removes a latent Moto/Bonbonna hazard without changing their behaviour. (TAX-G3, TAX-G4)
4. **T4 — Supply.** Add `auto` to DriverApply and admin approval/filter surfaces; onboard real Taxi drivers. (TAX-G2, TAX-G9)
5. **T5 — Customer product surface.** ServicesView tile, RideBooking union + Taxi product copy, labels/receipts/activity/wallet, no-driver recovery copy and cross-sell. (TAX-G7, TAX-G8, TAX-G10)
6. **T6 — Ops/analytics/support.** Taxi analytics family, capability entry, notification templates, ops filters. (TAX-G12)
7. **T7 — QA.** `_qa_node2_taxi*` harness + allowlist entry; then a full sweep (Node 0, Node 1, Node 2, Slice 13, vitest, build). (TAX-G11)
8. **T8 — optional.** Per-mode corridor tariffs and routing-profile validation. (TAX-G13, TAX-G14)

## D. Reuse vs new

Reused unchanged (locked, mode-agnostic): `ride_request_create`, `ride_get_quote`, `ride_reservation_amount_gnf`, holds/capture/release, `_cancellation_compute` + cancellation debt, pickup handshake/secret, `ride_complete`, receipts pipeline, autonomous no-driver sweep + zero-fee expiry, reconnect restore, idempotent booking request id, `get_nearby_available_drivers`, ledger/settlement/payout stack.

Modified (shared, must not regress Node 0/1): `ride_dispatch` vehicle mapping, `driver_offer_accept` revalidation, `_ride_mission_type`, `ride_mode` enum, generated types.

New and Taxi-specific: `auto` fare row + `taxi` policy key, Taxi product identity/positioning copy and icon, Taxi discovery tile, Taxi driver onboarding option, Taxi analytics family, `_qa_node2_taxi` harness.

## E. Proposed Node 2 exit gates

1. Taxi is discoverable and bookable as a distinct product with its own copy — never labelled Moto/Bonbonna.
2. Quote and hold come from the server for `auto`; no client fare, no client hold.
3. Only approved `auto` drivers receive Taxi offers; dispatch fails closed for unmapped modes.
4. Acceptance revalidates `vehicle_type='auto'`; a moto/Bonbonna driver is rejected.
5. Single-winner acceptance and idempotent replay hold for Taxi offers.
6. No-driver window closes autonomously with zero fee, hold fully released, recovery sheet correct for Taxi and cash-aware.
7. Cancellation uses the central calculator with the Taxi policy snapshot; cash debt path correct.
8. Completion captures Chop Pay exactly once and commission uses the Taxi policy, not the Moto policy.
9. Receipts, activity, wallet, notifications, ops and support all read "Taxi".
10. `_qa_node2_taxi` passes with no manufactured assertions; Node 0 34/34, Node 1 78/78 and Slice 13 507/507 unchanged; vitest, typecheck and build green.
11. Gate 14 two-actor live run (expected YELLOW/HOLD in this environment).
12. At least one approved live `auto` driver before any activation claim.

Regression matrix per slice: T1 → typecheck + Node 0/1 harness; T2 → quote/commission assertions; T3 → Node 0 + Node 1 harness must stay green (they cover the mapping); T4–T6 → vitest + build; T7 → full sweep.

## F. Founder decisions required before implementation

- **F1 — Taxi fare structure.** Base price and per-km rate for `auto` in GNF (Moto 500/1000, Bonbonna 1000/1500). Taxi is presumably the premium tier; the number is a product decision, not an engineering one.
- **F2 — Taxi commission policy.** Own `taxi` policy key and rate, or reuse the `ride` (Moto) 1000 bps? Recommendation: own key, so it can move independently.
- **F3 — Product positioning.** Taxi's capacity/cargo/weather/positioning copy in the same qualitative style as Bonbonna (no numeric passenger counts, per the locked rule).
- **F4 — Naming.** Customer-facing name: "Taxi", "Voiture", or a local brand name (internal identifier stays `auto`).
- **F5 — Supply strategy.** How Taxi drivers are recruited/verified (car documents, insurance) and whether an existing moto driver may switch vehicle type.
- **F6 — Activation posture.** Whether Taxi launches behind a flag, and in which zones.

Verdict: **NOT SUFFICIENTLY BUILT** — Taxi does not exist as a service node today. Two latent shared-spine hazards (TAX-G3, TAX-G4) must be fixed fail-closed as part of Node 2.
