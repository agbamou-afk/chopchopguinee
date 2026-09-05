# CHOP CHOP — Admin Capability Constitution

Status: **G1 CANONICAL / FROZEN**. Ratified 2026-09-05.
This document is the single constitutional source of admin authority. G2 enforcement code
(SQL helpers, grants, guards, approval gates) must be derived from this text. Where code and
this document disagree, this document defines the intent and the code is the defect.

Companion evidence: [`G1_ADMIN_AUTHORITY_AUDIT.md`](./G1_ADMIN_AUTHORITY_AUDIT.md).

---

## 1. Governing principles

1. **UI is never authority.** Menus, buttons, route guards, and the frontend permission
   registry are *affordances*. Authority exists only where the database or an Edge Function
   verifies the caller server-side. A hidden button is not a control.
2. **Deny by default.** Absence of an explicit grant is denial. No capability is implied by
   role name, table access, or historical convenience.
3. **Least privilege.** A staff class receives the minimum capability set required for its
   responsibility. Convenience never widens a class.
4. **Requester ≠ approver.** Any action classified APPROVAL_REQUIRED must be approved by a
   different natural person of the approver class. Self-approval is void.
5. **Read visibility does not imply mutation.** A class may be granted READ_ONLY sight of
   another domain's facts (needed for context and investigation) without any write path.
6. **Aliases never create authority accidentally.** Legacy role labels
   (`ops_admin`, `super_admin`, bare `admin`) resolve through one canonical normalization
   function. An unmapped or ambiguous label resolves to NULL — no authority.
7. **Frozen law supersedes admin convenience.** Node 5 identity law (closure, anonymization,
   professional lane exclusivity), Chop Pay / Slice 12 finance law (ledger immutability,
   named exceptions, no balancing plug), and Node 4 Marché law bind every staff class,
   including God Admin. An admin action that would violate frozen law must fail closed,
   not be granted an override.
8. **Every authority act is provenance-bearing.** Actor, canonical role, capability, target,
   material parameters, and (where applicable) approval id are recorded in `audit_logs`.

---

## 2. The three staff classes

### God Admin — constitutional / governance authority
Owns the constitution itself: staff lifecycle, role assignment, product and financial policy,
feature flags, account closure authority, and full audit visibility. God Admin is the only
class that may approve four-eyes actions. God Admin authority is *procedural*, not exempt:
frozen finance and identity law still apply, and destructive acts remain approval-bound.

### Operations Admin — operational authority
Owns the running of the service: users, drivers, merchants, orders and missions, support,
risk triage, live ops, maps and place corrections, driver signals, onboarding approvals.
Sees financial facts attached to the objects it operates (an order's amount, a driver's
balance) **READ_ONLY**. Holds no path to move, credit, adjust, release, or confirm money.

### Finance Admin — financial authority
Owns money: wallets, reconciliation, top-ups, payouts, driver cashouts, merchant
settlements, refunds, financial disputes, payment intents, treasury reporting.
Sees operational context **READ_ONLY** to justify a financial decision. Holds no path to
approve drivers, intervene in orders, edit maps, or change operational state.

Neither Operations nor Finance may create, modify, deactivate, or promote staff.

---

## 3. Constitutional capability matrix

Legend: **A** = ALLOW · **R** = READ_ONLY · **D** = DENY · **AR** = APPROVAL_REQUIRED (four-eyes).

### 3.1 Operations domain

| Capability | Ops | Finance | God |
|---|---|---|---|
| `ops.users.manage` — profile edit, contact correction, operational notes | A | R | A |
| `ops.drivers.manage` — application approve/reject, capability lanes, presence, groups | A | R | A |
| `ops.merchants.manage` — store verification, catalogue state, onboarding approvals | A | R | A |
| `ops.orders.manage` — order/mission intervention, reassignment, operational cancel | A | R | A |
| `ops.support.manage` — support issues, escalation, messaging | A | R | A |
| `ops.risk.manage` — risk queues, reversible flags, review outcomes | A | R | A |
| `ops.liveops.view` — live ops board, driver signals, route traces | A | R | A |
| `ops.maps.manage` — zones, places, duplicates, routing corrections | A | R | A |
| `ops.reports.view` — operational reporting | A | R | A |
| `ops.audit.view_own_domain` — audit entries for operational modules | A | R | A |

