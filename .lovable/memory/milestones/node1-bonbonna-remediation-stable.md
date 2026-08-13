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
- Expiry core lives in `_ride_expire_unfulfilled_internal(uuid)` (no session
  required, not executable by anon/authenticated).
- `ride_sweep_unfulfilled(int)` + pg_cron job `chopchop-ride-no-driver-sweep`
  (`10 seconds`, pg_cron 1.6 interval schedule) close abandoned searches **autonomously** — no customer device
  needed, reconnect-safe. Fails closed for any non-ops session; the client only
  keeps a slow idempotent backstop call and reacts to the ride row verdict.
- Regression harnesses: `_qa_node1_bonbonna()` (part 101) and
  `_qa_node1_bonbonna_full()` (part 102 = base + sweeper/receipt evidence).

## Product identity
`RIDE_MODE_PRODUCT` differentiates on room / cargo / weather. **Never state a
numerical passenger capacity anywhere** (legal/insurance): Bonbonna = "Plus de
place à bord", luggage and cartons, sheltered from rain. Moto = "Trajet
individuel", fastest through traffic. Shown in booking header + Services.

## Receipt + recovery truth
- Receipt payment label is persisted server truth only (`metadata.payment_mode`):
  Chop Pay / Espèces / "Non renseigné". No holdId fallback, never assume cash.
- `NoDriverRecoverySheet` is the AUTHORITATIVE recovery UX (no duplicate toast).
  Copy is cash-aware: only a Chop Pay search says the reservation was released
  in full; a cash search says only that no cancellation fee was charged.
- Bonbonna no-driver title is exactly "Aucun Bonbonna disponible pour le moment";
  actions are "Réessayer" and "Voir Moto" (never a silent auto-switch).
- Trip intent (pickup/dest coordinates + `metadata.pickup_label` /
  `dest_label`) is preserved into the retry / "Voir Moto" booking; retry always
  uses a FRESH idempotency uuid and never replays the cancelled commitment.
- Reconnect/reopen: `Index.tsx` reads the persisted verdict (status=cancelled +
  `cancel_reason=no_driver_available`, last hour) once per session and surfaces
  the recovery sheet. Expiry is never inferred from the client clock.

## Verification
- `_qa_node1_bonbonna_full()` = base + sweeper + `_qa_node1_bonbonna_matrix()`
  (eligibility, single-winner, cash truth, cash no-driver zero-movement/no-debt,
  central cancellation calculator parity, scheduler cadence + fail-closed grants)
- `_qa_node0_course()` 34/34 PASS (no Course regression)
- Slice 13 parts 1-7: 507/507 PASS, 0 failed
- Vitest 24/24 PASS, typecheck clean, no flag or master-wallet drift

## Known operational gap (not code)
BNB-G1: zero approved drivers with `vehicle_type = 'toktok'` exist. Bonbonna
cannot complete a real trip until the fleet is onboarded — dispatch correctly
returns no driver and the customer is refunded in full.
