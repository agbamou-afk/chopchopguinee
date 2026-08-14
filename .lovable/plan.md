# Node 3 — Repas Read-Only Certification Audit (Standard v1)

Read-only. No code, DB, migration, flag, policy, test, config, package, secret or milestone file was modified.

## 1. Current architecture and real persisted lifecycle

Customer: `ServicesView` -> `FoodView` (discovery/search) -> `RepasRestaurantDetail` (menu + cart + checkout) -> `src/lib/repas/cart.ts` / `orders.ts`.
Merchant: `MerchantCommandesView` / `components/merchant/repas/RepasOrdersSection.tsx` + `src/lib/merchant/operations.ts` + `src/lib/repas/merchantOps.ts`.
Driver: `components/driver/ActiveMissionCard.tsx` with `CashOrderPanel` / `ChopPayOrderPanel` / `OrderMessagingPanel`, fed by `missions` (`type='food_delivery'`, `ref_food_order_id`).
Admin: `pages/admin/RepasAdmin.tsx`, `RepasPayments.tsx`, `CashOrderDisputeQueue`, `ChopPayDisputeQueue`.

Persisted order state (`food_orders.state`, enum `food_order_state`): `placed -> confirmed -> preparing -> ready -> out_for_delivery -> completed`, plus `cancelled`. Payment truth: `payment_status`, `paid_at`, `settlement_state`, `settlement_tx_id`, `captured_intent_id`, `completed_at`.

Order creation is a **direct client INSERT** into `food_orders` + `food_order_items` (`src/lib/repas/orders.ts:36-62`), subtotal summed client-side from client-supplied `unitPriceGnf`. Wallet path then calls `choppay_create_payment_intent` and the client writes back `payment_status` (`orders.ts:84-127`). Delivery dispatch is a best-effort client `createMission(...)` with a hardcoded `REPAS_DEFAULT_COURIER_EARNING_GNF = 15000` (`orders.ts:27,179-192`).

Server-side engines that *do* exist: `cash_order_*` (quote/merchant_accept/merchant_prepare/customer_cancel/dispute/complete), `chop_pay_*` order runtime, `merchant_payable_*`, `repas_complete_order`, `repas_capture_and_settle_order`, `admin_repas_capture_and_settle_order`, plus triggers `trg_cash_order_block_direct_state`, `trg_chop_pay_block_direct_state`, `trg_prevent_unsafe_food_order_completion`, `trg_prevent_unsafe_food_order_payment_status_update`, `trg_block_frozen_food_orders`. These engines are entered only at **driver accept**, not at checkout.

## 2. Evidence by lens

| Lens | Grade | Evidence |
| --- | --- | --- |
| A Discovery/comprehension | CODE-VERIFIED (partial) / VISUAL-YELLOW | `FoodView.tsx` (305 l) search + `FoodCategories`; `RepasRestaurantDetail.tsx` (624 l) menu/cart/checkout; open/closed + `delivery_available`/`pickup_available` modelled. No delivery-fee or ETA field exists at all; no 390x844 authenticated visual pass. |
| B Runtime completeness | GAP (P0) | Checkout bypasses server RPC; no `client_request_id`; client-computed subtotal; no delivery fee/platform-fee persistence. |
| C Merchant fulfillment | CODE-VERIFIED with GAP | Accept/prepare/ready via `advanceRestaurantOrder`; cash path routed to `cash_order_merchant_accept/prepare`. Non-cash path is a raw table UPDATE (`operations.ts:101-105`). No explicit merchant *reject* action in the non-cash UI path; no incoming-order alert/sound; no merchant earnings read model surfaced for Repas. |
| D Driver fulfillment | CODE-VERIFIED | `ActiveMissionCard` renders cash funding + Chop Pay collateral panels; eligibility/exclusions inherited from the certified mission spine (not independently proven for `food_delivery`). No pickup handshake/proof for Repas custody. |
| E Financial integration | GAP (P0) | `finance_policies` for `repas` are correct (fee 100 bps, `fee_basis=merchandise_subtotal`, `cash_funding_mode=merchandise_subtotal` 10000 bps, collateral 5000 bps, cancel 500/1000 bps) but **no Repas checkout creates a cash/Chop Pay runtime row**; both runtime tables are empty. Wallet hold is a raw payment intent, not the engine. |
| F Failure/recovery/support/admin | PARTIAL | `OrderMessagingPanel` + `support_issues` exist; dispute queues exist; `admin_repas_capture_and_settle_order` exists. No no-driver recovery path for Repas (unlike Node 1/2), no merchant-timeout expiry, no auto-refund on rejection. |
| G UX/environmental | VISUAL-YELLOW | Repas-specific vocabulary is clean; low-data/offline behaviour untested for Repas; duplicate-tap protection absent by construction (no idempotency key). |
| H Engagement/reuse | GAP (P2) | `listMyFoodOrders` history exists; no reorder, no favorites, no ratings, no promos, no saved-address integration on Repas checkout. |

