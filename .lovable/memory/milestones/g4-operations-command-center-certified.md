---
name: G4 Operations Command Center — Certified
description: Operations Admin authority locked to operational domains, read-only finance facts, no governance; capability-gated read model and route guards
type: feature
---

Locked 2026-06 — see `docs/admin/G4_OPERATIONS_COMMAND_CENTER.md`.

- Operations Admin lands on `/admin/ops`; console is fed by the single read-only
  RPC `ops_command_overview()` gated on `ops.liveops.view`.
- Operations owns users, drivers, driver groups, merchants, orders/missions,
  Repas, Marché, Envoyer, support, risk, maps, field, reports/analytics.
- Financial facts are READ context only; escalation copy "Intervention Finance
  requise". No wallet credit/debit, payout, reconciliation, treasury, payment
  rail, finance policy. No staff, roles, flags, settings, capability registry.
- `MODULE_CAPABILITY` + `OPERATIONS_FORBIDDEN_MODULES` in
  `src/lib/admin/permissions.ts`; every `/admin/*` route wrapped in
  `AdminRouteGuard`. UI hiding is never authority — the DB gate is.
- Console never renders a failed read as 0: loading / unavailable / "0 élément —
  lecture réussie" are distinct.
- Boards: `_qa_g4_operations_command_center()` 40/40, focused UI 25/25, full
  Vitest 352/352, typecheck + build clean, PWA 137, linter 645 (+1 intended).
- Do not weaken: G1 constitution, G2 capability enforcement, G3 staff lifecycle.
  G5 (Finance) and G6 (certification) not started.
