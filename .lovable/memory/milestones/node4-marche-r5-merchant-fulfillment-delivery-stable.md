---
name: Node 4 Marché R5 — Merchant Fulfillment + Delivery (stable)
description: Certified server-authoritative Marché fulfillment lifecycle (committed→delivered) with mission dispatch, stock settlement and append-only history
type: feature
---
- States: committed, accepted, preparing, ready, courier_engaged, collected, delivering, delivered, rejected, cancelled.
- Authority: `marche_merchant_transition` (store owner), `marche_courier_transition` (assigned courier), `marche_dispatch_request` (creates the linked `marketplace_delivery` mission). No client-authoritative lifecycle.
- History: `marche_fulfillment_transitions` is append-only, ordered by `seq`, RPC-only (no anon/authenticated grants); read via `marche_order_fulfillment_history` (buyer/merchant/admin, courier PII + mission id admin-only).
- Stock: `_marche_reservation_settle` releases on reject/cancel and consumes on delivery, exactly once.
- Telemetry: R3.5 milestones MERCHANT_ACCEPTED, MERCHANT_READY, COURIER_ENGAGED, COURIER_AT_STORE, PICKED_UP, DELIVERED (plus ORDER_COMMITTED) are written only by the two transition RPCs.
- Client: `src/lib/marche/fulfillment.ts` + merchant order actions in `MerchantCommandesView`.
- Certification: `_qa_node4_marche_r5` 167/167; full frozen board 0 failures (node0 34, node1 78, node2 97, repas suites, slice13 507, Marché R1 55 / R1.5 38 / R2 82 / R3 136 / R3.5 198 / R4 79); tsgo clean, vitest 99/99, production build + PWA pass. No deploy, no flag activation.
