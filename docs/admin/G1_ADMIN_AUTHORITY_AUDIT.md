# G1 — Admin Authority Audit (evidence)

Census date: **2026-09-05**, live database `public` schema at current HEAD.
All figures below are re-counted from the live catalog and the repository, superseding the
earlier exploratory scan. Docs-only pass: **no DB mutation, no behavior change in G1.**

Constitution: [`ADMIN_CAPABILITY_CONSTITUTION.md`](./ADMIN_CAPABILITY_CONSTITUTION.md).

---

## 0. Correction of prior (stale) figures

| Prior exploratory claim | Verified at HEAD | Note |
|---|---|---|
| 86 `admin_*` RPCs | **91** (incl. 3 overload pairs) | catalog count |
| 34 anon-EXECUTE `admin_*` | **0** | closed by the G2/G3 pass already shipped 2026-09-05 (`REVOKE ... FROM PUBLIC, anon`) |
| 32 `admin_*` without a known guard helper | **0 genuinely unguarded**; 2 match no helper regex (`admin_clear_must_change_password`, `admin_email_delivery_diagnostics`) and were read line-by-line — both verify staff status inline (`admin_users.status='active'`, god/super only) | regex false positives |
| 42 admin pages | **43** page components, **42** sidebar entries, **44** routes under `/admin` | see §E |
| 4 operational pages without ModulePage | **4** (`AnalyticsAdmin`, `DriverSignalsAdmin`, `FieldPilotsAdmin`, `MapRoutingAdmin`), each now wrapped by `AdminRouteGuard` at the route; `AdminChangePassword` intentionally unguarded | see §E |
| staff-creation false 500 caused by `.catch()` on a PostgREST builder after successful writes | **CONFIRMED** — thenable, not a Promise; `TypeError` after all writes committed | fixed in G3 |
| two Operations Admin records may already exist | **CONFIRMED** — `admin_users`: `ops_admin` active = 2, `super_admin` active = 1 | remediation is a God decision, untouched in G1 |

---

## A. `admin_*` public RPCs — 91 total

Grants at HEAD: `anon` EXECUTE = **0**; `authenticated` EXECUTE = **90**;
`service_role` = all; 1 (`_finance_treasury_facts`-class internal) service-role only.
All are `SECURITY DEFINER`. Guard predicate present in **91/91**.

