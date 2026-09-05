# CHOP CHOP — Admin Capability Constitution

Status: ratified (G1) and enforced in the database (G2).
Classes: **God Admin** (constitutional super-admin), **Operations Admin**, **Finance Admin**.

## 1. Canonical role resolution

Two role systems exist and both stay live:

- `admin_users.admin_role` (`god_admin`, `super_admin`, `ops_admin`, `operations_admin`, `finance_admin`, `support_admin`) + `status`.
- `user_roles.role` (`god_admin`, `operations_admin`, `finance_admin`, …), guarded by `guard_user_roles_write`.

`public.admin_role_canonical(uuid)` reduces both to exactly one of
`god_admin | finance_admin | operations_admin | NULL`:

- `super_admin` ≡ `god_admin`; `ops_admin` ≡ `support_admin` ≡ `operations_admin`.
- `admin_users` rows only count when `status = 'active'`.
- A terminated/closed account (`auth_uid_active()` NULL) resolves to NULL — no authority survives closure.

## 2. Capability registry

`public.admin_capability_grants (capability, admin_role, mode)` is the constitution as data.
`mode` is `allow` or `approval_required`. God Admin holds every capability implicitly.

Checks:

- `admin_capability(_capability)` → boolean
- `admin_require_capability(_capability)` → raises `insufficient_privilege` (SQLSTATE 42501)
- `admin_capability_mode(_capability)` → `allow | approval_required | deny`
- `admin_four_eyes_gate(_capability, _approval_id)` → server-side four-eyes; requester ≠ approver, approver must be God Admin

`src/lib/admin/permissions.ts` mirrors this for UI affordances only. **The database is authoritative.**

## 3. ALLOW / DENY / APPROVAL matrix

| Domain | Operations Admin | Finance Admin | God Admin |
|---|---|---|---|
| Users, drivers, merchants, orders, missions, support, risk, live ops | ALLOW mutate | READ (finance-linked only) | ALLOW |
| Driver / merchant onboarding approval | ALLOW | DENY | ALLOW |
| Maps: zones, places, duplicates, routing, driver signals | ALLOW | DENY | ALLOW |
| Tariff grid, pricing, promotions | propose → approval | propose → approval | ALLOW |
| Wallet credit/debit, manual OM credit, refunds, adjustments | DENY | ALLOW via canonical RPCs (four-eyes above threshold) | ALLOW |
| Payouts, cashouts, settlements, reconciliation approval | READ | ALLOW (confirm = four-eyes) | ALLOW |
| Treasury, master wallet, dormant liabilities | DENY | READ + governed movement (four-eyes) | ALLOW |
| Finance / payout / settlement policy | DENY | propose → God Admin approval | ALLOW |
| Feature flags — non-financial | propose → approval | DENY | ALLOW |
| Feature flags — payment rails | DENY | propose → approval | ALLOW |
| Staff creation / deactivation / role change | DENY | DENY | ALLOW (four-eyes) |
| Account closure / anonymization / ban | reversible ops ban only | DENY | ALLOW |
| Audit logs | READ own scope | READ own scope | READ all |

Four-eyes actions: large refunds/credits, manual payouts, finance/payout/settlement policy change,
payment-rail flag activation, treasury movement, sensitive closure/anonymization, staff creation
and deactivation, emergency operational override.

## 4. G1 audit findings (verified)

- 86 `admin_*` RPCs. **34 were EXECUTE-granted to `anon`** — all revoked in G2.
- Every `admin_*` RPC guards internally through one of `is_god_admin`, `has_admin_role`,
  `can_manage_operations`, `can_manage_wallet`, `is_any_admin`, `has_role`, `_finance_privileged`,
  `_governance_role_allowed`, `_marche_ops_actor_role`, or an explicit `admin_users` lookup —
  **except** `admin_log_test_delete`, which had no guard at all and now requires a staff role.
  (The earlier "32 unguarded" figure was a scan artefact: those functions guard through helper
  names the first scan did not match.)
- `/admin/*` is wrapped once by `AdminGuard` (is-any-admin). Per-module gating comes from
  `<ModulePage module=…>`; the four pages without it (`AnalyticsAdmin`, `DriverSignalsAdmin`,
  `FieldPilotsAdmin`, `MapRoutingAdmin`) are now wrapped by `AdminRouteGuard` at the route level.
- `admin-create-staff-user` called `.catch()` on a Postgrest builder (a thenable, not a Promise):
  it threw *after* all writes succeeded, so accounts were created while the UI reported a 500.
  Fixed in G3, together with real error surfacing via `FunctionsHttpError.context`.

## 5. Frozen laws — untouched by this work

Node 5 identity law (lane exclusivity, `auth_uid_active()`, `pgrst_pre_request`, closure blockers,
`account_access_terminations`); Chop Pay / Slice 12 finance law (ledger immutability,
`_finance_treasury_facts` service_role only, treasury exception classes, raw finance tables
SELECT-only, Stage 5/6/7 flags OFF); Marché Node 4 order/economics/procurement contracts.
No RLS policy was weakened.

## 6. Landing consoles

- Operations Admin → `/admin/ops`
- Finance Admin → `/admin/finance`
- God Admin → full `/admin` dashboard
