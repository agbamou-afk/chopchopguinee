# Slice 9 — Orange Money Inbound Reconciliation — QA Results (FINAL)

Harnesses: `_qa_s9_run()` + `_qa_s9f_run()` (exactness closeout) + `_qa_s9b_run()`
(driver / receiving-account re-test with complete evidence). All SECURITY DEFINER,
all self-rolling-back, all dropped after this record was written.

Result: **105 / 105 PASS, 0 FAIL.**

Every fixture (top-up requests, provider events, ledger journals, wallet
balances, master wallet) is rolled back inside the harness; closing assertions
verify zero residue.

## Frozen contract enforced

An automatic production credit requires **all** of:
exact normalized provider reference, exact amount, canonical payer phone present
and equal on **both** the provider event and the top-up request, and
`receiving_account_id` present and equal on **both** sides, plus matching
`environment` and a non-expired request. Anything missing or differing parks the
request in `needs_review` with a machine reason — never a silent credit, and
never a value silently borrowed from the customer side to patch missing provider
evidence.

Machine reasons: `payer_phone_missing`, `payer_phone_mismatch`,
`receiving_account_missing`, `receiving_account_mismatch`, `amount_mismatch`,
`environment_mismatch`, `topup_expired`, `missing_provider_reference`,
`multiple_candidates`, `awaiting_customer_code`.

## A. Customer inbound queue (16) — A1–A16 PASS
Pending moves nothing; exact production event credits once; customer wallet
+250 000; driver wallet untouched; request `credited`; honest customer stage;
`matched_event_id` linked; replay inert; exactly one transaction; direct
re-credit returns the same transaction; journal posted, zero-sum, customer
liability increased, never platform revenue.

## B. Driver inbound queue (6+3) — PASS
Driver request with complete exact evidence credits; driver wallet +300 000;
driver's client wallet untouched; routed to `L_DRIVER_UNRESTRICTED`; never
surfaces in the customer queue; driver eligibility reflects real balance.
Master unchanged, zero QA rows/events remaining.

## C. Mismatch handling — no silent credit (PASS)
Amount mismatch, payer-phone mismatch, receiving-account mismatch (C7/C7b/C8),
multiple candidates, expired request, unmatched receipt parked as
`awaiting_customer_code`, unsuccessful provider status rejected. In every case
zero value moves and forced admin credit is refused.

## D. Global reference uniqueness (4) — PASS
Duplicate provider reference rejected at index level; a credited event cannot
serve a second customer; second wallet +0; consumed event returns the original
credit only.

## E. Sandbox / production isolation (6) — PASS
No cross-environment match; forced credit in either direction denied with
`environment_mismatch`; reference uniqueness is global.

## H. Exact-match completeness closeout (29) — PASS
| ID | Assertion |
| --- | --- |
| H1–H2 | Complete evidence (ref+amount+phone+account) credits exactly once |
| H3/H3b/H3c | Missing **event** payer phone → `payer_phone_missing`, zero credit, forced credit refused |
| H4/H4b | Missing **request** payer phone → `payer_phone_missing`, forced credit refused |
| H5/H5b | Payer phone mismatch → `payer_phone_mismatch`, forced credit refused |
| H6/H6b | Missing **event** receiving account → `receiving_account_missing`, forced credit refused |
| H7/H7b | Missing **request** receiving account → `receiving_account_missing`, forced credit refused |
| H8/H8b | Receiving account mismatch → `receiving_account_mismatch`, forced credit refused |
| H9–H10 | Only the complete-evidence case moved value; exactly one top-up transaction |
| H11–H13 | Matcher and credit primitive both carry the presence guards |
| H14 | `admin_record_om_receipt` records evidence but routes credit through `om_auto_match` — it can record incomplete evidence, it can never auto-credit it |
| H15–H18 | Privilege matrix (below) |
| H19–H22 | Master unchanged, zero residue |

## Privilege matrix (truthful)
| Surface | anon | authenticated | Notes |
| --- | --- | --- | --- |
| Raw primitives: `om_auto_match`, `wallet_topup_om_credit` | denied | denied | service_role / SECURITY DEFINER callers only |
| Participant wrappers: `submit_customer_om_code`, `list_my_topup_requests`, `driver_topup_history`, `wallet_topup_om_create` | denied | EXECUTE granted | bodies are self-scoped to `auth.uid()` |
| Admin wrappers: `admin_record_om_receipt`, `admin_retry_om_credit`, `om_pending_topups_for_event` | denied | EXECUTE granted | bodies enforce `can_manage_wallet` / finance-ops role |
| `topup_requests` RLS | no anon policy | self-scoped | — |

## Posture after the run
- Master wallet: **-100 435 GNF**, held **0** — untouched, never manually reset.
- Feature flags unchanged: only `om_topup_enabled` ON; all other Chop Pay / OM
  checkout / cashout / settlement rails OFF.
- No outbound money, payout or settlement executed.
- `_qa_s9%` objects: **0** — harnesses and `_qa_s9_results` dropped after this
  record was written.

## Defects fixed in this closeout
1. P1 — `om_auto_match` only rejected payer phone / receiving account when both
   sides carried a value, so an event with either field NULL could auto-credit on
   reference + amount alone. Presence is now mandatory on both sides.
2. `wallet_topup_om_credit` now independently re-validates reference, amount,
   phone presence/equality, receiving-account presence/equality, environment,
   target party and expiry, so no admin wrapper can bypass the contract.
3. QA privilege section previously claimed authenticated could not execute
   legitimate participant/admin wrappers. Rewritten above to the real, correct
   three-tier shape; no legitimate access was revoked to make the old text true.

## YELLOW register
- **Live provider receipt test — YELLOW.** No real observed Orange Money provider
  receipt/reference from an actual transaction was used. Production-format
  exact-reference matching and idempotency PASS against synthetic
  production-shaped references only. "One real provider reference" is **not**
  literally proven.
- PWA/service-worker build warning remains reported honestly in the release docs.
