> Historical QA record. Current policy authority: `docs/product/chop-pay-canonical-operating-policy.md`.

# Chop Pay Slice 0/1 — QA evidence (2026-08-05)

Executed through a temporary self-rolling-back SECURITY DEFINER harness
(`_qa_slice1_run` / `_qa_slice1_selftest`, invoked once via a throwaway
service-role edge function). Every write was rolled back with the enclosing
subtransaction; the harness and the edge function were **dropped afterwards**.
Test driver: an existing approved driver with a 0 GNF wallet.

| # | Case | Expected | Observed | Result |
| --- | --- | --- | --- | --- |
| 1 | Approved driver grant | one 25 000 GNF restricted credit | `granted`, 25 000 | PASS |
| 2 | Grant replay | no second grant | `already_granted`, 25 000 | PASS |
| 3 | Non-approved driver | refusal, 0 GNF | `not_eligible / driver_not_approved` | PASS |
| 4 | Balance surface | bonus visible, withdrawable 0 | balance 25 000, `promo_available` 25 000, `withdrawable_gnf` 0, `unrestricted_available` 0 | PASS |
| 5 | Cash-out of 5 000 | refused | `insufficient_available_balance` | PASS |
| 6 | Cash-order funding from bonus | rejected | `CASH_FUNDING_REQUIRES_UNRESTRICTED` | PASS |
| 7 | Commission allocation | promo-first | promo 20 000 / unrestricted 0 | PASS |
| 8 | Ride hold (fare 100 000) | 10 000 commission, promo-funded | hold 10 000, `promo_gnf` 10 000, `unrestricted_gnf` 0 | PASS |
| 9 | Release | bonus bucket restored | wallet held 0, `promo_available` back to 25 000 | PASS |
| 10 | Capture | bonus permanently consumed | captured 10 000, `promo_consumed` 10 000, balance 15 000 | PASS |
| 11 | Release replay | idempotent | `released_gnf` 0 | PASS |
| 12 | Capture replay | idempotent | `already_resolved` | PASS |
| 17 | Repas requirement (subtotal 150 000) | 50% collateral, 1% fee, 100% cash funding | collateral 75 000, fee 1 500, `cash_funding_gnf` 150 000 | PASS |
| 18 | Ride requirement (fare 50 000) | 10% commission, no collateral, no fee | commission 5 000, collateral 0, fee 0 | PASS |
| 19 | Envoyer declared 900 000 | flagged over cap, collateral capped | `declared_value_exceeds_cap: true`, collateral 375 000 | PASS |
| 20 | Envoyer declared 500 000 | 375 000 collateral | 375 000 | PASS |

Note on case 9: an initial reading appeared stale because the release and the
following summary were arguments to the same `jsonb_build_object` call. Re-run
as separate statements, the release correctly zeroes `wallets.held_gnf` and
restores the promotional bucket.

## Defect found and fixed during QA
A superseded 6-argument overload of `driver_mission_hold_place` still existed
alongside the new 7-argument version, making 4-argument calls ambiguous. The
old overload was dropped.

## Not covered (no runtime wiring yet)
Live mission acceptance/completion, cash-order funding placement, starting-credit
grant on approval, admin treasury/reversal UI. Tracked as DEF-019/020/021.