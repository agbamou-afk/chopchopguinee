# Chop Pay — Slice 7: Ledger-Truth Surfaces (Customer / Driver / Merchant)

Status: **PASS** — 78/78 assertions, 0 failures.
Scope: read models + merchant settlement **request-only** model + product surfaces.
No finance rail activated. `merchant_om_settlement_enabled = false`, `chop_pay_enabled = false`,
`om_topup_enabled = true` (already canonical).

## 1. Exit gate

> EVERY DISPLAYED FINANCIAL NUMBER COMES DIRECTLY FROM LEDGER/AUTHORITATIVE SERVER TRUTH,
> WITH ZERO CLIENT-SIDE FINANCIAL ARITHMETIC OR RECONSTRUCTION.

**PASS.** Client-side arithmetic removed:

| Removed | File | Replacement |
|---|---|---|
| `wallet.balance_gnf - wallet.held_gnf` | `src/components/views/WalletView.tsx` | `customer_finance_overview.available_gnf` |
| 30-day inflow reduce over transactions | `src/components/views/WalletView.tsx` | `ecosystem_spend_gnf` / `topup_credited_gnf` / `refund_total_gnf` |
| `Math.max(0, available - promo)` withdrawable fallback | `DriverOperatingBalanceCard.tsx` | `driver_balance_summary.withdrawable_gnf` |
| UI-inferred "blocked" from balance | `DriverOperatingBalanceCard.tsx` | `driver_financial_eligibility` |
| `transactions.filter(...).reduce(...)` today revenue | `MerchantWalletSection.tsx` | `merchant_finance_overview` |

## 2. Server read models

| RPC | Scope | Authority |
|---|---|---|
| `customer_finance_overview()` | self (auth.uid) | `wallets` (client) + open `mission_financial_holds` + captured spend journals |
| `customer_finance_history(p_limit)` | self | `wallet_transactions` ∪ `topup_requests` (pending flagged, `counts_as_balance=false`) |
| `customer_receipt(p_transaction_id)` | self | completed transaction + `ledger_journals` provenance |
| `driver_balance_summary()` (reused) | self | driver wallet buckets + holds |
| `driver_financial_eligibility()` (reused) | self | canonical finance rule path |
| `driver_topup_history(p_limit)` | self, driver-target only | `topup_requests` + credited transaction link |
| `merchant_finance_overview(p_store_id)` | store owner / staff, or finance/god admin | merchant wallet + `merchant_payables` state sums |
| `merchant_settlement_requests_list(p_store_id, p_limit)` | same | `merchant_settlement_requests` |
| `merchant_settlement_request_create(...)` | store owner | validated against server eligible amount, idempotent |

All are `SECURITY DEFINER`, `SET search_path = public`, explicit `auth.uid()` / role checks.
`EXECUTE` revoked from `PUBLIC` and `anon`.

## 3. UI → read model → canonical source provenance

| UI field (surface) | Read model field | Canonical computation | Assertion |
|---|---|---|---|
| Solde disponible (Wallet) | `available_gnf` | wallet balance − reconciled open holds, server-side | A1 |
| Bloqué (Wallet) | `held_gnf` / `open_hold_gnf` | `wallets.held_gnf` reconciled to open `mission_financial_holds` | A2, A3 |
| Dépenses écosystème | `ecosystem_spend_gnf` | captured/settled spend journals only (excl. topups, releases, failed holds) | A6, A7 |
| Recharges créditées | `topup_credited_gnf` | credited `topup_requests` linked to wallet credit txn | A8 |
| Recharge à vérifier | `topup_pending_gnf/_count` | pending topups, excluded from balance | A9, A10 |
| Remboursements | `refund_total_gnf` | refund journals; hold releases excluded | A11, A12 |
| Historique | `customer_finance_history` rows | txn/topup rows with reference + provenance | A13–A16 |
| Reçu | `customer_receipt` | frozen captured order economics + journal | A17, A18 |
| Portefeuille chauffeur disponible | `available_gnf` | driver wallet − holds | B1 |
| Total / retenu | `balance_gnf` / `held_gnf` | wallet truth, holds reconciled | B2, B3 |
| Fonds libres | `unrestricted_available_gnf` | non-promo bucket | B4 |
| Crédit restreint | `promo_remaining_gnf` / `promo_available_gnf` | `driver_promo_credits` attribution incl. held part | B5–B8 |
| Montant retirable | `withdrawable_gnf` | unrestricted only, never promo | B9 |
| Éligibilité mission | `driver_financial_eligibility` | canonical finance rule path | B10–B13 |
| Mes recharges (driver) | `driver_topup_history` | driver-target topups only | B14–B17 |
| Solde des ventes | `sales_balance_gnf` | merchant wallet balance | C1 |
| À régler (en attente) | `pending_payable_gnf` | pending `merchant_payables`, excl. reversed/settled | C2, C3 |
| Financé, non réglé | `funded_unsettled_gnf` | funded payables not settled | C4 |
| Déjà réglé / remboursé | `settled_total_gnf` / `reversed_total_gnf` | payable state sums | C5, C6 |
| Montant éligible | `eligible_settlement_gnf` | funded unsettled − open requests, server-side | C7, C8 |
| Historique règlements | `merchant_settlement_requests_list` | request rows, `settled` only with evidence | C9–C12 |

