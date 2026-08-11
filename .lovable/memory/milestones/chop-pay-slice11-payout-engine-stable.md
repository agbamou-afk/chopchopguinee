---
name: Chop Pay Slice 11 — Merchant settlement + future payout engine
description: Locked 2026-08-11 — reservation/evidence/reconciliation payout spine; a payable is debited only on exact reconciled outbound proof; 33/33 assertions pass; Stage 5 and 6 remain OFF
type: feature
---

# chop-pay-slice11-payout-engine-stable

- Canonical boundary: eligibility -> reservation -> outbound evidence ->
  reconciliation -> settlement. Nothing debits a merchant payable except
  `_payout_settle_internal`, and only with reconciled evidence.
- `payout_orders` is the generalized spine for merchant and driver payouts,
  with frozen provider-fee and settlement-policy snapshots per order.
- Evidence must agree on provider, reference, recipient MSISDN, amount,
  provider status and environment. Anything else parks in review and moves
  zero. A provider reference can settle exactly one payout, forever.
- No "mark as paid" action exists in the product. Merchant receipts are only
  issued from reconciled evidence plus the ledger journal.
- Scheduled settlement queue generation is idempotent per store and period,
  and never pays.
- Stage 5 (`merchant_om_settlement_enabled`) and Stage 6
  (`driver_cashout_enabled`) remain OFF; Stage 5 is blocked only by the
  absence of a real outbound provider rail.
- Evidence: `docs/qa/chop-pay-slice11-results.md` (33/33 PASS),
  master wallet baseline -100435 GNF.
