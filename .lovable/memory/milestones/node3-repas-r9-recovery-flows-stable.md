---
name: Node 3 Repas R9 — Recovery Flows Stable
description: Repas ambiguous-commit recovery — durable client request id, read-only repas_order_resume, idempotent replays proven by _qa_node3_repas_r9_recovery_flows (68/68)
type: feature
---

# Node 3 / Repas R9 — Recovery Flows (LOCKED)

Frozen baseline: R1–R8 economics, custody, tracking, discovery and all finance
flags unchanged. R9 added only recovery seams.

## Server
- `public.repas_order_resume(uuid)` — STABLE, SECURITY DEFINER, `search_path=public`,
  anon revoked / authenticated granted. Read-only: resolves the caller's OWN
  `client_request_id` to the canonical order (state, frozen total, mission) or
  `found:false`. Never creates durable state, never leaks pricing snapshot,
  courier payout or another party's order.
- Existing idempotency reconfirmed, not rewritten: `repas_order_create`
  (request fingerprint + `FOR UPDATE` replay), `repas_merchant_transition`
  (`idempotent:true`), `repas_customer_cancel_order`, custody code consumption.

## Client
- `src/lib/repas/checkoutRequestId.ts` — durable per-intent idempotency key
  (localStorage, order-insensitive cart fingerprint). Survives reload/crash.
- `resumeFoodOrder()` in `src/lib/repas/orders.ts`.
- `RepasRestaurantDetail`: unknown commit outcome resolves through resume before
  showing an error; mount rehydrates a pending request id from server truth;
  key cleared only once the order is known to exist.
- `RepasOrdersSection`: a refused merchant action re-reads canonical order +
  tracking instead of leaving a stale card.

## Certification (all after the last edit)
- `_qa_node3_repas_r9_recovery_flows()` — **68/68 PASS**, rollback-safe fixtures,
  residue + master-wallet + feature-flag invariance proven.
- R8 202/202 · R7 203/203 · R6 171/171 · R5 71/71 + runtime 91/91 · R4.5 64/64 ·
  R1–R4 148/148 · Node0 34/34 · Node1 78/78 · Node2 97/97 · Slice 13 507/507.
- Vitest 60/60, tsgo exit 0, production build PASS.
