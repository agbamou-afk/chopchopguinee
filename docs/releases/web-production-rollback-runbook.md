# Web Production Rollback Runbook (`web-rc-1`)

## Severity triggers

| Severity | Trigger | Action |
|---|---|---|
| SEV-1 | money corruption, duplicate charge, cross-user data access, auth bypass, sandbox contamination | immediate flag kill + deployment rollback |
| SEV-2 | a role cannot complete its primary mission | flag kill for that module, hotfix forward |
| SEV-3 | degraded but recoverable | monitor, patch in next release |

## Step 1 — Emergency feature-flag kill order (fastest lever, no deploy)

Execute top to bottom. Each is a single `feature_flags` update and takes effect
on the next client flag load.

1. `om_checkout_enabled = false` — stops all OM checkout orchestration.
2. `om_ride_checkout_enabled`, `om_repas_checkout_enabled`, `om_marche_checkout_enabled = false`.
3. `om_sandbox_enabled = false`, `om_environment = false` — kills any sandbox leakage.
4. `wallet_public_enabled = false` — hides all public balance surfaces.
5. `driver_mode = false` — stops new driver offers (active missions keep server state).
6. `repas = false` / `marche = false` — closes the affected commerce vertical.
7. `agent_topup = false` — stops new top-up intake.
8. `scanner = false` — disables QR handshake if it is the failing surface.

Never delete rows. Flip `enabled` only, so the audit trail (`updated_at`) is preserved.

## Step 2 — Deployment rollback

1. Identify last-known-good SHA from `docs/releases/web-production-release-candidate.md`.
2. Re-publish that SHA from Lovable (frontend only).
3. Re-deploy Edge Functions from that SHA if any function changed in the bad release.

## Step 3 — Database compatibility rule

**Migrations are never rolled back.** Every migration in the Android 1.0 line
must be additive and backward-compatible (new nullable columns, new tables, new
functions) so the previous frontend keeps working against the newer schema.
If a migration is not backward-compatible it must not ship; fix forward instead.

## Step 4 — PWA / service-worker cache handling

- `registerType: autoUpdate` — a rollback publish emits a new `sw.js`; clients
  adopt it on the next navigation.
- If a client is stuck on a bad shell, the kill switch `?sw=off` unregisters the
  app service worker.
- Never blanket-`caches.delete` — messaging workers must survive.

## Step 5 — Payment / mission reconciliation after rollback

1. Freeze manual OM verification (`om_provider_mode` already false).
2. List `payment_intents` created during the bad window; classify
   authorized-but-not-finalized.
3. For each, either finalize via the normal server path or open a
   `support_issues` recovery record. **Never** mark success without a real
   provider reference.
4. Cross-check `payment_refund_requests` and `payment_reconciliation_events`
   for orphans.
5. Verify master wallet delta equals expected fee capture only.

## Step 6 — Communications

- In-app: honest banner ("service momentanément indisponible"), no fake success.
- Support: pre-seeded macro pointing users to `/help/issues`.
- Drivers: notify that new offers are paused; active missions still complete.

## Step 7 — Recovery validation

Re-run the deploy runbook post-deploy smoke order 1–10, then confirm zero open
recovery items from Step 5.

## Rollback test status

- **Flag rollback: TESTED.** Sandbox flags were flipped `true → false` in
  production during this phase (DEF-001) with no data corruption and an intact
  `updated_at` audit trail; UI returned to the honest non-sandbox state.
- **Deployment rollback: NOT YET EXECUTED (YELLOW).** Requires one real
  publish→rollback→re-publish cycle against production hosting. This is the
  remaining gate item for §L.
