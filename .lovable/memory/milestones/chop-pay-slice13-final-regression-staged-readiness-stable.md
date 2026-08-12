---
name: Chop Pay Slice 13 — Final Regression & Staged Readiness (Stable)
description: Locked 2026-08-11 — entire Chop Pay finance stack re-proved as one system, 503/503 assertions PASS across parts 1-7, staged rails remain OFF
type: feature
---

# chop-pay-slice13-final-regression-staged-readiness-stable

Full-system financial regression across all seven parts: **503 / 503 assertions PASS, 0 failures**
(1: 18, 2: 32, 3: 54, 4: 98, 5: 115, 6: 87, 7: 99). Harness `public._qa_s13_run1..run7()`,
service_role only, each part self-rolling-back. Results table: `public._qa_s13_results`.

App regression at this head: typecheck PASS, vitest 20/20 PASS, production Vite build PASS
(PWA service worker generated).

## Security posture fixes landed in Part 7
- `provider_fee_schedules` and `payment_provider_events` no longer grant anything to `anon`.
  `authenticated` keeps SELECT on fee schedules, and SELECT + UPDATE on provider events
  (admin-only RLS policy powers the reconciliation screen). INSERT/DELETE denied.
- 14 internal money-moving primitives (`_ledger_*`, `_payout_*`, `_merchant_*`, `_chop_pay_*`,
  `_cash_order_*`, `_package_*`, `_driver_*`, `_customer_cancellation_*`) revoked from
  `anon`/`authenticated`; `service_role` only. Full rerun after revocation is green.

## Live posture (unchanged by the regression)
Master wallet -100435 GNF / held 0. Global ledger posting sum 0, zero imbalanced journals.
Feature flags byte-identical; `om_topup_enabled` is the only finance rail ON. No fixture residue.

## Staged readiness — NO FLAG ACTIVATED
Stages 1-4 GREEN but OFF. Stage 4b (OM inbound top-up) LIVE. Stage 5 (merchant settlement +
manual OM outbound) GREEN on synthetic evidence, OFF — activation is a business decision.
Stages 6 (driver cashout) and 7 (P2P) GREEN as *blocked*, OFF.

## YELLOW (carried)
- All provider evidence, inbound and outbound, is production-format **synthetic** — no live
  Orange Money receipt has ever been exercised.
- No authenticated Finance-operator visual QA of `/admin/wallet/payouts` or `/admin/treasury`.

Details: `docs/qa/chop-pay-slice13-results.md`.

## Final closeout (2026-08-11 23:43 UTC)

### `sandbox_exec` disposition
`sandbox_exec` is the platform-managed maintenance/debug DB login (LOGIN, INHERIT, BYPASSRLS, not
superuser; grantable only to `postgres`; no EXECUTE on any function, including the `_qa_s13_*`
harness — the harness runs as `postgres`/`service_role`). It held blanket `SELECT, INSERT` on all 278
public tables, which is why it appeared on `provider_fee_schedules` / `payment_provider_events`.
Because it holds BYPASSRLS, grants — not policies — are the only boundary.

Applied (posture only): `INSERT` **revoked** from `sandbox_exec` on all 38 money-bearing tables
(wallets, ledger, payment intents/events, payouts + evidence, provider fee schedules, merchant
settlement, claims, debts, driver finance, order/package runtimes, topups, feature flags).
`SELECT` retained. No product RLS, no `service_role` boundary, no `anon`/`authenticated` grant changed;
no financial semantics changed. Proven post-fix: production-mode inserts into
`payment_provider_events`, `provider_fee_schedules`, `ledger_postings`, `wallets` all refused.
Residual stated honestly: it keeps BYPASSRLS and blanket read — a platform login unreachable from any
application path.

### Single untouched atomic sweep
`_qa_s13_run1() … run7()` executed once, in order, in one transaction after the final edit.
All seven rows share the final-batch timestamp **2026-08-11 23:43:16.779052+00**.
**18 / 32 / 54 / 98 / 115 / 87 / 99 = 503 / 503 PASS, 0 failures.**

Posture after: master **-100435 GNF / held 0**; ledger posting sum 0 over 0 rows (rollback
cleanliness — production ledger tables are empty, not balanced-volume proof); zero imbalanced
journals; flags byte-identical with `om_topup_enabled` the only finance rail ON; no financial
fixture residue; `_qa_s13_run1..7` service_role only; 0 internal money-moving primitives exposed to
anon/authenticated. Typecheck PASS, vitest 20/20, Vite build PASS + PWA (chunk advisory YELLOW).

YELLOW carried: no live Orange Money receipt ever exercised; no authenticated Finance-operator
visual QA. No flag activated. Slice 13 closed — no Slice 14.

## Final security closeout correction (2026-08-12 00:00 UTC) — 503 retired, 507/507 is the board

A post-closeout independent audit found a real production defect: `public.admin_anonymize_user`
(SECURITY DEFINER) was guarded by `_caller IS NOT NULL AND NOT (god_admin OR super_admin)`, so any
caller with `auth.uid() IS NULL` passed. EXECUTE was held by PUBLIC → anon, authenticated and
`sandbox_exec` all had effective EXECUTE on an arbitrary-target account anonymizer.

Fixed (posture only, no financial semantics, RLS, flags, wallet or Slice 13 behaviour changed):
- fail-closed guard — NULL caller forbidden unless the request role is `service_role` (the only real
  callsite is the `admin-delete-user` edge function, which calls with the service key); non-null
  callers must be god_admin/super_admin;
- PUBLIC + anon EXECUTE revoked; only `authenticated` and `service_role` retained;
- `_anonymize_user_core` → `service_role` only;
- `admin_auth_user_exists` (unguarded existence oracle, PUBLIC EXECUTE) given the same fail-closed
  guard and PUBLIC/anon revoked; `admin_pre_purge_test_user` grant-tightened only.
- Sibling sweep: no other anon/authenticated-reachable SECURITY DEFINER function uses the pattern;
  all others gate through `_is_ops_or_god_admin` / `has_admin_role` / `has_role`, which fail closed
  on NULL.

Part 7 gained four non-vacuous security assertions (S7.1 grants, S7.2 anon refused, S7.3 non-admin
refused, S7.4 God Admin still succeeds), so Part 7 is **103** and the honest total is **507**.

One untouched sequential sweep after the last edit, single transaction, all seven rows stamped
**2026-08-11 23:59:40.002633+00**: **18 / 32 / 54 / 98 / 115 / 87 / 103 = 507 / 507 PASS, 0 failures.**

Posture re-proved: master **-100435 / held 0**; ledger sum 0 over 0 rows (rollback cleanliness);
0 imbalanced journals; flags unchanged with `om_topup_enabled` the only finance rail ON; no fixture
residue; `_qa_s13_*` service_role-only; 0 internal money primitives exposed to anon/auth;
`sandbox_exec` INSERT on the locked 38 money-bearing tables = 0; anon and `sandbox_exec` effective
EXECUTE on `admin_anonymize_user` = false. Typecheck PASS, vitest 20/20, Vite build PASS + PWA.

YELLOW carried: no live Orange Money receipt; no authenticated Finance-operator visual QA; chunk
advisory. NEW YELLOW (DEF-OPS-003, surfaced by S7.4): `_anonymize_user_core` has two stale steps
(`merchant_stores.is_active`, `driver_locations.driver_id`, SQLSTATE 42703) — pre-existing data
hygiene, deliberately not patched so the final sweep stayed untouched.

No flags activated. Slice 13 closed. No Slice 14.
