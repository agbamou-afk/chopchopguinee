# Orange Money Sandbox — Admin Guide

Route: `/admin/payments/sandbox` (God Admin & Finance Admin read; simulation & archive are God Admin only).

## Role matrix

| Role              | Access                                                                 |
|-------------------|------------------------------------------------------------------------|
| God Admin         | Full read + simulate + complete + archive + mock-driver                |
| Finance Admin     | Read-only inspection of metrics, runs and correlated logs              |
| Operations Admin  | No access (no financial simulation controls)                            |
| Ordinary user     | No access (own refund status only in OM Wallet)                        |

## Enable / disable safely

1. Set `om_environment=true` and `om_sandbox_enabled=true` in `/admin/flags`.
2. Run controlled tests.
3. Restore both to `false` after QA. The status banner turns amber and simulation disables.

`om_provider_mode` stays `manual` in production regardless of sandbox flags.

## Deterministic fixtures

| Fixture                       | Outcome                                  |
|-------------------------------|------------------------------------------|
| `OM-SBX-SUCCESS-001`          | intent → authorized                      |
| `OM-SBX-REVIEW-001`           | intent → needs_review                    |
| `OM-SBX-REJECT-001`           | intent → failed                          |
| `OM-SBX-EXPIRED-001`          | intent → expired                         |
| `OM-SBX-DUPLICATE-001`        | duplicate branch, intent stays pending   |
| `OM-SBX-FINALIZE-FAIL-001`    | finalization KO + support issue          |
| `OM-SBX-REFUND-001`           | refund → paid, intent → refunded         |
| `OM-SBX-REFUND-REVIEW-001`    | refund → needs_review + support issue    |

## Test-run lifecycle

- Auto-registered on first sandbox activity (backfill covers pre-existing runs).
- God Admin can `complete` or `archive` from the run detail sheet.
- `om_sandbox_archive_test_run(uuid, notes)` refuses mixed/live runs, marks records with `sandbox_archived_at`, and returns per-table counts.
- Archived runs are frozen by a BEFORE trigger on `payment_intents` and `payment_refund_requests`.
- Idempotent replay is safe.

## Financial isolation invariant

Sandbox never invokes any `wallet_*` function. Ride cancellation fee is
recorded on the refund row only and is never captured to the master
wallet. Master wallet delta = 0 across every sandbox cycle.

## Production defaults after QA

- `om_sandbox_enabled = false`
- `om_environment = false`
- `om_provider_mode = manual`
- `wallet_public_enabled = false`

## Known limitations

- Ride quote uses `fare_settings` base + per-km only (matches production).
- Finance Admin inspects but does not simulate or archive.
- No broad purge RPC — archival is the sole cleanup surface (preserves audit trail).
