# Driver Groups / Syndicates — v5

_Stable candidate: `driver-groups-syndicates-v5-scorecards-exports-ops-stable`._

## What's new in v5

1. **Scheduled milestone processing.** `pg_cron` is enabled, and
   `process_driver_referral_milestone_jobs_cron(100)` runs every 10 minutes.
   Runs are logged to `driver_referral_milestone_job_runs`. Admins still have
   a manual "Actualiser les jalons" button.
2. **Field check-in photos.** Private bucket `driver-group-checkins`. Path
   layout `{group_id}/{checkin_id|timestamp}.{ext}`. JPG/PNG/WebP, ≤ 5 MB.
   Leaders upload/read only their own group; admins/ops manage all. Customers
   and unrelated drivers have no access. Signed URLs only.
3. **Polygon / zone coverage.** No real polygon geometry exists in
   `public.zones` yet (only commune/neighborhood labels). The admin Zone tab
   continues to show label-based coverage and a clearly worded
   "polygones à connecter" note. Polygon import is deferred to v6.
4. **Leader & group scorecards.** New RPCs `admin_group_scorecard(group, days)`
   and `leader_get_my_scorecard(days)` return real metrics computed from
   rides, referrals, commissions, check-ins. Admin Scorecards tab adds 7/30/90
   day filters and a metric grid. Leader portal adds a compact scorecard tile
   on Vue d'ensemble with a "next recommended action" line.
5. **Payout statement exports.** Richer CSV with period/group/leader columns
   via `downloadStatementCsvRich`. PDF export is deferred (V6) — UI clearly
   says so and falls back to CSV + printable HTML.
6. **Risk scorecard.** `score_driver_referral_risk_v2` returns `score`,
   `level` (clear/low/medium/high), and `reason_codes text[]`. New aggregate
   `admin_group_risk_scorecard()` powers the admin "Risque (scorecard)" tab.
   Strictly review-only — no auto-ban, no auto-freeze, no auto-deduction.
7. **Incentive optimization suggestions.** `admin_incentive_suggestions()`
   surfaces operational hints (low active drivers, risk-held concentration,
   uncovered zones) in an admin-only tab. Suggestions never touch money.
   Labelled "Suggestions opérationnelles", not "AI decisions".

## Security & wallet integrity

- No frontend wallet mutation. Payouts continue to go through the v1 backend
  RPC `wallet_pay_driver_commission_batch`.
- All new RPCs are `SECURITY DEFINER`, `SET search_path = public`, `REVOKE
  PUBLIC`, scoped by `_is_ops_or_god_admin` or leader ownership.
- Storage policies on `storage.objects` scope the new bucket to
  group leaders (path-based check) and admins/ops only.

## v6 roadmap

- Polygon import for `zones` and real geometry-based coverage.
- PDF payout statements with CHOPCHOP branding.
- Driver retention proxy + cancellation rate in scorecards.
- Leader push notifications when risk holds occur.
- Zone-level demand signals for incentive suggestions (requires ride
  request-without-fulfilment data).