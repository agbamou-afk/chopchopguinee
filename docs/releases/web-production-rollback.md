# Web Production Rollback Instructions (`web-rc-1`)

## 1. Trigger conditions

| Severity | Trigger | Action |
|---|---|---|
| SEV-1 | money corruption, duplicate charge, cross-role data access, auth bypass, sandbox contamination in production | immediate flag kill, then code rollback |
| SEV-2 | a launch role cannot complete its primary mission | flag-kill the affected module, fix forward |
| SEV-3 | degraded but recoverable | monitor, patch next release |

## 2. Feature-flag emergency disable (fastest lever, no deploy)

Execute in order; each is a single `enabled` update on `feature_flags` and takes
effect on the next client flag load. **Never delete rows** — flipping `enabled`
preserves `updated_at` as the audit trail.

1. `om_checkout_enabled = false`
2. `om_ride_checkout_enabled`, `om_repas_checkout_enabled`, `om_marche_checkout_enabled = false`
3. `om_sandbox_enabled = false`, `om_environment = false`
4. `wallet_public_enabled = false`
5. `agent_topup = false` — **payment intake shutdown** (stops new top-up intake)
6. `driver_mode = false` — stops new offers; active missions keep server state
7. `repas = false` / `marche = false` — closes the affected vertical
8. `scanner = false` — only if the QR handshake is the failing surface

## 3. Application-code rollback

1. Identify the last-known-good SHA from the milestone file.
2. Re-publish that SHA (frontend).
3. Re-deploy Edge Functions from that SHA **only** if a function changed in the
   bad release.

## 4. Handling in-flight paid missions

Rides, orders and offers are server-authoritative. A frontend rollback does not
change mission state. After rolling back:

1. List `payment_intents` created in the bad window; classify
   authorized-but-not-finalized.
2. Finalize each through the normal server path, or open a `support_issues`
   recovery record. **Never** mark success without a real provider reference.
3. Check `payment_refund_requests` and `payment_reconciliation_events` for orphans.
4. Confirm master wallet delta equals expected fee capture only.
5. Drivers on active missions complete them normally; only new dispatch is paused.

## 5. Database migration constraints — read carefully

**Migrations are forward-only and are not rolled back.** Every migration in the
Android 1.0 line must be additive and backward-compatible (new nullable columns,
new tables, new functions) so the previous frontend still works against the
newer schema.

Honest limitation: any migration that drops a column, drops a table, narrows a
type, or rewrites data **is not reversible** without a point-in-time restore, and
a point-in-time restore would discard all financial activity recorded after the
restore point. Such a migration must not ship in this line; if one is
unavoidable it requires its own release phase with an explicit backup and
reconciliation plan. Do not represent destructive migrations as reversible.

## 6. Service-worker / PWA handling

`registerType: autoUpdate` — a rollback publish emits a new `sw.js` that clients
adopt on the next navigation. A client stuck on a bad shell can be recovered
with the `?sw=off` kill switch. Never blanket-`caches.delete`: messaging workers
must survive.

## 7. Reconciliation after rollback

Run §4 to completion, then re-run the release smoke tests 1–10 and confirm zero
open recovery items.

## 8. Support communication

- In-app: honest banner ("service momentanément indisponible") — never a fake
  success or a silent failure.
- Support macro directing users to `/help/issues`.
- Driver notice: new offers paused, active missions unaffected.

## 9. Audit preservation

Do not delete flag rows, payment intents, refund requests, reconciliation
events, sandbox test runs or admin audit rows during a rollback. Archive, never
delete — archived sandbox rows are already frozen by `_om_sandbox_block_archived`.

## 10. Rollback rehearsal status

| Path | Status | Evidence |
|---|---|---|
| Feature-flag disable | **TESTED** | `om_sandbox_enabled` / `om_environment` flipped `true → false` in production (DEF-001), `updated_at 2026-07-28T17:17Z`; 0 sandbox and 0 production payment intents affected; UI returned to the honest non-sandbox state; no record corruption |
| Previous stable build re-publish | **NOT EXECUTED — YELLOW** | requires one real publish → rollback → re-publish cycle |
| In-flight mission visibility during rollback | **NOT EXECUTED** | depends on the cycle above |
| Admin access retained during rollback | **NOT EXECUTED** | depends on the cycle above |
