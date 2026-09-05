---
name: G2 Backend Capability Enforcement — Stable
description: Server-side admin capability law — canonical roles, 44-capability registry, four-eyes approvals, 34 gated RPCs
type: milestone
---
Locked 2026-09-05. Doc: `docs/admin/G2_BACKEND_CAPABILITY_ENFORCEMENT.md`.

- `admin_role_canonical(uuid)` is the single source of admin authority: god_admin / operations_admin / finance_admin / NULL. Bare `admin` grants nothing. Role conflicts and inactive accounts resolve to NULL. All legacy predicates delegate to it, wrapped in `COALESCE(..., false)`.
- `admin_capability_grants`: 94 rows, 44 capabilities, modes allow/approval_required/read (25 approval_required). Missing row = denial. Registry writes blocked from browser sessions.
- Four-eyes: `approval_requests` bound by `admin_intent_hash` (action+target+material params), expiry, single-use `consumed_at`. Requester ≠ approver; approver class checked.
- Gate: `admin_enforce(...)` (signed-in) and `admin_enforce_as(...)` (service_role only). 34 sensitive RPCs wrapped; original logic preserved in `_g2i_<name>` internals not callable by anon/authenticated.
- Public signatures gained trailing `_g2_approval uuid DEFAULT NULL`.
- 0 `admin_*` functions executable by anon. QA: `_qa_g2_admin_authority()` 28/28.
- G3–G6 not started.
