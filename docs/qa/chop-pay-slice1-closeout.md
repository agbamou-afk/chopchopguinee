# Chop Pay Slice 1 — micro-closeout (P1 RPC authority)

Scope: privilege hardening only. No UI changed. No feature flag enabled.
Both `chop-pay-ledger-revival-stable` and
`web-production-release-candidate-stable` remain UNLOCKED.

## P1 fixed — mission money resolution is now server-authoritative

Before: `driver_mission_hold_release`, `driver_mission_commission_capture` and
`driver_mission_fee_capture` were EXECUTE-able by `authenticated`, and their
internal guard treated a NULL/owner caller as sufficient authority. A driver
could therefore release their own collateral/commission hold or capture with a
caller-supplied final basis of 0.

After:
- EXECUTE revoked from `PUBLIC`, `anon`, `authenticated`; granted to
  `service_role` only, for every mission settlement / capture / release /
  refund / merchant-funding / debt / payout / settlement / claims primitive.
- Authorization guards hoisted **above** the hold lookup in
  `driver_mission_hold_release` and `driver_mission_fee_capture`, so a
  non-privileged caller is rejected before any row is read (previously an
  early `no_hold` return leaked a silent no-op success).
- `driver_funding_allocate` gained a caller guard (it had none) and is now
  service-role only.
- Read-only surfaces (`driver_balance_summary`, `driver_financial_eligibility`,
  `finance_policy_current`, `finance_mission_requirement(_v2)`) revoked from
  `PUBLIC`/`anon`, granted to `authenticated`; `driver_balance_summary` still
  self-guards cross-driver reads.
- Exceptional resolution stays narrow and audited: capture reversal and claims
  resolution remain God-Admin-only; starter credit remains God Admin /
  approval service only.

## Post-hardening privilege matrix (`has_function_privilege`)

| function | anon | authenticated | service_role |
|---|---|---|---|
| `driver_mission_hold_release` | f | f | t |
| `driver_mission_commission_capture` | f | f | t |
| `driver_mission_fee_capture` | f | f | t |
| `driver_collateral_resolve` | f | f | t |
| `driver_mission_capture_reverse` | f | f | t |
| `driver_funding_allocate` | f | f | t |
| `_ledger_post` / `_ledger_reverse` / `_promo_*` | f | f | t |
| `merchant_payable_*` / `merchant_settlement_*` | f | f | t |
| `customer_cancellation_debt_*` | f | f | t |
| `claims_reserve_*` / `driver_payout_hold_place` | f | f | t |
| `driver_starter_credit_grant` | f | f | t |
| `chop_pay_customer_capture` / `_refund` | f | f | t |
| `chop_pay_customer_hold_place` | f | t | t (intended: customer places own hold) |
| `driver_balance_summary` | f | t | t (read-only, self-scoped) |
| `driver_financial_eligibility` | f | t | t (read-only) |
| `finance_policy_current` | f | t | t (read-only) |

## Executed abuse QA (self-rolling-back, driver identity simulated)

22/22 PASS. Harness raised at the end to force ROLLBACK; runner deleted after.

| # | Test | Result |
|---|---|---|
| A | Direct commission release | DENIED — Not authorized |
| B | Direct collateral release | DENIED — Not authorized |
| C | Commission capture, final value 0 | DENIED |
| D | Commission capture, manipulated value | DENIED |
| E | Platform-fee capture, basis 0 | DENIED |
| F | Collateral resolve | DENIED |
| G | Capture reversal | DENIED — God Admin only |
| H | Cross-driver source ID release | DENIED |
| I1 | Merchant payable funding | DENIED |
| I2 | Cancellation debt waive | DENIED |
| I3 | Payout hold place | DENIED |
| I4 | Merchant settlement complete | DENIED |
| I5 | Claims resolve | DENIED — God Admin only |
| I6 | Self-grant starter credit | DENIED |
| I7 | Internal funding allocator | DENIED (was ALLOWED before this patch) |
| I8 | Direct `_ledger_post` | rejected (empty-journal invariant; EXECUTE also revoked) |
| K1 | Own balance summary read | ALLOWED (intended) |
| K2 | Other driver's balance read | DENIED |
| J1 | Service-role commission capture | OK, `captured_gnf` 10 000 from unrestricted |
| J2 | Service-role release | OK |
| J3 | Release replay | idempotent |
| J4 | All journals zero-sum | sum = 0 |

Honest caveat on I8: PostgreSQL forbids `SET ROLE` inside a SECURITY DEFINER
harness, so role switching was not possible in-transaction. Denials A–K were
proven through the functions' identity guards; the role-level barrier is proven
separately by the `has_function_privilege` matrix above. Both layers now hold.

Rollback proof — wallet total identical before (10 703 711 GNF) and after
(10 703 711 GNF); in-transaction fixtures (2 holds, 3 journals) all gone.

## Cleanup counts (post-run, read-only)

journals 0 · postings 0 · holds 0 · promo_credits 0 · payables 0 ·
cancellation debts 0 · claims 0.

QA runner source removed: `supabase/functions/qa-s1x/` and the temporary
`qa-s1c` runner are deleted from the repo and undeployed; DB harness functions
dropped. No `_qa_s1x_run`, `_qa_s1c_run` or test-persona code remains
deployable. Historical migrations retain create/drop evidence only.

## DEF-FIN-001 — platform master wallet negative balance (Finance follow-up)

- wallet id `b6858980-43d2-425d-b12d-b02aac3de52d`
- party_type `master`, `owner_user_id` NULL
- balance / available: **-100 435 GNF**
- Pre-existing production data; predates Slice 1 and is unrelated to any test
  fixture (all Slice 1 harnesses verified rolled back).
- Classification: Finance reconciliation follow-up. **Not** a Slice 1 test leak
  and **not** a user-wallet negative-balance failure.
- Action: do NOT credit or normalize. Reconcile against historical commission
  captures and cancellation fees before Chop Pay activation.

## Build / test evidence

- `tsgo --noEmit` — clean, exit 0.
- `vitest run` — 12/12 passed (2 files).
- `vite build` — success in 21.59 s. Largest asset `index-*.js` 2 131.20 kB
  (gzip 614.29 kB); `mapbox-gl` 1 781.48 kB.
- PWA `generateSW` — `dist/sw.js` + `dist/workbox-*.js` generated, 129 precache
  entries (11 824.25 KiB) under the 4 MiB per-file Workbox limit.
- No manual mobile/user-flow QA claimed: no UI changed in this closeout.

## Feature flags (unchanged, all financial rails OFF)

`chop_pay_enabled` f · `chop_pay_checkout_enabled` f · `chop_pay_p2p_enabled` f
· `driver_balance_gate_enabled` f · `driver_starter_credit_enabled` f ·
`envoyer_enabled` f · `om_direct_checkout_enabled` f ·
`merchant_om_settlement_enabled` f · `wallet_public_enabled` f ·
`om_topup_enabled` **t** (the only intentionally live rail).