Gate 14 (three-actor/two-device + merchant): **FIELD-YELLOW — not attempted, no supply.**

## 3. Findings

**P0**
- REP-G1 — Checkout is client-authoritative. Client inserts the order, sums the subtotal and picks the courier earning. A tampered client can set any price. Evidence: `src/lib/repas/orders.ts:34-62,179-192`; RLS `Users create own orders` only checks `auth.uid() = user_id`.
- REP-G2 — No idempotency. No `client_request_id` on `food_orders`; a retry/double-tap creates a second order and a second wallet hold. Evidence: table columns; `orders.ts`.
- REP-G3 — Repas checkout never enters the locked cash / Chop Pay engines. `cash_order_runtime` = 0 rows, `chop_pay_order_runtime` = 0 rows; the engines are only entered at driver accept. Therefore §3/§4 economics (driver funding, 50% collateral, merchant payable, 1% platform fee) are **not proven for a Repas order at order time**.
- REP-G4 — No delivery fee is modelled anywhere in `food_orders`; the customer is never quoted a delivery price and the courier earning is a client constant. Cancellation basis `merchandise_plus_delivery` therefore cannot be computed truthfully.
- REP-G5 — Flag posture inconsistency: `repas = true` while `chop_pay_checkout_enabled`, `chop_pay_enabled`, `cash_order_funding_enabled`, `non_ride_transaction_fee_enabled` are all `false`. The live wallet checkout path is reachable without the staged finance gates.
- REP-G6 — Zero automated Repas evidence: no `_qa_node3_repas*` function exists; no Repas test file in `src/test` or `tests/e2e`.
- REP-G7 — Supply/content is effectively zero: 1 restaurant, **0 menu items**, 0 orders, 0 food missions. Repas is switched on with nothing to sell in Conakry.

**P1**
- REP-G8 — Post-preparation cancellation block is only partially enforced. RLS `Users cancel own pending orders` limits customer UPDATE to `placed`/`confirmed`, which satisfies the frozen boundary for the RLS path, but there is no explicit customer cancel RPC for wallet orders and no hold-release on cancel. CODE-VERIFIED partial, not REGRESSION-PROVEN.
- REP-G9 — Merchant non-cash state advance is a raw table UPDATE, so prep/ready transitions are not server-validated (only `completed` is trigger-protected).
- REP-G10 — No merchant rejection / item-unavailable / no-response timeout path for Repas; no automatic customer refund on merchant rejection.
- REP-G11 — No no-driver / dispatch-failure recovery UX; `orders.ts` silently swallows dispatch errors and returns `deliveryPending` with no operator or customer follow-up.
- REP-G12 — Menu photos are stored in the `marche-listings` bucket (`merchantOps.ts:22`), a cross-service coupling that will confuse ops/retention.

**P2/P3**
- REP-G13 — No reorder/favorites/ratings/promos; weak repeat loop (P2).
- REP-G14 — No ETA/prep-time surfacing at checkout beyond `prep_time_min` (P2).
- REP-G15 — No Repas email/push notification templates for order state changes (P2).
- REP-G16 — No Repas-specific admin earnings/settlement dashboard beyond `RepasPayments` preview (P3).

