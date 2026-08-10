---
name: Chop Pay Slice 5 — Repas / Marché engine
description: Slice 5 Chop Pay order engine for Repas and Marché — frozen collateral, merchant capture on accept, disputes, 152/152 QA green
type: feature
---

# Chop Pay Slice 5 — Repas / Marché Chop Pay engine (stable)

Locked after a full-green regression: **152 / 152 assertions PASS** across the
four internal harness parts, all rolled back.

## Canonical behaviour
- Customer authorization holds the **full order total** once and freezes the
  Snapshot v2 economics on `chop_pay_order_runtime`.
- Driver collateral is **50% of merchandise only**, frozen at authorization and
  never re-derived from the live policy (DEF-FIN-S5-001, closed).
- Merchant is captured **on accept**; driver earning and platform fee settle on
  delivery. No cash leg.
- Cancellation charges and dispute outcomes use the frozen basis.
- Dispute outcomes: `complete_as_delivered`, `refund_customer`, `close_no_value`.

## Invariants
- Every ledger journal balances to zero with ≥2 non-zero postings.
- `captured + released` never exceeds the reserved amount.
- All `_chop_pay_*` helpers and `_driver_exact_hold_place_internal` are
  service_role only; Slice 1–4 money primitives stay closed to app roles.

## Surfaces
`src/lib/chopPay/chopPayOrders.ts`, `src/components/chopPay/ChopPayOrderPanel.tsx`,
wired into Repas merchant orders, Marché merchant offers, customer deliveries,
driver active mission, and `ChopPayDisputeQueue` in admin Repas payments.

## Flags
Only `om_topup_enabled` is ON. `chop_pay_checkout_enabled` stays OFF, so the new
surfaces are inert in production until launch.

## Carried YELLOW
Master wallet at -100 435 GNF — treasury reconciliation still owed.

QA detail: `docs/qa/chop-pay-slice5-results.md`.
