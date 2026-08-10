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


---

# Part 4 — Final exit-gate regression (QA-only run)

Harness: `public._qa_s4_run()` — reconstructed rollback harness executed against
the **real canonical paths** (`mission_claim`, `mission_confirm_pickup`,
`mission_confirm_dropoff`, `create_marketplace_offer`, `cash_order_*`,
`admin_cash_order_dispute_resolve`). All fixtures were created inside a
sub-transaction that is deliberately aborted at the end, so the run leaves no
row behind. The harness and its results table were dropped afterwards.

## Totals

| Metric | Value |
| --- | --- |
| Assertions executed | **81** |
| Passed | **81** |
| Failed | **0** |
| Original Part 1 economic scope re-proved | 150 000 + 25 000 + 1 500 → cash due 176 500; merchant +150 000 once; master +1 500 once; driver wallet out 151 500; zero driver earning credit; drift 0; replay inert |
| New integration assertions added | 59 (real canonical Repas + Marché lifecycle, tender, dispute economics, privilege, ledger invariants, cleanup) |

## Defect found and fixed during this QA-only run

**DEF-S4-004 (P1) — dispute `release_driver_funding` was broken at runtime.**
`_merchant_payable_reverse_internal` recorded its wallet movement with
`wallet_transactions.type = 'reversal'`, which is **not** a member of the
`txn_type` enum. Every real D2 resolution would have aborted with
`invalid input value for enum txn_type`. The Part 3 code path had never been
executed end-to-end, so the audit could not have caught it by reading alone.
Fixed by recording the movement as `adjustment` with
`metadata.movement = 'merchant_payable_reversal'`; ledger postings, idempotency,
beneficiary validation and privileges are unchanged. Re-proved by F2/F4/F5.

## Assertion log

- PASS | F0 fixtures + flag ON for QA
- PASS | A1 real mission_claim creates runtime atomically
- PASS | A2 economics 150000/25000/1500 -> cash due 176500 — sub=150000 del=25000 fee=1500 due=176500
- PASS | A3 cash_funding + platform_fee holds placed
- PASS | A4 restricted promo NEVER funds merchandise principal — promo_in_cash_funding=0
- PASS | A5 restricted promo MAY fund the 1% platform fee — promo_in_fee=1500
- PASS | A6 driver held_gnf = 151500 after acceptance — held=151500
- PASS | A7 mission moved to heading_to_pickup — heading_to_pickup
- PASS | A8 merchant credited exactly +150000 once — merchant_balance=150000
- PASS | A9 food order synchronised to confirmed — confirmed
- PASS | A10 replayed merchant accept is inert
- PASS | A11 preparation lock reached — preparing
- PASS | A12 food order synchronised to preparing — preparing
- PASS | A13 completion blocked before custody — CUSTODY_NOT_ESTABLISHED
- PASS | A14 canonical dropoff completes runtime with cash fields — completed collected=176500 princ=150000 earn=25000 fee=1500
- PASS | A15 food order completed — completed
- PASS | A16 mission delivered — delivered
- PASS | A17 no fake driver wallet earning credit for physical cash
- PASS | A18 driver wallet out exactly 151500 (150000+1500) — bal=4848500 held=0
- PASS | A19 master captured exactly +1500 once — master=-98935
- PASS | A20 replayed completion adds zero
- PASS | A21 economic drift on the source is exactly 0 — sum=0
- PASS | A22 every journal has >=2 non-zero postings
- PASS | B1 insufficient funds -> claim rejected, courier NULL, no runtime/holds/payable — INSUFFICIENT_DRIVER_BALANCE
- PASS | B2 cash order direct state write denied before any runtime exists — CASH_ORDER_STATE_ENGINE_ONLY
- PASS | B3 non-cash direct lifecycle still works — confirmed
- PASS | B4 flag OFF rolls back claim entirely (no partial assignment) — CASH_ORDER_FUNDING_DISABLED
- PASS | B5 flag OFF does not open a legacy direct-write bypass — CASH_ORDER_STATE_ENGINE_ONLY
- PASS | C1 customer cancel after dispatch: one debt, holds released, runtime cancelled — debts=1 held=0 state=cancelled
- PASS | C2 source + mission coherent after cancellation — mission=failed order=cancelled
- PASS | C3 replayed cancellation creates no second debt
- PASS | C4 merchant rejection: holds released, payable reversed, no debt, no fee revenue — held=0 payable=reversed debts=0
- PASS | C5 rejected cash mission + order no longer active — failed/cancelled
- PASS | C6 replayed rejection inert
- PASS | D1 Marche cash tender persisted atomically in offer creation — cash
- PASS | D2 invalid tender rolls back offer creation entirely — INVALID_TENDER
- PASS | D3 NULL Marche tender -> MARCHE_TENDER_REQUIRED, no assignment/runtime/holds — MARCHE_TENDER_REQUIRED
- PASS | D4 missing tender is never interpreted as cash
- PASS | D5 explicit choppay keeps the non-cash branch (no cash engine) — runtime=0 holds=0
- PASS | E1 Marche cash claim creates runtime + economics atomically — sub=150000 fee=1500 due=176500
- PASS | E2 Marche holds placed
- PASS | E3 Marche merchant funded once + preparation substate — merchant=300000 state=preparing
- PASS | E4 Marche delivered: runtime completed + fulfillment delivered + mission delivered — offer=delivered mission=delivered
- PASS | E5 Marche platform fee captured exactly once (+1500) — master delta=1500
- PASS | E6 no driver wallet earning credit on Marche cash
- PASS | E7 Marche completion replay adds zero
- PASS | E8 Marche ledger drift 0
- PASS | F1 BENEFICIARY_MISMATCH blocks arbitrary reversal, no value moves — BENEFICIARY_MISMATCH
- PASS | F2 release_driver_funding restores captured principal to the driver — driver=4697000 held=0 payable=reversed
- PASS | F3 fee hold released, zero platform fee revenue, nothing encumbered
- PASS | F4 reversal journals balanced (drift 0 on disputed source)
- PASS | F5 dispute resolution replay moves zero
- PASS | F6 close_no_value: merchant + driver principal unchanged — merchant=450000 driver=4547000
- PASS | F7 close_no_value releases the stuck platform-fee hold — held 1500 -> 0
- PASS | F8 close_no_value captures no fee revenue and leaves nothing encumbered
- PASS | F9 complete_as_delivered populates true cash recovery fields — 176500/150000/25000/1500
- PASS | F10 complete_as_delivered completes source + mission — completed/delivered
- PASS | F11 fee captured exactly once, no wallet earning credit — master delta=1500
- PASS | F12 dispute completion replay adds zero
- PASS | F13 settled payable -> FINANCE_RECONCILIATION_REQUIRED, no fabricated value — FINANCE_RECONCILIATION_REQUIRED
- PASS | G1 raw money primitives are service-role only — violations=0
- PASS | G2 participant/admin cash RPCs remain callable by authenticated — granted=9/9
- PASS | G3 mission_claim + create_marketplace_offer anon=false
- PASS | G4 Slice 3 inbound-OM / ride guards preserved — violations=0
- PASS | G5 non-finance caller cannot resolve a dispute — Not authorized
- PASS | H1 all journals created in this run balance to 0
- PASS | H2 captured + released never exceeds reserved amount
- PASS | H3 source attribution exact on every journal
- PASS | H4 every journal in this run has >=2 non-zero postings
- PASS | Z1 master wallet unchanged at -100435 after rollback — master=-100435
- PASS | Z2 zero cash_order_runtime rows remain — rows=0
- PASS | Z3 zero mission_financial_holds remain — rows=0
- PASS | Z4 zero merchant_payables remain — rows=0
- PASS | Z5 zero customer_cancellation_debts remain — rows=0
- PASS | Z6 zero QA merchant stores remain
- PASS | Z7 zero QA restaurants remain
- PASS | Z8 zero QA listings/offers remain
- PASS | Z9 zero QA promo credits remain
- PASS | Z10 zero QA ledger journals persisted — rows=0
- PASS | Z11 zero QA audit rows persisted — rows=0
- PASS | Z12 canonical flags: only om_topup_enabled ON — other_on=0 topup_on=1

