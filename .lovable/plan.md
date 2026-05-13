# CHOP CHOP Wallet — Orange Money Top-Up & Reconciliation

This is a large piece of work. I'll ship it in phases so each phase is reviewable, testable, and the app stays working between approvals.

## Current state (what already exists)

- `wallets` table with `owner_user_id`, `party_type`, `balance_gnf`, `held_gnf`. Already used by app.
- `wallet_transactions` table with `type` (topup/payment/refund/adjustment/transfer/...), `status`, `amount_gnf`, `from_wallet_id`, `to_wallet_id`, `reference`.
- `topup_requests` table — currently scoped to **agent → client** top-ups (has `agent_user_id`, `confirmation_code`).
- RPCs: `wallet_hold`, `wallet_capture`, `wallet_release`, `wallet_internal_transfer`, `wallet_topup_create/confirm/cancel`, `admin_adjust_agent_float`.
- `audit_logs` already exists with actor/role/module/before/after.
- Home `WalletCard` currently shows a hard-coded `walletBalance = 2500000` in `UserHome.tsx`.
- No Orange Money provider, no reconciliation UI, no provider event ingestion.

The existing schema already covers ~70% of what's specified. I'll **extend** rather than duplicate so `agent → client` top-ups keep working alongside the new Orange Money flow.

---

## Phase 1 — Real wallet balance on home + `useWallet` hook (small, ship first)

Outcome: Home page wallet card and any other balance display reflect the authenticated user's true `client` wallet balance with loading/error states. No mock numbers anywhere.

Changes:
- Audit `useWallet` hook (already exists at `src/hooks/useWallet.ts`) — make sure it returns `{ balance, held, available, loading, error, refresh }` and subscribes to realtime `wallets` row changes for the current user.
- `UserHome.tsx`: remove `walletBalance = 2500000`, use `useWallet()`. Skeleton while loading, error fallback, "Créer portefeuille" CTA only if no row exists (auto-created by `handle_new_user` trigger so this is rare).
- `AppHeader` already takes `amountValue` — drive it from the hook.
- `WalletView` — same wiring; remove any remaining mock balances.
- Add visibility toggle (eye icon) persisted to `localStorage`.
- Driver mode: show driver-party wallet balance instead of client wallet on driver home.

No DB migration in this phase.

## Phase 2 — Orange Money top-up data model

Outcome: New tables to support merchant-account top-ups and provider event ingestion, without breaking the existing agent flow.

