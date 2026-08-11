---
name: Chop Pay Slice 8 — Centralized Cancellation + Customer Debt
description: One canonical server cancellation calculator, frozen policy snapshots, cash cancellation debt, cash-exposure restriction and repayment
type: feature
---

# chop-pay-slice8-cancellation-debt — landed 2026-08-11

## Canonical rule
`public._cancellation_compute(snapshot, stage, fare, subtotal, delivery_fee,
responsible_party)` is the ONLY place a cancellation amount is derived. Preview
(`cancellation_quote`) and every execution path bind to it through the frozen
policy snapshot. Never reintroduce a percentage or basis formula in SQL or React.

## Bases (frozen at acceptance, never re-derived)
- Ride / Bonbonna → authoritative fare.
- Repas / Marché → merchandise subtotal + delivery fee (1% platform fee excluded).
- Envoyer → delivery/service fee ONLY. Declared value and collateral never enter.

Defaults: 500 bps before dispatch, 1000 bps after. Provider / platform /
merchant / driver-caused → fee 0, debt 0.

## Locks
Repas/Marché `preparing` and later, Chop Pay `merchant_accepted` (merchandise
funded), Envoyer post-custody and open claim → normal cancellation denied;
route to dispute/claims. Locks are atomic with zero finance mutation.

## Debt and restriction
Cash cancellations create exactly one `customer_cancellation_debt` per source
(idempotent). Outstanding debt restricts **new cash exposure only** via
`_block_new_cash_exposure`; auth, history, receipts, support and Chop Pay stay
open. Repayment (`customer_cancellation_debt_repay`) draws unrestricted funds
only, is idempotent on the pre-state, cannot over-collect, and clears the
restriction on the next authoritative check. Waiver is God/Finance-Admin only,
reason-required, and is NOT payment.

## Closed
DEF-FIN-S8-002 — Envoyer preview/execution used a hard-coded 10% of the whole
quoted amount, ignoring the pre-dispatch rate and the delivery-fee basis.

## Evidence
`docs/qa/chop-pay-slice8-results.md` — 66/66 PASS, self-rolling-back harness,
master wallet baseline −100 435 GNF untouched, all activation flags unchanged.
Guards: `src/test/slice8-cancellation-truth.test.ts`.