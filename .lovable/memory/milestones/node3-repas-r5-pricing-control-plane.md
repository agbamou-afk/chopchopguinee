---
name: Node 3 Repas R5 — Pricing Control Plane
description: Admin-editable Repas pricing (delivery price, max distance, pickup fee, courier pay), promotion overlay, server-frozen order economics, courier pay independence
type: feature
---

# Node 3 Repas R5 — Pricing Control Plane (green)

## What is now product law
- Repas pricing lives on the effective-dated `finance_policies` row: `delivery_flat_fee_gnf`,
  `delivery_max_distance_km`, `pickup_platform_fee_bps`, `courier_payout_gnf`.
  No hardcoded 15 000 anywhere; `repas_delivery_earning_gnf` is no longer the source of truth.
- Single pricing brain: `repas_pricing_effective(fulfillment, at)` = base policy + optional promotion.
- Quote (`repas_quote_preview`) and commitment (`repas_order_create`) both read it; client input is ignored.
- Orders freeze: policy id, base delivery, customer delivery, promo discount, promotion id,
  platform fee, courier payout, order total, distance, full snapshot. Chop Pay uses the frozen fee.
- Courier pay is independent of the customer price; the gap is settled against the master wallet
  via `_chop_pay_courier_adjust_internal` (`R_DELIVERY_SUBSIDY` / `R_DELIVERY_MARGIN`).
- Promotions (`repas_pricing_promotions`) never overwrite base price, are windowed, auto-expire,
  God-Admin only, reason mandatory, fully audited.
- Delivery zone enforced server-side when both restaurant and destination are mapped; unmapped
  restaurant = distance honestly unknown, never fabricated as 0.

## Honest limitations
- Distance is straight-line (haversine), not routed.
- CASH: refused whenever customer delivery price <> courier payout
  (`CASH_DELIVERY_PRICING_UNSUPPORTED`); cash has no primitive to settle the gap.
  Seed policy therefore aligns both at 15 000 GNF. Margins/promotions are a Chop Pay capability.
- Cash pickup still refused (`PICKUP_CASH_NOT_SUPPORTED`), unchanged from R4.5.

## Evidence
- `_qa_node3_repas_r5()` 71/71 PASS · R1–R4 147/147 · pickup 63/63
- Node 0 34/34 · Node 1 78/78 · Node 2 97/97 · vitest 28/28 · build + PWA PASS
