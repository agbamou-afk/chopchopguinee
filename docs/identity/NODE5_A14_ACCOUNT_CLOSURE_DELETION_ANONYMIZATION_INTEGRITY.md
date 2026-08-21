# NODE 5 · A14 — ACCOUNT CLOSURE / DELETION / ANONYMIZATION / RE-REGISTRATION INTEGRITY

Starting repo HEAD: `20aabd91dc322e0735816fa1522e07b2da875b95`

## Constitutional law (frozen)

> Account closure ends access and present authority; it does not erase financial,
> professional, governance, operational, or audit provenance. PII may be
> anonymized/released under policy, but retained history stays attached to the
> closed canonical UUID and can never migrate to a successor account.
> Re-registration is a new identity, not resurrection.

Carried forward unchanged: A11 axis separation, A12 offboarding law, A13 continuity law.

## Preflight defects found

1. `request_account_deletion` performed zero blocker checks and anonymized immediately.
2. `_anonymize_user_core` left `professional_identities.claim_state='active'`,
   `admin_users.status='active'`, and `user_roles` intact — closure removed PII but not authority.
3. `account_recovery_profiles` / `account_recovery_challenges` survived closure (PII leak).
4. `user_has_financial_history` ignored payouts, payables, holds, Marché orders, missions,
   professional and governance history — and was executable by `anon`.
5. `auth.users` FKs cascaded into financial/audit provenance
   (`driver_cashout_requests`, `account_freezes`, `field_daily_reports`,
   `field_merchant_visits`, `account_recovery_*`).

## Implemented (smallest surgical change, no parallel subsystem)

- `_account_closure_blockers(uuid,text)` — single canonical fail-closed blocker engine.
  Tokens: `WALLET_BALANCE_NONZERO`, `WALLET_FUNDS_HELD`, `OPEN_FINANCIAL_HOLD`,
  `CUSTOMER_CANCELLATION_DEBT`, `PENDING_TOPUP`, `DRIVER_CASH_DEBT_OUTSTANDING`,
  `DRIVER_CASHOUT_IN_FLIGHT`, `MERCHANT_UNSETTLED_PAYABLE`, `MERCHANT_SETTLEMENT_IN_FLIGHT`,
  `ACTIVE_RIDE`, `ACTIVE_MISSION`, `ACTIVE_FOOD_ORDER`, `ACTIVE_MARCHE_ORDER`,
  `ACTIVE_PACKAGE_DELIVERY`, `ACCOUNT_FREEZE_ACTIVE`, `OPEN_SUPPORT_ISSUE`,
  `GOVERNANCE_AUTHORITY_ACTIVE` (self mode only), plus the A12
  `professional_offboard_blockers` contract reused verbatim for active lanes.
- `account_closure_blockers(uuid)` — self-or-ops read surface, `authenticated` only.
- `_account_closure_core(uuid,text,text)` — ordered: lock → blockers (fail closed, zero
  mutation) → professional lane stand-down + `_professional_identity_release` →
  `admin_users` suspend (row retained) → `user_roles` revoke → recovery material erase →
  `_anonymize_user_core` PII release → `audit_logs` `account.closure`.
- `request_account_deletion(text)` and `admin_anonymize_user(uuid,text)` now both delegate
  to that single core. Admin path returns `{ok:false, error:'ACCOUNT_CLOSURE_BLOCKED', blockers:[...]}`;
  self path raises `ACCOUNT_CLOSURE_BLOCKED: [...]`.
- `user_has_financial_history` widened to all provenance surfaces; `anon` EXECUTE revoked.
- FK provenance protection: `ON DELETE RESTRICT` on `driver_cashout_requests`,
  `professional_identities`, `account_freezes`, `field_daily_reports`,
  `field_merchant_visits` → hard-deleting a login can no longer shred history.
- `_qa_users_purge` extended so disposable QA fixtures stay purgeable under RESTRICT.
- Client: `SelfDeleteAccountSheet` renders blockers as human French reasons instead of a raw error.

## Certification

- `_qa_node5_identity_a14` — **114 / 114 PASS** (structural, blocker engine, fail-closed
  no-mutation, authority stand-down, history retention, idempotency, re-registration,
  hard-delete gate, authorisation matrix, mass-balance).
- Full board — 57 suites, **5952 raw assertions**, 0 failures after the single stale-fixture
  correction (`_qa_s13_run7` S7.4 now settles its own wallet/top-up before closing, since
  closure is legitimately fail-closed on outstanding money).
- Linter: **658**, unchanged accepted baseline.
- `tsgo --noEmit`: exit 0.
- No fourth harness token created; `QA_NODE_HARNESS_TOKEN_CERT` reused.

**VERDICT: NODE 5 · A14 — CERTIFIED.**
