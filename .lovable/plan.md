## WONGO Payments Foundation — Internal Ledger + Rail Readiness

Goal: prepare the ledger, payment-intent model, provider abstraction, sandbox simulator, and receipt continuity so WONGO Wallet can plug in Orange Money / MTN / cash / manual later without re-plumbing. **No live money movement. No new live providers.**

### Current baseline (already exists)
- `wallets` (party_type, balance_gnf, held_gnf) and `wallet_transactions` (with WONGO-style `reference`, `txn_status`, `txn_type`).
- `topup_requests` with `provider` text (`agent`, `orange_money`) and a rich `topup_status` enum.
- `payment_provider_events` table for inbound provider webhooks, with matching/credited lifecycle.
- `wallet_topup_om_create` RPC powering the existing Orange Money sheet.
- `txn_status` enum: `pending | completed | failed | reversed | cancelled` (no `processing`, `confirmed`, `refunded`, `expired`).

The base is already strong — the gap is **standardization, a unified intent model, a provider enum, sandbox tooling, and receipt copy**.

### Scope of this sprint

1. **Standardized payment-state vocabulary** (DB-level, no breaking writes)
   - New `payment_state` enum: `pending | processing | confirmed | failed | cancelled | refunded | reversed | expired`.
   - Used by the new `payment_intents` table and surfaced in UI mappers. Existing `txn_status` and `topup_status` stay intact; a TS mapper translates them to `payment_state` for receipts/notifications.

2. **`payment_provider` enum**
   - Values: `orange_money | mtn_money | cash | manual | internal | agent`.
   - Added as a Postgres enum and a TS const used in `topup_requests`, intents, and future flows. `topup_requests.provider` stays text for compatibility; a CHECK is widened to accept the new values.

3. **`payment_intents` table** (new, additive)
   - Columns: `id`, `user_id`, `amount_gnf bigint`, `currency text default 'GNF'`, `purpose` (enum: `wallet_topup | repas_payment | marche_payment | courier_payout | merchant_settlement | refund`), `state payment_state`, `provider payment_provider`, `provider_reference text`, `internal_reference text unique` (`WNG-YYYY-NNNNNN`), `related_order_id`, `related_mission_id`, `related_listing_id`, `related_store_id`, `metadata jsonb`, `created_at`, `updated_at`.
   - Triggers: `updated_at`, auto-generate `internal_reference` via a sequence + helper `next_wongo_reference()`.
   - RLS: users read own; admins manage; finance/ops admins manage by role.
   - Wallet credit rule enforced in a `confirm_payment_intent` SQL function — only flips state to `confirmed` and credits/holds wallet via existing ledger primitives (admin / sandbox only for now; no public RPC).

4. **`payment_reconciliation_events` table** (new, additive, append-only)
   - Columns: `id`, `intent_id`, `event_type` (enum: `intent_created | provider_pending | provider_confirmed | provider_failed | wallet_credited | payout_queued | payout_paid | refund_created | refund_completed`), `provider`, `provider_reference`, `payload jsonb`, `created_at`, `actor_user_id`.
   - RLS: admin-read only; inserts via SECURITY DEFINER helpers used by the intent functions.

5. **Provider abstraction layer (TS)**
   - `src/lib/payments/types.ts` — `PaymentState`, `PaymentProvider`, `PaymentPurpose`, `PaymentIntent`, `ReconciliationEvent` types mirrored from the DB enums.
   - `src/lib/payments/state.ts` — `mapTxnStatus()`, `mapTopupStatus()` → `PaymentState`; status label/colour helpers in FR.
   - `src/lib/payments/providers.ts` — provider registry: `{ id, label, kind: 'mobile_money' | 'cash' | 'manual' | 'internal', supports: { topup, payment, payout } }`. Replaces hardcoded Orange-only assumptions in the top-up sheet's text but keeps the existing OM flow as the only currently-enabled provider.
   - `src/lib/payments/intents.ts` — thin client around new RPCs: `createIntent`, `getIntent`, `listIntents`, `simulateConfirm` (sandbox-only, see §7).
   - `src/lib/payments/reference.ts` — formats `WNG-YYYY-NNNNNN` for display.

6. **Receipt continuity**
   - Update `src/components/wallet/TransactionReceiptSheet.tsx` to render:
     - WONGO reference (existing `reference`, displayed as `WNG-…` when present)
     - provider label (from registry; fallback "Interne")
     - normalized payment state chip + FR copy:
       - pending → "Paiement en attente de confirmation."
       - confirmed → "Paiement confirmé."
       - failed → "Paiement échoué. Réessayez."
       - refunded/reversed/cancelled/expired → matching FR strings
     - linked mission/order/listing/store summary line when `related_*` is present.

7. **Sandbox payment scenarios** (no DB writes)
   - Extend `src/lib/sandbox/scenarios.ts` + `engine.ts` with:
     - `wallet_topup_pending`, `wallet_topup_confirmed`, `provider_failure`, `duplicate_provider_confirmation`, `refund`, `merchant_settlement_pending`, `courier_payout_pending`, `courier_payout_confirmed`.
   - Each scenario emits in-memory intents + reconciliation events the sandbox panel can render. UI hook lives in the existing sandbox ops panel (no schema impact, no Supabase writes).

8. **Notifications (calm copy)**
   - Update `src/lib/notifications/walletNotifier.ts` keys/labels to the FR strings in the spec (Recharge demandée / confirmée, Paiement confirmé / échoué, Gain confirmé, Remboursement traité). Add a dedupe key `${intent_id}:${state}` so identical state transitions don't double-notify.

9. **Admin readiness (light)**
   - Add an admin module entry `payments` (route stub `/admin/payments`) listing pending `payment_intents` with reference, provider, state, amount, related entity. Buttons "Confirmer (test)" / "Marquer échec" are gated to `god_admin` and call the new SECURITY DEFINER functions. No bulk tooling, no dashboard polish.

### Explicit non-goals
- No live Orange Money / MTN integration, no API keys, no webhook endpoints beyond the existing `payment_provider_events` ingestion.
- No changes to existing wallet balances or to the live `wallet_topup_om_create` RPC behaviour.
- No crypto, remittance, bank rails, or KYC flows.
- No new public RPC that can credit a wallet from the client.

### Technical notes
- All schema work goes in **one migration** that is purely additive (new enums, tables, functions, RLS). Existing tables only get a relaxed CHECK on `topup_requests.provider` to accept `mtn_money | cash | manual | internal`.
- All new SQL functions are `SECURITY DEFINER` with explicit `search_path = public` and role checks (`is_any_admin` or `has_admin_role(..., 'god_admin')`).
- TS additions are tree-shakable and don't touch `src/integrations/supabase/*`.
- Receipt + notifications changes are pure presentation; existing data continues to render correctly via the status mappers.

### Acceptance check
- Migration applies cleanly; `payment_intents`, `payment_reconciliation_events`, enums exist with RLS.
- `payment_intents` can be inserted (admin) and confirmed via the new function; wallet balance only moves on confirmation; reconciliation rows are written.
- Receipts show WONGO ref, provider, normalized state + FR copy.
- Sandbox panel can run all listed scenarios without any Supabase write.
- Existing wallet, top-up, Repas, Marché, and ride flows continue to work unchanged (no regressions in current RPCs).
