# CHOPCHOP — Pilot Command Center / Ops Dashboard Spec

**Owner:** CHOP GUINEE LTD
**Status:** Draft v1 — specification only (no implementation yet)
**Scope:** Lightweight operational dashboard to run the controlled district pilot day by day.
**References:**
- `docs/pilot/WONGO_PILOT_READINESS_PLAN.md`
- `docs/pilot/WONGO_PILOT_EXECUTION_CHECKLIST.md`
- `src/pages/admin/PaymentsAdmin.tsx`, `src/pages/admin/WalletReconciliation.tsx`

---

## 1. Purpose

The Pilot Command Center is the **operational nerve center** for the CHOPCHOP district pilot. It exists so the on-duty operator can answer, in seconds:

- What is happening right now?
- What needs attention?
- Which missions are failing?
- Which payments need review?
- Which merchants are delaying?
- Which couriers are causing issues?
- Which district is active?
- Are we safe to keep operating today?

This is **operational triage**, not analytics. It is not a vanity dashboard, not investor metrics theater, not an enterprise ERP, not a dispatch control tower, not an accounting surface.

### Design principles
- Lightweight, glanceable, operator-first.
- Real-time enough (polling acceptable; websockets only where they already exist).
- Action-oriented: every signal should have a next step.
- Mobile/tablet friendly — operators will use it in the field.
- Pilot-safety focused — surface risks early, never hide failures.
- Reuse existing admin shell (`AdminGuard`, `AdminLayout`, `ModulePage`). Do not redesign the admin system.

---

## 2. Main Sections

1. Today's Pulse
2. Live Missions
3. Payments Review
4. Support Issues
5. Merchant Watch
6. Courier Watch
7. District Activity
8. Go / No-Go Health

Each section is a self-contained card/panel and can be collapsed on mobile. Sections fail soft: if a data source is missing, show an empty state, never a crash.

---

## 3. Today's Pulse

Small operational counters across the top of the dashboard. No charts.

| Counter | Source | Color rule |
|---|---|---|
| Active missions | `missions` where state ∈ (pending, accepted, heading_to_pickup, picked_up, heading_to_dropoff) | yellow if > capacity threshold |
| Completed today | `missions` where state = delivered, created_at ≥ today | green |
| Failed today | `missions` where state ∈ (failed, issue_reported), created_at ≥ today | red if > threshold |
| Pending payments | `payment_intents` where state ∈ (pending, processing) | yellow if any > 10 min old |
| Review-needed payments | derived via `src/lib/payments/review.ts` heuristics | red if any |
| Open support issues | issues table (TODO if missing) | red if any P0 |
| Active couriers | `driver_profiles` with recent presence | gray if 0 |
| Active merchants | `merchant_stores` / `restaurants` with `is_open = true` | gray if 0 |

**Status palette:** green = stable, yellow = watch, red = action needed, gray = inactive. Reuse existing semantic tokens (`--primary`, `--destructive`, `--muted`, etc.) — never raw hex.

---

## 4. Live Missions

Mission list grouped by status:
- pending
- accepted
- heading_to_pickup
- picked_up
- heading_to_dropoff
- delivered
- failed / issue_reported

**Mission types displayed:** Course Moto, Livraison Repas, Livraison Marché, Envoyer Colis.

**Row fields:** mission type, district pair (origin → dest), customer, merchant/seller (if applicable), courier, current state, age since creation, issue flag.

**Row actions:** view details, contact courier, contact customer, contact merchant, mark for review.

**Constraints:**
- Do **not** introduce unsafe state edits. Only expose state transitions that are already supported and permitted by existing RPC / mission pipelines.
- Use existing mission pipeline definitions (`src/lib/missions/pipelines.ts`).
- Filtering: by district, by mission type, by state, by "has issue".

---

## 5. Payments Review

Summary of the existing `/admin/payments` surface — **link, do not duplicate**.

**Cards:**
- Pending payments
- Failed payments
- Review-needed payments (uses `src/lib/payments/review.ts` heuristics)
- Confirmed today
- Payments pending too long (age threshold, e.g. > 10 min)

**Row fields:** CHOPCHOP reference (`internal_reference`), provider, amount (GNF), status chip, user, created time, review signal.

**Row actions:** open payment detail, jump to `/admin/payments` (filtered), `mark reviewed` (later, when supported).

**Strict rule:** no wallet credit buttons, no reconciliation logic, no manual confirms here. The reconciliation workspace remains the single source of truth.

---

## 6. Support Issues

Lightweight queue.

**Issue types:** payment pending, courier no-show, merchant not ready, customer unreachable, wrong address, failed payment, package dispute, app bug, other.

**Row fields:** severity, service, district, related mission/payment/order, assigned owner category, status, age.

**Row actions (initial):** view issue. **Later:** add internal note, mark resolved, escalate.

**Note:** A unified `issues` table does **not** yet exist (see Readiness Plan §11). Mark this section TODO and render an empty-state until the table lands. Do not invent fake data.

---

## 7. Merchant Watch

Pilot merchants needing attention.

**Signals:** order not acknowledged, prep delay, repeated cancellations, marked offline during operating hours, low listing quality, delivery handoff issue, payment confusion.

**Row fields:** name, type (restaurant/store), district, open/closed state, active orders, issue count, last response time (if available).

**Row actions:** contact merchant, open merchant profile, mark for follow-up.

Scope to pilot district(s) only.

---

