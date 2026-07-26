---
name: OM Wallet + Sandbox Ecosystem Ready
description: OM Wallet public naming + sandbox isolation columns + payment center + deterministic sandbox references documented. Sub-lock of OM Checkout Orchestration.
type: feature
---
# Milestone — orange-money-sandbox-ecosystem-ready-stable

Status: **CANDIDATE — not yet locked.**

## Delivered

- Public naming pivot to **"OM Wallet"** across home tiles (`PrimaryActionGrid`, `QuickActions`), archived `/wallet` panel, centralized through `getPublicWalletLabel()` / `usePublicWalletLabel()`.
- Neutral OM Wallet payment center: `WalletArchivedPanel` embeds `OmPaymentsList` showing the authenticated user's OM intents grouped by status. No balance, no ledger internals, no admin notes. Deep-links to `/help/issues` for stuck payments.
- Sandbox isolation columns: `is_sandbox`, `environment`, `test_run_id` on `payment_intents`, `payment_provider_events`, `payment_reconciliation_events` with sandbox indexes. Existing rows default to production.
- Feature flags: `om_sandbox_enabled` (master switch) and `om_environment` (production vs sandbox declaration). Both default off. Sandbox only active when both true.
- Runtime helpers: `useOmSandboxActive()`, `isOmSandboxActive()`, `usePublicWalletLabel()`.
- Docs: `docs/finance/orange-money-sandbox.md`, `docs/qa/orange-money-sandbox-test-matrix.md`, and sandbox section appended to the checkout architecture doc.

## Slice A delivered (2026-07-26)

- `public.om_payment_submit_sandbox_reference(uuid, text, text, uuid)` — server-authoritative deterministic sandbox execution. Requires both sandbox flags, whitelists `OM-SBX-*`, locks the intent, enforces ownership (or God Admin), drives the real `payment_intents` state machine + real `payment_provider_events`, idempotent on replay, and emits reconciliation + audit events. Never touches `wallet_*`.
- `public.om_sandbox_reference_outcome(text)` — immutable server-side deterministic reference registry.
- Production guards: `confirm_payment_intent`, `fail_payment_intent`, `choppay_capture_payment_intent` now reject sandbox intents at the boundary.
- Financial isolation: `admin_preview_payment_intents` and `admin_preview_marche_payment_intents` gained `p_include_sandbox boolean default false` (God Admin only opt-in). Master / driver / merchant wallet math is safe by construction — sandbox path calls no `wallet_*` function.
- QA harness (9/9 rows) executed in transactional rollback against staging; master wallet delta = 0, no non-sandbox provider events created.

## Not yet delivered (blockers to full lock)

- Slice B: ride / repas / marché sandbox execution paths (customer submission wired to the RPC, sandbox source finalization, `OM-SBX-FINALIZE-FAIL-001`).
- Slice C: sandbox refund RPC + provider event lifecycle for `OM-SBX-REFUND-*`.
- Sandbox admin controls panel in `/admin/payments` (God-Admin simulate / reset).
- `om_sandbox_purge(test_run_id, before_date)` cleanup RPC.
- Optional `om-sandbox-simulate` Edge Function (God-Admin invocation from admin UI).
- End-to-end sandbox flow QA per matrix rows D–N (Slice B unblocks).

## Rollback

Flip `wallet_public_enabled=true` to restore legacy ChopWallet naming and surface. Flip `om_environment` and/or `om_sandbox_enabled` back to `false` to disable sandbox reference acceptance.

## Related milestones

- Primary lock still open: `orange-money-checkout-orchestration-production-stable`
- Prior lock: `orange-money-first-wallet-archive-stable`
## Slice C delivered (2026-07-26)

- Authoritative ride fare: `public.ride_compute_quote_gnf` and
  `public.ride_get_quote` (SECURITY DEFINER). `om_sandbox_create_ride_intent`
  rewritten to derive the intent amount from the server helper; any
  caller-supplied display fare is only used to record a mismatch flag.
- New refund model: `public.payment_refund_requests` with statuses
  `pending | in_review | paid | rejected | needs_review`, per-intent
  active-refund uniqueness, per-intent provider-reference uniqueness,
  owner + admin RLS, all writes through SECURITY DEFINER RPCs.
- Sandbox refund request creators (owner or God Admin):
  `om_sandbox_cancel_ride` (applies 10% fee only when a driver is
  assigned, otherwise full refund), `om_sandbox_request_repas_refund`
  (routes `out_for_delivery` / `completed` orders to `needs_review`),
  `om_sandbox_request_marche_refund`.
