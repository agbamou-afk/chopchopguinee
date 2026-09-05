# G1 — Admin Authority Audit (CHOP CHOP)

Status: **G1 evidence pack — read-only.** Generated from current HEAD and a live read-only
census of the production Cloud database. No migration, grant, revoke, RLS edit, role row,
feature flag, or Edge Function behaviour was changed to produce this document.

Companion law: `docs/admin/ADMIN_CAPABILITY_CONSTITUTION.md`.

---

## 0. Corrections to earlier provisional numbers

| Provisional claim (earlier scan) | Verified at HEAD / live DB | Verdict |
|---|---|---|
| 86 `admin_*` RPCs | **91** | corrected |
| 34 `admin_*` RPCs executable by `anon` | **0** | corrected (already revoked) |
| 32 `admin_*` RPCs with no guard | **0** — every body inspected; the two regex-blind ones (`admin_clear_must_change_password`, `admin_email_delivery_diagnostics`) carry an inline `admin_users` predicate | corrected |
| ~42 admin pages | **43** page components, **44** routes (43 + index), **42** sidebar entries | corrected |
| `AnalyticsAdmin` / `DriverSignalsAdmin` / `FieldPilotsAdmin` / `MapRoutingAdmin` missing `ModulePage` | confirmed — but all four are wrapped in `AdminRouteGuard` with an explicit role list, so they are guarded, not open. Gap is *capability granularity*, not absence of a guard | refined |
| `AdminChangePassword` intentionally unwrapped | confirmed (must-change-password flow runs before module authority exists) | confirmed |
| False-500 on staff creation caused by `.catch()` on a PostgREST builder after successful writes | root cause confirmed; the code path at HEAD (`supabase/functions/admin-create-staff-user/index.ts` L197-215) now awaits and inspects `error`, with the defect documented inline | confirmed / already remediated at HEAD |
| Two Operations Admin records already exist | confirmed — `admin_users` holds `ops_admin:active = 2`, `super_admin:active = 1`. **Untouched in G1.** | confirmed |

---

## 1. Census (live, read-only)

| Metric | Value |
|---|---|
| `admin_*` public RPCs | 91 |
| Additional finance/governance/staff-reachable RPCs classified | 42 |
| **Total callables classified (section 2)** | **133** |
| `admin_*` RPCs executable by `anon` | 0 |
| `admin_*` RPCs executable by `authenticated` | 90 (1 service-only: `admin_log_test_delete`) |
| Admin-facing Edge Functions | 8 |
| Admin page components / routes / sidebar entries | 43 / 44 / 42 |
| Pages with no module-level capability binding | 4 (all `AdminRouteGuard`-wrapped) + 1 intentional |
| Public tables | 172 |
| Tables with an admin-referencing RLS policy | 110 |
| Public tables with **no** policy at all | 31 |
| `admin_role` enum labels | 6 → 3 canonical classes |
| `admin_users` rows | `ops_admin:active=2`, `super_admin:active=1` |
| `user_roles` staff-bearing rows | `god_admin=1`, `operations_admin=2`, `admin=1` (legacy) |
| `admin_capability_grants` rows / distinct capabilities | 18 / 18 |
| `approval_requests` rows | 0 (primitive exists, never exercised) |
| `audit_logs` rows | 94 |
| APPROVAL_REQUIRED callables (section 2) | 21 |

Mutation classes across the 133 callables: read 48 · operational 30 · financial 43 ·
governance 3 · identity 6 · destructive 3.

Domains: finance 73 · operations 26 · identity 9 · cross-domain 9 · governance 8 ·
support-risk 7 · maps 1.

G2 remediation tags: KEEP 36 · GUARD 69 · SERVER_APPROVAL_GATE 28 · REVOKE_ANON 0 ·
SPLIT_READ_WRITE 0 · MANUAL_REVIEW_REQUIRED 0.

Guard predicates in use (occurrences): `_is_ops_or_god_admin` 30 · inline `admin_users`
check 25 · `has_role(...)` 21 · `is_god_admin` 24 (incl. combinations) · `can_manage_wallet` 8 ·
`_is_god_admin` 4 · `_finance_privileged` 3 · `_finance_treasury_gate` 3 ·
`can_manage_operations` 3 · `is_any_admin` 4 · `admin_capability` / `admin_require_capability` 4 ·
`_governance_role_allowed` 2 · `admin_role_canonical` 2 · `auth_uid_active` 1.

---

## 2. A + B — every callable RPC, classified

Every row was produced from `pg_get_functiondef` at census time. Ambiguous bodies
(`admin_clear_must_change_password`, `admin_email_delivery_diagnostics`,
`admin_link_restaurant_to_merchant_store`, `admin_marche_capture_and_settle_offer`,
`admin_repas_capture_and_settle_order`, `admin_merchant_service_agent_decision`, and all
`admin_preview_*`) were read individually: the first two use an inline
`admin_users` predicate, the rest use `has_role(auth.uid(), 'admin')` — the **legacy bare
`admin` alias**, which the constitution refuses as a source of authority. Those are the
highest-value `GUARD` items in the G2 worklist.

Legend — Ops / Finance / God columns: ALLOW · DENY · READ_ONLY · APPROVAL_REQUIRED.
Rows marked `n/a (end-user rail)` are runtime rails callable by the owning end user, not
staff surfaces; they are listed because they are reachable by an authenticated staff
session and must stay outside the staff capability model.