| Domain | Count | Callables | Mutation class | Target capability | Ops / Fin / God | Four-eyes | G2 status |
|---|---|---|---|---|---|---|---|
| capability-core | 5 | `admin_capability`, `admin_capability_mode`, `admin_four_eyes_gate`, `admin_require_capability`, `admin_role_canonical` | read | (infrastructure) | R/R/R | no | KEEP |
| identity/governance | 15 | `admin_ban_user`, `admin_unban_user`, `admin_freeze_user`, `admin_unfreeze_user`, `admin_anonymize_user`, `admin_account_closure_reconcile`, `admin_governance_set_status`, `admin_professional_offboard`, `admin_professional_restore`, `admin_auth_user_exists`, `admin_check_email_reuse_blocker`, `admin_clear_must_change_password`, `admin_dormant_liabilities`, `admin_log_test_delete`, `admin_pre_purge_test_user` | identity mutation / destructive (ban, freeze reversible) | `governance.account.ban` / `.freeze` / `.close` / `.anonymize`, `governance.professional.offboard` | ban+freeze A/D/A; closure, anonymize, offboard D/D/AR | yes for destructive | GUARD + SERVER_APPROVAL_GATE |
| finance/payments | 23 | `admin_adjust_agent_float`, `admin_set_finance_policy`, `admin_set_finance_delegation`, `admin_set_payout_policy`, `admin_set_merchant_settlement_policy`, `admin_generate_payout_statement`, `admin_set_statement_status`, `admin_review_commission`, `admin_review_commission_risk`, `admin_backfill_missing_driver_earnings`, `admin_cash_order_dispute_resolve`, `admin_chop_pay_cancel`, `admin_chop_pay_dispute_resolve`, `admin_promotional_credit_treasury`, `admin_set_repas_promotion`, `admin_disable_repas_promotion`, `admin_preview_*` (7 read-only previews) | financial mutation (previews = read) | `finance.policy.change`, `finance.payouts.manage`, `finance.wallet.adjust`, `finance.treasury.move`, `finance.flags.payment` | D/A or AR/AR | yes for policy, float above limit, treasury movement | GUARD + SERVER_APPROVAL_GATE |
| operations/driver | 21 | `admin_list_driver_applications`, `admin_get_driver_application_detail`, `admin_request_driver_info`, `admin_set_driver_capability`, `admin_create_driver_group`, `admin_update_driver_group`, `admin_assign_driver_to_group`, `admin_remove_driver_from_group`, `admin_create_contract`, `admin_update_contract`, `admin_create_campaign`, `admin_update_campaign`, `admin_attach_referral_campaign`, `admin_mark_referral`, `admin_review_referral_risk`, `admin_regenerate_group_referral_code`, `admin_enqueue_milestone_refresh`, `admin_driver_group_stats`, `admin_group_scorecard`, `admin_group_risk_scorecard`, `admin_list_field_checkins` | operational mutation / read | `ops.drivers.manage` | A/R/A | no | KEEP + GUARD |
| operations/commerce | 7 | `admin_merchant_decision`, `admin_merchant_service_agent_decision`, `admin_set_merchant_location_status`, `admin_link_restaurant_to_merchant_store`, `admin_marche_capture_and_settle_offer`, `admin_repas_capture_and_settle_order`, `admin_preview_missing_merchant_revenue` | operational mutation; the two `capture_and_settle` are **financial mutation** | `ops.merchants.manage`; capture/settle → `finance.payouts.manage` | A/R/A; capture/settle D/A/A | no | SPLIT_READ_WRITE (capture/settle must leave the ops capability) |
| maps | 1 | `admin_zone_coverage_stats` | read | `ops.maps.manage` | A/R/A | no | KEEP |
| support-risk | 1 | `admin_email_delivery_diagnostics` | read | `ops.support.manage` (currently god-only inline) | A/R/A | no | GUARD (widen to ops via capability, not role literal) |
| cross-domain | 18 | `admin_create_agent`, `admin_staff_role_grant`, `admin_staff_role_revoke`, `admin_set_feature_flag`, `admin_set_provider_fee_schedule`, `admin_set_starter_credit_policy`, `admin_reverse_starter_credit`, `admin_manual_om_credit`, `admin_record_om_receipt`, `admin_retry_om_credit`, `admin_mark_om_conflict`, `admin_package_claim_resolve`, `admin_package_claim_set_documented_value`, `admin_preview_p2p_transfers`, `admin_preview_service_agent_cashins`, `admin_incentive_suggestions`, `admin_set_statement_status`, `admin_pre_purge_test_user` | mixed: governance mutation (`staff_role_*`, `set_feature_flag`), financial mutation (OM credit/receipt/retry, starter credit, fee schedule, package claim value) | `governance.staff.manage`, `governance.roles.assign`, `governance.flags.manage` / `finance.flags.payment`, `finance.topup.manage`, `finance.wallet.credit` | staff/roles D/D/AR; flags D(propose)/D/A, payment flags D/AR/AR; OM D/A/A; manual credit D/AR/AR | yes for staff, roles, payment flags, manual credit | SERVER_APPROVAL_GATE + MANUAL_REVIEW_REQUIRED (`admin_set_feature_flag` must split product vs payment-rail flags) |

Unclassified rows: **0**.

## B. Privileged non-`admin_*` RPCs reachable by authenticated callers — 44

Domain prefixes `finance_*`, `wallet_*`, `payout_*`, `driver_cashout_*`,
`merchant_settlement_*`, `payment_*`. `anon` EXECUTE = 2, both **trigger functions**
(`payment_intents_before_insert`, `payment_intents_after_insert`) which PostgREST does not
expose — not callables.