### 3.2 Finance domain

| Capability | Ops | Finance | God |
|---|---|---|---|
| `finance.wallet.read` — wallets, ledger, transactions | R | A | A |
| `finance.wallet.credit` — manual credit / correction | D | AR | AR |
| `finance.wallet.adjust` — reversal, write-off, commission correction | D | AR | AR |
| `finance.topup.manage` — OM reconciliation queues, match, expire, cancel | D | A | A |
| `finance.payouts.manage` — driver cashouts, merchant settlements, payout release | D | A | A |
| `finance.payout.confirm` — confirm a manual provider payout (money leaves) | D | AR | AR |
| `finance.reconciliation.approve` — close an exception with a stated cause | D | A | A |
| `finance.refund.approve` — refund above policy threshold | D | AR | AR |
| `finance.treasury.read` — treasury overview, exceptions, drilldown | D | A | A |
| `finance.treasury.move` — any treasury-affecting movement | D | AR | AR |
| `finance.policy.change` — finance policy / commission / settlement policy | D | AR | AR |
| `finance.flags.payment` — payment-rail and financial feature flags | D | AR | AR |
| `finance.audit.view_financial` — audit entries for financial modules | R | A | A |

Refund thresholds, cashout ceilings, and float limits are **`POLICY_THRESHOLD_REQUIRED`**:
no numeric value is constitutional. Thresholds live in God-configured finance policy
(`finance_policies`) and the gate reads them at execution time.

### 3.3 Governance / identity domain

| Capability | Ops | Finance | God |
|---|---|---|---|
| `governance.staff.manage` — create/deactivate staff, change admin role | D | D | AR |
| `governance.roles.assign` — grant or revoke an app role | D | D | AR |
| `governance.flags.manage` — non-financial product feature flags | D (propose) | D | A |
| `ops.flags.propose` / `ops.pricing.propose` — submit a change for approval | A | D | A |
| `governance.pricing.change` — tariffs, fares, promotions as policy | D | D | AR |
| `governance.account.ban` — reversible ban / unban | A | D | A |
| `governance.account.freeze` — reversible account freeze / unfreeze | A | AR | A |
| `governance.account.close` — closure with financial consequence | D | D | AR |
| `governance.account.anonymize` — destructive identity erasure (Node 5) | D | D | AR |
| `governance.professional.offboard` — professional lane termination | D | D | AR |
| `governance.audit.read_all` — full cross-domain audit visibility | D | D | A |
| `governance.settings.manage` — app settings, provider configuration | D | D | A |

**Reversible vs destructive.** Ban and freeze are reversible operational controls and stay
with Operations (freeze with a financial dimension needs Finance sign-off). Closure,
anonymization, and professional offboarding are destructive identity acts, God-only and
four-eyes, and remain subject to Node 5 blockers (`_account_closure_blockers`) which no
staff class can override.

**Audit log visibility scope.** Operations sees operational-module entries; Finance sees
financial-module entries plus operational entries attached to a financial target;
God sees everything including staff and governance entries. No class may delete or edit an
audit entry — `audit_logs` is append-only for every class.

### 3.4 Remaining domains

