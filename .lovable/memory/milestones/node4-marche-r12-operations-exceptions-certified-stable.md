---
name: Node 4 Marché R12 — Operations + Exceptions (certified)
description: Server-authoritative Marché ops case system with prospective controls, immutable intervention history, role-gated commands and admin cockpit
type: feature
---

# Node 4 — Marché R12: Operations + Exceptions — CERTIFIED / LOCKED / FROZEN

## Core product law

Operations may control what happens NEXT. Operations must NOT rewrite what already happened.
No ops path touches wallets, ledger journals/postings, payables, payout orders, orders, procurement,
price observations, custody or raw reputation events. Corrections must travel canonical rails.

## Model

- `marche_ops_cases` — 10 case types: merchant_suspension, catalog_violation, price_anomaly, fraud,
  procurement_anomaly, customer_dispute, shopper_dispute, rating_abuse, stock_accuracy, merchant_reliability.
- `marche_ops_events` — append-only, immutable intervention history (actor role, reason, before/after, finance_ref),
  idempotent by `request_id`.
- `marche_ops_controls` — prospective only: store suspension, listing quarantine, user restriction.
- `marche_ops_reputation_moderations` — excludes a rating from aggregates; raw R9 evidence never deleted.
- `v_marche_listing_truth` gains refusals `LISTING_QUARANTINED`, `STORE_SUSPENDED`.
- `marche_reputation_summary` excludes moderated events.

## RPC surface (SECURITY DEFINER, search_path pinned, authenticated-only EXECUTE)

`marche_ops_queue`, `marche_ops_case_detail`, `marche_ops_case_open`, `marche_ops_signal` (detector-idempotent,
service_role allowed), `marche_ops_command`. Allowed actions are server-computed by `_marche_ops_allowed_actions`;
the client never derives them. `operations_admin` owns operational controls; `finance_admin` is required for
`record_finance_resolution`. Missing role fails closed. Direct table CRUD revoked from anon and authenticated.

## Client

- `src/lib/marche/ops.ts` — typed RPC bindings, French labels, error translation.
- `src/pages/admin/MarcheOpsAdmin.tsx` at `/admin/marche/ops`, sidebar entry "Opérations Marché" (module `marche`).
- Rendering only: queue counts, subjects, controls, allowed actions, immutable timeline.

## Certification

| Suite | Assertions | Failed |
| --- | --- | --- |
| Node 0/1/2 | 209 | 0 |
| Slice 13 | 507 | 0 |
| Repas | 1,612 | 0 |
| Marché R1–R11 | 1,760 | 0 |
| Marché R12 | 129 | 0 |

Machine-derived board: **4,217 executed / 0 failed / 0 timeouts**.
Client gates: tsgo exit 0; Vitest 18 files / 138 tests passed; unit board green.
Non-drift: profiles 1,534 → 1,534; wallets 68; ledger postings 120, sum 0; ops cases/controls residue 0.

**NODE 4 · MARCHÉ R12 — CERTIFIED / LOCKED / FROZEN**
