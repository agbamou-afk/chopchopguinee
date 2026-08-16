---
name: Node 4 — Marché R3 Order Commitment, Price & Stock Truth — CERTIFIED STABLE
description: Canonical Marché order object, server-authoritative pricing, immutable line snapshots, atomic stock reservation, idempotent commitment
type: feature
---

# node4-marche-r3-order-commitment-basket-price-stock-truth — CERTIFIED STABLE

Locked on top of certified Node4 R1 / R1.5 / R2, Nodes 0–3 and Slice13. No deploy, no flag activation.

## Laws (frozen)
1. Money is server truth. Any client-sent price/subtotal/total is refused with `CLIENT_PRICE_NOT_ALLOWED`.
2. `marche_orders` + `marche_order_items` are the only order objects. `marketplace_offers` stays an agreement object, never a basket.
3. Line items freeze title, unit price, qty and line total at commitment and are immutable (`ORDER_LINE_IMMUTABLE`).
4. Unit price truth: `fixed` reads the listing; `negotiable` requires an accepted, unexpired, buyer-owned R2 agreement (`OFFER_REQUIRED` / `OFFER_NOT_AGREED`).
5. Stock is reserved atomically under deterministic row locks via `quantity_reserved`; oversell is impossible (`INSUFFICIENT_STOCK`).
6. One order = one approved merchant store (`SINGLE_STORE_ONLY`); R1.5 supply doctrine is re-enforced at commit.
7. Idempotency by `client_request_id`: same key + same payload replays the same order; different payload → `IDEMPOTENCY_CONFLICT`.
8. R3 carries no finance: `merchant_fee_gnf`, `delivery_charge_gnf`, `fee_policy_id` stay NULL until a later certified pass.

## Surface
- DB: `marche_order_commit`, `marche_order_cancel`, `marche_order_release_expired`, `marche_order_get`, `marche_orders_for_buyer`, `marche_orders_for_merchant`, `marche_orders_admin`; guards `marche_order_guard`, `marche_order_item_guard`; tables denied to all roles but `service_role`.
- Client: `src/lib/marche/orders.ts` (typed RPC wrappers + refusal translation), `src/lib/marche/orderRequestId.ts` (durable commitment key), `src/components/marche/MarcheOrderReview.tsx`, `Commander` path in `ListingDetail.tsx`, `Commandes` tab in `MerchantCommandesView.tsx`.

## Certification
- `_qa_node4_marche_r3()` 136/136 PASS.
- Full frozen board, 2639 assertions, 0 failures: Course 34, Bonbonna 78, Taxi 97, Repas R1–R4 148, Pickup 64, R5 static 71 + runtime 91, R6 171, R7 canonical 203, R8 canonical truth 202 (incl. P15.5) + companions 89/60/53/142, R9 68, R10 134, R11 116, Slice13 runs 1–7 = 507 (18/32/54/98/115/87/103), Marché R1 55, R1.5 38, R2 82, R3 136.
- R7 fixture-dependent companions (`_qa_node3_repas_r7_semantics|readtruth|ext`) remain non-standalone (`RESTAURANT_NOT_PUBLISHED`) — pre-existing, unrelated to R3.
- Posture: order tables RLS-on with service_role-only grants, all R3 mutations SECURITY DEFINER with `search_path=public`, `anon` excluded from every order RPC and from `has_role`, listing truth 53 rows / 5 orderable / 48 storeless quarantined, reservations 0 and non-negative, zero finance/payment/ledger/mission/courier/settlement drift, zero fixtures.
- Client gates: tsgo clean, Vitest 90/90 (incl. 19 new R3 tests), production build OK.
