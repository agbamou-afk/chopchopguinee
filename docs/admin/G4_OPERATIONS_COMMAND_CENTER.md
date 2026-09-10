# G4 — Operations Admin Command Center

**Status: CERTIFIED.** Scope executed: G4 only. G1 constitution, G2 backend capability
enforcement and G3 staff lifecycle are unchanged law. G5 and G6 not started.

## 1. What an Operations Admin is

An Operations Admin runs the *live business*: courses (Moto · Bonbonna · Taxi),
Envoyer, Repas, Marché, couriers, merchants, support, risk, maps and field.
It holds **no monetary mutation authority and no governance authority**. It may
*read* financial facts as operational context and must escalate anything monetary.

Landing console: `/admin/ops` (`AdminHomeRoute` routes `operations_admin` there;
Finance to `/admin/finance`; God to the full dashboard).

## 2. Capability binding (G1 registry, unchanged)

| Surface | Capability | Mode for Operations |
|---|---|---|
| Command center, live ops | `ops.liveops.view` | allow |
| Users | `ops.users.manage` | allow |
| Drivers, driver groups, field pilots | `ops.drivers.manage` | allow |
| Merchants | `ops.merchants.manage` | allow |
| Orders / Repas / Marché / missions | `ops.orders.manage` | allow |
| Support | `ops.support.manage` | allow |
| Risk | `ops.risk.manage` | allow |
| Maps, zones, places, duplicates, routing | `ops.maps.manage` | allow |
| Reports / analytics / own-domain audit | `ops.reports.view`, `ops.analytics.view`, `ops.audit.view_own_domain` | allow |
| Notifications | `ops.notifications.send` (broadcast = approval_required) | allow |
| Pricing | `ops.pricing.propose` | allow (propose only) |
| Financial facts | `finance.wallet.read`, `finance.audit.view_financial` | **read** |
| Wallet credit/adjust, payouts, treasury, reconciliation, finance policy | finance.* | **absent** |
| Staff, roles, flags, settings, governance pricing | governance.* | **absent** |

`MODULE_CAPABILITY` in `src/lib/admin/permissions.ts` binds each frontend module to
exactly one registry capability; `OPERATIONS_FORBIDDEN_MODULES` records the modules
Operations must never reach.

## 3. Server read model

`public.ops_command_overview()` — SECURITY DEFINER, read-only, gated on
`admin_capability_mode('ops.liveops.view', auth.uid()) IS NOT NULL` (so readiness,
suspension and role conflict all fail closed). No `anon`/`PUBLIC` execute.

Returns `generated_at`, `role`, `mode`, a bounded `snapshot` (rides active/today/
unassigned, missions, Repas, Marché, Envoyer, drivers online/approved, driver and
merchant applications pending, ops cases, support open/critical, map duplicates) and
up to 60 prioritised `attention` items, each with service, short reference, state,
age, severity, a read-only `finance_context` string and a canonical `href`.

No PII (no phone numbers, no customer names) crosses the boundary.

## 4. Prohibited on every Operations surface

Credit or debit a wallet · execute or release a payout or cashout · approve
reconciliation · change finance policy, fee schedules or settlement policy · move
treasury · switch a payment rail · create, role-change or deactivate staff · read
the staff roster · change platform settings or feature flags · mutate the capability
registry. Each is denied by the database, not merely hidden.

Escalation copy shown to Operations: **"Intervention Finance requise"**.

## 5. Route enforcement

Every `/admin/*` route in `src/App.tsx` is wrapped in `AdminRouteGuard` with its
module. A direct URL to a forbidden console renders the denied state; the server
gate remains the authority. Hidden navigation is never treated as authority.

## 6. Honest data

The console distinguishes three states: **loading**, **unavailable** (read failed or
denied — never rendered as `0`), and **0 élément — lecture réussie**. Refresh is
manual and on a visibility-aware interval.

## 7. Certification

| Board | Result |
|---|---|
| `_qa_g4_operations_command_center()` | **40/40**, 0 failures |
| Focused UI suite `src/test/g4OperationsCommandCenter.test.ts` | **25/25** |
| Full Vitest | **35 files / 352 tests**, 0 failures |
| Typecheck `tsgo --noEmit -p tsconfig.app.json` | clean |
| Build + PWA | success, 137 precache entries |
| Supabase linter | 645 (baseline 644, +1 = the new authenticated SECURITY DEFINER read model, intended and capability-gated) |
| Admin census | 1 active God (`super_admin`), 2 active Operations, 0 Finance |
| Real Operations fingerprint | `02d3a40415844089cab507f366921ac7`, unchanged before/after |
| QA fixture residue | 0 identities, 0 authority rows |
| Ledger / feature flags / capability registry drift | none (94 grants, unchanged) |

Server-proved denials include: wallet credit and adjust, payout execution,
reconciliation approval, finance policy change, payment-rail activation, treasury
move, `admin_manual_om_credit`, `admin_adjust_agent_float`, `admin_set_finance_policy`,
`admin_reverse_starter_credit`, `admin_staff_role_grant`, staff roster read,
settings change and direct capability-registry insert. Customers, signed-out
callers, suspended admins and temporary-password admins are denied the command
center entirely.

## 8. Status

**G4 — CERTIFIED / OPERATIONS COMMAND CENTER ENFORCED / G5–G6 NOT STARTED.**
