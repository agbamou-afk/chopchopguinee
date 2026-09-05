# Admin Responsibility & Capability Architecture (G1–G6)

Goal: define and enforce a capability constitution for three staff classes — God Admin (constitutional
super-admin), Operations Admin, Finance Admin — and make staff-account creation reliable. No code edits yet.

## What the audit found (verified against the live project)

### 1. The Operations Admin creation error — exact root cause
`supabase/functions/admin-create-staff-user/index.ts` line ~184 calls
`admin.from("audit_logs").insert({...}).catch(...)`. A Supabase query builder is a thenable, not a Promise,
so `.catch` is not a function. It throws **after** every write has already succeeded, the outer catch returns
`500 {error:"exception"}`, and `AdminsAdmin.tsx` (line 177) sees `data === null` and shows the generic
"Edge Function returned a non-2xx status code".

Consequence confirmed in the database: **two Operations Admin accounts were actually created** despite the
error (`jjkolie@…` and `jkolie@…`, both `admin_users.admin_role = ops_admin`, `status = active`,
`user_roles = {client, operations_admin}`). Retrying with the same email now fails with "email already
registered" — a second, misleading error. Nothing else in the function is broken: the enum accepts
`ops_admin`, all columns exist, no blocking trigger on `admin_users`.

Two defects, not one: the `.catch` bug, and error surfacing that hides the real server message.

### 2. Role sources (two parallel systems, both live)
- `admin_users.admin_role` (enum `admin_role`: super_admin, ops_admin, finance_admin, god_admin,
  operations_admin, support_admin) + `status` + `must_change_password`.
- `user_roles.role` (enum `app_role`, includes god_admin / operations_admin / finance_admin), guarded by
  trigger `guard_user_roles_write`.
- Frontend maps both through `useAdminAuth` → `src/lib/admin/permissions.ts` (`AdminRole`, `PERMISSIONS`,
  `can()`), with `roles.includes("admin") → god_admin` as a legacy fallback.
- Backend helpers: `_is_god_admin`, `_is_ops_or_god_admin`, `_finance_privileged`, `_governance_role_allowed`,
  `has_role`, `_finance_treasury_gate`, `auth_uid_active()` (Node 5 termination gating).

Risk: the enum carries both `ops_admin` and `operations_admin`, and legacy `super_admin` vs `god_admin`.
Any capability law must resolve to one canonical set.

### 3. Route / UI gating today
`/admin/*` (42 pages) is wrapped once by `AdminGuard` in `AdminLayout` — it checks "is any admin", not module.
Per-module gating is only inside each page via `<ModulePage module=…>`. Five pages have no `ModulePage`
wrapper at all: `AnalyticsAdmin`, `DriverSignalsAdmin`, `FieldPilotsAdmin`, `MapRoutingAdmin`
(plus `AdminChangePassword`, which is intentional). Sidebar filters by `can(module)` only — cosmetic.

### 4. Server-side enforcement gaps (the real loopholes)
- 86 `admin_*` RPCs exist; **34 are EXECUTE-granted to `anon`** (e.g. `admin_ban_user`, `admin_freeze_user`,
  `admin_merchant_decision`, `admin_create_driver_group`, `admin_unban_user`). They are SECURITY DEFINER and
  most do check a role internally, but the grant surface itself is wrong.
- 32 `admin_*` functions show no reference to any known role helper in their body — including
  `admin_manual_om_credit`, `admin_set_feature_flag`, `admin_set_finance_policy`, `admin_set_payout_policy`,
  `admin_promotional_credit_treasury`, `admin_anonymize_user`, `admin_chop_pay_dispute_resolve`. Some may
  guard via a helper this scan did not match; each must be read individually in G1 before any conclusion.
- Net effect: hiding a page in the sidebar prevents nothing. An Operations Admin with a browser console can
  call any of these directly.

### 5. Reusable governance primitives already in place
`approval_requests` table + `src/lib/admin/approvals.ts` (`requireApprovalOr`, `APPROVAL_REQUIRED_ACTIONS`,
`requestApproval`), `audit_logs` + `log_admin_action` RPC, `admin_governance_set_status`,
`account_access_terminations` worker, `_finance_evidence_claim`. The four-eyes scaffolding exists but is
frontend-evaluated only — `requiresApproval()` runs in the browser.

## Frozen — do not modify

- Node 5 identity law: lane exclusivity, `auth_uid_active()`, `pgrst_pre_request`, closure/anonymization
  blockers, `account_access_terminations`, professional-lane claim.
- Chop Pay / Slice 12 finance law: ledger immutability, `_finance_treasury_facts` (service_role only),
  treasury exception classes, raw finance tables SELECT-only for `authenticated`, Stage 5/6/7 flags OFF.
- Marché Node 4 order/economics/procurement contracts.
- No RLS may be weakened anywhere in this work.

## Phased slices

### G1 — Audit closure + capability constitution (no behaviour change)
- Read every `admin_*` / finance / governance RPC body; produce a signed inventory table:
  function → classification (read / operational mutation / financial mutation / governance mutation /
  identity mutation / destructive) → current guard → target guard.
- Same for admin-reachable table RLS and grants, Edge Functions
  (`admin-create-staff-user`, `admin-delete-user`, `admin-driver-doc-url`, `admin-email-resend`,
  `om-import-csv`, `account-access-termination-worker`, `qa-*`).
