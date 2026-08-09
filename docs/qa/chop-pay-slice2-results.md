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