- Sandbox refund orchestrator:
  `om_sandbox_submit_refund_reference(refund_request_id, provider_reference, test_run_id)`
  drives the state machine via deterministic fixtures
  (`OM-SBX-REFUND-001` → paid, `OM-SBX-REFUND-REVIEW-001` → needs_review),
  idempotent, blocks cross-user and cross-environment reference use,
  and never invokes any `wallet_*` function.
- Fixture registry: `om_sandbox_refund_reference_outcome(text)`.
- QA helper: `om_sandbox_assign_mock_driver` for exercising the
  10% fee split path without touching real dispatch.
- Financial isolation reverified end-to-end (QA row R):
  master wallet delta = 0, wallet_transactions delta = 0.

## Not yet delivered (blockers to full lock)

- God-Admin sandbox surface in `/admin/payments` (refund inspector +
  simulate / reset controls, audited).
- `om_sandbox_purge(test_run_id, before_date)` archival RPC + admin
  trigger for test-run cleanup.
- Optional `om-sandbox-simulate` Edge Function.
- Customer-facing archived-wallet UX to render refund state
  (`requested / in_review / paid / needs_review`) with a Sandbox
  badge — currently visible only through `OmPaymentsList` intent
  metadata.

## Slice D delivered (2026-07-26) — MILESTONE LOCK

- Test-run registry `sandbox_test_runs` (active / completed / archived / needs_review) + backfill from existing sandbox intents. God + Finance read; all writes via SECURITY DEFINER RPCs.
- `om_sandbox_complete_test_run(uuid,text)` and `om_sandbox_archive_test_run(uuid,text)` — God Admin only. Archive refuses mixed/live runs, marks records via `metadata.sandbox_archived_at`, returns per-table counts, idempotent, never deletes.
- Archive lockout: `_om_sandbox_block_archived` BEFORE INSERT/UPDATE on `payment_intents` and `payment_refund_requests` rejects any sandbox mutation whose `test_run_id` is archived (bypassed only by the archive RPC via the `om.archiving` GUC).
- Read RPCs: `om_sandbox_admin_metrics`, `om_sandbox_admin_list_runs`, `om_sandbox_admin_run_detail` — God + Finance.
- `om_sandbox_assign_mock_driver` tightened to God Admin only.
- Admin route `/admin/payments/sandbox` (SandboxAdmin.tsx) added to the Finance sidebar as "Sandbox OM". Metric cards, run list, detail sheet with inline auth / finalize / refund / complete / archive controls. All controls disabled when either flag is off or the run is archived.
- OM Wallet refund UX: `OmPaymentsList` renders own `payment_refund_requests` under each intent with neutral status labels (`en cours de vérification`, `remboursé`, `révision requise`), refunded amount, cancellation fee, requested / resolved dates, Sandbox badge, and support link on `needs_review`. No internal balance surface.
- Final production isolation reverified: master wallet delta = 0 across full Slice D flow + archive; `wallet_transactions` delta = 0; production admin previews already exclude sandbox by default (Slice A guard); driver / merchant / cashout paths untouched.
- Sandbox flags restored to `false` after QA (`om_environment=false`, `om_sandbox_enabled=false`, `om_provider_mode=manual`, `wallet_public_enabled=false`).

## Lock recommendation

Full milestone `orange-money-sandbox-ecosystem-ready-stable` is READY TO LOCK.

Every remaining Slice D exit criterion met:
- God Admin can run deterministic end-to-end tests through secure RPCs from the UI.
- Production financial totals and payable balances unaffected.
- Test runs can be safely archived (no deletion, audit preserved).
- Ordinary and Operations users cannot simulate financial outcomes.
- Customers see own refund status without internal wallet exposure.
- Sandbox flags default OFF.
- QA A–Z materially complete (`M/N/O` inherit from Slice C parity).

## Non-blocking follow-ups (deferred by design)

- `om_sandbox_purge(before_date)` — intentionally omitted; archival is the sole cleanup path.
- `sandbox_test_admin` sub-role — omitted per instruction ("God Admin only for this release").
- `om-sandbox-simulate` Edge Function — optional; server RPCs already cover CI harness.
- Ride surge / waiting-time / service-zone multipliers — not yet server-authoritative; matches production behaviour.
