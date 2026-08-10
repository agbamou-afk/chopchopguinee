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
---

# Part 3 — Product-integration hardening (P1-1 … P1-5)

Run date: 2026-08-10. Scope: Slice 4 only. No finance capability flag enabled
(`om_topup_enabled` remains the only ON canonical finance flag).

## Defects closed

| ID | Defect | Fix (evidence) |
| --- | --- | --- |
| P1-1 | Marché tender written in two steps (`createOffer` then `marche_offer_set_tender`): an offer could persist with no tender if the second call failed. | `create_marketplace_offer(uuid,bigint,text,text)` now takes `p_payment_method` and writes `metadata.payment_method` in the same transaction; the 3-arg signature was dropped, so no overload ambiguity remains. Client: `src/lib/marche/offers.ts`, `src/components/marche/OfferSheet.tsx` (no tender preselected, submit disabled until chosen, single RPC). |
| P1-2 | `_cash_order_block_direct_state` only fired when a `cash_order_runtime` row existed, so a cash Repas order could be advanced by a direct write before a courier engaged. | Trigger now treats `food_orders.payment_method = 'cash'` as authoritative, independent of runtime existence. |
| P1-3 | Marché merchant prep tab hid accepted cash offers when `prepInterests` was empty. | `MerchantCommandesView` renders the accepted-offer `CashOrderPanel` list independently of prep interests. |
| P1-4 | Repas customers had no cash-order surface (cancel / dispute). | `CustomerMarketplaceDeliveries` now also lists `food_delivery` missions and renders `CashOrderPanel module="repas"` for `ref_food_order_id`. |
| P1-5 | Marché missions could be claimed with unknown tender. | `mission_claim` raises `MARCHE_TENDER_REQUIRED` when `marketplace_offers.metadata->>'payment_method'` is NULL or not in (`cash`,`choppay`) — refusal happens before any funding/runtime work, so no half-assignment. |
| P1-6 | `_merchant_payable_reverse_internal` accepted an arbitrary `p_beneficiary`. | Beneficiary is validated against `cash_order_runtime.driver_user_id`; mismatch raises `BENEFICIARY_MISMATCH`. Restoration remains unrestricted-only. |

## Privilege matrix (live grants, verified read-only)

| Function | anon | authenticated | service_role |
| --- | --- | --- | --- |
| `_cash_order_accept_internal` / `_complete_internal` / `_capture_platform_fee` / `_facts` / `_economics` / `_deactivate_source` | – | – | ✅ |
| `_merchant_payable_reverse_internal` | – | – | ✅ |
| `merchant_payable_create` / `merchant_payable_fund` / `driver_mission_hold_release` / `customer_cancellation_debt_create` | – | – | ✅ |
| `cash_order_quote/accept/merchant_accept/reject/prepare/complete_cash/customer_cancel/dispute_open` | – | ✅ (self-scoped) | ✅ |
| `admin_cash_order_dispute_resolve` | – | ✅ (`_finance_privileged` gated) | ✅ |
| `create_marketplace_offer` | – | ✅ | ✅ |
| `mission_claim` | – | ✅ | ✅ |

`anon` was additionally revoked from `create_marketplace_offer`, `mission_claim`
and `_cash_order_runtime_immutable` during this pass. Slice 3 inbound-OM guards
untouched.

## Build / test evidence

- `tsgo --noEmit` — clean.
- Vitest — 12/12 pass (2 files).
- `vite build` — green, PWA precache 130 entries / 11 867.30 KiB (< 4 MiB per-file limit respected).

## YELLOW register (carried forward)

1. Slice 2 God Admin finance policy / control-plane visual QA — **YELLOW**.
2. Slice 3 Ride / Bonbonna + OM reconciliation visual QA — **YELLOW**.
3. DEF-FIN-001 master wallet −100 435 GNF — **YELLOW**, untouched.
4. Slice 4 Repas / Marché cash-order visual QA — **YELLOW** (preview signed out).
5. **NEW** Part 3 integration re-run of the 46-assertion economic harness was
   **not** re-executed after these changes; the Part 1 evidence stands for the
   engine internals, which Part 3 did not modify (offer tender, trigger scope,
   claim guard, UI wiring, beneficiary validation only). A full harness re-run is
   owed before lock. Owner: Finance/QA agent.

Slice 4 remains **UNLOCKED**. Slice 5 **NOT STARTED**.