## 4. Live counts (read-only)

restaurants total 1 / active 1 / open 1 / delivery_available 0; menu items 0 (available 0); food_orders 0; food_order_items 0; missions type=food_delivery 0; approved drivers 4 (all delivery-capable vehicle types); merchant_stores 6; `cash_order_runtime` 0; `chop_pay_order_runtime` 0. Flags: `repas=true`, `chop_pay_*=false`, `cash_order_funding_enabled=false`, `non_ride_transaction_fee_enabled=false`. No stale/pending historical Repas orders (table empty) — zero migration risk, and zero live evidence.

## 5. Automated evidence inventory

Existing: `_qa_node0_course`, `_qa_node1_bonbonna*`, `_qa_node2_taxi_full`, `_qa_s13_*`; vitest `slice7-ui-truth`, `slice8-cancellation-truth`, `node2-taxi-labels`, `bookingRequestId`, `auth`. **Missing for Repas:** every rail — order create, merchant accept/reject, prep boundary, driver funding/collateral, completion settlement, cancellation, replay, negative security, read-model truth, rollback cleanliness.

## 6. Required Node 3 certification matrix

1. Positive cash order end-to-end (funding from unrestricted funds, merchant payable, 1% fee, driver delivery fee).
2. Positive Chop Pay order end-to-end (full-order hold, 50% merchandise collateral, merchant principal, fee, release).
3. Merchant rejection -> full customer release/refund, no orphan collateral.
4. Pre-preparation customer cancellation -> policy fee + release.
5. Post-preparation cancellation blocked (frozen boundary) at server, not UI.
6. No-driver / dispatch failure -> honest terminal state + hold release.
7. Driver funding gate and collateral semantics, including insufficient/restricted funds.
8. Replay / idempotency: duplicate checkout creates exactly one order and one hold.
9. Negative eligibility/security: offline/suspended/frozen driver, foreign merchant, anon RPC execution.
10. Receipt / activity / wallet read-model truth from persisted server values only.
11. Rollback cleanliness: zero fixture residue, zero flag drift, master wallet unchanged.
12. Gate 14 three-actor two-device + merchant field run (FIELD-YELLOW until performed).

## 7. Provisional verdict

**NOT SUFFICIENTLY BUILT.** Repas has real groundwork (schema, engines, merchant dashboard, messaging, dispute queues) but the actual customer transaction is client-authoritative, non-idempotent, fee-less and disconnected from the locked Chop Pay/cash engines, with zero menu content, zero orders and zero automated evidence. It cannot be certified as a service node and should not be treated as launch-capable in Conakry.

## 8. Remediation sequence (not implemented)

P0, in order:
1. `repas_order_create` SECURITY DEFINER RPC: server-recomputed subtotal from `food_menu_items`, server delivery fee, policy snapshot, `client_request_id` idempotency; revoke direct client INSERT on `food_orders`/`food_order_items`.
2. Wire that RPC into the locked engines: cash -> `cash_order_*`; Chop Pay -> `chop_pay_*` hold at checkout with 50% collateral at driver accept; 1% fee on merchandise subtotal.
3. Add `delivery_fee_gnf` + fee/policy snapshot columns to `food_orders` and surface them in checkout, receipt and admin.
4. Server-side merchant transitions (accept/reject/prepare/ready) with post-prep cancel block proven at server level; automatic release/refund on rejection.
5. Align flag posture: gate Repas checkout behind the staged finance flags, or keep `repas` on as discovery-only until they are activated.
6. Build `_qa_node3_repas_full()` covering matrix rows 1-11, rollback-clean.
7. Seed real Conakry restaurant/menu content operationally (no fabricated fixtures).

P1: no-driver/merchant-timeout recovery, item-unavailable path, merchant alerting, dedicated Repas storage prefix/bucket.
P2: reorder/favorites/ratings, checkout ETA truth, order-state notifications, admin Repas earnings view.

## 9. HEAD and change confirmation

HEAD: `57db98d0766a6a22534cc4386c27d0d867016161`. Zero changes made — audit is read-only; the only file written is this plan document.
