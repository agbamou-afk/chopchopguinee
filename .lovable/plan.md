
# Orange Money Checkout Orchestration

Scope is very large — this plan stages the work into landable slices. Each slice ends in a working, non-regressing build. I stop between slices for your go/no-go.

**Non-negotiables (unchanged across all slices):** no public wallet restore; no ledger deletion; no fake OM success; no service_role in frontend; no client-trusted prices; no dispatch before authorization; RLS never weakened; existing capture/settlement/cashout logic untouched.

---

## Phase 0 — Architecture audit (deliverable = markdown, no code)

Read and document the current state into `docs/finance/orange-money-checkout-architecture.md`:

- `payment_intents` schema, current status enum, existing RPCs (`confirm_payment_intent`, `fail_payment_intent`, `cancel_payment_intent`)
- `payment_provider_events` schema (already exists — reuse, don't duplicate)
- `wallet_hold` / `wallet_capture` / `wallet_release` / `wallet_pay_merchant` behavior
- Current `ride_create` funding dependency
- Repas intent path (`src/lib/repas/orders.ts`)
- Marché offer intent path (`src/lib/marche/payments.ts`)
- Top-up OM path (`wallet_topup_om_create`, `submit_customer_om_code`, `get_my_topup_om_status`) — this is our template
- Existing admin reconciliation surfaces
- `feature_flags` runtime cache

Output = the audit doc + a chosen accounting invariant: **provider inflow → source-scoped ledger authorization → source finalization, all in one transaction; no spendable customer balance surfaced.**

---

## Slice 1 — Flags + payment-intent status alignment (migration)

- Seed flags: `om_checkout_enabled`, `om_provider_mode` (`manual|automated|disabled`, default `manual`), `om_ride_checkout_enabled`, `om_repas_checkout_enabled`, `om_marche_checkout_enabled`. Extend `FlagKey` union and the flag loader.
- Extend `payment_state` enum if missing values (`proof_submitted`, `in_review`, `authorized`, `needs_review`) — added additively, never renaming existing values. Add columns to `payment_intents` if missing: `expires_at`, `authorized_at`, `rejected_at`, `rejection_reason`, `ledger_hold_tx_id`, `ledger_capture_tx_id`, `ledger_release_tx_id`, `checkout_session_id`, `payer_phone`, `provider_event_id`, `source_module` (rides/repas/marche).
- Kill-switch UI in `FlagsAdmin` (module-level pause).

## Slice 2 — Checkout session + unified OM submission RPCs

- New table `service_checkout_sessions` (fields per Phase 3), RLS: user reads own, service_role writes, expiry TTL, one finalized source per session.
- SECURITY DEFINER RPCs:
  - `om_checkout_create(source_module, source_payload jsonb, quoted_amount_gnf)` — validates payload server-side per module, computes authoritative amount, creates intent + session
  - `om_payment_submit_proof(p_payment_intent_id, p_payer_phone, p_provider_reference, p_proof_url)` — ownership check, duplicate-reference detection → `needs_review`, idempotent
  - `om_payment_authorize(p_intent_id, p_note)` — finance/god-admin only, atomic: locks intent, validates uniqueness, calls source-specific finalizer, links source_id, marks `authorized`, on finalization failure → `needs_review` + high-severity support issue
  - `om_payment_reject(p_intent_id, p_reason)` — finance/god-admin
- All idempotent; audit entries via existing `audit_logs`.

## Slice 3 — Ride OM checkout (replaces wallet_hold dead end)

- New RPCs `ride_om_checkout_create(pickup, dropoff, quoted_fare)` (recomputes fare server-side, creates session+intent, no ride yet) and `ride_om_finalize(p_intent_id)` (creates ride row atomically inside `om_payment_authorize`).
- Frontend: replace `wallet_hold → ride_create` in booking sheet with `ride_om_checkout_create` → OM payment sheet (reused from top-up) → poll intent status → dispatch begins only after `authorized`. Resumable from a "Paiements" entry if user refreshes.
- Legacy wallet path retained behind `wallet_public_enabled=true`.
- Copy strictly matches Phase 4 whitelist.

## Slice 4 — Ride cancellation + OM refund requests

- New table `om_refund_requests` (intent_id, amount_gnf, status: pending/in_review/paid/rejected/needs_review, provider_reference, operator_id, timestamps). RLS: owner reads, finance/god-admin manages.
- Rewrite `ride_cancel` for OM-funded rides: pre-assignment → 100% refund request; post-assignment → 10% to master wallet + 90% refund request; in-progress → current review path. Idempotent.
- Admin finance UI to mark refunds paid with OM reference.
- Customer sees refund status in Payment Center.

## Slice 5 — Repas + Marché OM checkout wiring

- Reuse `om_checkout_create` with `source_module='repas'|'marche'`. Server-side cart/offer revalidation is the source-specific finalizer inside `om_payment_authorize`.
- Repas: restaurant sees confirmed order only after `authorized`. Existing capture/settlement untouched.
- Marché: accepted-offer flow gated on authorization. Existing capture/settlement untouched.

## Slice 6 — Admin finance verification page

- New `/admin/payments/orange-money` (or integrate into `PaymentsAdmin`): queues by status/module, duplicate-reference warning, expected-amount vs submitted, acknowledgement checkbox before `om_payment_authorize`. Ops admin read-only, finance/god-admin can authorize.

## Slice 7 — Customer Payment Center

- New `/payments` and `/payments/:intentId` — reads own intents/refunds/sessions. No wallet balance shown. Entry points from Activity, Orders, archived wallet panel.

## Slice 8 — Provider adapter, event table, webhook hardening

- Extend `orangeMoneyAdapter` with `createPaymentRequest`, `queryTransaction`, `initiateRefund` stubs (real work is `verifyPayment`/`handleWebhook`).
- Confirm `payment_provider_events` schema matches Phase 14 fields; add missing ones.
- Harden `payment-webhook-orange-money` edge function: require signature when `om_provider_mode=automated`; in `manual` mode webhook only files evidence, never authorizes.

## Slice 9 — Ops Command Center, Support, Observability

- Add OM cards to `OpsCommandCenter` (awaiting/in_review/needs_review/refunds pending/unmatched events/oldest age). Links only, no actions.
- Extend `ReportIssueButton` with OM categories + metadata attachments.
- Audit events emitted from RPCs into `audit_logs`. No secrets logged.

## Slice 10 — Security sweep, QA A–X, milestone lock

- RLS cross-user tests, role tests, secret audit, `tsgo` build.
- Fill the return format (A–Z).
- Write `.lovable/memory/milestones/orange-money-checkout-orchestration-production-stable.md` and update `mem://index.md`.

---

## Files (new)

Migrations for slices 1/2/3/4/5/8; `src/lib/checkout/orangeMoney.ts`; `src/components/checkout/OrangeMoneyCheckoutSheet.tsx`; `src/pages/PaymentCenter.tsx`; `src/pages/PaymentDetail.tsx`; `src/pages/admin/OrangeMoneyReview.tsx`; `docs/finance/orange-money-checkout-architecture.md`; milestone doc.

## Files (edited)

`src/lib/flags/featureFlags.ts`, ride booking components, `src/lib/repas/orders.ts`, `src/lib/marche/payments.ts`, `src/pages/admin/PaymentsAdmin.tsx`, `src/pages/admin/OpsCommandCenter.tsx`, `src/pages/admin/FlagsAdmin.tsx`, `supabase/functions/payment-webhook-orange-money/index.ts`, `src/App.tsx`, `.lovable/memory/index.md`.

## Risks

- Existing ride/wallet integration is broad — Slice 3 is the highest-risk step. Legacy path stays available behind `wallet_public_enabled=true` for rollback.
- Enum/column additions must be additive; no renames. Migration audit before writing.
- Full 21-phase execution in one turn would exceed safe review — I execute slice by slice.

## Approve to proceed

If you approve, I start with **Phase 0 audit + Slice 1 (flags + payment-intent alignment migration)** and return for review before Slice 2.
