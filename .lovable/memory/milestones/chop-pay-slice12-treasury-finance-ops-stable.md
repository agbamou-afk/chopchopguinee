---
name: Chop Pay Slice 12 — Treasury & Finance Ops Stable
description: Lock 2026-08-11 — role-gated treasury read models, named/quantified finance exception queue, /admin/treasury console, raw finance tables locked to SELECT-only for authenticated
type: feature
---
# chop-pay-slice12-treasury-finance-ops-stable

Every treasury KPI traces to authoritative server/ledger/provider facts. Unexplained differences become
named, quantified exceptions (`TREASURY_SHORTFALL/SURPLUS`, `WALLET_LEDGER_MISMATCH`, `MASTER_WALLET_DEFICIT`,
`MERCHANT_PAYABLE_MISMATCH`, `CLAIM_RESERVE_MISMATCH`, `PROVIDER_CLEARING_MISMATCH`,
`INBOUND_OM_UNRECONCILED`, `INBOUND_OM_UNMATCHED_EVENT`, `OUTBOUND_PAYOUT_UNRECONCILED`,
`LEDGER_GLOBAL_IMBALANCE`, `LEDGER_JOURNAL_IMBALANCE`) with drilldown to source records.
No inferred adjustment or balancing plug class exists.

- RPCs: `finance_treasury_overview`, `finance_treasury_exceptions`, `finance_treasury_drilldown`
  (god_admin / finance_admin only); `_finance_treasury_facts` is service_role only.
- Raw finance tables: `anon` revoked, `authenticated` SELECT-only, writes via approved RPCs.
- Stage 5/6/7 activation flags remain OFF. Master wallet DEF-FIN-001 (-100 435 GNF) frozen, reported not normalized.
- QA: 46/46 PASS (`docs/qa/chop-pay-slice12-results.md`). tsgo clean, Vitest 20/20, vite build OK.
