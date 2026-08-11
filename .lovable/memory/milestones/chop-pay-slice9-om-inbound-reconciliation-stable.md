---
name: Chop Pay Slice 9 — Orange Money Inbound Reconciliation Stable
description: Locked 2026-08-11 — exact-reference OM matching, environment isolation, one-credit-per-reference invariants, honest customer/driver top-up stages, 72/72 QA PASS
type: feature
---
# Slice 9 — Orange Money Inbound Reconciliation (LOCKED)

Inbound Orange Money is the only funding rail into Chop Pay balances, and
it is now exact-match only.

## Rules that must not regress
- A credit requires an **exact provider reference match**. No fuzzy
  payload containment, no phone-only fallback.
- Amount, payer phone and receiving account must all agree, or the request
  goes to `needs_review` with a machine-readable `review_reason`.
  Mismatch never credits, silently or otherwise.
- `environment` (`production` | `sandbox`) must match on both sides.
  Cross-environment credits raise `environment_mismatch`.
- One credit per provider reference, per event, per top-up request —
  enforced by unique indexes, not by application code.
- Expired requests can never be credited, even by an admin.
- Every credit posts a zero-sum ledger journal
  (`A_PROVIDER_CLEARING` vs `L_CUSTOMER_CHOPPAY` / `L_DRIVER_UNRESTRICTED`).
  A top-up is never platform revenue.
- Customer and driver top-up queues are separate: `target_party_type`
  decides the wallet and the liability account.
- `anon` and `authenticated` hold no execute privilege on any inbound OM
  primitive. Wallet mutation from the client is impossible.

## Verification
`SELECT public._qa_s9_run();` → 72/72 PASS, self-rolling-back.
Full record: `docs/qa/chop-pay-slice9-results.md`.
