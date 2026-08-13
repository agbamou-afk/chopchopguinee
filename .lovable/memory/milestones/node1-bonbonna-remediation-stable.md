---
name: Node 1 — Bonbonna Remediation Stable
description: Bonbonna (toktok) service node hardened — own product identity, mode-true driver/customer surfaces, vehicle eligibility enforced at acceptance, 60s no-driver expiry with full hold release
type: feature
---

# Node 1 — Bonbonna Remediation (locked)

Bonbonna is the tricycle service. Internally the identifier stays `toktok`
(DB enum `ride_mode`, fare keys, capabilities, analytics). `Bonbonna` is the
only user-visible name. `src/lib/rides/rideModeLabel.ts` is the single mapping
point — never hardcode a service name in a component.

## Server truth (locked)
- `ride_offers.ride_mode` column, backfilled by `trg_ride_offer_fill_mode`.
- `driver_offer_accept` re-validates driver approval + `vehicle_type` at accept
  time. A moto driver accepting a Bonbonna ride gets `DRIVER_VEHICLE_NOT_ELIGIBLE`
  and the ride stays unassigned.
- `ride_expire_unfulfilled(uuid)`: 60-second search window. On no-driver it
  cancels with `no_driver_available`, releases the Chop Pay reservation in full
  and charges **zero** cancellation fee. Idempotent, owner-only, fails closed
  for anon.
- Regression harness `_qa_node1_bonbonna()` → `_qa_s13_results` part 101.

## Product identity
`RIDE_MODE_PRODUCT` differentiates on capacity / cargo / weather:
Bonbonna = up to 3 passengers, luggage and cartons, sheltered from rain.
Moto = 1 passenger, fastest through traffic. Shown in booking header + Services.

## Verification
- `_qa_node1_bonbonna()` 24/24 PASS
- `_qa_node0_course()` 34/34 PASS (no Course regression)
- Vitest 24/24 PASS, typecheck clean

## Known operational gap (not code)
BNB-G1: zero approved drivers with `vehicle_type = 'toktok'` exist. Bonbonna
cannot complete a real trip until the fleet is onboarded — dispatch correctly
returns no driver and the customer is refunded in full.
