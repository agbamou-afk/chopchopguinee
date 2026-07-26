# Orange Money Wallet Surface + Sandbox Ecosystem Readiness

Extends the OM Checkout Orchestration phase. Two locks in play:
- Primary (still open): `orange-money-checkout-orchestration-production-stable`
- New sub-lock: `orange-money-sandbox-ecosystem-ready-stable`

## Scope discipline

Surgical patch. No reopening of ride/repas/marché business logic beyond what is needed to route them through the OM checkout state machine in sandbox. Public wallet stays archived. Internal ledger stays untouched as an accounting substrate.

## Assumptions (flag if wrong)

1. `/payments` and `/payments/:id` do NOT yet exist as customer-facing routes — Slice 1 audit will confirm; if they do, we reuse.
2. `om_provider_mode` today is a boolean flag row (`enabled` = manual vs automated). We will extend it to a 4-value string via `feature_flags.description` or add `om_sandbox_enabled` as a separate boolean flag rather than mutating the enum column (safer, non-breaking).
3. Sandbox isolation is done via `is_sandbox boolean` + `environment text` metadata on payment intents, checkout sessions, provider events, refunds, audit logs. No parallel tables.
4. Sandbox ledger entries reuse existing ledger tables but are tagged `is_sandbox=true` and excluded from every finance aggregate. Master wallet card, driver earnings, cashout eligibility, Ops Command Center totals all get sandbox-exclusion filters.
5. Manual/live intents and sandbox intents are strictly non-convertible.

## Deliverables

### Slice A — Public naming: "OM Wallet"

- Add `getPublicWalletLabel()` in `src/lib/flags/useFeatureFlag.ts` returning `"OM Wallet"` when `wallet_public_enabled=false`, else `"ChopWallet"`.
- Sweep home service grid (`PrimaryActionGrid`, `MoreServicesGrid`), `BottomNav` (already 4-col), any "Portefeuille"/"Wallet"/"ChopWallet" public label. Route the tile to `/payments` (payment center) when archived, `/wallet` when public wallet re-enabled.
- Icon: keep `Smartphone`/`Wallet` per Orange Money hero visual language.

### Slice B — Neutral OM Payment Center (`/payments`)

- Audit first. If missing, create `src/pages/Payments.tsx` + optional `src/pages/PaymentDetail.tsx`.
- Lists the authenticated user's OM payment intents grouped by status: awaiting proof, submitted, in_review, authorized, captured, rejected, expired, refund pending/paid. Deep-links to related ride/order/offer. Support escalation button per row.
- Explicitly no balance, no master wallet, no raw provider payload, no admin notes. Subtitle: "Vos paiements Orange Money, vérifications et remboursements."

### Slice C — Sandbox mode foundation

- Migration: seed feature flags `om_sandbox_enabled` (default false) + description-based mode ("sandbox"/"manual"/"automated"/"disabled") on `om_provider_mode`.
- `FlagKey` union + `useFeatureFlag` helpers: `useOmProviderMode()`, `useOmSandboxEnabled()`.
- Environment resolver: `getOmEnvironment()` returns `"sandbox" | "production"` based on flag + host.
- Sandbox mode never exposed to end users in production.

### Slice D — Provider adapter + deterministic test refs

- Extend `src/lib/payments/providers/` with `orangeMoneySandbox.ts` adapter fulfilling the same `PaymentProviderAdapter` interface.
- Server-side: new Edge Function `om-sandbox-simulate` (God Admin + sandbox mode gated) that dispatches deterministic outcomes for the reference codes:
  - `OM-SBX-SUCCESS-001`, `OM-SBX-REVIEW-001`, `OM-SBX-REJECT-001`, `OM-SBX-DUPLICATE-001`, `OM-SBX-EXPIRED-001`, `OM-SBX-REFUND-001`, `OM-SBX-REFUND-REVIEW-001`.
- Extend `om_payment_submit_proof` (or add `om_payment_submit_sandbox_reference`) RPC to accept sandbox refs only when the intent is `is_sandbox=true`. Live/manual intents reject sandbox refs; sandbox intents reject non-sandbox proof. Idempotency + duplicate detection preserved.

