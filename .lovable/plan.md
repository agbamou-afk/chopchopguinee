

# Milestone locked

`chopchop-guinea-phone-input-stable` saved to memory.

# Why a plan first

The new request is genuinely huge: new DB tables + RPCs, a full two-sided manual Orange Money reconciliation queue, a rewrite of the customer Recharger flow, and a sweep of fake/mock data across ~15 admin tabs. Done in one shot it would be hundreds of lines of SQL plus dozens of files — impossible to review or QA confidently. I want to ship it in 3 small, individually verifiable passes, each ending in a stable build.

Before writing code I also need a short audit (Phase 0 of your brief) so we agree on the source of truth and don't create a duplicate top-up path.

# Pass 1 — Audit (read-only, no code)

I'll inspect and report back:

- Current Recharger handler (`WalletHero` → ?) and existing `TopUpOrangeMoney` component.
- Existing `payment_intents` helpers and any `topup_requests` table/RPCs (`create_wallet_topup_intent`, `wallet_topup_om_credit`, `confirm_payment_intent`, etc.).
- What `PaymentsAdmin` and `WalletReconciliation` currently read.
- Every admin tab still rendering `MOCK` / hardcoded rows.
- Whether `payment_intents` alone can be the source of truth (preferred) or if a parallel `topup_requests` table exists and must be linked.

Deliverable: short written report with file:line refs and the chosen source-of-truth model. No code changes.

# Pass 2 — Real Recharger + admin visibility (small migration + UI)

Goal: a real customer top-up appears in `/admin/payments` and can be confirmed/failed by finance/god admin via secure RPC.

- New table `payment_receiving_accounts` (admin-managed OM receiving numbers) + sanitized `get_active_payment_receiving_accounts()` RPC.
- New RPC `create_wallet_topup_intent(amount, provider, receiving_account_id)` → inserts `payment_intents` row with `purpose = wallet_topup`, status `pending`, public reference. Never credits.
- Customer: `Recharger` opens a real amount sheet → method picker → shows active OM receiving number → creates intent → shows pending receipt.
- Admin `PaymentsAdmin`: wire real query of `payment_intents` (it likely already does — confirm and fix filters/refetch). Confirm/Fail buttons call existing `confirm_payment_intent` / `fail_payment_intent` RPCs (already SECURITY DEFINER + admin-gated).
- Admin settings panel inside `/admin/payments` to CRUD receiving accounts.
- Polling + manual refresh on both sides (no financial realtime).

# Pass 3 — Two-sided OM reconciliation queue

Goal: customer code + admin OM receipt match automatically and credit wallet idempotently.

- New tables: `om_customer_confirmations`, `om_admin_receipts`, `om_reconciliation_matches` with strict RLS.
- RPCs (all SECURITY DEFINER, idempotent):
  - `submit_customer_om_code(payment_intent_id, code)` — owner-only.
  - `submit_admin_om_receipt(code, amount, receiving_account_id, payer_phone, note)` — finance/god only.
  - `reconcile_om_topup(...)` — normalizes code, matches code+amount, on success calls existing confirm path to credit wallet via `wallet_transactions`. Conflicts/duplicates marked for review, never credited.
- Customer UI: after top-up intent, second step "Coller le code Orange Money".
- Admin UI: new "Réconciliation OM" tab with the 4 queues (waiting admin / waiting customer / matched / conflicts) + quick-entry form.
- Command Center counts wired to real pending/conflict counts.

# Pass 4 — Admin mock-data sweep

Per-tab pass replacing `MOCK` arrays with real queries or honest `À connecter` empty states. Tabs: `UsersAdmin`, `DriversAdmin`, `MerchantsAdmin`, `OrdersAdmin`, `RepasAdmin`, `MarcheAdmin`, `RiskAdmin`, `PromotionsAdmin`, `ZonesAdmin`, `ReportsAdmin`, `NotificationsAdmin`, `LiveOps`, `AdminDashboard`, `PilotCommandCenter`, `WalletAdmin`. No fake users, ledgers, charts, or `Math.random`.

# Security invariants kept across all passes

- No frontend wallet credit.
- No self-confirm of own top-ups.
- Financial realtime stays off — polling + visibilitychange + manual refresh.
- All new tables: explicit `GRANT`s, RLS enabled, anon has no access to payment data.
- Existing security scan findings stay fixed; `security--run_security_scan` re-run after each migration.

# What I need from you

1. Approve this 4-pass split (or tell me to collapse / reorder).
2. Confirm: use `payment_intents` as the single source of truth for wallet top-ups, and treat any existing `topup_requests` table as legacy to deprecate/link — not maintain in parallel.
3. Confirm Pass 1 (audit) lands first as a written report, no code, so we lock the model before migrations.

Once approved I'll start with the audit and report back before any DB or code changes.
