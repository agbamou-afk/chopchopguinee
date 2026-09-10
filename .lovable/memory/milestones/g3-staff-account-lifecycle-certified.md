---
name: G3 Staff Account Lifecycle — Certified
description: Governed Ops/Finance staff provisioning saga, readiness law, retired legacy creation endpoint
type: milestone
---
Locked 2026-09-10. See `docs/admin/G3_STAFF_ACCOUNT_LIFECYCLE.md`.

- Canonical edge function `admin-staff-lifecycle` (CREATE / DEACTIVATE / REACTIVATE /
  ROLE_CHANGE / ACCESS_RESET). Always HTTP 200 with a machine-readable outcome —
  never the generic non-2xx copy.
- `admin-create-staff-user` is RETIRED (tombstone, zero writes).
- Only `operations_admin` / `finance_admin` are provisionable. God Admin is never
  creatable or targetable through G3.
- Temporary passwords: server-generated, Auth API only, shown once, never stored or logged.
- `must_change_password=true` ⇒ zero effective capability; governance reads require a
  lifecycle-ready God Admin (`_g3_require_governance_read`).
- `staff_lifecycle_requests`: service_role only, RLS on, sanitized read RPCs.
- Quorum: 1 active God Admin ⇒ approval quorum unavailable, surfaced verbatim in the UI.
- Gates: G3 24/24, G2 28/28, Node 5 A2–A14 0 failures, Vitest 327/327, typecheck clean,
  build + PWA 136 entries, linter 644 (+5 intended), fixture residue 0.
- G4/G5/G6 not started.
