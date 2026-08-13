
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

## T7 correction pass (2026-08-13) — real handshake + negative rails

The first harness version was rejected for shortcutting the pickup handshake via
direct `metadata` writes. It was replaced by a version that drives the **real**
production RPCs (`ride_set_phase` → wrong-code rejection → `ride_confirm_pickup`
with the true code → `ride_start` → `ride_complete`), plus explicit negative
dispatch rails (moto, Bonbonna, offline, suspended, frozen `auto` drivers each
get exactly zero Taxi offers), zero-movement proof for flag-off refusals,
`ride_complete` replay idempotency (no second wallet/ledger/journal effect) and
full residue/master-wallet cleanliness.

One real defect in the harness assumptions was found and corrected against
server truth rather than by weakening it: closing an unfulfilled search first
retires the pending offer, so an old offer fails with `OFFER_NO_LONGER_PENDING`
(not `MISSION_NO_LONGER_AVAILABLE`). Two extra assertions were added — the offer
is really `expired`, and a *fresh* offer planted after the sweep is refused with
`MISSION_NO_LONGER_AVAILABLE` and never gives the cancelled trip a driver.

Client label leakage fixed in the same pass: `taxi` mission kind added to
`src/lib/activity/types.ts`, `ActivityRow.tsx` ("Course Taxi"),
`useActivityFeed.ts` (`auto` → `taxi`) and `src/lib/wallet/labels.ts`
("Gain Course Taxi reçu"), covered by `src/test/node2-taxi-labels.test.ts`.

Coverage (97 assertions, all natural-language labelled):
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
Node 2 97/97 · Node 0 34/34 · Node 1 full 78/78 ·
Slice 13 parts 1–3 18/32/54 — **313/313 PASS, 0 failed**.
Vitest 28/28, typecheck clean.
Posture re-read after the sweep: `feature_flags.taxi` = false, 0 approved `auto`
drivers, 0 `auto` rides, 0 `qa-s13-n2%` residue.

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