| Capability | Ops | Finance | God |
|---|---|---|---|
| `ops.onboarding.decide` — field pilots, field check-ins, agent onboarding decisions | A | D | A |
| `ops.liveops.view` — driver signals, presence, route traces | A | R | A |
| `finance.dispute.resolve` — Chop Pay / cash-order / package claim outcomes with money effect | D | AR | AR |
| `finance.dormant.review` — dormant closed-account liabilities | R | A | A |
| `governance.capability.resolve` — capability/role resolution and four-eyes gate helpers | A (self) | A (self) | A |
| `governance.sandbox.run` — QA harnesses, sandbox test runs | D | D | A |
| `ops.analytics.view` — product/behaviour analytics, AI insights | A | R | A |
| `ops.notifications.send` — operational notification dispatch | A | D | A |
| `ops.notifications.broadcast` — mass broadcast to a user population | AR | D | AR |

**Product flags vs payment rails.** A non-financial product flag (surface exposure, UI
capability, service availability) is `governance.flags.manage`: God allows, Operations may
only propose. Any flag that changes a payment rail, tender, settlement path or fee behaviour
is `finance.flags.payment`: Finance with four-eyes, Operations denied outright.

**Pricing.** Operations may read tariffs and *propose* a change (`ops.pricing.propose`).
Turning a proposal into policy — fares, tariff grids, commission, promotions with a money
effect — is `governance.pricing.change`, God-only and four-eyes.

---


## 4. Canonical role-normalization law (specification for G2)

Canonical names, and only these three: **`god_admin`**, **`operations_admin`**,
**`finance_admin`**.

| Legacy label | Source | Canonical resolution |
|---|---|---|
| `super_admin` | `admin_users.admin_role` | `god_admin` |
| `god_admin` | either source | `god_admin` |
| `ops_admin` | `admin_users.admin_role` | `operations_admin` |
| `support_admin` | `admin_users.admin_role` | `operations_admin` |
| `operations_admin` | either source | `operations_admin` |
| `finance_admin` | either source | `finance_admin` |
| `admin` (bare) | `user_roles.role` | **no authority** — legacy fallback is not constitutional; a bare `admin` row must be migrated to an explicit class |
| anything else / unknown | either | NULL |

Resolution law:
1. `auth_uid_active()` must return a live, non-terminated identity, else NULL.
2. `admin_users` counts only when `status = 'active'`.
3. Both sources are consulted; the resolver returns the **highest** matching class in the
   order god_admin > finance_admin > operations_admin.
4. **Conflicts fail closed.** If a subject carries labels that map to different classes and
   the higher class cannot be corroborated in `admin_users` with `status='active'`, resolution
   returns NULL rather than guessing.
5. G1 mutates no role row. Reconciling existing rows is a G2 item.

---

## 5. Four-eyes law (server-side, conceptual)

An APPROVAL_REQUIRED action executes only when a server-side gate finds an approval that:

1. **Distinct persons** — `requested_by <> reviewed_by`; self-approval is void even for God.
2. **Approver class** — reviewer resolves to `god_admin` at review time and at consumption time.
3. **Exact binding** — the approval names the exact capability, the exact target id, and the
   material parameters (amount, currency, new policy value). A change to any bound parameter
   invalidates the approval; it does not "cover" a different amount or a different target.
4. **Expiry** — an approval unused past its validity window is dead and cannot be revived.
5. **Single consumption + idempotency** — one approval authorizes one execution; a replay with
   the same idempotency key returns the original outcome instead of executing twice.
6. **Provenance** — the executing statement writes the approval id, requester, approver,
   capability, target, and parameters to `audit_logs`.
7. **No browser enforcement.** The frontend may only *display* whether approval is needed;
   `requiresApproval()` in `src/lib/admin/permissions.ts` is advisory. The database gate is
   the enforcement point.

Actions that are APPROVAL_REQUIRED under current ChopChop architecture:
`finance.wallet.credit`, `finance.wallet.adjust` (reversal/write-off),
`finance.payout.confirm`, `finance.refund.approve` (`POLICY_THRESHOLD_REQUIRED`),
`finance.treasury.move`, `finance.policy.change`, `finance.flags.payment`,
`governance.staff.manage`, `governance.roles.assign`, `governance.pricing.change`,
`governance.account.close`, `governance.account.anonymize`,
`governance.professional.offboard`, agent float increase above policy limit
(`POLICY_THRESHOLD_REQUIRED`), driver/merchant payout above policy limit
(`POLICY_THRESHOLD_REQUIRED`), bulk broadcast.

