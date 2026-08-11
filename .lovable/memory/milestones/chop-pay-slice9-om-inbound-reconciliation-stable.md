---
name: Chop Pay Slice 9 — Orange Money Inbound Reconciliation Stable
description: Locked 2026-08-11 — exact-reference + complete-evidence OM matching (payer phone and receiving account mandatory on both sides), environment isolation, one-credit-per-reference invariants, honest customer/driver top-up stages, 105/105 QA PASS
type: feature
---
# Slice 9 — Orange Money Inbound Reconciliation (LOCKED)

Inbound Orange Money is the only funding rail into Chop Pay balances, and
it is now exact-match only.

## Rules that must not regress
- A credit requires an **exact provider reference match**. No fuzzy
  payload containment, no phone-only fallback.
- Amount, payer phone and receiving account must all be **present on both
  the provider event and the request** and agree. Missing evidence on
  either side parks `needs_review` (`payer_phone_missing`,
  `receiving_account_missing`); differing values park
  `payer_phone_mismatch` / `receiving_account_mismatch`. Missing provider
  evidence is never backfilled from customer/request data.
- `wallet_topup_om_credit` re-validates reference, amount, phone,
  receiving account, environment, target party and expiry independently,
  so no admin wrapper can bypass the exact-match contract.
- `admin_record_om_receipt` may RECORD incomplete evidence, but it can
  never auto-credit it — credit always routes through `om_auto_match`.
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
- Privilege tiers: raw credit/matching primitives are denied to `anon` and
  `authenticated`; participant wrappers are `authenticated` + self-scoped
  bodies; admin wrappers are `authenticated` + `can_manage_wallet` guard;
  `anon` is denied everywhere. Wallet mutation from the client is impossible.

## Verification
105/105 PASS across the three self-rolling-back harnesses, which were then
dropped (zero `_qa_s9%` residue). Master wallet -100 435 GNF / held 0,
unchanged; only `om_topup_enabled` ON.
Full record: `docs/qa/chop-pay-slice9-results.md`.
YELLOW: no real observed Orange Money provider receipt was tested.
