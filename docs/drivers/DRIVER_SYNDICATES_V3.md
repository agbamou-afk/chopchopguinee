# Driver Syndicates v3 — Campaigns, milestones, contracts, payouts, risk

Builds on v0 (groups/memberships/referrals/commissions), v1 (wallet-safe payout RPC, leader portal, analytics), and v2 (controlled Conakry zones, referral codes, batch payouts, fraud guardrails).

## Highlights

### Recruitment campaigns
- New `driver_recruitment_campaigns` table tied to a group, optional leader, zones, dates, targets, bonus, and milestone rule.
- Admin RPCs: `admin_create_campaign`, `admin_update_campaign`, `admin_attach_referral_campaign`.
- Leaders read their own via `leader_list_my_campaigns()`.
- Driver referrals can be attached to a campaign for attribution.

### Bonus milestones
Each referral carries a `milestone_rule` (default `approved`). Supported rules:
- `approved` — driver approved by admin
- `first_ride_completed` — one completed ride
- `five_rides_completed` — five completed rides
- `seven_days_active` — approved + 7 days since approval

Backend `refresh_driver_referral_milestones(p_driver uuid)` recomputes status; trigger `trg_dr_milestones_on_ride` runs after `rides.status` becomes `completed` (failure is logged, never blocks the ride). Status flow: `pending → milestone_pending → met → bonus_eligible → paid` (or `not_met` / `rejected`).

Guardrails preserved from v2:
- One bonus per driver (`dr_unique_active_per_driver`).
- Rejected / held referrals cannot be paid by the batch RPC.
- Wallet credits only via the v1 `wallet_pay_driver_commission*` RPCs.

### Performance contracts
- `driver_group_contracts` records targets per leader/group (drivers, rides, earnings, zones, optional commission override / bonus pool, terms).
- Admin RPCs: `admin_create_contract`, `admin_update_contract`.
- Leaders read their own via `leader_list_my_contracts()`.

### Payout statements
- `driver_group_payout_statements` + `driver_group_payout_statement_items` aggregate approved/paid commissions and bonus_eligible/paid referrals for a date range. Risk-held items are excluded.
- Admin RPCs: `admin_generate_payout_statement`, `admin_set_statement_status` (`draft / finalized / paid / void`).
- "Mark paid" requires every linked commission to already be `paid` (commissions can only become paid via the wallet RPC). No wallet writes happen here.
- Leaders read `finalized`/`paid` statements for their own group only, plus their items. CSV export from the admin UI for offline use.

### Zone coverage intelligence
- `admin_zone_coverage_stats()` returns active/total drivers and group counts per service zone, based on v2 controlled zones. Pickup/dropoff polygon mapping is deferred to v4.

### Risk scoring
- `score_driver_referral_risk(p_referral)` returns `{ score, status, reason }` from heuristic signals: suspended driver/group, no rides after approval, rapid-fire 24h volume.
- Admin can `clear / hold / reject / review` flagged items via `admin_review_referral_risk` / `admin_review_commission_risk`. Risk decisions never auto-ban a user; admin must act.
- `risk_status='held' | 'rejected'` blocks payout inclusion in statements.

## Security
- All mutation RPCs are `SECURITY DEFINER`, `SET search_path = public`, `REVOKE PUBLIC` then `GRANT EXECUTE ... TO authenticated, service_role`, with explicit admin gates.
- New tables: admin manage-all, leader read own (campaigns/contracts), leader read finalized statements for own group only. No customer/anon access.
- Wallet integrity unchanged — no balance mutation outside the v1 wallet RPCs.

## Leader portal v3
New sections in `/leader`: Campagnes, Contrats, Relevés. All read-only.

## Admin UI v3
New tabs in `DriverGroupsAdmin`: Campagnes, Contrats, Relevés, Risque, Zones.

## V4 roadmap
- Pickup/dropoff polygon-based zone analytics.
- Device/IP signals for risk scoring.
- Automated payout statement scheduling.
- Leader OTP attestation when contesting flagged items.