| Group | Callables | Mutation class | Capability | Ops / Fin / God | Four-eyes | G2 status |
|---|---|---|---|---|---|---|
| Treasury read | `finance_treasury_overview`, `finance_treasury_exceptions`, `finance_treasury_drilldown` | read | `finance.treasury.read` | D/A/A (already gated by `_finance_treasury_gate`) | no | KEEP (Slice 12 frozen) |
| Finance policy read | `finance_policy_current`, `finance_policy_at`, `finance_policy_snapshot`, `finance_policy_predecessor`, `merchant_settlement_policy_at`, `finance_mission_requirement`, `finance_mission_requirement_v2`, `finance_payout_queue` | read | `finance.wallet.read` | R/A/A | no | KEEP |
| Wallet money movement | `wallet_admin_credit`, `wallet_hold`, `wallet_capture`, `wallet_release`, `wallet_pay_driver_commission`, `wallet_pay_driver_commission_batch`, `wallet_reverse_driver_commission`, `wallet_pay_merchant`, `wallet_ensure`, `wallet_ensure_master`, `wallet_get_master_balance` | financial mutation | `finance.wallet.credit` / `.adjust` / `.read` | D/AR/AR (`wallet_admin_credit`), engine calls stay service-side | yes | SERVER_APPROVAL_GATE for `wallet_admin_credit`; MANUAL_REVIEW_REQUIRED that engine-only functions are not directly callable by staff |
| Top-ups | `wallet_topup_create`, `wallet_topup_om_create`, `wallet_topup_confirm`, `wallet_topup_cancel`, `wallet_topup_admin_cancel`, `wallet_topup_admin_mark_expired` | financial mutation | `finance.topup.manage` | D/A/A | no | GUARD |
| Cashouts / settlements / payouts | `driver_cashout_create_request`, `driver_cashout_cancel_request`, `driver_cashout_mark_paid`, `driver_cashout_reject_request`, `merchant_settlement_request_create`, `merchant_settlement_requests_list`, `merchant_settlement_receipt`, `merchant_settlement_schedule_generate`, `payout_reconcile_evidence`, `payout_record_provider_evidence`, `payout_reject_release`, `finance_confirm_manual_om_payout` | financial mutation | `finance.payouts.manage`, `finance.payout.confirm` | D/A/A; `finance_confirm_manual_om_payout` D/AR/AR | yes on manual confirm | SERVER_APPROVAL_GATE |
| P2P | `wallet_p2p_lookup_recipient`, `wallet_p2p_transfer` | financial mutation (user-scoped, not staff) | n/a — end-user path | D/D/D as staff capability | no | KEEP (self-scoped) |

## C. Admin-facing Edge Functions — 8

| Function | Domain | Mutation class | Caller check at HEAD | Target capability | Ops / Fin / God | Four-eyes | G2 status |
|---|---|---|---|---|---|---|---|
| `admin-create-staff-user` | staff | governance mutation | JWT + `admin_users` god/super OR `user_roles.god_admin` | `governance.staff.manage` | D/D/AR | yes | SERVER_APPROVAL_GATE |
| `admin-delete-user` | identity | destructive | JWT + `admin_users` god | `governance.account.anonymize` | D/D/AR | yes | SERVER_APPROVAL_GATE |
| `admin-driver-doc-url` | operations | read (signed URL, 600s) | JWT + RPC `can_manage_operations` | `ops.drivers.manage` | A/R/A | no | KEEP |
| `admin-email-resend` | support | operational mutation | JWT + `admin_users` god | `ops.support.manage` | GUARD to A/R/A | no | GUARD (currently narrower than constitution) |
| `om-import-csv` | finance | financial mutation | JWT + `admin_users` god | `finance.topup.manage` | D/A/A | no | GUARD (widen to finance, capability-based) |
| `account-access-termination-worker` | identity | destructive worker | service_role / god | `governance.account.close` | D/D/A (system) | n/a | KEEP |
| `qa-merchant-harness` | cross-domain | operational mutation (creates test data) | env flag `QA_HARNESS_ENABLED` + `has_role('admin')` | (non-production) | D/D/A | no | MANUAL_REVIEW_REQUIRED — `has_role('admin')` is the bare-`admin` alias the constitution refuses |
| `qa-node-harness` | cross-domain | mixed | static `x-qa-token` OR service key OR `has_role('admin')` | (non-production) | D/D/A | no | MANUAL_REVIEW_REQUIRED — static-token path and bare-`admin` alias |

