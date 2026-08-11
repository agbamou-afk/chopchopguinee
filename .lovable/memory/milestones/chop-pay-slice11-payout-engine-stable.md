---
name: Chop Pay Slice 11 — Merchant settlement + future payout engine
description: Locked 2026-08-11 (hardening closeout) — reservation/evidence/reconciliation payout spine; _payout_settle_internal is the only merchant-payable debit and revalidates evidence itself; 65/65 assertions pass; Stage 5/6/7 remain OFF
type: feature
---

# chop-pay-slice11-payout-engine-stable

- Canonical boundary: eligibility -> reservation -> outbound evidence ->
  reconciliation -> settlement. Nothing debits a merchant payable except
  `_payout_settle_internal`, and only with reconciled evidence.
- `_payout_settle_internal` independently revalidates evidence via
  `_payout_evidence_mismatch_reason` before any mutation, even when called
  directly as service_role. Bad evidence raises
  `EVIDENCE_VALIDATION_FAILED:<reason>` and moves zero.
- `payout_orders.expected_provider_transfer_gnf` is the single frozen amount
  contract (recipient-borne = principal - fee; platform-borne = principal).
  Evidence must equal it exactly; the frozen fee must match too.
- Legacy `merchant_settlement_hold/complete/fail` are hard-disabled
  (`LEGACY_PATH_DISABLED:*`) with all EXECUTE grants revoked.
- Legacy `driver_payout_hold_place/confirm` and `driver_cashout_mark_paid`
  raise `STAGE_DISABLED:driver_cashout_enabled` before any mutation and are no
  longer callable by `authenticated`.
- `payout_orders` is the generalized spine for merchant and driver payouts,
  with frozen provider-fee and settlement-policy snapshots per order. A later
  policy change never alters a reserved order.
- A provider reference can settle exactly one payout, forever, across merchant
  and driver namespaces.
- No "mark as paid" action exists in the product. Merchant receipts are only
  issued from reconciled evidence plus the ledger journal.
- Scheduled settlement queue generation is idempotent per store and period,
  and never pays.
- Stage 5 (`merchant_om_settlement_enabled`), Stage 6 (`driver_cashout_enabled`)
  and Stage 7 (`chop_pay_p2p_enabled`) remain OFF; Stage 5 is blocked only by
  the absence of a real outbound provider rail.
- Evidence: `docs/qa/chop-pay-slice11-results.md` (65/65 PASS),
  master wallet baseline -100435 GNF, global ledger sum 0, zero `_qa_s11%`
  objects remaining.
