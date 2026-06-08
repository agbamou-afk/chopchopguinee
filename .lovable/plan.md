# Driver Groups / Syndicates v1

Routed to Rides Agent with ChopWallet Agent review and Admin & Operations review. Scope is divided into 5 workstreams, sequenced to avoid contract collisions.

## 1. ChopWallet payout RPC (ChopWallet agent owns)

Goal: move commission rows `pending → approved → paid` and credit the leader's wallet exactly once, only from the backend.

**Migration**
- New SECURITY DEFINER RPC `wallet_pay_driver_commission(p_commission_id uuid)`:
  - Admin gate via `is_admin()` (finance_admin or god_admin).
  - Lock the `driver_group_commissions` row `FOR UPDATE`.
  - Reject unless `status='approved'` and `wallet_transaction_id IS NULL` and `leader_user_id IS NOT NULL` and `commission_amount_gnf > 0`.
  - Idempotency guard: unique partial index `(source_type, source_id, driver_user_id) WHERE status IN ('approved','paid')` already exists; additionally check no prior `wallet_transactions.reference = 'driver_commission:'||commission_id`.
  - Insert into `wallet_transactions` (kind=`commission_credit`, direction=`credit`, amount=commission_amount_gnf, user_id=leader_user_id, reference=`driver_commission:<id>`, metadata=group/source).
  - Update `wallets.balance_gnf` via existing secure helper (same path used by topup credit).
  - Update commission row: `status='paid'`, `wallet_transaction_id=<new id>`, `paid_at=now()`.
- New RPC `wallet_reverse_driver_commission(p_commission_id uuid, p_reason text)` for paid reversals: debit leader wallet, mark commission `reversed`, write reversal `wallet_transactions` row referencing the original.
- `REVOKE ALL ... FROM PUBLIC; GRANT EXECUTE ... TO authenticated`.

**Frontend**
- `src/lib/admin/driverGroups.ts`: replace `reviewCommission('mark_paid')` to call `wallet_pay_driver_commission`. Keep `approve`/`reverse` actions.
- `CommissionsTable`: relabel "Marquer payé" → "Payer (ChopWallet)", show resulting `wallet_transaction_id`, remove the v0 "hors-wallet" banner.
- Zero frontend wallet balance writes; verify with grep.

## 2. Group leader self-service portal (Rides agent)

Read-only portal for the authenticated leader.

**RPCs (SECURITY DEFINER, leader gate = `auth.uid() = group.leader_user_id`)**
- `leader_get_my_group()` → group row + summary counts.
- `leader_list_my_members()` → membership rows (sanitized: driver display name, phone last 4, zone, joined_at).
- `leader_list_my_commissions(p_status text default null)` → commission rows for own group.
- `leader_list_my_referrals(p_status text default null)` → referrals for own group.
- `leader_get_my_stats(p_from date, p_to date)` → counts/sums (see §5).

**Frontend**
- New route `/leader` → `src/pages/LeaderPortal.tsx`.
- Tabs: Vue d'ensemble · Chauffeurs · Parrainages · Commissions.
- Strictly read-only. No approve, no edit %, no assignment. CTA "Contacter l'admin" for changes.
- Routing guard: redirect to `/` if user has no group; show empty state if group `suspended`.

## 3. Terminology cleanup

- Replace "Référrals" / "Référral" with **"Parrainages"** / **"Parrainage"** everywhere in `DriverGroupsAdmin.tsx`, leader portal, docs.
- Update `docs/drivers/DRIVER_SYNDICATES_V0.md` (rename copy only; file path stays).

## 4. Zones: controlled vocabulary

- Switch `assigned_zones text[]` UX from free-form input to multi-select fed by `public.zones` (existing table).
- Migration: add `assigned_zone_ids uuid[]` on `driver_groups` and `driver_group_memberships`. Keep `assigned_zone(s)` text columns for backwards compatibility, populated via trigger from the joined `zones.name`.
- `GroupFormSheet` and `AssignDriverDialog`: replace `<Input>` with a checkbox/combobox sourced from `zones` (active only).
- Polygon coverage stays out of scope (noted as v2 in doc).

## 5. Performance analytics

- New RPC `admin_driver_group_stats(p_group_id uuid default null, p_from timestamptz, p_to timestamptz)` returning per-group:
  - active_drivers, rides_completed, gross_driver_earnings_gnf, commissions_pending_gnf, commissions_paid_gnf, signup_bonus_eligible_count, signup_bonus_paid_gnf.
- Admin: new "Analytics" tab in `DriverGroupsAdmin` with date range + per-group table + totals.
- Leader portal: same numbers scoped to own group via `leader_get_my_stats`.

## Security & QA matrix

- RLS unchanged on existing tables; all new access through SECURITY DEFINER RPCs with explicit role gates.
- Verify: non-leader cannot call `leader_*` RPCs; non-admin cannot call `wallet_pay_driver_commission`; paying a commission twice is rejected; reversal debits exactly the original amount; analytics totals reconcile against raw tables; build clean; security linter clean for new objects.

## Files (planned)

- migrations: `wallet_pay_driver_commission` + `leader_*` RPCs + `admin_driver_group_stats` + zone columns
- edits: `src/lib/admin/driverGroups.ts`, `src/pages/admin/DriverGroupsAdmin.tsx`, `src/App.tsx`, `docs/drivers/DRIVER_SYNDICATES_V0.md`
- new: `src/pages/LeaderPortal.tsx`, `src/lib/leader/driverGroup.ts`

## Lock candidate
`driver-groups-syndicates-v1-stable`

## Open question before build
Should the leader portal entry point live in the main bottom nav for users whose `auth.uid()` is a `driver_groups.leader_user_id`, or be reachable only via a direct `/leader` link (admin-shared)? Default if no answer: direct link only, no nav change.