## 4. QA parts (self-rolling-back fixtures)

| Part | Coverage | Result |
|---|---|---|
| 1 | Customer overview / history / receipt / refund vs release / cross-customer denial | 21/21 |
| 2 | Driver buckets, promo through hold+release, eligibility flip, driver-scoped topups, cross-driver denial | 20/20 |
| 3 | Merchant sales balance, payable states, reversal, settlement cap, idempotent replay, cross-merchant denial | 22/22 |
| 4 | Privileges (anon denied, no client writes), cleanup, master/flag posture | 15/15 |
| **Total** | | **78/78** |

**DEF-FIN-S7-001 (fixed):** `merchant_settlement_requests` inherited the schema-wide default
grants, giving `anon`/`authenticated` INSERT/UPDATE/DELETE. Revoked; `authenticated` keeps
`SELECT` only (RLS-scoped), writes are `service_role`/RPC-only. Part 4 D4 re-run → PASS.

## 5. Settlement semantics (request-only)

- `merchant_settlement_requests`: immutable requested amount + `request_key` idempotency,
  store ownership, audit log entry, server-side validation against eligible amount.
- No OM send, no merchant debit, no reservation of funds.
- Statuses: `requested` / `pending_review` / `rejected` / `cancelled` / `settled`;
  `settled` only with canonical evidence. UI states this explicitly in French.

## 6. Cleanup / posture

- All fixtures rolled back; `merchant_settlement_requests` row count = 0.
- Master wallet **exactly −100 435 GNF**, held 0 — unchanged.
- Flags unchanged: `om_topup_enabled=true`, `chop_pay_enabled=false`, `merchant_om_settlement_enabled=false`.
- No Slice 3/4/5/6 privilege or engine regression.

## 7. Build evidence

- `tsgo --noEmit -p tsconfig.app.json` → clean.
- Vitest → 12/12 passing (2 files).
- `vite build` → success, 18.3s.
- PWA precache 130 entries / ~11.9 MiB; chunk-size warning (`index` 2.16 MB, `mapbox-gl` 1.78 MB)
  **still open** — not addressed in Slice 7.

## 8. YELLOW register (carried forward)

- Slice 2–6 visual QA — YELLOW (preview signed out).
- **Slice 7 visual QA — YELLOW** (preview signed out; no authenticated session available).
- DEF-FIN-001 negative master treasury (−100 435 GNF) — expected baseline, unresolved.
- PWA chunk-size / precache weight — open.

**Slice 7 exit gate: PASS.**

---

## 9. Final UI-truth closeout (product wiring proof)

DB/read-model proof (78/78) and product wiring proof are **separate**:

| Layer | Proof | Status |
|---|---|---|
| DB read models | `_qa_s7_results` parts 1–4 = 21+20+22+15 = **78/78** | PASS (re-verified after code changes, no rerun needed) |
| Product wiring | source-level guards in `src/test/slice7-ui-truth.test.ts` (3 tests) | PASS |

Three product-layer gaps closed:

1. `WalletView` → `SendMoneySheet` now receives `overview.available_gnf`
   (`available`), not `balance_gnf - held_gnf`. No client arithmetic in the send path.
2. Customer history now renders `customer_finance_history(p_limit)` events —
   amount/direction/status/kind/reference/label/module come verbatim from the
   server. Pending top-up rows (`counts_as_balance=false`) are badged "Non compté"
   and are not receipt-openable. Raw `useWallet().transactions` is retained only
   for the non-financial "Marchands récents" strip.
3. `TransactionReceiptSheet` now takes `transactionId` and fetches
   `customer_receipt(p_transaction_id)`. Amount, direction, status, reference,
   transaction identity, completion timestamp and journal-provenance indicator all
   come from the RPC. On fetch failure it renders a calm "Reçu indisponible"
   state — **no fallback to raw transaction values**.

Surface audit (post-fix) — no client-side financial reconstruction found in
`WalletView`/`SendMoneySheet` handoff, `TransactionReceiptSheet`,
`DriverOperatingBalanceCard`, `MerchantWalletSection`, or any
`src/lib/finance/readModels.ts` consumer.

Live posture re-verified: master wallet **−100 435 GNF / held 0**,
`merchant_settlement_requests` rows = 0, `merchant_om_settlement_enabled=false`,
no finance flag activation.

Build evidence: `tsgo --noEmit -p tsconfig.app.json` clean · Vitest **15/15** (3 files) ·
`vite build` green (19.7s) · PWA precache 130 entries / ~11.9 MiB, chunk-size warning
(`index` 2.16 MB, `mapbox-gl` 1.78 MB) **still open, unchanged**.

Slice 7 visual QA remains **YELLOW** (preview signed out — no authenticated session).

**Slice 7 final UI-truth closeout: PASS.** No new defects found.
