# Slice 4 Closeout Audit — Read-only Evidence Report

Baseline: 3a58fc4. No code, migrations, or DB state changed.

## 1. Product-code call sites for the Slice 4 RPCs — **ZERO** (P1)

Search over `src/**` and `supabase/functions/**` for `cash_order_quote|accept|merchant_accept|merchant_reject|merchant_prepare|complete_cash|customer_cancel|dispute_open|admin_cash_order_dispute_resolve`:

- `src/**`: only two hits, both non-invocations —
  - `src/integrations/supabase/types.ts` (generated type entries for the RPCs + `cash_order_runtime` table)
  - `src/components/admin/finance/FinanceControlsPanel.tsx:30` — the `cash_order_funding_enabled` **feature flag label** only.
- `supabase/functions/**`: no hits.
- Only other hits are inside the Slice 4 migrations themselves (definitions + the now-dropped QA harness).

Live product lifecycle screens still use the legacy paths and never touch the engine:
- Repas merchant: `src/components/merchant/OrdersSection.tsx` → `advanceRestaurantOrder` (direct `food_orders.state` writes).
- Marché merchant: `src/components/merchant/MerchantCommandesView.tsx` → `respondToInterest`, `respondOffer`.
- Customer/driver Repas: `src/lib/repas/orders.ts` → direct `food_orders` insert + `createMission`, ChopPay intent for wallet.

**Finding 1 — P1.** The cash-order engine is deployed but fully unwired. No user, driver, merchant, or admin surface can reach quote/accept/fund/prepare/complete/cancel/dispute. Slice 4's "wire cash order selection" objective is not met in product code; DB-level QA passed against synthetic rows only.

## 2. Marché state synchronization — **not implemented** (P1)

Reading the live definitions of all `cash_order_*` functions:

- `_cash_order_facts` **reads** `marketplace_offers` (buyer, store, merchant_user_id, `COALESCE(counter_amount_gnf, offer_amount_gnf)`, cash inferred from `metadata->>'payment_method'`) and the latest `missions` row via `ref_market_order_id`.
- **No** `cash_order_*` function performs any `UPDATE` on `marketplace_offers`. Product-state writes exist only under `IF p_source_module = 'repas'`:
  - merchant_accept → `food_orders.state='confirmed'`
  - merchant_prepare → `'preparing'`
  - merchant_reject / customer_cancel → `'cancelled'`
  - complete_cash → `'completed'` + `completed_at`
- **No** `cash_order_*` function updates `missions` at all — for either module. `complete_cash` *reads* mission state as a gate (`pickup_confirmed`, state in picked_up/heading_to_dropoff/arrived_dropoff/delivered) but never advances it to `delivered`, and never sets a mission failure/cancel state on reject/cancel/dispute.
- Delivery fee is derived from `missions.estimated_earning_gnf`; if no mission row exists, `delivery_fee_gnf = 0`.

States living **only** in `cash_order_runtime`, invisible to the product lifecycle: `accepted`, `merchant_accepted`, `preparing`, `merchant_rejected`, `disputed`, `dispute_resolved`, `cancelled`, `completed` — for Marché, **all** of them; for Repas, `disputed` / `dispute_resolved` / `merchant_rejected` (partially mapped to `cancelled`) and every mission-side transition.

**Finding 2a — P1.** Marché has zero write-back: an offer can be funded, prepared, and cash-completed while `marketplace_offers.status` stays unchanged.
**Finding 2b — P1.** Mission state is read-only to the engine for both modules; delivery/custody completion is never recorded on `missions`.

## 3. Post-preparation dispute economics (`admin_cash_order_dispute_resolve`)

Exact behavior from the live definition:

```
complete_as_delivered  -> _cash_order_capture_platform_fee(...)
release_driver_funding -> _driver_mission_hold_release_internal(module, id, NULL, reason, caller)
close_no_value         -> jsonb_build_object('status','closed_no_value')   -- no financial call
then: runtime.state = 'dispute_resolved' + audit_logs row
```

**3a. `release_driver_funding` after merchant acceptance — P1.**
`_merchant_payable_fund_internal('driver_cash_funding')` has already: incremented `mission_financial_holds.captured_gnf/captured_unrestricted_gnf` to full, set the cash_funding hold `state='captured'`, debited the driver wallet `balance_gnf` and `held_gnf`, credited the merchant wallet `balance_gnf`, and posted `L_HOLD_CASH_FUNDING → L_MERCHANT_PAYABLE`.
`_driver_mission_hold_release_internal` only iterates holds in `('held','partially_captured','frozen')` and releases `amount - captured - released`, which is **0** for the captured cash_funding hold (and the hold is `captured`, so it is not even selected).
=> The merchandise principal is **NOT** restored to the driver. The merchant payable and merchant wallet are **NOT** debited or reversed. In practice this outcome only releases still-open holds — i.e. the `platform_fee` hold (and any partially-captured remainder). The outcome name overstates what it does.

