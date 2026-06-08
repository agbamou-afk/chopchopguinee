# Driver Syndicates / Group Leaders — v0

Admin-managed groups of drivers under a syndicate leader. Default commission **1%** of driver net earnings per completed ride. Configurable per group.

## Data
- `driver_groups` — group config (commission %, signup bonus, zones, leader).
- `driver_group_memberships` — drivers assigned (one active per driver, enforced by partial unique index).
- `driver_referrals` — signup attribution + bonus eligibility.
- `driver_group_commissions` — pending ledger of leader commission per ride (unique on `(source_type, source_id, driver_user_id)`).

## Triggers
- `trg_ride_commission_after_complete` on `public.rides` writes a `pending` commission row when a ride transitions to `completed`, using `driver_earning_gnf * commission_percent / 100`. Reverses if the same ride is later cancelled.
- `trg_driver_group_on_approval` on `public.driver_profiles` activates pending memberships and marks pending referrals `bonus_eligible` (copying the group's `signup_bonus_gnf`).

## RPCs (admin-only, SECURITY DEFINER, search_path=public, REVOKE PUBLIC)
- `admin_create_driver_group(payload)`
- `admin_update_driver_group(p_group, payload)`
- `admin_assign_driver_to_group(p_group, p_driver, p_zone, p_notes)`
- `admin_remove_driver_from_group(p_membership, p_reason)`
- `admin_review_commission(p_commission, p_action)` — `approve | mark_paid | reverse`
- `admin_mark_referral(p_referral, p_action)` — `approve | mark_eligible | mark_paid | reject`

## Wallet safety (v0)
**No wallet mutation.** "Marqué payé" is admin bookkeeping only; `wallet_transaction_id` stays `NULL`. v1 will introduce a ChopWallet-reviewed payout RPC.

## Admin UI
`/admin/driver-groups` · sidebar "Groupes chauffeurs" (Opérations).
Tabs: Vue d'ensemble · Groupes · Membres · Commissions · Référrals.

## Permissions
- `god_admin`: ALL.
- `operations_admin`: view + edit.
- `finance_admin`: view + approve.
- Drivers can read their own membership row only. No leader portal in v0.
