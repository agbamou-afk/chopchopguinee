# Driver Groups / Syndicates — v2

Builds on v0 (groups, memberships, referrals, commissions, 1% default) and v1 (wallet payout RPCs, leader portal, Parrainages, analytics, controlled zone columns).

## What's new in v2

### Controlled zones
- `public.zones` seeded with 20 Conakry communes (Kaloum, Dixinn, Ratoma, Matam, Matoto, Coyah, Dubréka, Kipé, Lambanyi, Sonfonia, Cosa, Bambéto, Madina, Enta, Gbessia, Taouyah, Nongo, Wanindara, Hamdallaye, Coleah).
- Admin "Create group" and "Assign driver" UIs use a controlled selector when zones exist; legacy free-form text remains as fallback.
- Saved zone ids are mirrored to legacy `assigned_zones` text columns via the v1 trigger for backwards compatibility.

### Referral / recruitment codes
- Each `driver_groups.referral_code` is unique. Admins can regenerate via `admin_regenerate_group_referral_code(p_group, p_code)` (auto-generates `CHOP-<NAME>-NNNN` when no code is passed).
- Public lookup `validate_referral_code(p_code)` (authenticated only) returns `{ group_id, group_name, leader_name, status, valid }` — used by the driver application form for inline validation.
- Leader portal `/leader` now shows the active group code prominently with copy-to-clipboard.

### Driver application referral capture
- `DriverApply` step 6 (verification) exposes an optional **Code de parrainage** field with live validation.
- `driver_apply(p_payload)` reads `referral_code`, looks up the matching active group, and creates a `driver_referrals` row with status `pending` linked to that group and leader. It never grants the bonus and never assigns the driver to the group immediately. Invalid codes do not block submission.
- A leader cannot refer themselves (leader_user_id check).

### Driver approval → referral attribution
- When `driver_admin_decide` flips a driver to `approved`, the trigger `_driver_group_on_driver_approval`:
  1. Activates any `pending` memberships for that driver.
  2. Promotes their `pending` referral to `bonus_eligible`, copies the group's `signup_bonus_gnf`.
  3. **New in v2:** if the driver has no active membership, auto-activates one in the referring group.
- Admins still review every referral in the Parrainages tab and can approve / reject / mark eligible / mark paid.

### Fraud guardrails
- Partial unique index `dr_unique_active_per_driver` on `driver_referrals(referred_driver_user_id)` where `status <> 'rejected'` — guarantees **one signup bonus per driver**.
- Leaders cannot refer themselves.
- Commission ride trigger remains idempotent (unique source key on rides).
- `wallet_pay_driver_commission` and `_reverse_` remain the only paths that touch wallet balances; both are idempotent.
- Batch payout `wallet_pay_driver_commission_batch(p_commission_ids uuid[])` row-locks each commission, skips already-paid rows, and returns `{ paid_count, skipped_count, total_paid_gnf, errors[] }`.

### Admin payout workflow
- Commissions tab: filter by status (pending/approved/paid/reversed/all) and group; checkbox-select multiple rows; "Payer le batch (ChopWallet)" calls the batch RPC. Total preview before confirmation.
- All payments still flow through ChopWallet RPCs. **Zero frontend wallet mutation.**

### Leader portal v2
- Referral code panel with copy.
- Existing tabs: overview stats (7/30/90d), members (last-4 phone only), commissions, parrainages.
- Leader cannot edit anything, cannot see other groups, cannot see full phones or driver documents.

## Security
- All sensitive mutations go through `SECURITY DEFINER` RPCs gated by `_is_ops_or_god_admin`, `has_role(..., 'finance_admin')`, or `has_role(..., 'god_admin')`.
- `validate_referral_code` is `SECURITY DEFINER` but only exposed to `authenticated` — `anon` and `PUBLIC` are revoked.
- Driver approval, RLS on `driver_profiles`/`wallets`/`wallet_transactions` unchanged.

## v3 roadmap
- Polygon-based zone coverage and live driver-in-zone tracking.
- Configurable bonus milestones (`approved` / `first_ride` / `five_rides` / `seven_days_active`).
- Leader-side payout scheduling and tax receipts.
- Self-serve leader code regeneration with rate limits.
- Referral fraud scoring (device, IP, time-to-first-ride).
