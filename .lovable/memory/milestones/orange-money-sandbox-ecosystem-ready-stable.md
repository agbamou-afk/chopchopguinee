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

## Not yet delivered (blockers to full lock)

- Server-side `OrangeMoneySandboxProvider` adapter + Edge Function `om-sandbox-simulate` deployment.
- `om_payment_submit_sandbox_reference` RPC + mismatch rejection between sandbox/live intents.
- Wiring `is_sandbox` filter into all finance aggregate RPCs (master wallet balance, driver earnings, cashout eligibility, merchant settlement, Ops Command Center metrics).
- Sandbox admin controls panel in `/admin/payments` (God Admin gated simulate/reset).
- `om_sandbox_purge` cleanup RPC.
- End-to-end sandbox flow QA per matrix rows D–N.

## Rollback

Flip `wallet_public_enabled=true` to restore legacy ChopWallet naming and surface. Flip `om_environment` and/or `om_sandbox_enabled` back to `false` to disable sandbox reference acceptance.

## Related milestones

- Primary lock still open: `orange-money-checkout-orchestration-production-stable`
- Prior lock: `orange-money-first-wallet-archive-stable`