## 8. Courier Watch

Couriers needing attention.

**Signals:** no-show, repeated rejection, issue reports, late pickup, low acceptance, active mission stuck, district mismatch, payout/payment concern.

**Row fields:** name, masked phone, active district, capability (`rides_moto`, `repas_delivery`, etc.), active mission, issue count, acceptance signal.

**Row actions:** contact courier, open courier profile, mark for follow-up.

---

## 9. District Activity

Pilot district health cards.

**Initial pilot:** Kipé (primary), Dixinn (secondary/fallback).

**District card fields:**
- active missions
- completed today
- failed today
- active couriers
- active merchants
- support issues
- payment issues

Use existing district metadata + colors (`src/lib/districts/`) subtly as accents. **No heatmaps, no choropleths** in this phase.

---

## 10. Go / No-Go Health

Daily operating health checklist that maps to the Pilot Execution Checklist.

| Check | Source / signal |
|---|---|
| Support staffed? | manual toggle by ops lead at shift start |
| Payment review clear? | review-needed count = 0 AND no pending > 30 min |
| Dispatch stable? | failed-mission ratio under threshold last hour |
| Active couriers available? | active couriers ≥ pilot minimum |
| Merchant response acceptable? | avg merchant ack time under threshold |
| App errors under control? | error rate under threshold (later) |
| Unresolved P0 issues? | none open |
| Wallet/reconciliation healthy? | `/admin/wallet-reconciliation` discrepancy = 0 |

**Result light:**
- 🟢 Green — operate normally
- 🟡 Yellow — operate with caution (note in shift log)
- 🔴 Red — pause affected service / district and escalate

Decision authority: Ops Lead, in consultation with Payment Lead and Tech Lead per the Execution Checklist risk playbook.

---

## 11. Data Sources

| Source | Status | Used by |
|---|---|---|
| `missions` | ✅ exists | Pulse, Live Missions, District |
| `mission_events` | ✅ exists | Live Missions (age, issues) |
| `food_orders` | ✅ exists | Merchant Watch (Repas) |
| Marketplace listings / interests / delivery missions | ✅ exists | Merchant Watch (Marché) |
| `payment_intents` | ✅ exists | Pulse, Payments Review |
| `payment_reconciliation_events` | ✅ exists | Payments Review |
| `merchant_stores` | ✅ exists | Merchant Watch |
| `restaurants` | ✅ exists | Merchant Watch |
| `driver_profiles` (+ presence) | ✅ exists | Courier Watch, Pulse |
| `wallets`, `wallet_transactions` | ✅ exists | Go/No-Go health |
| District metadata (`src/lib/districts/`) | ✅ exists | District Activity |
| Unified `issues` table | 🔴 TODO | Support Issues, Merchant/Courier Watch issue counts |
| Shift / operating-state log | 🔴 TODO | Go/No-Go health (manual toggles) |

If a source is missing, render an empty state with a TODO marker. **Never invent fake data.**

---

## 12. Permissions

Reuse `AdminGuard` + `useAdminAuth` + `src/lib/admin/permissions.ts`.

| Role | Access |
|---|---|
| `god_admin` | Full access (all sections, all actions) |
| `operations_admin` | Full read; mission/merchant/courier contact actions |
| `finance_admin` | Read access to Payments Review + Go/No-Go payment health only |
| `support_admin` (future) | Read + Support Issues actions |
| Any non-admin user | ❌ Hard deny → `/no-access` |

- Sensitive payment actions (confirm, refund, reverse) stay **only** in `/admin/payments` and `/admin/wallet-reconciliation`. The Command Center links into them; it never re-implements them.
- New module key suggestion: `command_center` (added to `AdminModule` in a later phase). Until then, gate on `dashboard:view` + `live_ops:view`.

---

## 13. Implementation Strategy (Phased)

| Phase | Deliverable | Notes |
|---|---|---|
| **A** | This spec document | ✅ current sprint |
| **B** | Read-only dashboard shell at `/admin/command-center` with the 8 section cards, all wired to empty states | No data wiring yet |
| **C** | Wire live counters and lists from existing tables (missions, payment_intents, etc.) via existing hooks | Read-only |
| **D** | Add Support Issues queue + lightweight actions once the `issues` table exists | Requires schema work |
| **E** | Add Go/No-Go daily health indicator + manual operator toggles | Requires shift-log table |

**Do not skip phases.** Do not merge B–E into one release.

---

## 14. Out of Scope / Do NOT

- ❌ Manual dispatch overrides
- ❌ Wallet credit / debit buttons
- ❌ Duplicate payment reconciliation logic
- ❌ Large analytics charts, cohort views, funnels
- ❌ Broad exposure of PII (phones masked, addresses truncated)
- ❌ Fake / placeholder pilot metrics
- ❌ Changes to dispatch, payment, wallet, or mission rules
- ❌ National rollout assumptions

---

## 15. Acceptance

- [x] `docs/pilot/WONGO_PILOT_COMMAND_CENTER_SPEC.md` exists
- [x] References Readiness Plan and Execution Checklist
- [x] Purpose clearly operational (triage, not analytics)
- [x] 8 sections clearly defined with fields + actions
- [x] Data sources listed with existence status
- [x] Permissions defined per role
- [x] Phased implementation strategy (A–E) included
- [x] No product logic changed
- [x] Build remains clean (doc-only sprint)

---

_End of CHOPCHOP Pilot Command Center Spec v1._