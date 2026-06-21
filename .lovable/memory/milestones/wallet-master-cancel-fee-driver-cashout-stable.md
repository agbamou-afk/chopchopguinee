# Wallet — Master Wallet + Cancellation Fee + Driver Cashout (stable)

Locked: 2026-06-21. Lock id: `wallet-master-cancel-fee-driver-cashout-stable`.
Also closes the cashout follow-up noted against `chauffeur-courier-production-readiness-stable`.

## Scope
P0 Finance phase: introduces the platform master wallet, the client cancellation fee, and operator-mediated driver cashout. CHOPCHOP is a real product, not an MVP. Money movement is auditable, idempotent, role-controlled, and never faked.

## Hard exits (all verified)
- A singleton master wallet exists (`wallets.party_type='master'`, unique partial index, `wallet_ensure_master()` idempotent).
- Master balance is god-admin only:
  - RLS: `Admins view non-master wallets` + `Admins manage non-master wallets` exclude master rows; only `God admins view master wallet` allows reading the row.
  - `wallet_get_master_balance()` SECURITY DEFINER guards `is_god_admin()` and raises `not_authorized` otherwise.
- Client cancels before driver assigned → no fee, full hold released.
- Client cancels after driver assigned (`driver_id IS NOT NULL`) → 10% fee captured to master, remainder released atomically via existing `wallet_capture` semantics.
- Driver / admin cancellation → never charge the client a fee.
- `ride_cancel` blocks client cancellation while `status='in_progress'` (`ride_in_progress_cancel_not_allowed`).
- Cancellation is idempotent: re-running on a `cancelled` ride is a no-op; the fee branch is guarded by `metadata->>'cancellation_fee_gnf' = 0`.
- Cancellation fee path is exception-safe: if `wallet_capture` fails the function falls back to `wallet_release` so cancellation never breaks.
- `audit_logs` records `cancellation_fee_captured`, `driver_cashout_requested`, `driver_cashout_rejected`, `driver_cashout_paid`.
- Driver cashout requests:
  - Amount must be > 0 and a multiple of 5,000 GNF.
  - Driver cannot request more than `(balance - held - sum(pending|approved cashouts))`.
  - Driver cannot mark paid; only `can_manage_wallet()` (god / super / finance admin) can.
  - `driver_cashout_mark_paid` re-locks the wallet, re-checks balance, debits once, writes a `payout` `wallet_transactions` row referencing the OM provider reference, is idempotent on `paid`.
  - Rejection records reason; cancellation only by the driver on `pending`.
- No frontend writes to `wallets`, `wallet_transactions`, or `driver_cashout_requests`. All mutations go through SECURITY DEFINER RPCs with `set search_path = public` and `REVOKE ALL ... FROM PUBLIC`.

## Files of record
- Migration: master wallet + tightened wallet RLS + `ride_cancel` rewrite + `driver_cashout_requests` table + four cashout RPCs (`create_request`, `cancel_request`, `reject_request`, `mark_paid`) + audit logging.
- `src/components/wallet/DriverCashoutSheet.tsx` — driver-side request UI, recent-requests list with status badges, prefilled +224 phone via shared helpers, 5,000 GNF stepper, operator-mediated copy.
- `src/components/views/DriverEarningsView.tsx` — "Versement" button now opens the cashout sheet.
- `src/pages/admin/DriverCashouts.tsx` — admin queue: filter by status, mark paid with OM reference, reject with reason. Route `/admin/wallet/driver-cashouts`.
- `src/components/admin/wallet/MasterWalletCard.tsx` — god-admin-only platform-revenue card. Self-hides for non-god callers (RPC throws `not_authorized`).
- `src/pages/admin/WalletAdmin.tsx` — mounts `MasterWalletCard` and links to `/admin/wallet/driver-cashouts`.
- `src/pages/Index.tsx` — surfaces honest cancellation-fee toast based on returned ride metadata.

## Out of scope (do not regress)
- Ride completion capture logic is unchanged.
- Global pricing is unchanged; the only new platform charge is the 10% client cancellation fee, and only when a driver was assigned.
- Wallet hold / capture / release contracts are unchanged.
- Sub-admin account provisioning (the third item on the parent P0 list) is not included in this milestone — handle in a follow-up run.
- No auto Orange Money payout. The app records manual operator confirmation only.

## QA smoke script
A) Cancel pre-assign → no fee, hold released, status `cancelled`.
B) Cancel post-assign as client → fee row in `wallet_transactions` (type `payment`, to master), driver unpenalised, ride metadata carries `cancellation_fee_gnf`, master balance increased by ROUND(fare*0.10).
C) Re-run `ride_cancel` on a cancelled ride → no double fee, idempotent.
D) Non-god admin calls `wallet_get_master_balance` → raises `not_authorized`; god admin sees real balance.
E) Driver requests cashout 20,000 → pending row created. 22,000 → `amount_must_be_multiple_of_5000`. Over balance → `insufficient_available_balance`. Driver calls `driver_cashout_mark_paid` → `not_authorized`.
F) Finance/god admin marks paid with reference → driver wallet debited once, `payout` transaction recorded with reference, idempotent second call returns unchanged.
G) Reject path → status `rejected`, no debit.
H) `wallets` SELECT as a non-god admin returns only non-master rows.
I) Build clean.

## Lock notes
- All new functions: SECURITY DEFINER, `SET search_path = public`, EXECUTE revoked from PUBLIC and granted to `authenticated` (self-guarded role checks inside).
- `driver_cashout_requests` has no client INSERT/UPDATE/DELETE policies — RPC is the only write path.
- Existing wallet hold/capture/release RPCs were not modified.