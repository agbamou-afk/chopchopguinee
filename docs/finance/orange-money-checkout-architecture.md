# Orange Money Checkout Architecture

Living reference for the OM-first payment rail. Companion to
`docs/finance/orange-money-rail.md` (public-facing framing). This doc is
for engineers touching checkout, ledger, or reconciliation code.

## Accounting invariant

**Provider inflow → source-scoped ledger authorization → source finalization,
all in one transaction. No spendable customer balance is ever surfaced.**

Concretely: a customer never "recharges" a public wallet. Every OM payment is
bound to a specific source (ride, food order, marketplace offer) via a
checkout session. When finance authorizes the payment, the same DB
transaction (a) records the ledger authorization, (b) creates or unlocks the
source row, and (c) transitions the payment intent to `authorized`. If any
step fails, the whole transaction rolls back to `needs_review` and files a
high-severity support issue. The internal `wallets` / `wallet_transactions`
ledger remains the source of truth for capture, settlement, cancellation
fees, driver earnings, master wallet revenue, and cashout — none of it is
visible as a public balance.

## Current infrastructure (Phase 0 audit)

### Reusable — extend, do not duplicate

- `payment_intents` — already carries `source_module`, `source_id`,
  `wallet_hold_tx_id`, `captured_tx_id`, `settlement_tx_id`. Unique partial
  index `uidx_payment_intents_source_payer_active` blocks a second live
  intent per (source_module, source_id, user_id). Existing states:
  `pending, processing, confirmed, failed, cancelled, refunded, reversed,
  expired`. Slice 1 adds `proof_submitted`, `in_review`, `authorized`,
  `needs_review` additively.
- `payment_reconciliation_events` — append-only per-intent audit trail.
- `payment_provider_events` — normalized inbound OM events with
  `provider_transaction_id` uniqueness, `om_code_normalized`,
  `receiving_account_id`, `processing_status`. Reused as-is.
- Existing RPCs `confirm_payment_intent`, `fail_payment_intent`,
  `cancel_payment_intent` — kept for backward compatibility. New OM flow
  adds `om_payment_authorize`, `om_payment_reject`, `om_payment_submit_proof`
  which layer on top of these.
- Top-up OM path (`wallet_topup_om_create`, `submit_customer_om_code`,
  `get_my_topup_om_status`) — canonical template for manual verification UX.

### Wallet ledger (unchanged, internal only)

- `wallet_hold` / `wallet_capture` / `wallet_release` / `wallet_pay_merchant`
  — remain the ledger primitives. OM authorization internally calls the
  hold/capture pair against a system-owned OM inflow account so the ledger
  stays double-entry, but the customer never sees a spendable balance.

### Source modules

- **Rides**: `ride_create` currently depends on `wallet_hold`. Slice 3 wraps
  this in `ride_om_finalize` invoked from `om_payment_authorize`.
- **Repas**: `src/lib/repas/orders.ts` already creates intents; Slice 5
  routes them through `om_checkout_create` when
  `om_repas_checkout_enabled=true`.
- **Marché**: `src/lib/marche/payments.ts` — same pattern as Repas.

### Feature flags

Managed through `public.feature_flags` and `src/lib/flags/featureFlags.ts`.
Slice 1 adds:

| Flag | Default | Meaning |
|---|---|---|
| `om_checkout_enabled` | false | Master gate for the new OM checkout rail |
| `om_provider_mode` | `manual` | `manual` / `automated` / `disabled` — persisted as description; enabled=true means feature reachable |
| `om_ride_checkout_enabled` | false | Rides use OM checkout instead of wallet_hold |
| `om_repas_checkout_enabled` | false | Repas orders authorize via OM |
| `om_marche_checkout_enabled` | false | Marché offers authorize via OM |

All default off. Rollback = flip flag in `/admin/flags`.

## Roll-forward sequence (this milestone)

See `.lovable/plan.md` for the 10 slices. Each slice is landable and
non-breaking on its own; downstream slices are guarded by their flags.

## Non-goals

- Restoring the public CHOP Wallet.
- Deleting `wallet_transactions`, `wallets`, master wallet, or cashout code.
- Auto-confirming OM payments without operator review while
  `om_provider_mode='manual'`.
- Storing provider secrets in frontend code.
- Trusting client-computed prices.