## Cleanup / production post-state

- `_qa_s4%` functions and tables: **0**.
- `cash_order_runtime`, `mission_financial_holds`, `merchant_payables`,
  `customer_cancellation_debts`: **0 rows**.
- QA stores / restaurants / listings / offers / promo credits / audit rows /
  ledger journals: **0**.
- Master wallet `b6858980-43d2-425d-b12d-b02aac3de52d`: **−100 435 GNF** (unchanged).
- Canonical finance flags: `om_topup_enabled = true`, all other 16 **false**
  (`cash_order_funding_enabled` was toggled ON only inside the aborted
  sub-transaction and is OFF in production).
- DEF-FIN-001 untouched.

## Build evidence

- `tsgo --noEmit` — clean.
- Vitest — **12/12 pass** (2 files).
- `vite build` — green. PWA precache **130 entries / 11 867.30 KiB**; largest
  single asset `index-*.js` 2 140.09 kB — under the 4 MiB per-file limit.

## Product call sites (read-only audit, post-wiring)

| Surface | File |
| --- | --- |
| Repas merchant | `src/components/merchant/repas/RepasOrdersSection.tsx`, `src/lib/merchant/operations.ts` |
| Repas customer | `src/components/missions/CustomerMarketplaceDeliveries.tsx` |
| Marché merchant | `src/components/merchant/MerchantCommandesView.tsx` |
| Marché buyer atomic tender | `src/components/marche/OfferSheet.tsx`, `src/lib/marche/offers.ts` |
| Driver claim / completion | `src/lib/missions/missions.ts`, `src/components/driver/ActiveMissionCard.tsx` |
| Finance dispute resolution | `src/components/admin/CashOrderDisputeQueue.tsx`, `src/pages/admin/RepasPayments.tsx` |
| Shared bindings/surface | `src/lib/cash/cashOrders.ts`, `src/components/cash/CashOrderPanel.tsx` |

## YELLOW register (carried forward)

1. Slice 2 God Admin finance policy / control-plane visual QA — **YELLOW**.
2. Slice 3 Ride / Bonbonna + OM reconciliation visual QA — **YELLOW**.
3. DEF-FIN-001 master wallet −100 435 GNF — **YELLOW**, untouched.
4. Slice 4 Repas / Marché cash-order visual QA — **YELLOW** (preview still signed
   out; no authenticated visual session was available, so no visual PASS is claimed).
5. Part 3 "harness re-run owed" — **CLOSED** by this run (81/81).

## Exit-gate recommendation

Slice 4 database + product integration evidence is **GREEN** (81/81, drift 0,
cleanup clean, flags correct, build green). The only open item is the
authenticated **visual** QA (YELLOW #4). Slice 4 remains **UNLOCKED** pending
that visual session. Slice 5 **NOT STARTED**.

