# G2 — Backend Capability Enforcement

Status: **CERTIFIED / BACKEND CAPABILITY LAW ENFORCED**
Scope: server-side enforcement of the G1 constitution. No product behaviour changed.
Frozen and untouched: Node 5 identity law (A1–A14), Chop Pay / Slice 12 finance law, Marché (Node 4), Repas (Node 3), Course (Node 0/2).

---

## 1. Canonical role resolution

`public.admin_role_canonical(_uid uuid)` returns exactly one of
`god_admin` · `operations_admin` · `finance_admin` · `NULL`.

| Source label | Canonical class |
| --- | --- |
| `super_admin`, `god_admin` | `god_admin` |
| `ops_admin`, `operations_admin`, `support_admin` | `operations_admin` |
| `finance_admin` | `finance_admin` |
| bare `admin` | **no authority** |

Rules enforced:
- `admin_users` rows count only when `status = 'active'`.
- `auth_uid_active()` is required — a closed, banned or frozen account resolves to `NULL`.
- Conflicting classes across `admin_users` and `user_roles` resolve to `NULL` (fail closed) with a readable diagnostic.
- `service_role` / migration context (`_g2_internal_caller()`, i.e. `auth.uid() IS NULL`) keeps internal execution working.
- Every legacy predicate (`is_god_admin`, `_is_god_admin`, `_is_ops_or_god_admin`, `can_manage_operations`, `can_manage_wallet`, `has_admin_role`, `is_any_admin`, `_finance_privileged`, `guard_user_roles_write`) now derives from this single function and is wrapped in `COALESCE(…, false)` so a `NULL` can never be read as "no objection".

No role row was created, edited or deleted. The two live Operations Admin accounts are untouched (`ops_admin`, `active`).

## 2. Capability registry

`admin_capability_grants` holds **94 rows over 44 capabilities**, one explicit entry per class:
`allow` · `approval_required` · `read`. **25 grants are `approval_required`.**

- Absence of a row = denial. An unknown capability = denial.
- `read` never implies mutate.
- God Admin is no longer a bypass for two-person actions.
- `trg_admin_capability_registry_guard` blocks any write to the registry from a browser session.

Resolver: `admin_capability_mode(_capability, _uid)` → mode or `NULL`; `admin_capability(...)` returns a strict boolean.

## 3. Four-eyes law

`approval_requests` now binds an approval to the exact intent:
action + target type + target id + material parameters (`admin_intent_hash`), an expiry, and `consumed_at` for single use.

- `admin_request_approval` / `admin_review_approval` create and decide.
- Requester ≠ approver is enforced server-side.
- Approver class is checked against the capability.
- Target mismatch, material-parameter mismatch, expiry and replay are all refused.
- Consumption is atomic with the guarded mutation.

## 4. Central gate

- `public.admin_enforce(_capability, _target_type, _target_id, _material, _approval_id, _module)` — for signed-in callers.
- `public.admin_enforce_as(_caller uuid, …)` — identical rules for server code; `REVOKE`d from `PUBLIC`, `anon`, `authenticated`, granted to `service_role`.

Both write immutable provenance through `admin_audit_write`.

## 5. Wiring

**34 sensitive RPCs** are wrapped: the public entry point performs `admin_enforce(...)` then delegates to an internal copy named `_g2i_<original>`. The internal copies are not callable by `anon` or `authenticated` and carry the original, unmodified business logic — which is why no downstream behaviour changed.

Covered domains: wallet credit/adjust, Orange Money receipts and manual credits, Marché and Repas capture-and-settle, driver and merchant payout confirmation, refunds and disputes, finance policy / payout policy / settlement policy / provider fees / starter credit, payment-rail flags, staff creation and role grant/revoke, professional offboarding, account closure and anonymisation, Repas pricing.

Public signatures gained a trailing `_g2_approval uuid DEFAULT NULL`; existing callers that omit it still resolve, and an approval-required action without an approval id fails closed.

Counts: 100 `admin_*` RPCs in `public`; **0 executable by `anon`**; 35 functions call the gate.

