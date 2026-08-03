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

## Slice 2 — Client shell + Services navigation (approved amendment, NOT locked)

- Bottom nav: Accueil · Services · Activité · Compte. Center scanner FAB removed.
  Wallet tab removed from nav (payments reachable from Services).
- New `ServicesView` directory: 10 services wired to existing actions/routes.
- Home reduced to a compact subset + `Voir tous les services`.
- Envoyer: final tile, honest interim state, dedicated parcel module is Slice 3.
- No pricing/wallet/backend changes. Flags unchanged (sandbox OFF, public wallet OFF).
- RC deliberately remains UNLOCKED.

## Slice 3 (2026-08-03) — Envoyer v1, flag-OFF

- Real parcel module on `package_delivery` missions: server-authoritative quote
  from the moto tariff, provider-neutral payment intent (`source_module='package'`,
  `package_payment`), sender-only 6-digit pickup/delivery codes, courier view
  without codes, idempotent sender-only cancellation with fee/refund/dispute
  branches. No pricing, wallet or payment-architecture change.
- Ships behind `envoyer_enabled = false`. `om_sandbox_enabled`, `om_environment`
  and `wallet_public_enabled` all verified false.
- QA A–AH: 24 PASS/PASS(code), 5 YELLOW (no sandbox, driver or real-money run).
- DEF-015 (P1, contained by the OFF flag): production `confirm_payment_intent`
  does not call `package_delivery_finalize_from_intent` — sandbox path only.
- DEF-016 (P2): no admin capability editor; `package_delivery` is driver
  self-selected.
- Build: green. Workbox precache limit raised to 4 MiB (main chunk 2,100.58 kB
  exceeded the 2 MiB default) — a packaging correction, not a runtime defect.
- RC remains **UNLOCKED**.

## Slice 4 (2026-08-03) — DEF-015 closure + Bonbonna rename

- **DEF-015 (P1) CLOSED.** `confirm_payment_intent` — the canonical production /
  manual admin confirmation RPC — now finalises `source_module = 'package'`
  intents through the existing `package_delivery_finalize_from_intent`, accepts
  `pending | processing | authorized`, is replay-idempotent (one mission, one
  code pair, no duplicate reconciliation events, earnings or support issues),
  and on finalisation failure moves the intent to `needs_review`, opens a linked
  high-severity `payment_failed` support issue and writes a `provider_failed`
  reconciliation event **without re-raising** (a raise would roll the recovery
  trail back). No wallet, master-wallet or driver-earning movement at
  confirmation; earnings still only at trusted delivery completion. Sandbox
  finalisation untouched and still isolated.
- Confirmation-path audit: `confirm_payment_intent` is the only genuinely active
  production route for package intents. `choppay_capture_payment_intent`
  requires a wallet hold (Envoyer creates none; `wallet_public_enabled` OFF) and
  the Orange Money webhook edge function is still a TODO stub with no dispatch.
- Verification: 9 rolled-back transactional cases PASS against the live schema
  with production-shaped fixtures; zero committed financial value. Real
  Orange Money money movement remains **unexecuted (YELLOW)**.
- **Bonbonna rename**: customer-facing TokTok copy is now `Bonbonna` everywhere
  (Services, ride composer, quotes, trip screens, activity, driver cards,
  onboarding, driver apply, admin pricing tab, AI command router, SEO copy,
  alt/aria text). Internal identifiers — DB enum value `toktok`, fare keys,
  routes, analytics keys, `rides_toktok` capability, asset filenames and
  migration history — are unchanged. Rendering is centralised in
  `src/lib/rides/rideModeLabel.ts` so historical `toktok` rows display as
  Bonbonna.
- Flags at end of slice: `envoyer_enabled` false, `om_sandbox_enabled` false,
  `wallet_public_enabled` false, `app_settings.orange_money.mode` = manual_csv.
- RC remains **UNLOCKED**.
