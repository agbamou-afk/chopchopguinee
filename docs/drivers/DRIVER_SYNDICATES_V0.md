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

## Wallet (v1)
`wallet_pay_driver_commission(p_commission_id)` — finance/god admin only. Locks the commission row, validates `status='approved'` and absence of `wallet_transaction_id`, then debits the master wallet and credits the leader's driver wallet exactly once (idempotent via `reference='CC-COMM-<id>'`). Updates the commission to `paid` with the new `wallet_transaction_id`.

`wallet_reverse_driver_commission(p_commission_id, p_reason)` — debits the leader and credits the master wallet, marks the commission `reversed`, and writes a `CC-COMM-REV-<id>` ledger row. Idempotent.

No frontend wallet mutation. Both RPCs write `audit_logs` entries.

## Leader self-service portal
`/leader` — read-only. Auth required. RPCs (all SECURITY DEFINER, leader-gate `auth.uid() = driver_groups.leader_user_id`):
- `leader_get_my_group()` · `leader_list_my_members()` (sanitized: full name + phone last4) · `leader_list_my_commissions(p_status)` · `leader_list_my_referrals(p_status)` · `leader_get_my_stats(p_from, p_to)`.
Leader cannot approve drivers, change commission %, or assign drivers.

## Analytics
`admin_driver_group_stats(p_group, p_from, p_to)` returns per-group: active drivers, completed rides, gross driver earnings, commissions pending/paid, signup-bonus eligible count, signup-bonus paid. Surfaced in Admin → Driver Groups → Analytics tab and (own-group only) in the leader portal overview.

## Zones (v1 transition)
New columns `driver_groups.assigned_zone_ids uuid[]` and `driver_group_memberships.assigned_zone_id uuid` reference `public.zones`. A trigger keeps the legacy text columns (`assigned_zones`, `assigned_zone`) in sync from `coalesce(neighborhood, commune, city, kind)`. UI still accepts free-form text until `public.zones` is populated; controlled multi-select is wired to switch on automatically.

## Admin UI
`/admin/driver-groups` · sidebar "Groupes chauffeurs" (Opérations).
Tabs: Vue d'ensemble · Groupes · Membres · Commissions · **Parrainages** · Analytics.

## Permissions
- `god_admin`: ALL.
- `operations_admin`: view + edit (groups, memberships).
- `finance_admin`: view + approve + **pay commissions via ChopWallet**.
- Drivers can read their own membership row.
- Leaders use `/leader` (RPC-gated, no direct table access).