| Callable | Domain | Mutation class | Grants | Current guard | Target capability | Ops | Finance | God | 4-eyes | G2 tag |
|---|---|---|---|---|---|---|---|---|---|---|
| `admin_account_closure_reconcile(_target uuid, _reason text)` | identity | identity | auth,service | `_is_ops_or_god_admin` | `governance.account.close` | DENY | DENY | APPROVAL_REQUIRED | yes | SERVER_APPROVAL_GATE |
| `admin_adjust_agent_float(p_agent_user_id uuid, p_delta_gnf bigint, p_reason text)` | finance | financial | auth,service | `has_role` | `finance.wallet.adjust` | DENY | APPROVAL_REQUIRED | APPROVAL_REQUIRED | yes | GUARD |
| `admin_anonymize_user(_target uuid, _reason text)` | identity | destructive | auth,service | `has_admin_role` | `governance.account.anonymize` | DENY | DENY | APPROVAL_REQUIRED | yes | SERVER_APPROVAL_GATE |
| `admin_assign_driver_to_group(p_group uuid, p_driver uuid, p_zone text, p_notes text)` | operations | operational | auth,service | `_is_ops_or_god_admin` | `ops.drivers.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_attach_referral_campaign(p_referral uuid, p_campaign uuid, p_reason text)` | operations | operational | auth,service | `_is_ops_or_god_admin` | `ops.drivers.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_auth_user_exists(_target uuid)` | identity | read | auth,service | `has_admin_role` | `ops.users.manage` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_backfill_missing_driver_earnings(p_dry_run boolean, p_limit integer, p_reason text)` | finance | financial | auth,service | `has_role` | `finance.wallet.adjust` | DENY | APPROVAL_REQUIRED | APPROVAL_REQUIRED | yes | GUARD |
| `admin_ban_user(_target uuid, _reason text, _expires_at timestamp with time zone)` | identity | identity | auth,service | `_is_god_admin` | `governance.account.ban` | DENY | DENY | APPROVAL_REQUIRED | yes | SERVER_APPROVAL_GATE |
| `admin_capability(_capability text, _uid uuid)` | governance | read | auth,service | `admin_capability; admin_role_canonical` | `governance.capability.resolve` | READ_ONLY | READ_ONLY | ALLOW | no | KEEP |
| `admin_capability_mode(_capability text, _uid uuid)` | governance | read | auth,service | `admin_capability; admin_role_canonical` | `governance.capability.resolve` | READ_ONLY | READ_ONLY | ALLOW | no | KEEP |
| `admin_cash_order_dispute_resolve(p_source_module text, p_source_id uuid, p_outcome text, p_reason text)` | support-risk | operational | auth,service | `_finance_privileged` | `finance.dispute.resolve` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_check_email_reuse_blocker(p_email text)` | identity | read | auth,service | `has_admin_role` | `ops.support.manage` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_chop_pay_cancel(p_source_module text, p_source_id uuid, p_responsible_party text, p_reason text)` | cross-domain | read | auth,service | `has_admin_role; is_god_admin` | `finance.audit.view_financial` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_chop_pay_dispute_resolve(p_source_module text, p_source_id uuid, p_outcome text, p_reason text)` | support-risk | operational | auth,service | `has_admin_role; is_god_admin` | `finance.dispute.resolve` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_clear_must_change_password()` | governance | governance | auth,service | `inline admin_users check` | `governance.staff.manage` | DENY | DENY | APPROVAL_REQUIRED | yes | GUARD |
| `admin_create_agent(p_phone text, p_business_name text, p_location text, p_daily_limit_gnf bigint, p_commission_rate numeric)` | operations | operational | auth,service | `has_role` | `ops.onboarding.decide` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_create_campaign(payload jsonb)` | operations | operational | auth,service | `_is_ops_or_god_admin` | `ops.drivers.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_create_contract(payload jsonb)` | operations | operational | auth,service | `_is_ops_or_god_admin` | `ops.drivers.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_create_driver_group(payload jsonb)` | operations | operational | auth,service | `_is_ops_or_god_admin` | `ops.drivers.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_disable_repas_promotion(p_id uuid, p_reason text)` | operations | operational | auth,service | `is_god_admin` | `governance.pricing.change` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_dormant_liabilities()` | finance | read | auth,service | `_is_ops_or_god_admin; has_role` | `finance.treasury.read` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_driver_group_stats(p_group uuid, p_from timestamp with time zone, p_to timestamp with time zone)` | operations | read | auth,service | `_is_ops_or_god_admin` | `ops.drivers.manage` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_email_delivery_diagnostics(p_email text)` | support-risk | read | auth,service | `inline admin_users check` | `ops.orders.manage` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_enqueue_milestone_refresh(p_driver uuid, p_event text)` | operations | operational | auth,service | `_is_ops_or_god_admin` | `ops.drivers.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_four_eyes_gate(_capability text, _approval_id uuid)` | governance | read | auth,service | `admin_capability; admin_require_capability; admin_role_canonical` | `governance.capability.resolve` | READ_ONLY | READ_ONLY | ALLOW | no | KEEP |
| `admin_freeze_user(_target uuid, _reason text, _freeze_type text, _expires_at timestamp with time zone)` | identity | identity | auth,service | `_is_ops_or_god_admin` | `governance.account.freeze` | DENY | DENY | APPROVAL_REQUIRED | yes | SERVER_APPROVAL_GATE |
| `admin_generate_payout_statement(p_group uuid, p_from date, p_to date, p_notes text)` | finance | financial | auth,service | `_is_ops_or_god_admin` | `finance.payouts.manage` | DENY | ALLOW | ALLOW | no | GUARD |
| `admin_get_driver_application_detail(p_user_id uuid)` | operations | read | auth,service | `can_manage_operations` | `ops.drivers.manage` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_governance_set_status(_target uuid, _status text, _reason text)` | governance | governance | auth,service | `_is_god_admin` | `governance.staff.manage` | DENY | DENY | APPROVAL_REQUIRED | yes | SERVER_APPROVAL_GATE |
| `admin_group_risk_scorecard()` | support-risk | read | auth,service | `_is_ops_or_god_admin` | `ops.drivers.manage` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_group_scorecard(p_group uuid, p_days integer)` | operations | read | auth,service | `_is_ops_or_god_admin` | `ops.drivers.manage` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_incentive_suggestions()` | operations | read | auth,service | `_is_ops_or_god_admin` | `ops.drivers.manage` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_link_restaurant_to_merchant_store(p_restaurant_id uuid, p_merchant_store_id uuid)` | operations | operational | auth,service | `has_role` | `ops.merchants.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_list_driver_applications(p_status text)` | operations | read | auth,service | `can_manage_operations` | `ops.drivers.manage` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_list_field_checkins(p_group uuid, p_limit integer)` | operations | read | auth,service | `_is_ops_or_god_admin` | `ops.onboarding.decide` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_log_test_delete(_target uuid, _caller uuid, _reason text)` | governance | destructive | service | `admin_role_canonical` | `governance.audit.read_all` | DENY | DENY | APPROVAL_REQUIRED | yes | SERVER_APPROVAL_GATE |
| `admin_manual_om_credit(p_event_id uuid, p_topup_request_id uuid)` | finance | read | auth,service | `can_manage_wallet` | `finance.audit.view_financial` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_marche_capture_and_settle_offer(p_offer_id uuid, p_reason text)` | finance | financial | auth,service | `has_role` | `finance.wallet.adjust` | DENY | APPROVAL_REQUIRED | APPROVAL_REQUIRED | yes | GUARD |
| `admin_mark_om_conflict(p_event_id uuid, p_reason text)` | finance | financial | auth,service | `can_manage_wallet` | `finance.reconciliation.approve` | DENY | ALLOW | ALLOW | no | SERVER_APPROVAL_GATE |
| `admin_mark_referral(p_referral uuid, p_action text)` | operations | operational | auth,service | `_is_ops_or_god_admin` | `ops.drivers.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_merchant_decision(_store_id uuid, _decision text, _reason text)` | operations | operational | auth,service | `has_role` | `ops.merchants.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_merchant_service_agent_decision(_store_id uuid, _decision text, _notes text)` | operations | operational | auth,service | `has_role` | `ops.merchants.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_package_claim_resolve(p_package_id uuid, p_outcome text, p_reason text, p_evidence_ref text, p_pay_customer_gnf bigint)` | support-risk | operational | auth,service | `is_god_admin` | `finance.dispute.resolve` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_package_claim_set_documented_value(p_package_id uuid, p_documented_actual_value_gnf bigint, p_evidence_ref text, p_reason text)` | support-risk | operational | auth,service | `is_god_admin` | `finance.dispute.resolve` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_pre_purge_test_user(_target uuid)` | cross-domain | destructive | auth,service | `has_admin_role` | `governance.account.anonymize` | ALLOW | READ_ONLY | ALLOW | no | SERVER_APPROVAL_GATE |
| `admin_preview_marche_payment_intents(p_limit integer)` | finance | read | auth,service | `is_any_admin` | `finance.audit.view_financial` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_preview_marche_payment_intents(p_limit integer, p_include_sandbox boolean)` | finance | read | auth,service | `is_any_admin; is_god_admin` | `finance.audit.view_financial` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_preview_marche_payment_settlement(p_limit integer)` | finance | read | auth,service | `has_role` | `finance.audit.view_financial` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_preview_missing_driver_earnings()` | finance | read | auth,service | `has_role` | `finance.wallet.read` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_preview_missing_merchant_revenue(p_source_module text)` | finance | read | auth,service | `has_role` | `finance.wallet.read` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_preview_missing_mission_earnings()` | finance | read | auth,service | `has_role` | `finance.wallet.read` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_preview_p2p_transfers(p_limit integer)` | finance | read | auth,service | `has_role` | `finance.wallet.read` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_preview_payment_intents(p_state text, p_source_module text, p_limit integer, p_include_sandbox boolean)` | finance | read | auth,service | `is_any_admin; is_god_admin` | `finance.audit.view_financial` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_preview_payment_intents(p_state text, p_source_module text, p_limit integer)` | finance | read | auth,service | `is_any_admin` | `finance.audit.view_financial` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_preview_repas_payment_settlement(p_limit integer)` | finance | read | auth,service | `has_role` | `finance.audit.view_financial` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_preview_service_agent_cashins(p_limit integer)` | operations | read | auth,service | `has_role` | `ops.onboarding.decide` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_professional_offboard(_target uuid, _reason text)` | cross-domain | operational | auth,service | `_is_ops_or_god_admin` | `governance.account.close` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_professional_restore(_target uuid, _type text, _reason text)` | cross-domain | operational | auth,service | `_is_ops_or_god_admin` | `ops.merchants.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_promotional_credit_treasury()` | finance | read | auth,service | `has_admin_role; is_god_admin` | `finance.treasury.read` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_record_om_receipt(p_provider_transaction_id text, p_amount_gnf bigint, p_payer_phone text, p_receiving_account_id uuid, p_note text)` | finance | financial | auth,service | `can_manage_wallet` | `finance.reconciliation.approve` | DENY | ALLOW | ALLOW | no | SERVER_APPROVAL_GATE |
| `admin_regenerate_group_referral_code(p_group uuid, p_code text)` | operations | operational | auth,service | `_is_ops_or_god_admin` | `ops.drivers.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_remove_driver_from_group(p_membership uuid, p_reason text)` | finance | financial | auth,service | `_is_ops_or_god_admin` | `finance.reconciliation.approve` | DENY | ALLOW | ALLOW | no | GUARD |
| `admin_repas_capture_and_settle_order(p_food_order_id uuid, p_reason text)` | finance | financial | auth,service | `has_role` | `finance.wallet.adjust` | DENY | APPROVAL_REQUIRED | APPROVAL_REQUIRED | yes | GUARD |
| `admin_request_driver_info(p_user_id uuid, p_missing text[], p_note text)` | operations | operational | auth,service | `can_manage_operations` | `ops.drivers.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_require_capability(_capability text)` | governance | read | auth,service | `admin_capability; admin_require_capability` | `governance.capability.resolve` | READ_ONLY | READ_ONLY | ALLOW | no | KEEP |
| `admin_retry_om_credit(p_event_id uuid)` | finance | financial | auth,service | `can_manage_wallet` | `finance.reconciliation.approve` | DENY | ALLOW | ALLOW | no | SERVER_APPROVAL_GATE |
| `admin_reverse_starter_credit(p_driver uuid, p_reason text)` | finance | financial | auth,service | `is_god_admin` | `finance.wallet.adjust` | DENY | APPROVAL_REQUIRED | APPROVAL_REQUIRED | yes | SERVER_APPROVAL_GATE |
| `admin_review_commission(p_commission uuid, p_action text, p_notes text)` | finance | financial | auth,service | `_is_ops_or_god_admin` | `finance.wallet.adjust` | DENY | APPROVAL_REQUIRED | APPROVAL_REQUIRED | yes | GUARD |
| `admin_review_commission_risk(p_commission uuid, p_action text, p_reason text)` | finance | financial | auth,service | `_is_ops_or_god_admin` | `finance.wallet.adjust` | DENY | APPROVAL_REQUIRED | APPROVAL_REQUIRED | yes | GUARD |
| `admin_review_referral_risk(p_referral uuid, p_action text, p_reason text)` | support-risk | operational | auth,service | `_is_ops_or_god_admin` | `ops.drivers.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_role_canonical(_uid uuid)` | cross-domain | read | auth,service | `admin_role_canonical; auth_uid_active` | `governance.capability.resolve` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `admin_set_driver_capability(_driver_user_id uuid, _capability text, _grant boolean)` | governance | governance | auth,service | `_is_ops_or_god_admin` | `governance.capability.resolve` | DENY | DENY | APPROVAL_REQUIRED | yes | SERVER_APPROVAL_GATE |
| `admin_set_feature_flag(p_key text, p_enabled boolean, p_note text)` | cross-domain | operational | auth,service | `is_god_admin` | `governance.flags.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_set_finance_delegation(p_provider_fee_to_finance_admin boolean, p_note text)` | finance | financial | auth,service | `is_god_admin` | `ops.users.manage` | DENY | ALLOW | ALLOW | no | SERVER_APPROVAL_GATE |
| `admin_set_finance_policy(p_mission_type text, p_commission_bps integer, p_min_driver_balance_gnf bigint, p_collateral_mode text, p_collateral_pct_bps integer, p_collateral_fixed_gnf bigint, p_collateral_min_gnf bigint, p_collateral_max_gnf bigint, p_fixed_commission_gnf bigint, p_require_collateral_before_offer boolean, p_effective_from timestamp with time zone, p_note text, p_collateral_basis text, p_transaction_fee_bps integer, p_fee_basis text, p_cancel_before_dispatch_bps integer, p_cancel_after_dispatch_bps integer, p_cancel_basis text, p_cash_funding_mode text, p_cash_funding_pct_bps integer, p_cash_funding_max_gnf bigint, p_max_declared_value_gnf bigint, p_claims_exposure_max_gnf bigint, p_delivery_flat_fee_gnf bigint, p_delivery_max_distance_km numeric, p_pickup_platform_fee_bps integer, p_courier_payout_gnf bigint, p_merchant_platform_fee_bps integer)` | finance | financial | auth,service | `is_god_admin` | `finance.policy.change` | DENY | APPROVAL_REQUIRED | APPROVAL_REQUIRED | yes | SERVER_APPROVAL_GATE |
| `admin_set_merchant_location_status(p_store_id uuid, p_status text, p_note text)` | operations | operational | auth,service | `has_role` | `ops.merchants.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_set_merchant_settlement_policy(p_configured boolean, p_min_settlement_gnf bigint, p_max_settlement_gnf bigint, p_cadence text, p_fee_bps integer, p_fee_fixed_gnf bigint, p_fee_passthrough boolean, p_effective_from timestamp with time zone, p_note text)` | finance | financial | auth,service | `is_god_admin` | `finance.payouts.manage` | DENY | ALLOW | ALLOW | no | SERVER_APPROVAL_GATE |
| `admin_set_payout_policy(p_min_request_gnf bigint, p_max_request_gnf bigint, p_daily_limit_gnf bigint, p_cancel_window_seconds integer, p_processing_estimate_min_minutes integer, p_processing_estimate_max_minutes integer, p_provider_fee_passthrough boolean, p_effective_from timestamp with time zone, p_note text)` | finance | financial | auth,service | `is_god_admin` | `finance.payouts.manage` | DENY | ALLOW | ALLOW | no | SERVER_APPROVAL_GATE |
| `admin_set_provider_fee_schedule(p_provider text, p_fee_bps integer, p_fee_fixed_gnf bigint, p_min_fee_gnf bigint, p_max_fee_gnf bigint, p_passthrough_to_recipient boolean, p_effective_from timestamp with time zone, p_note text)` | finance | financial | auth,service | `has_role; is_god_admin` | `governance.settings.manage` | DENY | ALLOW | ALLOW | no | GUARD |
| `admin_set_repas_promotion(p_name text, p_reason text, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_fulfillment_scope text, p_delivery_fee_override_gnf bigint, p_delivery_discount_gnf bigint)` | operations | operational | auth,service | `is_god_admin` | `governance.pricing.change` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_set_starter_credit_policy(p_amount_gnf bigint, p_enabled boolean, p_effective_from timestamp with time zone, p_note text)` | finance | financial | auth,service | `is_god_admin` | `finance.wallet.adjust` | DENY | APPROVAL_REQUIRED | APPROVAL_REQUIRED | yes | SERVER_APPROVAL_GATE |
| `admin_set_statement_status(p_statement uuid, p_status text, p_notes text)` | cross-domain | operational | auth,service | `_is_ops_or_god_admin` | `finance.payouts.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_staff_role_grant(_target uuid, _role text, _reason text)` | cross-domain | operational | auth,service | `_governance_role_allowed; _is_god_admin` | `governance.staff.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_staff_role_revoke(_target uuid, _role text, _reason text)` | cross-domain | operational | auth,service | `_governance_role_allowed; _is_god_admin` | `governance.staff.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_unban_user(_target uuid, _lift_reason text)` | identity | identity | auth,service | `_is_god_admin` | `governance.account.ban` | DENY | DENY | APPROVAL_REQUIRED | yes | SERVER_APPROVAL_GATE |
| `admin_unban_user(_target uuid, _ban_id uuid, _lift_reason text)` | identity | identity | auth,service | `_is_god_admin` | `governance.account.ban` | DENY | DENY | APPROVAL_REQUIRED | yes | SERVER_APPROVAL_GATE |
| `admin_unfreeze_user(_target uuid, _freeze_id uuid, _lift_reason text)` | identity | identity | auth,service | `_is_ops_or_god_admin` | `governance.account.freeze` | DENY | DENY | APPROVAL_REQUIRED | yes | SERVER_APPROVAL_GATE |
| `admin_update_campaign(p_campaign uuid, payload jsonb)` | operations | operational | auth,service | `_is_ops_or_god_admin` | `ops.drivers.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_update_contract(p_contract uuid, payload jsonb)` | operations | operational | auth,service | `_is_ops_or_god_admin` | `ops.drivers.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_update_driver_group(p_group uuid, payload jsonb)` | operations | operational | auth,service | `_is_ops_or_god_admin` | `ops.drivers.manage` | ALLOW | READ_ONLY | ALLOW | no | GUARD |
| `admin_zone_coverage_stats()` | maps | read | auth,service | `_is_ops_or_god_admin` | `ops.maps.manage` | READ_ONLY | READ_ONLY | ALLOW | no | GUARD |
| `driver_cashout_cancel_request(p_id uuid)` | finance | financial | auth,service | `inline admin_users check` | `finance.payouts.manage` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `driver_cashout_create_request(p_amount_gnf bigint, p_payout_phone text, p_driver_note text)` | finance | financial | auth,service | `inline admin_users check` | `finance.payouts.manage` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `driver_cashout_mark_paid(p_id uuid, p_provider_reference text, p_admin_note text)` | finance | financial | auth,service | `can_manage_wallet` | `finance.payouts.manage` | DENY | ALLOW | ALLOW | no | SERVER_APPROVAL_GATE |
| `driver_cashout_reject_request(p_id uuid, p_reason text)` | finance | financial | auth,service | `can_manage_wallet` | `finance.payouts.manage` | DENY | ALLOW | ALLOW | no | SERVER_APPROVAL_GATE |
| `finance_confirm_manual_om_payout(p_payout_order_id uuid, p_provider_reference text, p_attestation boolean, p_transferred_at timestamp with time zone)` | finance | financial | auth,service | `has_admin_role; is_god_admin` | `finance.reconciliation.approve` | DENY | ALLOW | ALLOW | no | SERVER_APPROVAL_GATE |
| `finance_mission_requirement(p_mission_type text, p_value_gnf bigint)` | finance | read | auth,service | `inline admin_users check` | `ops.orders.manage` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `finance_mission_requirement_v2(p_mission_type text, p_fare_gnf bigint, p_merchandise_subtotal_gnf bigint, p_delivery_fee_gnf bigint, p_declared_value_gnf bigint, p_payment_mode text)` | finance | read | auth,service | `inline admin_users check` | `ops.orders.manage` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `finance_payout_queue(p_bucket text, p_limit integer)` | finance | read | auth,service | `has_admin_role; is_god_admin` | `finance.audit.view_financial` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `finance_policy_at(p_mission_type text, p_as_of timestamp with time zone)` | finance | read | auth,service | `inline admin_users check` | `finance.audit.view_financial` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `finance_policy_current(p_mission_type text)` | finance | read | auth,service | `inline admin_users check` | `finance.audit.view_financial` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `finance_policy_predecessor(p_mission_type text, p_effective_from timestamp with time zone)` | finance | read | auth,service | `inline admin_users check` | `finance.audit.view_financial` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `finance_policy_snapshot(p_mission_type text, p_as_of timestamp with time zone, p_payment_mode text, p_fare_gnf bigint, p_merchandise_subtotal_gnf bigint, p_delivery_fee_gnf bigint, p_declared_value_gnf bigint, p_is_sandbox boolean)` | finance | read | auth,service | `inline admin_users check` | `finance.audit.view_financial` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `finance_treasury_drilldown(p_code text, p_limit integer)` | finance | read | auth,service | `_finance_treasury_gate` | `finance.treasury.read` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `finance_treasury_exceptions()` | finance | read | auth,service | `_finance_treasury_gate` | `finance.treasury.read` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `finance_treasury_overview()` | finance | read | auth,service | `_finance_treasury_gate` | `finance.treasury.read` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `merchant_settlement_policy_at(p_as_of timestamp with time zone)` | finance | read | auth,service | `inline admin_users check` | `finance.audit.view_financial` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `merchant_settlement_receipt(p_request_id uuid)` | finance | read | auth,service | `_finance_privileged` | `finance.audit.view_financial` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `merchant_settlement_request_create(p_amount_gnf bigint, p_idempotency_key text, p_store_id uuid, p_note text)` | finance | financial | auth,service | `inline admin_users check` | `finance.payouts.manage` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `merchant_settlement_requests_list(p_store_id uuid, p_limit integer)` | finance | read | auth,service | `_finance_privileged` | `finance.audit.view_financial` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `merchant_settlement_schedule_generate(p_as_of timestamp with time zone)` | finance | financial | auth,service | `has_admin_role; is_god_admin` | `finance.payouts.manage` | DENY | ALLOW | ALLOW | no | SERVER_APPROVAL_GATE |
| `payout_reconcile_evidence(p_evidence_id uuid)` | finance | read | auth,service | `has_admin_role; is_god_admin` | `finance.audit.view_financial` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `payout_record_provider_evidence(p_payout_order_id uuid, p_provider text, p_provider_reference text, p_recipient_msisdn text, p_amount_gnf bigint, p_provider_status text, p_environment text, p_transferred_at timestamp with time zone, p_fee_gnf bigint, p_raw jsonb)` | finance | financial | auth,service | `has_admin_role; is_god_admin` | `finance.payouts.manage` | DENY | ALLOW | ALLOW | no | SERVER_APPROVAL_GATE |
| `payout_reject_release(p_payout_order_id uuid, p_reason text)` | finance | financial | auth,service | `has_admin_role; is_god_admin` | `finance.payouts.manage` | DENY | ALLOW | ALLOW | no | SERVER_APPROVAL_GATE |
| `wallet_admin_credit(p_user_id uuid, p_amount_gnf bigint, p_reason text, p_provider_tx_id text)` | finance | financial | auth,service | `inline admin_users check` | `finance.wallet.adjust` | DENY | APPROVAL_REQUIRED | APPROVAL_REQUIRED | yes | GUARD |
| `wallet_capture(p_hold_id uuid, p_to_user_id uuid, p_to_party_type party_type, p_actual_amount_gnf bigint, p_description text)` | finance | financial | auth,service | `has_role` | `finance.wallet.adjust` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `wallet_ensure(_party_type text)` | finance | financial | auth,service | `inline admin_users check` | `finance.wallet.adjust` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `wallet_ensure_master()` | finance | financial | auth,service | `inline admin_users check` | `finance.treasury.read` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `wallet_get_master_balance()` | finance | read | auth,service | `is_god_admin` | `finance.treasury.read` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `wallet_hold(p_amount_gnf bigint, p_reference text, p_description text)` | finance | financial | auth,service | `inline admin_users check` | `finance.wallet.adjust` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `wallet_p2p_lookup_recipient(p_phone text)` | finance | read | auth,service | `inline admin_users check` | `finance.wallet.read` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `wallet_p2p_transfer(p_recipient_user_id uuid, p_amount_gnf bigint, p_note text, p_idempotency_key text)` | finance | financial | auth,service | `inline admin_users check` | `finance.wallet.adjust` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `wallet_pay_driver_commission(p_commission_id uuid)` | finance | financial | auth,service | `inline admin_users check` | `finance.wallet.adjust` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `wallet_pay_driver_commission_batch(p_commission_ids uuid[])` | finance | read | auth,service | `has_role` | `finance.wallet.read` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `wallet_pay_merchant(p_merchant_id uuid, p_amount_gnf bigint, p_description text)` | finance | financial | auth,service | `inline admin_users check` | `finance.wallet.adjust` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `wallet_release(p_hold_id uuid, p_reason text)` | finance | financial | auth,service | `has_role` | `finance.wallet.adjust` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `wallet_reverse_driver_commission(p_commission_id uuid, p_reason text)` | finance | financial | auth,service | `inline admin_users check` | `finance.wallet.adjust` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `wallet_topup_admin_cancel(p_topup_id uuid, p_reason text)` | finance | financial | auth,service | `can_manage_wallet` | `finance.reconciliation.approve` | DENY | ALLOW | ALLOW | no | SERVER_APPROVAL_GATE |
| `wallet_topup_admin_mark_expired(p_topup_id uuid, p_reason text)` | finance | financial | auth,service | `can_manage_wallet` | `finance.reconciliation.approve` | DENY | ALLOW | ALLOW | no | SERVER_APPROVAL_GATE |
| `wallet_topup_cancel(p_topup_id uuid, p_reason text)` | finance | financial | auth,service | `inline admin_users check` | `finance.reconciliation.approve` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `wallet_topup_confirm(p_topup_id uuid, p_code text)` | finance | financial | auth,service | `inline admin_users check` | `finance.reconciliation.approve` | DENY | ALLOW | ALLOW | no | GUARD |
| `wallet_topup_create(p_client_user_id uuid, p_amount_gnf bigint)` | finance | financial | auth,service | `inline admin_users check` | `finance.reconciliation.approve` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |
| `wallet_topup_om_create(p_amount_gnf bigint, p_receiving_account_id uuid)` | finance | financial | auth,service | `inline admin_users check` | `finance.reconciliation.approve` | n/a (end-user rail) | READ_ONLY | READ_ONLY | no | KEEP |

**Zero unclassified callables:** 133 discovered, 133 rows above.

---

## 3. C — admin-facing Edge Functions

| Function | `verify_jwt` | Caller check at HEAD | Domain | Mutation class | Target capability | Ops | Finance | God | 4-eyes | G2 tag |
|---|---|---|---|---|---|---|---|---|---|---|
| `admin-create-staff-user` | true | service client + caller must be `god_admin`/`super_admin` in `admin_users` | staff | governance | `governance.staff.manage` | DENY | DENY | APPROVAL_REQUIRED | yes | SERVER_APPROVAL_GATE |
| `admin-delete-user` | true | `god_admin`/`super_admin` only; refuses targets with financial history | identity | destructive | `governance.account.anonymize` | DENY | DENY | APPROVAL_REQUIRED | yes | SERVER_APPROVAL_GATE |
| `admin-driver-doc-url` | true | authenticated caller + service client; no explicit admin-class assertion in body | identity | read | `ops.drivers.manage` | ALLOW | DENY | ALLOW | no | GUARD |
| `admin-email-resend` | true | reads `admin_users.admin_role,status`; god/super only | support-risk | operational | `ops.support.manage` | ALLOW | DENY | ALLOW | no | KEEP |
| `om-import-csv` | true | `admin_users` only; active `god_admin`/`super_admin`/`finance_admin` | finance | financial | `finance.reconciliation.approve` | DENY | ALLOW | ALLOW | no | KEEP |
| `account-access-termination-worker` | true | `service_role` JWT, or active `god_admin`/`operations_admin`/`super_admin` | identity | destructive | `governance.account.close` | DENY | DENY | APPROVAL_REQUIRED | yes | SERVER_APPROVAL_GATE |
| `qa-merchant-harness` | **false** | `has_role(caller,'admin')` — legacy bare alias | governance | operational | `governance.sandbox.run` | DENY | DENY | ALLOW | no | GUARD |
| `qa-node-harness` | true | `has_role(caller,'admin')` — legacy bare alias | governance | operational | `governance.sandbox.run` | DENY | DENY | ALLOW | no | GUARD |

8 admin-facing functions discovered, 8 classified. The remaining 18 functions in
`supabase/functions/` are public/product or webhook surfaces (maps, email, payments webhook,
recovery, AI, messaging) and carry no staff authority.

---

## 4. D — tables and views materially reachable by staff

- 172 public tables. 110 carry at least one RLS policy that references an admin predicate
  (`has_role`, `_is_god_admin`, `_is_ops_or_god_admin`, `_finance_privileged`,
  `_governance_role_allowed`, `admin_users`).
- 31 public tables have **no** policy at all. Under Supabase these are unreachable through
  the Data API unless explicitly granted; each must be confirmed one by one in G2 (tag
  `MANUAL_REVIEW_REQUIRED`) — the risk is a stray GRANT, not a policy gap.
- Finance-critical tables (`ledger_journals`, `ledger_postings`, `wallets`,
  `wallet_transactions`, `payment_intents`, `payout_orders`, `merchant_payables`,
  `dormant_closed_account_liabilities`, `finance_policies`) stay SELECT-only for staff with
  every mutation routed through a SECURITY DEFINER function. **Frozen — G2 must not widen.**
- `audit_logs` is append-only for every class; no staff class may update or delete a row.
- `admin_capability_grants` (18 rows) is the capability registry; `approval_requests` is the
  approval ledger (0 rows to date).

---

## 5. E — every `/admin` route, page, module and guard

| Page | Route | Module | Guard at HEAD | Target capability | Ops | Finance | God | G2 tag |
|---|---|---|---|---|---|---|---|---|
| `AdminChangePassword` | `/admin/change-password` | `NONE` | AdminGuard only — intentional (must_change_password flow) | `governance.capability.resolve` | DENY | DENY | ALLOW | KEEP |
| `AdminDashboard` | `/admin (index)` | `dashboard` | AdminGuard + ModulePage module="dashboard" | `ops.reports.view` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `AdminsAdmin` | `/admin/admins` | `admins` | AdminGuard + ModulePage module="admins" | `governance.staff.manage` | DENY | DENY | ALLOW | KEEP |
| `AnalyticsAdmin` | `/admin/analytics` | `NONE` | AdminRouteGuard (role list, no module) | `ops.reports.view` | ALLOW | READ_ONLY | ALLOW | GUARD |
| `AuditAdmin` | `/admin/audit` | `audit` | AdminGuard + ModulePage module="audit" | `governance.audit.read_all` | DENY | DENY | ALLOW | KEEP |
| `DriverCashouts` | `/admin/wallet/driver-cashouts` | `wallet` | AdminGuard + ModulePage module="wallet" | `finance.wallet.read` | READ_ONLY | ALLOW | ALLOW | KEEP |
| `DriverGroupsAdmin` | `/admin/driver-groups` | `driver_groups` | AdminGuard + ModulePage module="driver_groups" | `ops.drivers.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `DriverSignalsAdmin` | `/admin/map/driver-signals` | `NONE` | AdminRouteGuard (role list, no module) | `ops.liveops.view` | ALLOW | READ_ONLY | ALLOW | GUARD |
| `DriversAdmin` | `/admin/drivers` | `drivers` | AdminGuard + ModulePage module="drivers" | `ops.drivers.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `FieldPilotsAdmin` | `/admin/field/pilots` | `NONE` | AdminRouteGuard (role list, no module) | `ops.onboarding.decide` | ALLOW | READ_ONLY | ALLOW | GUARD |
| `FinanceCommandCenter` | `/admin/finance` | `payments` | AdminGuard + ModulePage module="payments" | `finance.policy.change` | READ_ONLY | ALLOW | ALLOW | KEEP |
| `FinancePolicyAdmin` | `/admin/finance-policy` | `pricing` | AdminGuard + ModulePage module="pricing" | `governance.pricing.change` | DENY | DENY | ALLOW | KEEP |
| `FlagsAdmin` | `/admin/flags` | `flags` | AdminGuard + ModulePage module="flags" | `governance.flags.manage` | DENY | DENY | ALLOW | KEEP |
| `LiveOps` | `/admin/live` | `live_ops` | AdminGuard + ModulePage module="live_ops" | `ops.liveops.view` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `MapDuplicatesAdmin` | `/admin/map/duplicates` | `zones` | AdminGuard + ModulePage module="zones" | `ops.maps.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `MapPlacesAdmin` | `/admin/map/places` | `zones` | AdminGuard + ModulePage module="zones" | `ops.maps.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `MapRoutingAdmin` | `/admin/map/routing` | `NONE` | AdminRouteGuard (role list, no module) | `ops.maps.manage` | ALLOW | READ_ONLY | ALLOW | GUARD |
| `MapTariffsAdmin` | `/admin/map/tarifs` | `zones` | AdminGuard + ModulePage module="zones" | `ops.maps.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `MapZonesAdmin` | `/admin/map/zones` | `zones` | AdminGuard + ModulePage module="zones" | `ops.maps.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `MarcheAdmin` | `/admin/marche` | `marche` | AdminGuard + ModulePage module="marche" | `ops.orders.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `MarcheOpsAdmin` | `/admin/marche/ops` | `marche` | AdminGuard + ModulePage module="marche" | `ops.orders.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `MerchantsAdmin` | `/admin/merchants` | `merchants` | AdminGuard + ModulePage module="merchants" | `ops.merchants.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `NotificationsAdmin` | `/admin/notifications` | `notifications` | AdminGuard + ModulePage module="notifications" | `ops.support.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `OpsCommandCenter` | `/admin/ops` | `dashboard` | AdminGuard + ModulePage module="dashboard" | `ops.reports.view` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `OrdersAdmin` | `/admin/orders` | `orders` | AdminGuard + ModulePage module="orders" | `ops.orders.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `PaymentsAdmin` | `/admin/payments` | `payments` | AdminGuard + ModulePage module="payments" | `finance.policy.change` | READ_ONLY | ALLOW | ALLOW | KEEP |
| `PayoutsAdmin` | `/admin/wallet/payouts` | `payments` | AdminGuard + ModulePage module="payments" | `finance.policy.change` | READ_ONLY | ALLOW | ALLOW | KEEP |
| `PilotCommandCenter` | `/admin/pilot-command` | `dashboard` | AdminGuard + ModulePage module="dashboard" | `ops.reports.view` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `PricingAdmin` | `/admin/pricing` | `pricing` | AdminGuard + ModulePage module="pricing" | `governance.pricing.change` | DENY | DENY | ALLOW | KEEP |
| `PromotionsAdmin` | `/admin/promotions` | `promotions` | AdminGuard + ModulePage module="promotions" | `governance.pricing.change` | DENY | DENY | ALLOW | KEEP |
| `RepasAdmin` | `/admin/repas` | `repas` | AdminGuard + ModulePage module="repas" | `ops.orders.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `RepasPayments` | `/admin/repas/payments` | `repas` | AdminGuard + ModulePage module="repas" | `ops.orders.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `ReportsAdmin` | `/admin/reports` | `reports` | AdminGuard + ModulePage module="reports" | `ops.reports.view` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `RiskAdmin` | `/admin/risk` | `risk` | AdminGuard + ModulePage module="risk" | `ops.risk.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `SandboxAdmin` | `/admin/payments/sandbox` | `payments` | AdminGuard + ModulePage module="payments" | `finance.policy.change` | READ_ONLY | ALLOW | ALLOW | KEEP |
| `SettingsAdmin` | `/admin/settings` | `settings` | AdminGuard + ModulePage module="settings" | `governance.settings.manage` | DENY | DENY | ALLOW | KEEP |
| `SupportAdmin` | `/admin/support` | `support` | AdminGuard + ModulePage module="support" | `ops.support.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `TreasuryAdmin` | `/admin/treasury` | `wallet` | AdminGuard + ModulePage module="wallet" | `finance.wallet.read` | READ_ONLY | ALLOW | ALLOW | KEEP |
| `UsersAdmin` | `/admin/users` | `users` | AdminGuard + ModulePage module="users" | `ops.users.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `VendorsAdmin` | `/admin/vendors` | `vendors` | AdminGuard + ModulePage module="vendors" | `ops.merchants.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |
| `WalletAdmin` | `/admin/wallet` | `wallet` | AdminGuard + ModulePage module="wallet" | `finance.wallet.read` | READ_ONLY | ALLOW | ALLOW | KEEP |
| `WalletReconciliation` | `/admin/wallet/reconciliation` | `wallet` | AdminGuard + ModulePage module="wallet" | `finance.wallet.read` | READ_ONLY | ALLOW | ALLOW | KEEP |
| `ZonesAdmin` | `/admin/zones` | `zones` | AdminGuard + ModulePage module="zones" | `ops.maps.manage` | ALLOW | READ_ONLY | ALLOW | KEEP |

