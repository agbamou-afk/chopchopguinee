
# Wallet Master + Cancellation Fee + Driver Cashout

Locking `chauffeur-courier-production-readiness-stable` with a note that driver cashout was out-of-scope and is now this P0. Lock candidate after this run: `wallet-master-cancel-fee-driver-cashout-stable`.

## 1. Current state (audit)

- `wallets.party_type` enum already includes `master` — no enum change needed.
- Existing money RPCs (SECURITY DEFINER): `wallet_hold`, `wallet_capture(p_hold_id, p_to_wallet_id, p_to_party_type, p_amount, ...)`, `wallet_release(p_hold_id, p_reason)`, `wallet_ensure`, `wallet_pay_driver_commission(_batch)`, `wallet_pay_merchant`, `wallet_topup_om_credit`.
- `ride_cancel(p_ride_id, p_reason)` currently always calls `wallet_release` on the full hold — no fee path.
- Rides table has `fare_gnf`, `hold_tx_id`, `driver_id`, `status`, `metadata` jsonb.
- Roles: `is_god_admin()`, `can_manage_wallet()`, `can_manage_operations()`, `current_admin_role()`.
- No master wallet row guaranteed; no cashout schema, RPCs, or UI.

## 2. Migration: master wallet + cancellation fee + cashout schema

Single migration, no schema changes to existing money RPCs beyond `ride_cancel`.

### 2a. Master wallet singleton
- `wallet_ensure_master() returns uuid` SECURITY DEFINER: inserts a `wallets` row with `party_type='master'`, `owner_user_id=NULL`, `status='active'` if one doesn't already exist; returns its id.
- Partial unique index `CREATE UNIQUE INDEX wallets_singleton_master ON public.wallets ((true)) WHERE party_type='master'`.
- Seed: `SELECT public.wallet_ensure_master();` inside migration.
- `wallet_get_master_balance() returns bigint` SECURITY DEFINER: guards `is_god_admin()`, returns balance.
- Grants: execute on both to `authenticated` (function self-guards role).
- RLS on `wallets`: confirm no select policy currently exposes `party_type='master'` to non-god rows. If existing policy is `owner_user_id = auth.uid()`, master is already hidden (owner is NULL). No policy change unless audit shows leak; if leak, tighten.