Migration:
- Extend `topup_requests`:
  - Make `agent_user_id` nullable (it's currently NOT NULL).
  - Add `provider text` (default `'agent'`, allowed: `'agent' | 'orange_money'`).
  - Add `user_phone text`, `matched_provider_transaction_id text`, `expires_at` already exists.
  - Extend status enum to include `'matched'`, `'needs_review'`, `'credited'` (alias of `'confirmed'` kept for back-compat).
- New table `payment_provider_events` (provider, event_type, provider_transaction_id UNIQUE, payer_phone, amount_gnf, currency, status, raw_payload jsonb, matched_user_id, matched_topup_request_id, match_confidence numeric, processing_status, created_at, processed_at). RLS: admin-only read/write; `service_role` insert via edge function.
- Reference generator helper: SQL function `gen_topup_reference()` returning `CC-TOPUP-YYYY-NNNNNN` from a sequence.
- New RPC `wallet_topup_om_create(p_amount_gnf, p_user_phone)` — creates a `pending` topup_request with `provider = 'orange_money'`, `expires_at = now() + 24h`, returns reference.
- New RPC `wallet_topup_om_credit(p_event_id)` — SECURITY DEFINER, called only by edge function with service role; performs deterministic match → credits client wallet via `wallet_internal_transfer` from `master`, marks event `credited`, marks topup_request `credited`, writes `audit_logs` row.
- New RPC `wallet_admin_credit(p_user_id, p_amount_gnf, p_reason, p_provider_tx_id?)` — restricted to `god_admin`/`finance_admin` (use existing `is_god_admin` + new `is_finance_admin` helper or check `user_roles`), creates `adjustment` transaction, logs to `audit_logs`. Operations admin denied at RPC level.
- RLS: users read own `topup_requests`; admins read all; `payment_provider_events` admin-only.

## Phase 3 — User-facing top-up flow (Orange Money)

Outcome: User can request a top-up, gets a clear payment instruction screen with reference, and sees the request transition through statuses in real time.

Changes:
- New screen `WalletTopUpOM.tsx`: amount input (GNF), confirm → calls `wallet_topup_om_create` → shows instruction card:
  - "Envoyez {amount} GNF via Orange Money au numéro marchand CHOP CHOP `{merchant_msisdn}`"
  - Reference badge (copy button): `CC-TOPUP-2026-000001`
  - Countdown to `expires_at`
  - Live status (subscribes to `topup_requests` row by id)
  - When `credited`: success animation + new balance + receipt link
- Merchant MSISDN sourced from a new `app_settings` row (or `feature_flags`) so it's editable by admin without code change.
- Notifications: in-app toast on each transition; reuse existing `NotificationService` to enqueue WhatsApp/SMS receipt on `credited`.
- Add to `WalletView`: "Recharger" → opens new sheet with two options "Agent CHOP CHOP" (existing) or "Orange Money".

## Phase 4 — Admin reconciliation dashboard

Outcome: Finance/God admins can manage Orange Money reconciliation end-to-end.

Changes:
- New admin page `WalletReconciliation.tsx` under `/admin/wallet/reconciliation`. Tabs:
  1. Auto-credited (last 7d)
  2. Pending top-up requests
  3. Provider events needing review
  4. Failed / expired requests
  5. Duplicates / suspicious
  6. Manual allocations
- For each `needs_review` event: show payer phone, amount, time, top suggested matches (computed in edge function `om-suggest-matches` using phone fuzzy + amount + time window) with confidence score. Buttons: Approve credit → calls `wallet_topup_om_credit` with chosen `topup_request_id`; Reject; Add note; Escalate.
- Manual import: CSV uploader (admin pastes/uploads Orange Money export) → edge function `om-import-csv` parses rows and inserts into `payment_provider_events` with `processing_status = 'received'`, then runs auto-match.
- Existing `WalletAdmin.tsx` page: add "Créditer le portefeuille" action on user row → modal (amount, reason, optional provider tx id, admin PIN confirm) → calls `wallet_admin_credit`. Visible only for god_admin/finance_admin.

## Phase 5 — Auto-match edge function + AI advisory

Outcome: Provider events flow in (via webhook stub or CSV import) and match automatically when safe; AI helps admins on the rest.

Changes:
- Edge function `orange-money-webhook` (verify_jwt = false, HMAC signature check using `ORANGE_MONEY_WEBHOOK_SECRET`) — inserts into `payment_provider_events`, then calls `om_auto_match` SQL function.
- SQL `om_auto_match(event_id)`:
  1. provider status = `successful`
  2. provider_transaction_id not previously used (UNIQUE constraint enforces)
  3. find pending `topup_requests` where `provider='orange_money'`, `status='pending'`, `expires_at > now()`, `requested_amount_gnf = event.amount_gnf`, and (`user_phone = event.payer_phone` OR `reference appears in event memo`)
  4. exactly one match → call `wallet_topup_om_credit`; else mark event `needs_review`.
- Edge function `om-suggest-matches` (admin-only, JWT verified, role-checked) — calls Lovable AI Gateway `google/gemini-2.5-flash` with the unmatched event + a shortlist of candidate users; returns ranked suggestions with rationale. **Read-only**, never credits.
- Fraud checks in `wallet_topup_om_credit`: rate-limit (>5 top-ups/24h flags), wallet must be `active`, high-value threshold (>5,000,000 GNF) → forces `needs_review` even on perfect match.

## Phase 6 — Notifications, audit, tests

- Hook `notification_log` for every status transition.
- Every privileged RPC writes to `audit_logs` with before/after.
- Vitest tests for the conditions in spec (Testing Requirements section).
- Update `AUDIT.md` and memory.

## Secrets needed (asked at the right phase)

- `ORANGE_MONEY_MERCHANT_MSISDN` (Phase 3)
- `ORANGE_MONEY_WEBHOOK_SECRET` (Phase 5)
- `ORANGE_MONEY_API_KEY` + `ORANGE_MONEY_API_SECRET` if/when we wire the live verify-status endpoint (Phase 5, optional — manual import path works without it)

## Technical notes

- `topup_status` enum currently: `pending, confirmed, expired, cancelled, failed`. Adding `matched, needs_review, credited` requires `ALTER TYPE ... ADD VALUE` (one per migration statement, no transaction).
- `wallet_topup_om_credit` will reuse `wallet_internal_transfer('master' → 'client')` so the master wallet acts as the "Réserve plateforme" mirror of the OM merchant account. Ops will reconcile master vs OM merchant balance daily.
- Driver-mode wallet shown on driver home will read the `driver` party_type wallet for that user (already created by `ride_accept`).

## Proposed first action after approval

Implement **Phase 1** end-to-end (no migration, low-risk, immediate user-visible win), then come back for Phase 2 migration approval.

If you'd rather I start with the schema (Phase 2) so the data model is locked first, say so and I'll reorder.