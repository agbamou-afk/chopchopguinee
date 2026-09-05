---
name: Admin Capability Architecture — Stable
description: God/Operations/Finance admin constitution enforced in DB (admin_capability, four-eyes gate), anon EXECUTE revoked on all admin_* RPCs, staff creation fixed
type: milestone
---
Locked 2026-09-05.

- Canonical role: `admin_role_canonical(uuid)` → god_admin | finance_admin | operations_admin | NULL
  (ops_admin≡support_admin≡operations_admin, super_admin≡god_admin, inactive/terminated → NULL).
- Registry table `admin_capability_grants` (capability, admin_role, mode allow|approval_required),
  god_admin implicit ALL. Helpers: `admin_capability`, `admin_require_capability`,
  `admin_capability_mode`, `admin_four_eyes_gate` (requester ≠ approver, approver = god_admin).
- All `admin_*` RPCs: EXECUTE revoked from anon and PUBLIC (0 remaining). `admin_log_test_delete`
  was the only genuinely unguarded function — now staff-gated.
- `admin-create-staff-user`: `.catch()` on a Postgrest thenable caused a 500 after successful
  creation; fixed, plus 409 email conflict and real error surfacing via FunctionsHttpError.context.
- Landing consoles: /admin/ops (operations), /admin/finance (finance), /admin (god).
  Route guards added for analytics, driver-signals, field pilots, map routing.
- Doc: docs/admin/ADMIN_CAPABILITY_CONSTITUTION.md. Tests: src/test/adminCapability.test.ts (10).
  Linter 663 → 634. No RLS weakened; Node 5 / Slice 12 / Node 4 laws untouched.
