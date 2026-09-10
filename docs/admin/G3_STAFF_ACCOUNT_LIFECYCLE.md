# G3 — Staff Account Lifecycle / Governed Admin Identity Operations

Status: **CERTIFIED**. G1 constitution and G2 backend capability enforcement remain
canonical and unmodified. G4 (Operations command center), G5 (Finance command
center) and G6 (final certification) are **NOT STARTED**.

## 1. Law

1. Staff authority is attached to the canonical `auth.users` UUID. G3 introduces no
   second identity system.
2. The only provisionable classes are `operations_admin` and `finance_admin`.
   No G3 path — DB, edge or UI — can create, target or assign a God Admin.
3. Authority is dual-sourced and always mutated atomically: `admin_users` +
   `user_roles`.
4. `must_change_password = true` ⇒ **zero effective capability** server-side
   (`admin_capability_mode` returns NULL through `admin_staff_readiness`).
5. Governance reads require a *lifecycle-ready* God Admin, not merely the God role
   (`_g3_require_governance_read`).
6. Temporary passwords are generated server-side, handed only to the GoTrue admin
   API, returned exactly once in the response, and never written to any table,
   audit row, lifecycle row or log line.
7. Four-eyes, quorum, approval binding and idempotency are enforced in Postgres.
   The browser is a mirror.

## 2. State machine

```text
CREATE / DEACTIVATE / REACTIVATE / ROLE_CHANGE / ACCESS_RESET
        |
   begin (DB)  admin_staff_lifecycle_begin_as
        |      capability + four-eyes + quorum + idempotency + intent hash
        v
   [pending] --(CREATE only)--> auth provisioning (edge)
        |                          |
        |                    admin_staff_record_auth_as
        v                          v
   [auth_provisioned] -----> finalize (DB)
        |                    admin_staff_finalize_create_as
        |                    admin_staff_finalize_deactivate_as
        |                    admin_staff_finalize_authority_as
        v
   [completed]          admin_staff_fail_as -> [failed_retryable | failed_final]
```

Authority is written **only** in the finalize step, and only after the Auth
identity has been recorded. A crashed or timed-out attempt resumes on the same
lifecycle row and the same Auth user; it never creates a second one.

## 3. Idempotency & saga

- Durable key: `idempotency_key` supplied per operation, bound to a material
  intent hash (`action`, `admin_role`, `must_change_password`, target key).
- Same key + same intent ⇒ replay/resume, never a duplicate (`ALREADY_COMPLETED`).
- Same key + different intent ⇒ `IDEMPOTENCY_INTENT_MISMATCH`.
- Auth-user reuse is proven by `user_metadata.staff_lifecycle_request_id`.
- The historical false-500-after-success is structurally impossible: every
  outcome is returned with HTTP 200 and a machine-readable `result`.

## 4. Auth / DB boundary

| Concern | Owner |
| --- | --- |
| capability, four-eyes, quorum, idempotency, authority rows, audit | Postgres |
| auth user creation, password set/reset, session revocation | `admin-staff-lifecycle` edge function |
| display of state, confirmations, reasons | `/admin/admins` UI (mirror only) |

`admin-create-staff-user` is **retired**: it is now a tombstone that performs no
writes and returns `ENDPOINT_RETIRED`.

## 5. Outcome contract

`CREATED`, `ALREADY_COMPLETED`, `DEACTIVATED`, `REACTIVATE`, `ROLE_CHANGE`,
`ACCESS_RESET`, `ACCOUNT_ALREADY_EXISTS`, `PENDING_APPROVAL`,
`APPROVER_QUORUM_UNAVAILABLE`, `IDEMPOTENCY_INTENT_MISMATCH`, `TARGET_CONFLICT`,
`FORBIDDEN`, `FAILED_RETRYABLE`, `FAILED_FINAL`.

Each maps to an exact French sentence in `src/lib/admin/staffLifecycle.ts`. The
generic “Edge Function returned a non-2xx status code” copy can never be the
primary user message.

## 6. Readiness routing

temporary password login → `AdminGuard` detects `must_change_password` →
`/admin/change-password` (sibling route, no admin chrome) → `auth.updateUser` →
only then `admin_clear_must_change_password()` → `/admin` home per the certified
architecture. No loops; no admin page reachable before completion. The shared
`PasswordInput` primitive is used for both fields.

## 7. Lifecycle table least privilege

`public.staff_lifecycle_requests`: RLS enabled, `PUBLIC` / `anon` /
`authenticated` privileges revoked, table grants held only by `service_role`.
Governed reads go through sanitized RPCs (`admin_staff_roster`,
`admin_staff_lifecycle_history`, `admin_staff_approvals`) which mask CREATE email
labels and strip password fields from approval material. Production provenance is
immutable; the QA purge exception is scoped to `qa-g3-%` fixtures and is not
callable from a browser session.

## 8. Quorum

`_g3_active_god_count()` = **1** active God Admin. `governance.staff.manage` is
APPROVAL_REQUIRED, therefore quorum is currently **unavailable** and the UI shows
verbatim: `Quorum d’approbation indisponible — un deuxième God Admin actif est
requis.` No self-approval, no bypass, no backend weakening.

## 9. Live census & fingerprints

| Canonical | Legacy | Status | Count |
| --- | --- | --- | --- |
| god_admin | super_admin | active | 1 |
| operations_admin | ops_admin | active | 2 |

Real Operations Admin fingerprints, unchanged before/after G3:
- `a9e4f3b0-…afab0c` → `50d41e45d7c5b196e593e54401cb8103`
- `dfb6a0f8-…40e2f473` → `48060fc3861f7f7826e9bad899ae9ec7`

Fixture residue: **0**.

## 10. Certification board

| Gate | Result |
| --- | --- |
| `_qa_g3_staff_lifecycle()` | 24/24, 0 failures |
| `_qa_g2_admin_authority()` | 28/28, 0 failures |
| Node 5 A2–A14 | 0 failures (96/119/133/111/110/130/93/95/108/122/89/114) |
| Node 5 A9 role governance | 7/7 |
| Dormant-liability / identity finance | 63, 0 failures |
| Focused G3 UI/Edge tests | 27/27 (`src/test/g3StaffLifecycle.test.ts`) |
| Full Vitest | 34 files / 327 tests passed |
| `bunx tsgo --noEmit -p tsconfig.app.json` | clean |
| Build / PWA | built in 24.9 s, precache 136 entries |
| DB linter | 644 issues (baseline 639, +5: intended God-only governance read RPCs) |
| Feature flags / economics / ledger | untouched |

## 11. Changed surface

- Edge: `supabase/functions/admin-staff-lifecycle/index.ts` (canonical),
  `supabase/functions/admin-create-staff-user/index.ts` (retired tombstone).
- DB: `_g3_require_governance_read`, `admin_staff_roster`,
  `admin_staff_quorum_status`, `admin_staff_lifecycle_history`,
  `admin_staff_approvals`, lifecycle table grant revocation.
- Frontend: `src/lib/admin/staffLifecycle.ts`, `src/pages/admin/AdminsAdmin.tsx`.
- Tests: `src/test/g3StaffLifecycle.test.ts`.
- Docs: this file.

G4, G5 and G6 were not started.
