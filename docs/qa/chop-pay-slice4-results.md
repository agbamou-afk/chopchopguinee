# Chop Pay — Slice 4 QA results (Repas / Marché cash-order engine)

Authority: `docs/product/chop-pay-canonical-operating-policy.md`.
Run date: 2026-08-10. Harness: `_qa_s4_run()` — self-rolling-back, executed, then dropped.

## Exit gate — 150 000 + 25 000 + 1 500 GNF

| # | Assertion | Result |
| --- | --- | --- |
| T1.1 | Cash order accepted, Snapshot v2 frozen (150 000 / 25 000 / 1 500) | PASS |
| T1.2 | Merchandise principal 150 000 held, unrestricted only (promo 0) | PASS |
| T1.3 | Platform fee 1 500 reserved | PASS |
| T1.4 | Accept replay inert (`already_accepted`, 2 holds) | PASS |
| T1.5 | Preparation before funding denied | PASS |
| T1.6 | Wrong merchant denied | PASS |
| T1.7 | Merchant wallet funded exactly 150 000 | PASS |
| T1.8 | Merchant funding replay inert (still 150 000) | PASS |
| T1.9 | Driver debited principal only (balance 350 000, held 1 500) | PASS |
| T1.10 | Preparation lock engages after funding | PASS |
| T1.11 | Customer cancellation denied after prep, 0 debts | PASS |
| T1.12 | Completion before custody denied | PASS |
| T1.13 | Customer cannot complete | PASS |
| T1.14 | Wrong driver cannot complete | PASS |
| T1.15 | Cash due 176 500, no fake wallet credit (credit = 0) | PASS |
| T1.16 | Platform fee 1 500 captured exactly once | PASS |
| T1.17 | Driver delivery earning = 25 000 (physical cash) | PASS |
| T1.18 | Completion replay inert, master delta still 1 500 | PASS |
| T1.19 | Net drift zero: driver out 151 500 = merchant 150 000 + platform 1 500 | PASS |

## Restricted-bonus exclusion

| # | Assertion | Result |
| --- | --- | --- |
| T2.1 | Promo cannot fund merchandise principal (`CASH_FUNDING_REQUIRES_UNRESTRICTED`, no residue) | PASS |
| T2.2 | Promo may fund the 1% fee (fee 200 = promo 200) | PASS |
| T2.3 | Principal remains unrestricted-only under mixed buckets | PASS |

## Acceptance / stale offer · merchant accept/reject/prep

| # | Assertion | Result |
| --- | --- | --- |
| T3.1 | Stale/expired offer denied | PASS |
| T3.2 | Cross-driver acceptance denied, no runtime row | PASS |
| T4.1 | Pre-prep rejection restores buckets exactly (160 000 / held 0 / promo 25 000 / payable funded 0 / debts 0) | PASS |
| T4.2 | No platform-fee revenue on a rejected order | PASS |
| T4.3 | Rejection replay inert | PASS |

## Cancellation · dispute

| # | Assertion | Result |
| --- | --- | --- |
| T6.1 | After-dispatch debt = 10% of (150 000 + 25 000) = 17 500, basis 175 000, 1000 bps | PASS |
| T6.2 | Driver holds released on cancellation | PASS |
| T6.3 | Cancellation replay creates no second debt | PASS |
| T7.1 | Dispute freezes economic state | PASS |
| T7.2 | No completion while disputed | PASS |
| T7.3 | Ordinary driver cannot resolve a dispute | PASS |
| T7.4 | Authorized resolution idempotent (`resolved` → `already_resolved`) | PASS |
| T7.5 | Audit trail written | PASS |

## Tender selection · privilege · ledger

| # | Assertion | Result |
| --- | --- | --- |
| TA.1 | Non-cash tender rejected, never coerced | PASS |
| TA.2 | `cash_order_funding_enabled` OFF blocks funding | PASS |
| T8.1 | Internal funding/payable/fee/debt helpers not executable by anon/authenticated | PASS |
| T8.2 | anon cannot reach cash-order runtime RPCs | PASS |
| T9.1 | All journals balanced (unbalanced = 0) | PASS |
| T9.2 | No journal with < 2 nonzero postings | PASS |
| T9.3 | Capture attribution ≤ reserved source (violations = 0) | PASS |
| T9.4 | Slice 3 guards intact — `ride_accept` f, `ride_dispatch` f, `wallet_internal_transfer` f, `om_auto_match` f, `wallet_topup_om_credit` f | PASS |
| T10.1 | Master wallet restored to −100 435 (DEF-FIN-001) | PASS |
| T10.2 | Zero `cash_order_runtime` residue | PASS |
| T10.3 | Canonical finance flags remain OFF | PASS |

**Total: 46 / 46 PASS.**

## Defects found and fixed during the run

- **DEF-S4-001** — `driver_funding_allocate` raised `Not authorized` for its own internal caller (a driver accepting their own mission), making cash-order acceptance impossible. The `auth.uid()` gate was a false proxy for service_role; removed and replaced with explicit `REVOKE`/`GRANT service_role`. Allocation rules unchanged.
- **DEF-S4-002** — `cash_order_merchant_reject` / `cash_order_customer_cancel` wrote `merchant_payables.state = 'cancelled'`, which violates the state CHECK. Canonical terminal state for an unfunded voided payable is `reversed`.
- **DEF-S4-003** — `admin_cash_order_dispute_resolve` wrote audit rows using non-existent columns (`entity_type`, `entity_id`, `metadata`). Corrected to `module`, `target_type`, `target_id`, `after`, `note`.

## Cleanup proof (read-only, post-rollback)

`_qa_s4%` functions **0** · `_qa_s4%` tables **0** · `cash_order_runtime` rows **0** ·
Slice 4 QA audit rows **0** · enabled finance flags: **`om_topup_enabled` only**
(`driver_mode` is a UI flag, not a finance flag) · master wallet
`b6858980-43d2-425d-b12d-b02aac3de52d` = **−100 435 GNF**, unmutated.

## YELLOW register (carried forward, not closed)

- Slice 2 God Admin finance policy / control plane visual QA — **YELLOW** (preview signed out).
- Slice 3 Ride / Bonbonna + OM reconciliation visual QA — **YELLOW** (preview signed out).
- DEF-FIN-001 master wallet `b6858980-43d2-425d-b12d-b02aac3de52d`, master/owner NULL, −100 435 GNF — **YELLOW**, finance reconciliation follow-up; never mutated as QA cleanup.
- **NEW** Slice 4 Repas/Marché cash-order UI visual QA — **YELLOW** (preview signed out; no authenticated visual pass claimed). Owner: Platform/QA agent, next authenticated session.