## 6. Cross-domain corrections

| Surface | Before | After |
| --- | --- | --- |
| `admin_marche_capture_and_settle_offer` | operations authority | finance capability |
| `admin_repas_capture_and_settle_order` | operations authority | finance capability |
| `admin_set_feature_flag` | one switch for everything | split by flag class; payment-rail flags are governance + two-person |
| `om-import-csv` (edge) | `can_manage_wallet` | `finance.topup.manage` |
| `admin-email-resend` (edge) | raw `admin_users` tier check | `ops.support.manage` |
| `admin-driver-doc-url` (edge) | ad-hoc check | `ops.drivers.manage` |
| `qa-merchant-harness` (edge) | bare `has_role('admin')` | `governance.sandbox.run`, sign-in required |
| `qa-node-harness` (edge) | static `x-qa-token` bypass | bypass removed, `QA_HARNESS_ENABLED` off by default, `governance.sandbox.run` |
| `admin-delete-user` (edge) | legacy tier lookup | `admin_role_canonical` |
| `admin-create-staff-user` (edge) | no two-person control | `admin_enforce_as` on `governance.staff.manage` with `approval_id` |

Frontend: the legacy bare `admin` label no longer confers admin authority (`useAdminAuth`, `AuthContext.ADMIN_ROLES`).

## 7. Grants / RLS posture

- `anon` EXECUTE on `admin_*`: **0** (verified after every migration).
- Internal `_g2i_*` copies: 0 reachable by `anon` or `authenticated`.
- 31 tables have RLS enabled with no policy — all are service-role-only ledger/queue/evidence tables; deny-by-default is the intended posture and is recorded, not "fixed".

## 8. QA evidence

Adversarial DB harness `public._qa_g2_admin_authority()` — **28/28 pass**. It provisions ephemeral God A/B, Operations, Finance, plain and role-conflict fixtures, exercises every bypass path (bare `admin`, conflict, closed account, cross-class, self-approval, wrong approver class, target mismatch, material mismatch, expiry, replay, atomicity, registry tampering, static token, anon EXECUTE, audit provenance) and deletes its fixtures. It never touched the two real Operations Admin accounts.

Frozen-law regression suites, all at 0 failures after G2:

| Suite | Failures |
| --- | --- |
| `_qa_g2_admin_authority` | 0 (28 checks) |
| Node 5 `a2, a6, a7, a8, a9, a10, a11, a12, a13, a14`, `final_remediation` | 0 |
| Slice 13 `run1`–`run7` | 0 |
| Node 4 Marché `r1`–`r15` | 0 |
| Node 3 Repas `r1_r4` … `r11`, `pickup` | 0 |
| Node 0 Course, Node 2 Taxi | 0 |

Harness-only repairs made during certification (no product code touched):
- `_qa_s13_run5` F5/F6 aim at the public entry point again and accept the current denial vocabulary (`capability_denied`).
- `_qa_s13_run7_fxcore` S7.1 checks the current `admin_anonymize_user(uuid,text,uuid)` signature.
- `_qa_node4_marche_r11` B5 uses an Operations Admin fixture (the old fixture was seeded as God Admin, so the assertion was vacuous).
- `_qa_node4_marche_r4` A14 and `_qa_node3_repas_pickup_fxcore` P1.5/P1.6 read both the wrapper and the internal copy.
- `_qa_node5_identity_a2` B4 counts all active professional identities instead of only backfilled ones (it broke whenever a real driver signed up).
- `_qa_node5_identity_a12` entrypoint list uses the real public signatures.

Frontend: `bunx tsgo --noEmit -p tsconfig.app.json` clean; Vitest 300/300; build clean; PWA precache 136 entries.
Linter: 639 issues, unchanged from the pre-G2 baseline (31 rls-no-policy, 9 mutable search_path, 1 extension in public, 109 anon SECURITY DEFINER, 489 authenticated SECURITY DEFINER).

## 9. Not started

G3 (staff lifecycle), G4 (`/admin/ops`), G5 (`/admin/finance`), G6 (final adversarial certification).
