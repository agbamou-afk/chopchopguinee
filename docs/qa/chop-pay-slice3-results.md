# Chop Pay — Slice 3B hardening QA results

Harness: `_qa_s3b_run()` (self-rolling-back, raises `QA_S3B_RESULT`).

## Outcome — 60/61 assertions PASS

Key money proofs
- 100 000 GNF cash ride → commission reserve 10 000, captured exactly once (replay adds zero).
- Chop Pay ride → customer debited 100 000, driver net +90 000, platform +10 000.
- Bonbonna mission type resolves to `bonbonna`, reserve 10 000.
- Insufficient hold → `SETTLEMENT_REQUIRED_INSUFFICIENT_HOLD`, no capture, no driver credit, ride not completed.
- Cancellation: before dispatch 5 000, after dispatch 10 000, replay creates no duplicate debt.
- Snapshot survives a post-acceptance policy edit (commission split and cancel bps unchanged).
- Driver-caused cancellation: zero fee and **no** customer debt row.
- Ledger journals zero-sum; posting update / journal delete denied.

Security matrix
- `wallet_internal_transfer`: anon denied, authenticated denied, service_role allowed.
- `ride_accept` / `ride_dispatch`: anon + authenticated denied; only `driver_offer_accept_for_ride`
  and `ride_request_dispatch` are public entrypoints.
- Cross-driver offer acceptance and cross-driver completion denied; premature completion denied
  (`PICKUP_CONFIRMATION_REQUIRED`).
- Enabled finance flags: `om_topup_enabled` only.

## Defects fixed during this run
- DEF-FIN-002 — cancellation fee resolved from live policy instead of the ride's frozen snapshot.
  `customer_cancellation_debt_create` now accepts `p_policy_snapshot` and `ride_cancel` passes the
  ride snapshot.
- DEF-FIN-003 — non-customer-caused cancellations created a zero-amount debt row. They now create none.
- `ride_complete` called `_is_god_admin()` with no argument (runtime failure on admin override path).

## Known harness gap (not a product defect)
- `E2.eligible_after_topup` — the OM top-up pathway credits the **client** wallet and requires a
  `payment_provider_events` row; the harness calls it against a driver with no client wallet, so it
  reports `Wallet not found`. Driver funding via top-up + client→driver internal transfer must be
  re-tested in the Slice 4 harness.