43 page components discovered, 43 classified. Sidebar exposes 42 entries; the two
uncovered by the sidebar are `/admin` (index redirect via `AdminHomeRoute`) and
`/admin/change-password`.

---

## 6. F — role sources, helpers, aliases

| Source | Values in use at HEAD | Authority |
|---|---|---|
| `admin_users.admin_role` (enum `admin_role`: super_admin, ops_admin, finance_admin, god_admin, operations_admin, support_admin) + `status` + `must_change_password` | `ops_admin:active=2`, `super_admin:active=1` | authoritative for staff class |
| `user_roles.role` (enum `app_role`, write-guarded by `guard_user_roles_write`) | `god_admin=1`, `operations_admin=2`, `admin=1` (legacy), plus non-staff roles | corroborating; bare `admin` is **not** constitutional authority |
| Frontend `src/lib/admin/permissions.ts` | `AdminRole = god_admin | operations_admin | finance_admin`, `PERMISSIONS`, `can()`, `requiresApproval()` | display only — never authority |
| SQL helpers | `admin_capability`, `admin_capability_mode`, `admin_require_capability`, `admin_four_eyes_gate`, `admin_role_canonical`, `_is_god_admin`, `is_god_admin`, `_is_ops_or_god_admin`, `is_any_admin`, `has_admin_role`, `has_role`, `can_manage_operations`, `can_manage_wallet`, `_finance_privileged`, `_finance_treasury_gate`, `_governance_role_allowed`, `auth_uid_active` | 17 distinct predicates — G2 must collapse them onto `admin_require_capability` |

