# Chop Pay — Slice 2 (Finance Policy + Control Plane) QA results

**Date:** 2026-08-09 · **Status:** PASS (33/33) · **Locks:** none — both
`chop-pay-ledger-revival-stable` and `web-production-release-candidate-stable`
remain UNLOCKED.

Authority: `docs/product/chop-pay-canonical-operating-policy.md`.

## Harness

`public._qa_s2_run()` — self-rolling-back (raises at the end, discards all rows).
Executed once, then **dropped** from the database. No QA rows, roles, audit rows
or ledger postings survived (verified: 0 QA audit rows, 0 temp roles, delegation
back to `false`, 11 enabled flags unchanged).

## Results

| Group | Assertions | Result |
| --- | --- | --- |
| Economic resolution (ride, bonbonna, repas, marché, envoyer) | T1–T5 | PASS |
| Snapshot validator (canonical / ambiguous basis / >100% coverage) | T22a–c | PASS |
| Effective dating + snapshot stability | T6–T10, T12, T13 | PASS |
| Append-only / monotonic scheduling | T14a–c | PASS |
| Audit evidence on God Admin writes | T17 | PASS |
| Payout policy invariants | T19 | PASS |
| Role separation (finance / ops / anon) + delegation | T15a–f, T16a–c, T18 | PASS |
| Flag state (all financial OFF, `om_topup_enabled` ON) | T20 | PASS |
| Posted journals untouched by policy edits | T11 | PASS (see YELLOW) |

## YELLOW

- **T11 is currently vacuous**: `ledger_postings` holds 0 rows, so "journals
  unchanged by policy edits" passed trivially. Re-run this assertion during
  Slice 3 once live missions post journals.
- **DEF-FIN-001 still open**: platform master wallet balance is
  −100 435 GNF from pre-ledger history. Not touched by Slice 2; requires an
  authorized reconciliation slice.

## Build

- `tsgo --noEmit` clean, `vite build` green.
- PWA precache 129 entries / ~11.8 MiB, individual-file limit 4 MiB unchanged.

---

# Slice 2 — final hardening / exit-gate correction

**Date:** 2026-08-09 · **Status:** PASS (20/20 targeted) · **Locks:** none —
`chop-pay-ledger-revival-stable` and `web-production-release-candidate-stable`
remain UNLOCKED. No live mission wiring, no financial capability enabled.

## Defects fixed

| ID | Sev | Defect | Fix |
| --- | --- | --- | --- |
| DEF-S2X-01 | P1 | `admin_set_finance_policy` inherited from `finance_policy_current(now())`, so a policy scheduled after another scheduled policy silently regressed to today's economics | New `finance_policy_predecessor(mission_type, effective_from)`; all inherited values **and** the audit `before` object come from the immediate predecessor. UI mirrors it with `predecessorPolicy()` and recomputes base + diff whenever the effective date changes, labelling the base as *en vigueur* or *programmée* |
| DEF-S2X-02 | P1 | Controls panel wrote with a hardcoded note, no effective date, no diff | Starter bonus, payout, merchant settlement and provider fee now use the same effective-date + mandatory-reason + before/after diff flow, with current / next scheduled / immutable history per section. Server enforces a ≥5-char reason on every setter |
| DEF-S2X-03 | P1 | Merchant settlement panel unusable: `p_configured` echoed the current row, no cadence editor, `manual` fallback violated the DB check, blank inputs coerced to `0` | Explicit configured toggle, cadence selector over the exact DB enum plus a null state, null-preserving numeric inputs, server validation (`INVALID_SETTLEMENT_CADENCE`, cadence + minimum required when configured), `requires_evidence_reconciliation` untouched |
| DEF-S2X-04 | P1 | `/admin/flags` wrote the table directly; RLS still allowed God Admin table writes | Policy `God admins write flags` dropped; `INSERT/UPDATE/DELETE` revoked from `anon` + `authenticated`. `admin_set_feature_flag` (SECURITY DEFINER, God-Admin-only, reason-required) is the single path. `/admin/flags` and the finance Controls panel both confirm with a reason dialog. Controls now surfaces all 17 canonical finance flags |
| DEF-S2X-05 | P2 | Envoyer snapshot omitted `claims_exposure_max_gnf` because the legacy row is NULL | Snapshot v2 resolves it (`claims_exposure_max_source: derived`), keeps `claims_exposure_pct_bps` + `claim_envelope_gnf`, adds explicit `cash_funding_basis`; validator rejects an envelope above the resolved max. Future Envoyer rows persist the derived max unless a lower cap is set explicitly. Historical rows were **not** mutated |

## Targeted rollback QA (`public._qa_s2x_run()`, self-rolling-back, dropped after)

| # | Assertion | Result |
| --- | --- | --- |
| T1/T2 | B scheduled after A; C after B keeps B's 12 % commission while changing only cancellation | PASS |
| T3 | Repas: fee-only row after a collateral row keeps 30 % collateral | PASS |
| T4 | Envoyer future row at a 400 000 cap persists derived max 100 000 | PASS |
| T5 / T16 | Reason shorter than 5 chars rejected (policy + flag) | PASS |
| T6 | Starter bonus second future row chains from the latest scheduled row | PASS |
| T8 | Payout second future row chains safely | PASS |
| T9 | Unconfigured settlement keeps NULL min / cadence / fee (never 0) | PASS |
| T10 | Configured settlement with `weekly` succeeds | PASS |
| T11 | Cadence `manual` rejected | PASS |
| T12 | Delegated Finance Admin provider-fee row written **and** audited with a human reason | PASS |
| T13/T14 | Finance Admin cannot change service economics or toggle a flag | PASS |
| T15 | God Admin flag RPC succeeds and is audited | PASS |
| T17 | `authenticated`/`anon` have no UPDATE on `feature_flags`; SELECT retained | PASS |
| T18 | All 17 canonical finance flags present, no duplicates | PASS |
| T19 | Envoyer snapshot @500 000: pct 2500, resolved max 125 000, envelope 125 000, `cash_funding_basis: none` | PASS |
| T20 | Validator accepts the snapshot, rejects a 999 999 envelope | PASS |
| T21 | Snapshot unchanged after a later Envoyer edit | PASS |

Cleanup verified after rollback: 0 QA audit rows, 0 QA policy rows, 0
`finance_admin` roles, delegation back to `false`, harness function and scratch
table dropped.

## Flag state after QA

`om_topup_enabled = true`; all 16 other canonical finance flags `false`.

## Build evidence

- `tsgo --noEmit` clean.
- `vite build` green — PWA 129 entries / 11 854.99 KiB, 4 MiB per-file limit unchanged.
- **UI screenshots not captured**: the sandbox browser session is `signed_out`,
  so `/admin/finance-policy` redirects to `/auth`. No production policy write was
  performed through the UI; all evidence above is DB-level rollback evidence.

## Unchanged

- DEF-FIN-001 (platform master wallet −100 435 GNF) untouched.
- T11 of the original Slice 2 run remains vacuous (`ledger_postings` still empty).