- Write `docs/admin/ADMIN_CAPABILITY_CONSTITUTION.md`: ALLOW / DENY / APPROVAL-REQUIRED per class.

Constitution direction to ratify in G1:

| Domain | Operations Admin | Finance Admin | God Admin |
|---|---|---|---|
| Users, drivers, merchants, orders, missions, support, risk cases, live ops | ALLOW mutate | READ (finance-linked cases only) | ALLOW |
| Driver/merchant onboarding approval | ALLOW | DENY (except a named KYC/finance hold step) | ALLOW |
| Maps: zones, places, duplicates, routing, driver signals | ALLOW | DENY | ALLOW |
| Moto tariff grid (`map_fare_troncons`), pricing, promotions | READ / propose | propose → approval | ALLOW |
| Wallet credit/debit, manual OM credit, refunds, adjustments | DENY | ALLOW via canonical RPCs, four-eyes above threshold | ALLOW |
| Payouts, cashouts, settlements, reconciliation approval | READ | ALLOW (confirm = four-eyes) | ALLOW |
| Treasury, master wallet, dormant liabilities | DENY | READ + governed movement (four-eyes) | ALLOW |
| Finance policy, payout policy, settlement policy | DENY | propose → God Admin approval | ALLOW |
| Feature flags — non-financial | propose → approval | DENY | ALLOW |
| Feature flags — payment/financial rails | DENY | propose → approval | ALLOW |
| Staff creation / deactivation / role mutation | DENY | DENY | ALLOW (four-eyes for admin creation) |
| Account closure / anonymization / ban | narrow governed ops ban only, reversible | DENY | ALLOW |
| Audit logs | READ own-scope | READ own-scope | READ all |

Four-eyes (approval-required, requester ≠ approver, approver = God Admin unless stated):
large refunds/credits above threshold, manual payouts, finance/payout/settlement policy change, payment-rail
flag activation, master-wallet/treasury movement, sensitive account closure or anonymization, admin creation
and deactivation, emergency operational override.

### G2 — Backend capability enforcement (the load-bearing slice)
- Canonical role resolution in SQL: one `admin_capability(_capability text)` SECURITY DEFINER helper reading
  `user_roles` + `admin_users.status` + `auth_uid_active()`, with `ops_admin`/`operations_admin` and
  `super_admin`/`god_admin` normalized.
- `REVOKE EXECUTE … FROM anon` on all 34 anon-exposed `admin_*` RPCs; `authenticated` retained only where a
  guard exists inside.
- Add the missing internal guard to every function G1 flags as unguarded; raise a typed
  `insufficient_privilege` error naming the capability.
- Move four-eyes server-side: an `approval_requests`-backed gate the RPC itself consults, so a browser call
  cannot skip it. `APPROVAL_REQUIRED_ACTIONS` becomes a mirror of the DB list, never the authority.
- Every governance/financial mutation writes `audit_logs` with actor, capability, before/after.

### G3 — Staff-account lifecycle
- Fix `admin-create-staff-user`: replace `.catch(...)` on the audit insert with `await` + error check;
  return the real provider message; make `AdminsAdmin.tsx` read `FunctionsHttpError.context` so the server
  message reaches the operator.
- Idempotency: detect an existing auth user for the email and return a precise conflict, not a 500.
- Normalize the role written (single canonical value in both `admin_users` and `user_roles`), forbid
  god_admin creation (already), add deactivate / reactivate / role-change endpoints with four-eyes + audit.
- Reconcile the two accounts already created (confirm intent, or deactivate).

### G4 — Operations command center
- `/admin/ops` becomes the Operations Admin landing route; operational KPIs and queues only
  (drivers pending, missions in flight, support/risk cases, merchant onboarding, map duplicates).
- Sidebar and route tree driven by the shared capability registry; add `ModulePage`/route guards to the four
  unwrapped pages; finance modules render read-only or 403 for Operations.

### G5 — Finance command center
- `/admin/finance` landing for Finance Admin: treasury exceptions, reconciliation queues, payouts/cashouts,
  refunds, settlement, payment intents — each action labelled direct-execute vs approval-required.
- Operational modules read-only or hidden.

### G6 — Adversarial certification and lock
- Fixture users: god_admin, operations_admin, finance_admin, plain authenticated — created and purged
  within the run, zero residue asserted.
- Tests: direct RPC invocation bypassing UI for every DENY cell; direct table INSERT/UPDATE attempts;
  Edge Function caller-role tests; route + sidebar visibility; cross-role denial matrix; four-eyes cannot be
  self-approved; audit provenance for every mutation.
- Full Vitest regression, `bunx tsgo --noEmit -p tsconfig.app.json`, production build, Supabase linter diff,
  memory lock file.

## Recommended order
G1 → G3 (unblocks the owner immediately) → G2 → G4 → G5 → G6. G3 before G2 only because staff creation is
currently broken; G2 must land before either dashboard is trusted.

## Risks
- Two role systems: normalization can lock out an existing admin if done carelessly — G2 ships a read-only
  reconciliation report first.
- Revoking `anon` EXECUTE could break a caller that relies on it; G1 must confirm each caller is authenticated.
- Some `admin_*` functions may guard through helpers this scan did not match; per-function reading in G1 is
  mandatory before adding or changing a guard.
