# Slice 12 — Treasury, Claims & Finance Operations — results

Harness: `_qa_s12_results` (transient, dropped after the run). **46 assertions, 46 PASS**
(E8 initially FAILED and was re-verified PASS after the grant fix below).

## Server read models (all role-gated, SECURITY DEFINER, fixed search_path)
- `_finance_treasury_gate()` — god_admin / finance_admin only.
- `_finance_treasury_facts()` — raw authoritative aggregation, **service_role only**.
- `finance_treasury_overview()` — assets, obligations, restricted funds, claims, receivables, captured revenue, coverage.
- `finance_treasury_exceptions()` — named, quantified exceptions.
- `finance_treasury_drilldown(code, limit)` — exception → source records.

## Assertion groups
- **A (classification, 8)** — credited top-up = asset not revenue; merchant payable = obligation;
  promo credit tracked separately and excluded from cash-backed obligations; cancellation debt = receivable
  only; payout reservation is not a debit; captured revenue equals the sum of `R_*` ledger accounts.
- **B (exception honesty, 9)** — coverage delta is emitted as a named exception equal to the exact signed
  difference and is never forced to zero; wallet↔ledger, provider-clearing and payable mismatches all surface;
  DEF-FIN-001 master deficit (-100 435 GNF) is reported as its own exception, not normalized;
  no ADJUST/PLUG exception class exists.
- **C (reconciliation, 5)** — `needs_review` inbound produces zero credit and zero asset recognition;
  mismatched outbound evidence produces zero payable debit and zero outbound cash; reconciled evidence
  leaves the queue; one-reference-one-settlement uniqueness index intact.
- **D (claims, 5)** — open claim raises declared exposure and recognized reserve with no paid liability;
  reserve↔ledger difference is a named exception with drilldown; paid claim leaves exposure.
- **E (security, 9)** — anon denied on all three RPCs; raw fact primitive service_role only;
  no `auth.uid() IS NULL` shortcut; gate called in every public RPC; fixed search_path on all five functions.
- **F (state integrity, 8)** — Stage 5/6/7 flags remain OFF, `om_topup_enabled` ON, every journal sums to zero,
  master wallet unchanged, zero outbound money, snapshot returns byte-identical to baseline, no fixture residue.

## Defects found and fixed this slice
- **P1 — raw finance tables were world-granted.** `wallets`, `wallet_transactions`, `ledger_postings`,
  `ledger_journals`, `ledger_accounts`, `merchant_payables`, `claims_reserves`, `mission_financial_holds`,
  `driver_promo_credits`, `customer_cancellation_debts`, `finance_policies` all still carried default
  `arwdDxtm` grants for `anon` and `authenticated`; RLS was the only barrier. Now: `anon` revoked entirely,
  `authenticated` reduced to `SELECT` (existing read policies unchanged), writes are service_role/RPC only.
- **P2 — wrong terminal-state filters.** The fact engine treated `settled`/`cancelled` as closed for claims and
  debts, but the actual check constraints use `paid/denied/released/reversed` and `paid/waived/reversed/exempt`.
  Closed items were counted as open obligations. Corrected in `_finance_treasury_facts` and the drilldown.
- **P3 — `SUM(bigint)` returns `numeric`**, breaking `LEDGER_JOURNAL_IMBALANCE`. Explicit `::bigint` cast added.

## Known, deliberately unresolved (reported, not hidden)
The ledger is empty while legacy wallet balances persist, so the console currently shows
`WALLET_LEDGER_MISMATCH` (customer/driver/merchant), `PROVIDER_CLEARING_MISMATCH`, a signed
`TREASURY_SHORTFALL/SURPLUS` and `MASTER_WALLET_DEFICIT`. These are correct output: pre-ledger history is
surfaced as named, quantified Finance exceptions rather than normalized away.

## UI
`/admin/treasury` (`TreasuryAdmin.tsx`, sidebar → Finance → Trésorerie), bound through
`src/lib/finance/treasury.ts`. Zero client-side financial arithmetic; every figure and every exception
amount is rendered verbatim from the server.
