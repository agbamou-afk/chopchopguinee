# Node 0 Closeout — Course (Moto) P1 Remediation

Date: 2026-08-13 (UTC)
Scope: Course (Moto) request path only. No Node 1. No flag/activation change.
Frozen decisions applied: D1 (no new gate), D2 (revoke legacy `ride_create` from
`authenticated`), D3 (server-side named constant for the reservation buffer).

---

## 1. What changed

### `public.ride_request_create(...)` — new authoritative commitment RPC
Signature: `p_mode, p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng,
p_payment_mode, p_client_request_id, p_pickup_label, p_dest_label`.
There is **no fare parameter and no hold parameter**.

In one transaction it:
1. fails closed on a NULL caller and on a missing `client_request_id`;
2. validates coordinates are present and inside the Guinea service envelope;
3. returns the existing ride on replay (`status: already_created`);
4. refuses a second `pending`/`in_progress` Course for the same customer;
5. computes the fare via `ride_compute_quote_gnf` (**CRS-G1**);
6. freezes `finance_policy_snapshot(...)` at request time into `metadata.finance_snapshot`;
7. for `chop_pay`, derives the reservation as `ceil(fare * 1.10)` from the named
   server-side constant `C_RESERVATION_BUFFER_BPS = 11000` and places it through
   the locked `wallet_hold` primitive (**CRS-G2**);
8. inserts the ride with `metadata.payment_mode`, `fare_source`, `fare_authority`,
   `hold_amount_gnf`, `reservation_buffer_bps`.

Failure anywhere rolls the whole thing back: no ride, no orphan hold.

### D3 — why a constant, not a policy field
`finance_policies` / `finance_policy_snapshot` expose commission and cancellation
semantics only; there is no ride reservation-buffer field. Per D3, today's 1.10
buffer is preserved verbatim as a named server-side constant. No new
finance-policy semantics were introduced.

### Legacy `public.ride_create(...)`
Signature kept for internal compatibility, but it now:
- recomputes the fare and **ignores** `p_fare_gnf`;
- rejects a `p_hold_tx_id` that is not a pending `hold` owned by the caller, or
  that is already attached to another ride (`INVALID_HOLD_REFERENCE`);
- writes the same provenance + snapshot metadata.

Grants (D2): `EXECUTE` revoked from `PUBLIC`, `anon` and `authenticated`;
`service_role` only. `ride_request_create`: `authenticated` + `service_role`.

### Idempotency
`rides_client_request_id_uidx` — partial unique index on
`(client_id, metadata->>'client_request_id')`.

### Client
- `src/components/ride/RideBooking.tsx`: fare comes from `ride_compute_quote_gnf`
  (the same function the commitment RPC uses); the `fare_settings` client-side
  `base + perKm * km` arithmetic and the ±5%/+10% bracket are gone; the price is
  shown as the exact server quote; the CTA is disabled until the quote arrives.
  New explicit **Chop Pay / Espèces** selector (**CRS-G3**).
- `src/pages/Index.tsx`: the `wallet_hold` + `ride_create` + compensating
  `wallet_release` + support-issue choreography is replaced by a single
  `ride_request_create` call with a generated `client_request_id`. No
  `Math.ceil(fare * 1.1)`, no client fare rounding, no client-side compensation
  path. Cash bookings show honest copy (no "funds reserved" claim).

---

## 2. Regression — `public._qa_node0_course()`

Self-rolling-back harness (`service_role` only), same pattern as the Slice 13
suite: all fixtures and money movement are created inside a subtransaction that
is deliberately rolled back, and post-rollback posture is re-asserted.

**Result: 34 assertions, 34 PASS, 0 FAIL.**

| Group | Proves |
|---|---|
| N1.1–N1.3 | No client fare/hold parameter; persisted fare == `ride_compute_quote_gnf`; provenance recorded |
| N2.1–N2.2 | Reservation == server `fare * 1.10`; `held_gnf` moves by exactly that |
| N3.1–N3.4 | Replay returns the same ride, 1 ride, 1 hold, 0 extra GNF |
| N4.1–N4.4 | Insufficient funds ⇒ refusal, 0 rides, 0 orphan holds, `held_gnf` = 0 |
| N5.1–N5.3 | Cash ride: explicit mode, no hold, 0 funds reserved, cash cancellation path |
| N6.1–N6.2 | Chop Pay linked hold; completion captured through locked primitives |
| N7.1–N7.2 | Request-time snapshot frozen; completion economics derive from it |
| N8.1–N8.4 | Unauthenticated fails closed; `anon` cannot execute either RPC; `authenticated` cannot execute legacy `ride_create` |
| N9.1–N9.3 | Wrong pickup code refused; correct code advances; duplicate completion moves 0 GNF |
| N10.1 | Duplicate active Course request refused |
| N11.1–N11.2 | Legacy `ride_create` ignores a tampered fare and refuses an unrelated hold |
| N12.1 | Assignment only through the offer contract |
| Z0.1–Z0.3 | Master wallet unchanged (`-100435`), feature flags unchanged, zero fixture residue |

Honest limitation: N7.x proves the snapshot is frozen at request time and that
completion economics are derived from it. It does **not** mutate
`finance_policies` to exercise a live policy change, because policy rows are
immutable history and a QA mutation would leave real residue.

---

## 3. Posture after the closeout

- Feature flags: unchanged (D1). No new gate introduced.
- Master wallet: `-100435 GNF`, held `0` — unchanged.
- Typecheck clean, Vitest 20/20 pass, build green.
- Slice 0–13 finance architecture untouched: no new money primitive, no RLS
  change, no ledger change. `wallet_hold`, `ride_complete`, `ride_cancel`,
  `driver_offer_accept` are called, never modified.