## D. Tables and RLS reachable by staff

- Public tables: **172**.
- Tables with at least one admin-referencing policy: **110**.
- Tables with RLS enabled and **no policy at all**: **31** (deny-all by default — safe, but
  each must be confirmed intentional; linter INFO 0008).
- Slice 12 frozen posture holds: raw finance tables are `authenticated` SELECT-only,
  `anon` revoked, writes only through approved RPCs.
- `audit_logs` (94 rows) and `approval_requests` (0 rows) exist and are append-only for staff.

G2 status: MANUAL_REVIEW_REQUIRED on the 31 policy-less tables; SPLIT_READ_WRITE review on any
table where an operations policy currently permits writing a financial column.

## E. `/admin` surface

- Route entries under `/admin`: **44** (43 page components + index redirect).
- Sidebar entries: **42**.
- Pages with `ModulePage` module gating: **38**.
- Pages without `ModulePage`: **5** — `AnalyticsAdmin`, `DriverSignalsAdmin`,
  `FieldPilotsAdmin`, `MapRoutingAdmin` (all four wrapped by `AdminRouteGuard` at the route),
  and `AdminChangePassword` (intentionally outside the admin shell so a staff member forced to
  rotate a password can reach it).
- Pages with **no** module or capability gating: **0**.
- `AdminGuard` wraps the whole shell but only answers "is this an admin", not "which module" —
  module authority is the `ModulePage` / `AdminRouteGuard` layer, and both are frontend-only.

Every page maps to a constitutional capability through its declared `module`; unclassified
pages: **0**.

## F. Role sources

| Source | Values in use at HEAD | Authoritative for |
|---|---|---|
| `admin_users.admin_role` (enum `admin_role`: `super_admin`, `ops_admin`, `finance_admin`, `god_admin`, `operations_admin`, `support_admin`) + `status` + `must_change_password` | `ops_admin` active ×2, `super_admin` active ×1 | staff class, corroboration for conflict resolution |
| `user_roles.role` (enum `app_role`) | `god_admin` ×1, `operations_admin` ×2, bare `admin` ×1 | app-role checks (`has_role`) |
| Frontend `src/lib/admin/permissions.ts` (`AdminRole`, `PERMISSIONS`, `can()`), mapped in `useAdminAuth` with a `roles.includes("admin") → god_admin` fallback | 3 classes, 24 modules | **display only** — drift risk, see G2 worklist |
| SQL helpers | `admin_role_canonical`, `admin_capability`, `admin_capability_mode`, `admin_require_capability`, `admin_four_eyes_gate`, `auth_uid_active`, `is_any_admin`, `is_god_admin`, `has_admin_role`, `can_manage_operations`, `can_manage_wallet`, `_is_god_admin`, `_is_ops_or_god_admin`, `_finance_privileged`, `_governance_role_allowed`, `_finance_treasury_gate` | 6 enum labels → 3 canonical classes; **6 aliases** to normalize |

The frontend `admin → god_admin` fallback is unconstitutional (principle 6) and is a G2 item.

## G. Approval / audit primitives already present

- `approval_requests` (id, requested_by, requested_role, module, action, payload, status,
  reviewed_by, review_note, reviewed_at, created_at) — 0 rows; no expiry, no consumption
  marker, no target/parameter binding columns yet.
- `src/lib/admin/approvals.ts` — `requestApproval`, `requireApprovalOr`,
  `APPROVAL_REQUIRED_ACTIONS` (10 actions) — **frontend-only enforcement today**.
