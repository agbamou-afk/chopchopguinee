# Driver Syndicates v4 — Async jobs, field ops, lifecycle, risk audit

Builds on v3. Focus: keep ride completion fast, add real field-ops tooling, mature payout statements, and audit every risk decision.

## Async milestone refresh
- New queue table `driver_referral_milestone_jobs` (`pending → processing → processed / failed`).
- The previous synchronous trigger has been replaced by `_dr_milestones_enqueue_on_ride`, which only enqueues a job row when a referred driver completes a ride. Ride completion no longer runs the heavy milestone computation.
- `process_driver_referral_milestone_jobs(p_limit)` is the admin processor: locks rows with `FOR UPDATE SKIP LOCKED`, calls `refresh_driver_referral_milestones(driver)`, marks each job processed (or retries up to 5 times before `failed`).
- `admin_enqueue_milestone_refresh(driver_id, event)` lets ops backfill or trigger a refresh manually.
- No scheduler is installed yet — admin clicks **"Actualiser les jalons"** in the `Jalons` tab. A pg_cron job at 5–15 min cadence is the recommended v4.x follow-up.

## Field check-ins
- `driver_group_field_checkins` records leader/admin field activity tied to group/zone/driver with optional GPS, notes, photo, and a typed `checkin_type` (`field_visit`, `recruitment_visit`, `driver_meeting`, `market_station`, `issue_report`, `training`).
- Leaders insert/read only their own group's check-ins. `issue_report` requires notes.
- Admins see all check-ins via `admin_list_field_checkins`.
- This is intentionally not continuous tracking — it is operational logging.

## Payout statement lifecycle
- Added `finalized_by`, `paid_by`, `voided_by`, `void_reason` to `driver_group_payout_statements`.
- `admin_set_statement_status` now requires a reason on `void`, records the actor on each transition, and writes an audit row to `driver_group_risk_reviews`.
- "Mark paid" still requires every linked commission to be `paid` (only the wallet RPC can flip a commission to paid).
- Held risk items are still excluded at generation time.

## Risk operations + audit
- New `driver_group_risk_reviews` table captures every clear/hold/reject/release decision with reason, actor, entity (`referral` / `commission` / `payout_statement` / `group`).
- `admin_review_referral_risk` and `admin_review_commission_risk` now require a reason for `hold`, `reject`, and `release` actions, and always insert an audit row.
- `release` is supported as a first-class action that returns risk_status to `clear` (audited as `released`).
- Risk decisions still never auto-ban/freeze a user.
- Admin gets a new **Audit risque** tab showing the decision log.

## Zone coverage
- v3 `admin_zone_coverage_stats` continues to power the `Zones` tab.
- Polygons: no public table currently exposes polygon geometry in production. The UI continues to show label-based coverage and states explicitly that polygon mapping is a v5 item — no fake heatmaps.

## Leader portal v4
- New **Check-ins** tab + "Nouveau check-in terrain" sheet (type, notes, optional GPS).
- Generic risk-hold notice surfaces when any of the leader's commissions or referrals are non-clear: *"Certains paiements peuvent être temporairement en vérification par l'équipe CHOPCHOP."* No sensitive risk details are exposed.
- Existing read-only access to campaigns, contracts, finalized statements is unchanged.

## Admin UI v4
New tabs in `DriverGroupsAdmin`: **Audit risque**, **Jalons**, **Check-ins** (in addition to v3 tabs).

## Security
- All v4 tables RLS-on. Admins manage; leaders scoped to their group; no anon or customer access.
- All v4 RPCs are `SECURITY DEFINER`, `SET search_path = public`, `REVOKE PUBLIC`, `GRANT EXECUTE TO authenticated, service_role`, with explicit role/ownership checks.
- No wallet code paths changed. Wallet writes remain exclusively in v1 wallet RPCs.

## v5 roadmap
- Scheduled milestone processor via `pg_cron`.
- Polygon-based zone coverage with PostGIS, route ↔ zone attribution.
- Photo uploads to private storage bucket for check-ins.
- Driver-side check-in submissions for own group.
- Risk model upgrade with device/IP fingerprints.