### Slice E — Sandbox data isolation

- Migration: add `is_sandbox boolean not null default false` and `environment text not null default 'production'` to `payment_intents`, `payment_provider_events`, `payment_reconciliation_events`, `wallet_transactions` (nullable), `driver_cashout_requests`, `audit_logs` (nullable), `support_issues` (nullable). Backfill = false.
- Update all finance aggregate views/RPCs (`wallet_master_get_balance`, driver earnings, Ops Command Center metrics, cashout eligibility, merchant settlement) to filter `is_sandbox = false` by default. Add optional `include_sandbox` param on admin-only paths.
- Add `test_run_id uuid null` to sandbox rows for cleanup grouping.

### Slice F — Module coverage in sandbox

- Ride: `ride_om_finalize` already exists behind `om_ride_checkout_enabled`; verify it honors `is_sandbox` and creates sandbox rides tagged `is_sandbox=true` in `rides`.
- Repas: `om_repas_checkout_enabled` path — sandbox order rows tagged.
- Marché: `om_marche_checkout_enabled` path — sandbox offer rows tagged.
- Cancellation-fee logic runs in sandbox against sandbox master-wallet-shadow row (never touches real master wallet).
- Driver cashout sandbox: optional Slice F.1 — reuse cashout RPC with `is_sandbox=true`; never debits real balances.

### Slice G — Admin/finance controls

- Extend `/admin/payments` (or equivalent) with filter chips: Sandbox / Live / Automated / Source module / Status / Duplicate risk.
- Sandbox-only action panel (God Admin gated) invoking `om-sandbox-simulate` for: verified, rejected, needs_review, expired, refund paid, checkout reset.
- Audit every sandbox action.

### Slice H — Cleanup/reset

- RPC `om_sandbox_purge(test_run_id, before_date)` — archive sandbox intents/events/sessions/refunds/ledger rows scoped by sandbox=true. God Admin only. Logs the actor.
- Never touches live rows.

### Slice I — Observability

- Emit sandbox audit events listed in §11 into `audit_logs` with `is_sandbox=true`. No secrets, no proof image bytes.

### Slice J — Docs + memory

- Update `docs/finance/orange-money-checkout-architecture.md` (sandbox section).
- New `docs/finance/orange-money-sandbox.md` (how it works, how to run a mission, how to reset).
- New `docs/qa/orange-money-sandbox-test-matrix.md` (the A–U matrix).
- New milestone file `.lovable/memory/milestones/orange-money-sandbox-ecosystem-ready-stable.md`.
- Update `.lovable/memory/index.md`.

## Technical section

- All new/altered public tables get GRANTs in the same migration.
- All SECURITY DEFINER functions set `search_path = public`, validate `auth.uid()`, validate God Admin role via `has_role`, validate `is_sandbox` matches the intent, and validate `om_provider_mode` when relevant.
- No service_role or provider credentials leave server side.
- Sandbox references are rejected server-side when `om_provider_mode <> 'sandbox'`.
- Manual↔sandbox conversion is explicitly disallowed at RPC layer.
- Aggregates default to `is_sandbox = false` filter, ensuring master wallet, driver earnings, cashout eligibility, merchant settlement, Ops Command Center are unaffected by sandbox activity.

## Order of execution

1. Audit `/payments` existence + current flag machinery (read-only).
2. Slice A + B (naming + payment center) — small UI patch, high user visibility, no financial risk.
3. Slice C + E migrations (flags + isolation columns).
4. Slice D provider adapter + submit RPC.
5. Slice F module wiring behind flags.
6. Slice G admin controls.
7. Slice H cleanup RPC.
8. Slices I + J docs/memory.
9. Run QA matrix A–U and report.

## Lock policy

Neither lock lands from a rename alone. Locks require: consistent public naming; functional payment center; sandbox isolated from all financial aggregates; ride/Repas/Marché sandbox flows pass A–U; no client-side fake-success; build clean.

## Return format

Full A–V report per user's §16 upon completion.