- `audit_logs` + `log_admin_action` RPC — 94 rows, append-only.
- `admin_capability_grants` — 18 capabilities registered, **7** in `approval_required` mode.
- `admin_four_eyes_gate(capability, approval_id)` — enforces requester ≠ approver and
  approver-is-god, but does **not** yet bind target/parameters, expiry, or single consumption.
- `account_access_terminations`, `admin_governance_set_status`, `_finance_evidence_claim`.

---

## G2 worklist (generated by G1, prioritized)

### CRITICAL
1. Bind four-eyes approvals to exact target + material parameters; add expiry and
   single-consumption/idempotency to `approval_requests` and `admin_four_eyes_gate`.
2. Move approval enforcement from `src/lib/admin/approvals.ts` into the database for all
   17 APPROVAL_REQUIRED actions; the frontend list becomes advisory only.
3. Split `admin_set_feature_flag` into product flags (`governance.flags.manage`) and
   payment-rail flags (`finance.flags.payment`, approval-required).
4. Remove the `has_role('admin')` bare-alias acceptance from `qa-merchant-harness` and
   `qa-node-harness`, and retire the static `x-qa-token` path in production.
5. Move `admin_marche_capture_and_settle_offer` and `admin_repas_capture_and_settle_order`
   out of the operations capability into `finance.payouts.manage`.

### HIGH
6. Remove the frontend `roles.includes("admin") → god_admin` fallback in `useAdminAuth`.
7. Normalize role aliases in data: reconcile the 1 bare `admin` row and the
   `ops_admin` vs `operations_admin` split across `admin_users` and `user_roles`
   (includes a God decision on the two duplicate Operations Admin accounts).
8. Replace role literals inside RPC bodies (`admin_role IN ('god_admin','super_admin')`)
   with `admin_require_capability(...)` so the constitution is the only source.
9. Widen `admin-email-resend` and `om-import-csv` from god-only role literals to
   capability checks (`ops.support.manage`, `finance.topup.manage`).
10. Extend `admin_capability_grants` from 18 to the full 33-capability namespace.

### MEDIUM
11. Review the 31 RLS-enabled/no-policy tables; confirm deny-all is intended per table.
12. SPLIT_READ_WRITE review of policies letting an operations actor write financial columns.
13. Convert `AdminRouteGuard` route wrappers into in-page `ModulePage` gating for the
    4 pages that lack it, so module identity travels with the page.
14. Add a drift test binding `PERMISSIONS` in the frontend to `admin_capability_grants`.
15. Encode `POLICY_THRESHOLD_REQUIRED` values (refund, cashout, float) in `finance_policies`
    and have the gates read them at execution time.

Already closed before G1 (recorded for provenance, not G2 work):
`anon` EXECUTE revoked on all `admin_*` (34 → 0); `admin_log_test_delete` staff-gated;
staff-creation false-500 fixed; ops/finance landing consoles shipped.

---

## G1 QA evidence

| Metric | Count |
|---|---|
| `admin_*` RPCs | 91 |
| … anon-executable | 0 |
| … authenticated-executable | 90 |
| … with a guard predicate | 91 (0 unguarded) |
| Privileged non-`admin_*` finance/governance callables | 44 (2 anon entries are triggers, not callables) |
| Admin-facing Edge Functions | 8 |
| `/admin` routes | 44 |
| Admin page components | 43 |
| Sidebar entries | 42 |
| Pages without `ModulePage` | 5 (4 route-guarded + 1 intentional) |
| Pages with no gating at all | 0 |
| Role labels in the `admin_role` enum | 6 → 3 canonical (6 alias mappings incl. bare `admin`) |
| APPROVAL_REQUIRED actions | 17 |
| Capabilities in the namespace | 33 (18 currently registered in `admin_capability_grants`) |
| G2 items — CRITICAL / HIGH / MEDIUM | 5 / 5 / 5 |
| Unclassified callables or pages | 0 |
