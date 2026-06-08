# Driver Syndicate / Group Leader System — v0

**Routing:** Rides Agent (lead) · ChopWallet Agent (review ledger safety) · Admin & Ops Agent (review tab)

**Lock candidate:** `driver-groups-syndicates-commissions-v0-stable`

## Scope (v0)

Admin-only management. No leader portal yet. Commissions written as **pending ledger rows only** — no wallet credits in v0 (ChopWallet review gate). Default 1%, configurable per group.

## A. Database (one migration)

Tables (all `public`, with GRANTs + RLS + admin-only policies via `is_admin(auth.uid())` or `has_role`):

1. **`driver_groups`** — id, name, description, leader_user_id (nullable, fk profiles), leader_name, leader_phone, status (`active|suspended|archived`, default active), commission_percent numeric default 1.00, signup_bonus_gnf bigint default 0, assigned_zones text[] default '{}', referral_code text unique nullable, notes, created_by, created_at, updated_at.
2. **`driver_group_memberships`** — id, group_id fk, driver_user_id uuid, driver_profile_id fk driver_profiles nullable, status (`active|removed|pending`), assigned_zone text, joined_at, added_by, removed_at, removed_by, notes. **Partial unique index** on `(driver_user_id) WHERE status='active'`.
3. **`driver_referrals`** — id, group_id, referrer_user_id, referred_driver_user_id, referral_code, status (`pending|approved|bonus_eligible|paid|rejected`), bonus_amount_gnf bigint, approved_at, paid_at, created_at, metadata jsonb.
4. **`driver_group_commissions`** — id, group_id, leader_user_id, driver_user_id, source_type (`ride_earning|signup_bonus|adjustment`), source_id uuid, gross_driver_earning_gnf bigint, commission_percent numeric, commission_amount_gnf bigint, status (`pending|approved|paid|reversed`, default pending), wallet_transaction_id uuid nullable, created_at, approved_at, paid_at, notes. **Unique** on `(source_type, source_id, driver_user_id)` to prevent double-write.

All four tables: `GRANT SELECT,INSERT,UPDATE,DELETE ... TO authenticated; GRANT ALL ... TO service_role;` plus RLS policies that only admin roles can read/write (drivers may `SELECT` their own membership row in v0; no leader access).

## B. RPCs (SECURITY DEFINER, `set search_path=public`, REVOKE PUBLIC, admin gate)

- `admin_create_driver_group(payload jsonb)` → uuid
- `admin_update_driver_group(p_group uuid, payload jsonb)`
- `admin_assign_driver_to_group(p_group uuid, p_driver uuid, p_zone text, p_notes text)` — enforces one-active-membership rule.
- `admin_remove_driver_from_group(p_membership uuid, p_reason text)`
- `admin_review_commission(p_commission uuid, p_action text, p_notes text)` — pending→approved→paid (paid path is a no-op in v0, just sets status + timestamp; **no wallet mutation**).
- `admin_mark_referral(p_referral uuid, p_action text)`

### Trigger: commission auto-creation
`trg_ride_commission_after_complete` on `public.rides` AFTER UPDATE when `status` transitions to a completed/paid terminal state (whatever the rides agent currently uses — read existing earnings column; if no driver_earning column exists yet, no-op safely):
- look up active membership for `driver_user_id`
- if found and group active and commission_percent > 0:
  - insert `driver_group_commissions` row (`source_type='ride_earning'`, `source_id=ride.id`, status=`pending`)
  - ON CONFLICT do nothing (idempotent)

Reversal hook (best-effort): if a ride is later cancelled/refunded, set matching commission row to `reversed`.

### Trigger: on driver approval (`driver_applications` → approved)
- If a `driver_referrals` row exists for that user with status `pending`, set to `bonus_eligible` and copy `signup_bonus_gnf` from the group as `bonus_amount_gnf`.
- Activate matching pending `driver_group_memberships` (status `pending`→`active`).

## C. Admin UI

New module `driver_groups` in `src/lib/admin/permissions.ts` (god_admin: ALL; operations_admin: view+edit; finance_admin: view+approve).

New page `src/pages/admin/DriverGroupsAdmin.tsx` at route `/admin/driver-groups`, added to `AdminSidebar` under **Opérations** as **"Groupes chauffeurs"** (icon: `Users2`).

Sub-views (tabs inside the page):
- **Vue d'ensemble** — Stat cards: groupes, leaders actifs, chauffeurs assignés, chauffeurs non assignés, commissions en attente (sum GNF), bonus en attente.
- **Groupes** — table + "Créer un groupe" sheet (name, leader pick/manual, phone, commission %, signup bonus, zones multi-select from district hubs, notes).
- **Détail groupe** (drawer) — leader info, drivers table with assign/remove, zone chips, commission ledger, signup bonus list.
- **Commissions** — global ledger with filters and approve/mark-paid actions.
- **Référrals / Bonus** — list with mark-paid/reject.

All empty states: `"Aucun groupe chauffeur configuré."` etc. No mock data.

## D. Wallet / Ledger safety

**v0 does not credit wallets.** `paid` status is admin bookkeeping only; `wallet_transaction_id` stays NULL until ChopWallet agent provides a secure payout RPC in a follow-up. The UI clearly labels paid-status as "Marqué payé (hors-wallet)" with a tooltip explaining v1 will wire `wallet_internal_transfer`.

## E. Security

- Admin-only RLS via `has_role(auth.uid(),'admin')` / `is_admin()` (use whichever helper already exists in project).
- Driver may `SELECT` own membership row (`driver_user_id = auth.uid()`).
- No anon grants.
- RPCs `REVOKE EXECUTE ... FROM PUBLIC; GRANT EXECUTE ... TO authenticated;` with internal admin check that raises on non-admin.
- Linter run after migration; resolve any new warnings tied to these objects.

## F. Files touched

**Created**
- `supabase/migrations/<ts>_driver_groups_v0.sql`
- `src/pages/admin/DriverGroupsAdmin.tsx`
- `src/components/admin/driver-groups/GroupFormSheet.tsx`
- `src/components/admin/driver-groups/GroupDetailDrawer.tsx`
- `src/components/admin/driver-groups/AssignDriverSheet.tsx`
- `src/lib/admin/driverGroups.ts` (typed RPC + query helpers)
- `docs/drivers/DRIVER_SYNDICATES_V0.md`

**Edited**
- `src/lib/admin/permissions.ts` — add `driver_groups` module.
- `src/components/admin/AdminSidebar.tsx` — add nav entry.
- `src/App.tsx` — add lazy route under admin layout.
- `.lovable/plan.md` — append milestone entry.

## G. QA matrix

A create group · B assign leader (no admin powers) · C assign driver (one-active enforced) · D ride completes → pending commission row appears · E 1% math verified on sample · F change % → next ride uses new % · G approve driver with pending referral → bonus_eligible · H suspended driver group → no new commission · I non-admin user blocked by RLS+RPC · J admin tab shows real rows or honest empty states · K build clean · L security linter no new errors.

## H. Blockers to surface before coding

1. **Driver earnings field on `rides`**: I'll read `rides` columns first; if no per-driver-earning column exists, commission trigger uses `fare_gnf` minus platform fee if present, otherwise stores `gross_driver_earning_gnf=0` and logs a TODO in the commission row's `notes`. Will report exactly what's used in the final return.
2. No frontend wallet write anywhere in this feature — confirmed by design.

Proceed?
