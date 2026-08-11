---
name: Chop Pay Slice 10 — Full Financial Regression + Staged Activation
description: Locked 2026-08-11 — every financial rail independently gated on the server; 21/21 regression assertions pass; all stages HOLD except OM inbound top-up
type: feature
---

# chop-pay-slice10-full-regression-staged-activation-stable

- Seven-stage activation model: each rail has its own canonical flag and its
  own server enforcement point. `chop_pay_enabled` is surface visibility only
  and never implies a stage.
- Fixed P1 gaps: `wallet_p2p_transfer`, `driver_cashout_create_request`,
  `driver_cashout_mark_paid` and `merchant_settlement_complete` previously ran
  with no server flag gate. All now raise `STAGE_DISABLED:<flag>`.
- `anon` has no EXECUTE on payout / P2P / OM-credit primitives.
- Regression: 21/21 PASS (gates, non-implication, privileges, ledger zero-sum,
  OM strict evidence, flag state, master wallet baseline -100435 GNF).
- Stage status: 1–7 all HOLD (no flags flipped). `om_topup_enabled` stays ON.
  Stage 5 held for lack of an outbound provider; Stage 6 held pending recorded
  operational approval; Stage 7 held pending separate review.
- Evidence: `docs/qa/chop-pay-slice10-results.md`.