---

## 6. Capability namespace (exhaustive for G2 mapping)

```
ops.users.manage          ops.drivers.manage        ops.merchants.manage
ops.orders.manage         ops.support.manage        ops.risk.manage
ops.liveops.view          ops.maps.manage           ops.reports.view
ops.flags.propose         ops.pricing.propose       ops.audit.view_own_domain

finance.wallet.read       finance.wallet.credit     finance.wallet.adjust
finance.topup.manage      finance.payouts.manage    finance.payout.confirm
finance.reconciliation.approve                      finance.refund.approve
finance.treasury.read     finance.treasury.move     finance.policy.change
finance.flags.payment     finance.audit.view_financial

governance.staff.manage   governance.roles.assign   governance.flags.manage
governance.pricing.change governance.account.ban    governance.account.freeze
governance.account.close  governance.account.anonymize
governance.professional.offboard                    governance.audit.read_all
governance.settings.manage
```

Every audited callable in the G1 audit maps to exactly one of these capabilities.

---

## 7. Frozen law this constitution does not touch

- **Node 5 identity law** — lane exclusivity, capability gates, mode switcher, governance
  isolation, recovery, closure blockers, anonymization integrity.
- **Chop Pay / Slice 12 finance law** — ledger immutability, `_finance_treasury_facts`
  service-role only, named/quantified exception classes, no inferred adjustment or plug,
  raw finance tables SELECT-only for `authenticated`.
- **Node 4 Marché law** and Repas / ride node laws.

No capability in this constitution grants an override of any of the above.

---

## 8. Frontend module → capability mapping (display layer)

The frontend registry (`src/lib/admin/permissions.ts`) exposes 24 modules. Each is an
*affordance name*, not authority. Binding, so the display layer cannot drift from §3:

| Module | Capability | Ops | Fin | God |
|---|---|---|---|---|
| `dashboard` | class landing console | A | A | A |
| `live_ops` | `ops.liveops.view` | A | R | A |
| `users` | `ops.users.manage` | A | R | A |
| `drivers` | `ops.drivers.manage` | A | R | A |
| `driver_groups` | `ops.drivers.manage` | A | R | A |
| `merchants` | `ops.merchants.manage` | A | R | A |
| `vendors` | `ops.merchants.manage` (financial float → `finance.payouts.manage`) | R | A | A |
| `orders` | `ops.orders.manage` | A | R | A |
| `repas` / `marche` | `ops.orders.manage` | A | R | A |
| `support` | `ops.support.manage` | A | R | A |
| `risk` | `ops.risk.manage` | A | R | A |
| `zones` | `ops.maps.manage` | A | R | A |
| `notifications` | `ops.support.manage` | A | R | A |
| `reports` | `ops.reports.view` | A | R (export) | A |
| `analytics` | `ops.reports.view` | A | R | A |
| `wallet` | `finance.wallet.read` / `.credit` / `.adjust` | R | A/AR | AR |
| `payments` | `finance.payouts.manage`, `finance.payout.confirm` | D | A/AR | A |
| `pricing` | `ops.pricing.propose` vs `governance.pricing.change` | propose | R | AR |
| `promotions` | `ops.pricing.propose` vs `governance.pricing.change` | propose | R | AR |
| `flags` | `governance.flags.manage` / `finance.flags.payment` | propose | D/AR | A/AR |
| `settings` | `governance.settings.manage` | D | D | A |
| `admins` | `governance.staff.manage` | D | D | AR |
| `audit` | `ops.audit.view_own_domain` / `finance.audit.view_financial` / `governance.audit.read_all` | scoped | scoped | A |

Unmapped modules: **0**.