Alias drift is real: six enum labels, three canonical classes, and a bare `admin` fallback
still accepted by 21 RPCs and both QA harnesses.

---

## 7. G — approval and audit primitives already present

| Primitive | State |
|---|---|
| `approval_requests` (11 cols, 3 policies) + `src/lib/admin/approvals.ts` (`requireApprovalOr`, `APPROVAL_REQUIRED_ACTIONS`, `requestApproval`) | table exists, 0 rows; enforcement currently **frontend-advisory only** |
| `admin_four_eyes_gate(_capability, _approval_id)` | server gate exists; not yet called by the 21 APPROVAL_REQUIRED callables |
| `admin_capability_grants` (capability, admin_role, mode, note) | 18 rows, 7 marked `approval_required` |
| `audit_logs` + `log_admin_action` | 94 rows; append-only |
| `account_access_terminations`, `admin_governance_set_status`, `_finance_evidence_claim` | reusable governance/finance provenance primitives |

---

## 8. G2 worklist (generated by this audit)

### CRITICAL
1. **Browser-only four-eyes.** All 21 APPROVAL_REQUIRED callables execute today without
   `admin_four_eyes_gate`. Bind approval to capability + target + material parameters, with
   expiry, single consumption and audit provenance.
2. **Legacy bare `admin` alias.** 21 RPCs plus `qa-merchant-harness` and `qa-node-harness`
   accept `has_role(uid,'admin')`. This grants full financial reach (`admin_adjust_agent_float`,
   `admin_marche_capture_and_settle_offer`, `admin_repas_capture_and_settle_order`,
   `admin_backfill_missing_driver_earnings`) to any bare-`admin` row. Replace with
   `admin_require_capability`.
