# Slice 9 — Orange Money Inbound Reconciliation — QA Results

Harness: `public._qa_s9_run()` (SECURITY DEFINER, self-rolling-back).
Result: **72 / 72 PASS, 0 FAIL.**

All test rows (top-up requests, provider events, ledger journals, wallet
balances, master wallet) are rolled back inside the harness; the closing
G9–G12 assertions verify the database is left byte-identical.

## A. Customer inbound queue (16)
| ID | Assertion | Result |
| --- | --- | --- |
| A1 | Pending request moves no balance | PASS |
| A2 | Exact production event credits once | PASS (credited) |
| A3 | Customer wallet +250 000 | PASS |
| A4 | Driver wallet untouched | PASS |
| A5 | Request marked `credited` | PASS |
| A6 | Customer-visible stage = `credited` | PASS |
| A7 | `matched_event_id` linked | PASS |
| A8 | Auto-match replay is inert | PASS |
| A9 | Exactly one top-up transaction per event | PASS |
| A10 | Replay moves zero value | PASS |
| A11 | Direct re-credit returns the same transaction | PASS |
| A12 | Still one transaction after direct re-credit | PASS |
| A13 | Ledger journal posted | PASS |
| A14 | Journal is zero-sum | PASS |
| A15 | Customer liability increased (`L_CUSTOMER_CHOPPAY`) | PASS |
| A16 | Top-up is never platform revenue | PASS |

## B. Driver inbound queue (6)
| B1 | Driver request credited | PASS |
| B2 | Driver wallet +300 000 | PASS |
| B3 | Driver's client wallet untouched | PASS |
| B4 | Routed to `L_DRIVER_UNRESTRICTED` | PASS |
| B5 | Driver top-up never surfaces in customer queue | PASS |
| B6 | Driver eligibility reflects real balance | PASS |

## C. Mismatch handling — no silent credit (16)
| C1–C3 | Amount mismatch → `needs_review`, zero credit, machine reason stored | PASS |
| C4–C6 | Payer-phone mismatch → `needs_review`; forced credit denied | PASS |
| C7–C8 | Receiving-account mismatch → `needs_review`; forced credit denied | PASS |
| C9–C10 | Multiple candidates → no credit, zero value moved | PASS |
| C11–C13 | Expired request never matched; forced credit denied (`topup_expired`); honest expired stage | PASS |
| C14–C15 | Unmatched receipt parks as `awaiting_customer_code`, never rejected outright | PASS |
| C16 | Unsuccessful provider status rejected | PASS |

## D. Global reference uniqueness (4)
| D1 | Duplicate provider reference rejected at index level | PASS |
| D2 | Credited event cannot serve a second customer | PASS |
| D3 | Second customer wallet +0 | PASS |
| D4 | Consumed event returns the original credit, never a second one | PASS |

## E. Sandbox / production isolation (6)
| E1–E2 | Sandbox event cannot match a production request; credits nothing | PASS |
| E3 | Forced sandbox → production credit denied (`environment_mismatch`) | PASS |
| E4 | Production event cannot consume a sandbox request | PASS |
| E5 | Forced production → sandbox credit denied (`environment_mismatch`) | PASS |
| E6 | Provider-reference uniqueness is global | PASS |

## F. Privilege posture (12)
`anon` and `authenticated` cannot execute `om_auto_match`,
`wallet_topup_om_credit`, `om_pending_topups_for_event`,
`admin_record_om_receipt`, `admin_retry_om_credit`,
`wallet_topup_om_create`, `submit_customer_om_code`,
`list_my_topup_requests`, `driver_topup_history`. `topup_requests` has no
`anon` RLS policy. All PASS.

## G. Structural invariants (12)
Unique indexes present (`wallet_transactions_om_event_uidx`,
`ppe_credited_topup_uidx`, `topup_requests_credited_provider_tx_uidx`),
all top-up journals zero-sum, no fuzzy `ILIKE` matching left in the
matcher, matcher requires a provider reference, `om_topup_enabled` ON,
all gated rails still OFF, master wallet back to baseline, no QA residue.

## Defects found and fixed during this slice
1. `om_pending_topups_for_event` exposed customer PII to any authenticated
   user — now role-gated to finance/ops staff.
2. `topup_requests` had no environment marker — sandbox and production
   receipts could cross-credit. `environment` added and enforced end to end.
3. `om_auto_match` fell back to fuzzy payload containment and phone-only
   matching — removed; exact provider reference is now mandatory.
