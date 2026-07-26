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