**3b. `close_no_value` — P1.**
No financial call at all. Any `platform_fee` hold stays `state='held'` with driver `wallets.held_gnf` still encumbered, and the funded `merchant_payables` row stays `funded`. Runtime moves to `dispute_resolved`, so no later `cash_order_*` path can act on it (`complete_cash` requires `preparing|merchant_accepted`; `merchant_reject`/`customer_cancel` require `accepted`; a second resolve short-circuits with `already_resolved`). => Holds are left stuck with no in-engine recovery path.

**3c. `complete_as_delivered` — P1 (economics partially correct, lifecycle not).**
It captures the platform fee correctly (idempotent: `already_resolved` when the hold is not `held`). But it does **not** run the `complete_cash` body: `cash_collected_gnf`, `cash_principal_recovery_gnf`, `cash_delivery_earning_gnf`, `cash_fee_recovery_gnf` stay unpopulated; `completed_at` stays NULL; runtime state becomes `dispute_resolved`, never `completed`; `food_orders` is not set to `completed`; `marketplace_offers` and `missions` are untouched. => No true delivered/completed state, no cash-recovery record.

## 4. Grants — **PASS**

`pg_proc.proacl` (public schema):

| function | ACL |
|---|---|
| `merchant_payable_create`, `merchant_payable_fund`, `driver_mission_hold_release`, `customer_cancellation_debt_create`, `driver_funding_allocate` | `postgres`, `service_role` only |
| `_merchant_payable_create_internal`, `_merchant_payable_fund_internal`, `_driver_mission_hold_release_internal`, `_customer_cancellation_debt_create_internal` | `postgres`, `service_role` only |
| all `cash_order_*` (`quote`, `accept`, `merchant_accept`, `merchant_reject`, `merchant_prepare`, `complete_cash`, `customer_cancel`, `dispute_open`) | `postgres`, `authenticated`, `service_role` |
| `admin_cash_order_dispute_resolve` | `postgres`, `authenticated`, `service_role` (guarded by `_finance_privileged(auth.uid())`) |

No `anon` grant anywhere in this set; no raw money primitive is reachable by `public`/`anon`/`authenticated`. Each `authenticated`-callable `cash_order_*` re-checks caller identity against the runtime row (driver / merchant / customer) or `_finance_privileged`. `cash_order_runtime`: `SELECT` to `authenticated` under a participant RLS policy, `ALL` to `service_role`. **PASS.**

## 5. Classification against Slice 4 scope

| Scope item | Verdict | Evidence |
|---|---|---|
| Wire cash order selection | **P1** | zero call sites (§1) |
| Full merchandise funding | PASS (DB) | `_merchant_payable_fund_internal` captures full `amount - funded` |
| Bonus (restricted promo) exclusion | PASS | `RESTRICTED_FUNDS_CANNOT_FUND_MERCHANDISE` when `promo_gnf > 0` |
| 1% platform fee | PASS | `_cash_order_capture_platform_fee`, idempotent, ledger-posted |
| Merchant wallet credit | PASS | merchant wallet upsert + credit inside funding |
| Merchant acceptance | PASS (DB) / P1 (unwired) | `cash_order_merchant_accept` |
| Preparation | PASS (DB), Repas only | prepare writes `food_orders`; Marché no write-back (§2) |
| Delivery / cash recovery | YELLOW | correct on `complete_cash`; absent on dispute-resolved path (§3c); mission never advanced (§2b) |
| Cancellation debt | PASS | `_customer_cancellation_debt_create_internal` on both pre/post-dispatch stages |
| Merchant rejection release | PASS (Repas) / YELLOW (Marché) | holds released + payable `reversed`; no `marketplace_offers` write-back |
| Post-preparation dispute handling | **P1** | §3a principal not restored, §3b stuck holds, §3c no completion |
| Grants / privilege boundary | PASS | §4 |
| Marché state synchronization | **P1** | §2 |

### Summary
- PASS: 8 (core economics + privilege boundary)
- YELLOW: 2 (Marché reject write-back, delivery/cash recovery on dispute path)
- P1: 4 (zero product wiring; Marché state sync; mission state sync; dispute economics 3a/3b/3c)
- P2: none newly raised.

Carried-forward YELLOW register unchanged: Slice 2/3 visual QA (preview signed out), DEF-FIN-001 master wallet −100 435 GNF, Slice 4 UI visual QA.

**Recommendation: do not sign Slice 4 as complete.** No fixes proposed here per instruction.
