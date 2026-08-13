
## T2 + T4–T6 — Taxi product vertical (landed)

Founder decisions applied: fare 1500 base + 2000/km GNF; own `taxi` commission
policy key (1000 bps); customer name "Taxi"; launch behind a feature flag.

Database
- `_ride_mission_type`: `auto` -> `taxi` (own economics, not Moto's).
- `finance_policies_mission_type_chk` extended with `taxi`.
- `fare_settings` row `auto` = 1500 + 2000/km; `finance_policies` `taxi` = 1000 bps.
- `feature_flags.taxi` inserted, default **false**.
- `ride_request_create` fails closed with `TAXI_NOT_ENABLED` while the flag is off,
  so the gate is server-enforced and not merely a hidden tile.

Client
- `rideModeLabel.ts`: `auto` label/subtitle + `RIDE_MODE_PRODUCT` positioning
  (qualitative only, no numeric passenger counts).
- `featureFlags.ts` / `useFeatureFlag.ts`: `taxi` key + `useTaxiEnabled()`.
- `ServicesView.tsx`: Taxi tile, "Bientôt disponible" while the flag is off.
- `RideBooking.tsx`, `EtaPricePreview`, `NearbyAvailableDrivers`,
  `RealtimeTripScreen`, `NoDriverRecoverySheet`, `Index.tsx`: `auto` carried
  through booking, tracking, receipts and no-driver recovery (Taxi falls back
  to Moto as the cross-sell).
- `DriverApply.tsx`: Taxi vehicle option; `capabilities.ts`: `rides_taxi`;
  analytics taxonomy: `taxi.booking.*`.

Evidence after the last edit: Node 0 34/34, Node 1 78/78, vitest 24/24,
typecheck clean. Flag posture unchanged elsewhere; zero approved `auto`
drivers, so Taxi remains OFF (TAX-G2 still open, Gate 14 still unmet).

## T7 — Taxi certification harness + closeout evidence (2026-08-13)

Built `public._qa_node2_taxi_full()` — a single rollback-clean, SECURITY DEFINER,
service-role-only harness (allowlisted in `qa-node-harness`). It flips the `taxi`
flag ON only inside a subtransaction that always ends in `QA_NODE2_ROLLBACK`, so
production flag state, the master wallet and all fixtures are restored.

Coverage (48 assertions, all natural-language labelled):
- A Identity/config: `auto` enum, `_ride_mission_type='taxi'`, `_ride_required_vehicle='auto'`,
  fare 1500/2000, own 1000 bps policy, flag currently OFF.
- B Fail-closed: booking refused with `TAXI_NOT_ENABLED` and zero rides created while OFF;
  flipping `taxi` touches no other flag.
- C Booking truth: server-authoritative quote, reservation preview == `ride_reservation_amount_gnf`,
  Taxi priced above Moto, ride stored as `auto`, snapshot `mission_type='taxi'`,
  client-request replay is idempotent and reserves nothing extra.
- D Dispatch isolation: moto/Bonbonna drivers never offered; every offer carries `ride_mode='auto'`;
  planted cross-vehicle offer rejected; frozen driver ineligible + cannot accept; exactly one winner;
  winner really drives a Taxi.
- E Cancellation: fee equals `_cancellation_compute` (no Taxi fork); no residual reservation.
- F No-driver expiry: swept to `no_driver_available`, full refund, zero fee, zero debt.
- G Cash completion: no wallet debit, cash recorded, commission at the Taxi rate, mode preserved.
- H Chop Pay completion: capture exactly once, replay is a no-op, commission at most once.
- I Security: `ride_request_create` / `ride_sweep_unfulfilled` / the harness itself not
  executable by `anon` or `authenticated`.
- Z Rollback: master wallet unchanged, `taxi` flag back OFF, no flag drift, no fixture residue.

Final untouched sequential sweep (after the last edit):
Node 2 48/48 · Node 0 34/34 · Node 1 24/24 + full 78/78 + matrix 39/39 + sweeper 15/15 ·
Slice 13 parts 1–3 18/32/54 — **342/342 PASS, 0 failed**.
Vitest 24/24, typecheck clean.

Known evidence limitation (pre-existing, not Taxi-related): Slice 13 parts 4–7 use
`SET ROLE` and are SECURITY INVOKER, so they cannot be executed by `service_role`
through the QA edge function ("permission denied for table users"). A temporary
SECURITY DEFINER conversion was attempted and reverted: parts 4/5/7 then aborted on
"cannot set parameter role within security-definer function", while part 6 ran clean
at 87/87 PASS. These parts remain runnable only from a migration/postgres context.

## Node 2 verdict: HOLD — NOT LAUNCH-READY

Taxi is now structurally certified but must stay OFF:
- TAX-G2 remains open: 0 approved `auto` drivers in production, so there is no real
  Taxi supply to serve a customer.
- `feature_flags.taxi` = false, and `ride_request_create` fails closed server-side.
Flip the flag only after real approved Taxi drivers exist and a live field check passes.
