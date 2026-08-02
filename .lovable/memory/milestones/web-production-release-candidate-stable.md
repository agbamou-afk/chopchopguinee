---
name: Web Production Release Candidate
description: Release-freeze baseline web-rc-1 — RC freeze rules, mission matrix, defect register, secret audit, release/rollback/checklist docs. NOT LOCKED; OM real-money, SMTP inbox and deployment-rollback gates are YELLOW.
type: feature
---

# Web Production Release Candidate — `web-rc-1`

**Status: RELEASE CANDIDATE — LOCK WITHHELD**
Date: 2026-07-28 · Baseline: main after `orange-money-sandbox-ecosystem-ready-stable`

## Freeze rule (binding once locked)

After this lock, allowed Android 1.0 changes are limited to:
packaging / native integration · Android permissions · deep links ·
push-notification integration · safe-area & status-bar behaviour ·
Android-specific crash fixes · P0/P1 regressions.

Not allowed without reopening the web RC:
new business modules · new payment architecture · broad navigation changes ·
major role-flow redesign · new wallet model · major database state-machine
changes.

A future provider pivot is a **provider adapter plus its own tested release
phase**, never a silent insertion into the frozen Android baseline. Orange Money
stays the active launch rail; the intent/refund/reconciliation/ledger layers stay
provider-abstracted.

## Gate state at RC

GREEN: production build, typecheck, 12/12 tests, frontend secret sweep (0 source
maps, only the anon key, demo panel absent from bundle), sandbox flags OFF, RLS
on every public table, 0 error-level linter findings, feature-flag rollback
(materially tested), offline/low-data recovery, staff forced-password
enforcement, P0 open = 0, P1 open = 0.

YELLOW (external/manual, block the lock):
1. Orange Money real production payment evidence (16 paths A–P).
2. SMTP live inbox delivery (Gmail / Yahoo / iCloud / Orange).
3. Deployment rollback rehearsal (publish → rollback → re-publish).

## P0 / P1 found and fixed this phase

DEF-009 (P1): `WalletView` called three `useMemo` hooks *after* the
`wallet_public_enabled` early return. Because the flag resolves asynchronously,
executing a public-wallet flag rollback would have white-screened `/wallet` with
a React hook-order crash — the failure would have landed precisely during an
emergency rollback. Hooks hoisted; `react-hooks/rules-of-hooks` errors now 0.

## P0 found and fixed this phase

DEF-001: `om_sandbox_enabled` and `om_environment` were still `true` in the
production database after the sandbox phase claimed they were restored OFF.
Simulated references would have been honoured for real customers. Both now
`false`; a flag assertion is now a documented preflight step.

## Accepted P2

DEF-004 bundle size · DEF-005 451 warn-level linter findings (0 error-level) ·
DEF-006 self-serve read gaps (close with sanitized RPCs, never raw SELECT) ·
DEF-007 four platform-managed email queue functions without pinned search_path
(no PUBLIC execute) · DEF-008 `merchant_ensure_wallet` PUBLIC execute without an
internal guard (creates an empty wallet row only) · DEF-010 misleading non-hook
helper name (fixed) · DEF-011 602 lint errors, mostly `no-explicit-any`, no
known runtime impact, burn-down deferred post-1.0.

## Canonical documents

`docs/releases/web-production-rc.md`, `web-production-release.md`,
`web-production-rollback.md`, `web-production-checklist.md`,
`docs/qa/web-production-release-matrix.md`, `web-rc-defect-register.md`,
`smtp-inbox-test-results.md`, `docs/security/web-rc-frontend-secret-audit.md`.

## Lock condition

Lock only when the three YELLOW gates carry real external evidence, signed in
the release checklist. Record the lock commit SHA, release owner and date here
at that time. Code readiness is not operational readiness.

## Slice 1 (2026-08-02) — Repas P1 + server-side welcome email

- DEF-012 (P1, Repas settlement preview) verified CLOSED: the live
  `admin_preview_repas_payment_settlement` uses
  `COALESCE(fr.merchant_store_id, li.related_store_id)`; no second settlement
  model was introduced and Marché is untouched.
- DEF-013 CLOSED with a server-side design: `AFTER INSERT` trigger on
  `public.profiles` → `_dispatch_welcome_email` → `pg_net` →
  `send-transactional-email`. Exactly-once is enforced by claiming
  `public.welcome_email_dispatches` before sending; pre-existing accounts are
  backfilled as already-welcomed. Browser-side welcome path and the
  `send-welcome-email` wrapper were removed — one path only. Failure never
  blocks or rolls back account creation.
- DEF-014 CLOSED: `send-transactional-email` now recognises internal callers by
  a verified `service_role` claim, not raw key string equality (the DB reads a
  different-format service key out of Vault).
- Auto-confirm remains ON; email verification stays non-blocking for this
  release. Sandbox flags and public wallet remain OFF.
- SMTP gate stays **YELLOW**: rail proven end-to-end, real inbox placement not
  yet observed. Milestone remains **UNLOCKED**.