### 2b. `ride_cancel` cancellation fee
Replace `ride_cancel(p_ride_id, p_reason)`:
- Lock ride row.
- If status already `cancelled` / `completed` → no-op idempotent (return current row).
- Determine canceller: `auth.uid()`. Compute `v_is_client := (auth.uid() = v_ride.client_id)`.
- `v_driver_deployed := v_ride.driver_id IS NOT NULL OR v_ride.status IN ('accepted','driver_assigned','heading_to_pickup','arrived_pickup')`. (Statuses confirmed against current rides enum during implementation; if `in_progress` / `started` exists, return error `ride_in_progress_cancel_not_allowed`.)
- If `v_is_client AND v_driver_deployed AND v_ride.hold_tx_id IS NOT NULL`:
  - `v_fee := round(v_ride.fare_gnf * 0.10)::bigint`.
  - `v_master := public.wallet_ensure_master()`.
  - `wallet_capture(p_hold_id := v_ride.hold_tx_id, p_to_wallet_id := v_master, p_to_party_type := 'master', p_amount := v_fee, p_reason := 'ride_cancellation_fee')` — captures fee, releases remainder (this matches existing capture semantics; if capture doesn't auto-release, follow with `wallet_release`).
  - Stamp `rides.metadata` with `{cancellation_fee_gnf, fee_tx_id, cancelled_by:'client', cancelled_at}`.
- Else: existing `wallet_release` path (no fee).
- Always: expire open `ride_offers`, set ride `status='cancelled'`, reset driver presence as today.
- Idempotency: refuses to re-run if `metadata->>'cancellation_fee_gnf'` already set.

### 2c. `driver_cashout_requests`
Table (auth-only):
```
id uuid pk default gen_random_uuid()
driver_user_id uuid not null references auth.users(id) on delete cascade
wallet_id uuid not null references public.wallets(id)
amount_gnf bigint not null check (amount_gnf > 0 and amount_gnf % 5000 = 0)
status text not null default 'pending' check (status in ('pending','approved','paid','rejected','cancelled'))
payout_method text not null default 'orange_money'
payout_phone text not null
driver_note text
admin_note text
provider_reference text
rejected_reason text
requested_at timestamptz not null default now()
reviewed_by uuid; reviewed_at timestamptz
paid_by uuid; paid_at timestamptz
created_at, updated_at timestamptz default now()
```
GRANT block + ENABLE RLS + policies:
- driver: `select` own; `insert` only via RPC (no direct insert policy).
- finance/god admin (`can_manage_wallet()`): `select` all.
- no anon, no update from client.
Index on `(status, requested_at)`, `(driver_user_id, requested_at desc)`.

### 2d. Cashout RPCs (all SECURITY DEFINER, `set search_path = public`)

- `driver_cashout_create_request(p_amount_gnf bigint, p_payout_phone text, p_driver_note text)`:
  - auth required; resolve driver wallet (`party_type='driver'`, `owner_user_id=auth.uid()`).
  - validate amount > 0, % 5000 = 0, `<= balance_gnf - held_gnf`.
  - block if existing `pending` request from same driver (configurable; default: allow multiple but reject if sum-of-pending exceeds available).
  - insert row status `pending`; return id.

- `driver_cashout_cancel_request(p_id uuid)`: driver can cancel own `pending` only.

- `driver_cashout_reject_request(p_id uuid, p_reason text)`: requires `can_manage_wallet()`; only `pending`/`approved` → `rejected`.

- `driver_cashout_mark_paid(p_id uuid, p_provider_reference text, p_admin_note text)`:
  - requires `can_manage_wallet()` (finance_admin/god_admin).
  - lock request; must be `pending` or `approved`; if already `paid` → idempotent return.
  - lock driver wallet; re-check available balance `>= amount_gnf` else raise `insufficient_balance_at_payout`.
  - debit via direct `wallet_transactions` insert (type extension below) and `update wallets set balance_gnf = balance_gnf - amount where id = v_wallet`.
  - `wallet_transactions` insert: `type='cashout_payout'`, `status='completed'`, `from_wallet_id=driver_wallet`, `to_wallet_id=NULL`, `related_user_id=driver_user_id`, `related_entity='driver_cashout_request:'||id`, `description='Driver cashout via Orange Money'`, `metadata={provider_reference, payout_phone}`.
  - If `wallet_transactions.type` enum lacks `cashout_payout`, `ALTER TYPE ... ADD VALUE 'cashout_payout'` in same migration (before functions).
  - Update request `status='paid', paid_by=auth.uid(), paid_at=now(), provider_reference, admin_note`.
  - `audit_logs` insert.

Grants: `EXECUTE ... TO authenticated` for all four (each self-guards role).

## 3. Frontend

### 3a. Driver cashout UI
New component `src/components/wallet/DriverCashoutSheet.tsx`, opened from a "Demander un retrait" button in `DriverEarningsView` (existing). Shows:
- Available balance (already fetched).
- Amount input (stepper 5,000 GNF), validation.
- Payout phone (prefill driver profile phone, +224 normalized).
- Optional note.
- Recent requests list (status badges: En attente / Payé / Rejeté / Annulé) via `select` on `driver_cashout_requests` where `driver_user_id = auth.uid()`.
- Submit → `supabase.rpc('driver_cashout_create_request', …)`.
- Operator-mediated copy as specified.

### 3b. Admin cashout UI
New `src/pages/admin/DriverCashouts.tsx` mounted at `/admin/wallet/driver-cashouts`, plus link in `WalletAdmin` sidebar/tabs. Visible to `finance_admin` / `god_admin` only (use existing `can_manage_wallet` check / role context).
- Table of requests with filters (status, date).
- Row actions: Marquer payé (modal: provider reference + admin note), Rejeter (modal: reason).
- Uses `driver_cashout_mark_paid` / `driver_cashout_reject_request`.

### 3c. Master wallet view (God Admin only)
Small card on `WalletAdmin` page (or new `MasterWalletCard`) — calls `wallet_get_master_balance` RPC; renders only if RPC succeeds (otherwise hidden — non-god gets exception which we swallow).

### 3d. Cancellation fee client-side copy
- In ride cancel flow (Index.tsx ride cancel call + any cancel button surface), after `ride_cancel` success, if returned row metadata shows `cancellation_fee_gnf > 0`, toast: "Frais d'annulation: 10% car un chauffeur était déjà en route." + "Le reste de votre réservation a été libéré."
- No pricing or business-logic changes elsewhere.

## 4. Security / RLS

- All money mutations stay in SECURITY DEFINER RPCs; no frontend writes to `wallets`, `wallet_transactions`, or `driver_cashout_requests` outside RPCs.
- `wallets` policy for master: confirm during audit that `party_type='master'` rows are not selectable by non-god (existing owner-scoped policy already excludes them since owner is NULL). If a permissive policy exposes them, tighten with `AND party_type <> 'master'` and add separate god-admin policy.
- `driver_cashout_requests`: no direct insert/update policies — only via RPC.
- Audit log entries for: cancellation fee captured, cashout requested, paid, rejected.

## 5. QA (post-migration)
Run scenarios A–N from the brief: cancel pre-assign (no fee), cancel post-assign (fee to master, remainder released, idempotent on replay), god vs non-god master visibility, cashout valid/invalid amounts, balance enforcement, double-mark-paid idempotency, reject path, ledger references, build clean.

## 6. Milestone
On success, create `.lovable/memory/milestones/wallet-master-cancel-fee-driver-cashout-stable.md` and update `mem://index.md`. Also append a "cashout deferred → now closed" note in `chauffeur-courier-production-readiness-stable.md`.

## Files to add / change
- New migration (master wallet + ride_cancel rewrite + cashout table/RPCs + optional enum value).
- New: `src/components/wallet/DriverCashoutSheet.tsx`, `src/pages/admin/DriverCashouts.tsx`, optional `src/components/admin/wallet/MasterWalletCard.tsx`.
- Edit: `src/components/driver/DriverEarningsView.tsx` (entry button), `src/pages/admin/WalletAdmin.tsx` (tab/link), `src/App.tsx` or admin router (route), `src/pages/Index.tsx` (cancel toast based on returned metadata), `src/components/views/WalletView.tsx` only if cancel toast surfaces there.
- New milestone file + index update.

## Out of scope
No global pricing change. No auto Orange Money send. No change to ride completion capture. No new pricing for cashout. No RLS weakening. Sub-admin provisioning (item 3 in your P0 list) is NOT part of this run.