3. **Ops class touching money.** `admin_generate_payout_statement`,
   `admin_account_closure_reconcile`, and the dormant-liability readers are gated on
   `_is_ops_or_god_admin`; the constitution puts them under finance/governance authority.
4. **`qa-merchant-harness` runs with `verify_jwt = false`** and only an in-body legacy alias
   check.

### HIGH
5. Collapse 17 guard predicates onto `admin_require_capability(capability)`.
6. Give the 4 `AdminRouteGuard`-only pages an explicit module/capability binding.
7. `admin-driver-doc-url` asserts no admin class in its body — add a caller-class check.
8. Split `governance.flags.manage` (product) from `finance.flags.payment` (payment rails) at
   enforcement time, not just in the registry.
9. Extend `admin_capability_grants` from 18 to the full namespace so no capability resolves
   by omission.
10. Reconcile role rows: 2 `ops_admin` → `operations_admin`, 1 `super_admin` → `god_admin`,
    1 bare `admin` → explicit class or removal. Decide which of the two Operations Admin
    accounts survives (owner decision, still open).

### MEDIUM
11. Confirm grants on the 31 policy-less public tables.
12. Align `src/lib/admin/permissions.ts` with `admin_capability_grants` and add a drift test.
13. Scope audit-log visibility per class as the constitution states.
14. Route `admin_preview_*` readers to explicit read capabilities so read access stops
    borrowing a mutation guard.
15. Define the `POLICY_THRESHOLD_REQUIRED` values in `finance_policies` (God-configured).

---

## 9. Coverage proof

| Surface | Discovered | Classified | Unclassified |
|---|---|---|---|
| `admin_*` RPCs | 91 | 91 | 0 |
| Other staff-reachable finance/governance RPCs | 42 | 42 | 0 |
| Admin-facing Edge Functions | 8 | 8 | 0 |
| Admin page components | 43 | 43 | 0 |
| Admin routes | 44 | 44 | 0 |
| Role sources | 4 | 4 | 0 |
| Approval/audit primitives | 6 | 6 | 0 |

Post-documentation re-census matched the pre-documentation census exactly: 91 `admin_*`
RPCs, 0 anon-executable, 18 capability grants, 0 approval requests, 3 active staff rows,
94 audit rows. Nothing changed while this document was written.
