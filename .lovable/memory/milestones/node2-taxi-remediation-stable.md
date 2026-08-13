
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
