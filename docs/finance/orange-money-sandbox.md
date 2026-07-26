# Orange Money Sandbox Ecosystem

Companion to `orange-money-checkout-architecture.md`. Describes the
sandbox rail that lets QA drive the full OM checkout state machine end
to end without touching real money.

## Activation

Sandbox is only "on" when **both** feature flags are true:

| Flag | Meaning |
|---|---|
| `om_environment` | `true` means this deployment is a sandbox/staging environment |
| `om_sandbox_enabled` | Master sandbox switch |

Production defaults keep both flags **off**. Ordinary customers never
see sandbox affordances. The two flags are managed from `/admin/flags`
by God Admin only.

## Provider mode matrix

| Environment | `om_provider_mode` | Behaviour |
|---|---|---|
| production | manual | Operator manually verifies each OM payment (launch default) |
| production | automated | Reserved — requires live provider credentials + webhook signature |
| sandbox    | manual | Simulated manual review with deterministic outcomes |
| sandbox    | automated | Simulated provider webhooks with deterministic outcomes |

## Deterministic test references

Use these references **only** when `om_environment=true` and
`om_sandbox_enabled=true`. Any other environment rejects them.

| Reference | Outcome |
|---|---|
| `OM-SBX-SUCCESS-001` | verified → authorized → source finalized |
| `OM-SBX-REVIEW-001`  | routed to `in_review` (no finalization) |
| `OM-SBX-REJECT-001`  | provider `rejected` → intent `failed` |
| `OM-SBX-DUPLICATE-001` | duplicate-reference rule triggers, no second capture |
| `OM-SBX-EXPIRED-001` | provider `expired` → intent `expired` |
| `OM-SBX-REFUND-001`  | successful refund simulation |
| `OM-SBX-REFUND-REVIEW-001` | refund routed to `needs_review` |

## Data isolation

Every sandbox row carries three columns: `is_sandbox` (default false),
`environment` (default `'production'`), `test_run_id` (nullable). Applied
on `payment_intents`, `payment_provider_events`,
`payment_reconciliation_events`. Extended to ledger, cashout, audit and
support rows on demand.

**Invariants:**
- Production aggregates (`wallet_master_get_balance`, driver earnings,
  cashout eligibility, merchant settlement, Ops Command Center totals)
  filter `is_sandbox = false` by default.
- Sandbox payments never reach the real master wallet or driver
  earnings. Ledger rows created during sandbox flows are tagged and
  excluded from all payout math.
- A live/manual intent can never be converted to sandbox and vice
  versa — the submit RPC rejects a mismatch.

## Running a sandbox mission

1. Flip `om_environment=true` and `om_sandbox_enabled=true` in
   `/admin/flags` (God Admin only, staging only).
2. Create a ride / Repas order / Marché offer as usual — the checkout
   session is created with `is_sandbox=true`.
3. In the OM Wallet payment screen, paste the desired sandbox
   reference (e.g. `OM-SBX-SUCCESS-001`).
4. The server-side sandbox provider adapter emits a normalized event
   through the same validator / authorizer used by manual/live flows.
5. Source module (ride/order/offer) finalizes only after server-side
   authorization succeeds. No client-side fake-success branch exists.

## Reset / cleanup

`om_sandbox_purge(test_run_id uuid, before_date timestamptz)` — God
Admin only. Scopes strictly to `is_sandbox=true` rows. Live rows are
never touched. Every purge is written to `audit_logs` with the actor.

## Rollback

Flip either `om_environment` or `om_sandbox_enabled` back to `false`
in `/admin/flags` to disable sandbox. Existing sandbox rows remain
visible in admin (filtered to Sandbox tab) but no new sandbox events
can be created.

## Slice A — server-authoritative reference RPC (delivered)

### RPC contract

`public.om_payment_submit_sandbox_reference(
  p_payment_intent_id uuid,
  p_provider_reference text,
  p_payer_phone text default null,
  p_test_run_id uuid default null
) returns jsonb`

`SECURITY DEFINER`, `search_path = public`, `GRANT EXECUTE TO authenticated`.
Returns a jsonb envelope: `{ idempotent, intent_id, intent_state, outcome,
event_id, is_sandbox, test_run_id, source_finalization, needs_review }`.

### Guarantees

- Requires `auth.uid()` (no anon).
- Requires **both** `om_environment=true` and `om_sandbox_enabled=true`.
- Reference is trimmed and upper-cased. Only `OM-SBX-*` values are accepted;
  live-looking references raise `live_reference_rejected_on_sandbox_rpc`.
- Intent is locked `FOR UPDATE`, must have `is_sandbox=true`, must be in
  `pending` or `processing`.
- Caller must be `intent.user_id = auth.uid()` OR God Admin.
- Replaying the same reference on the same intent returns
  `idempotent=true` — no second provider event, no second transition.
- The `OM-SBX-DUPLICATE-001` fixture inserts a stable
  `provider_transaction_id` so a second attempt across intents hits the
  unique index and returns `idempotent=true, duplicate=true` without a
  second authorization.
- Every call writes a `payment_provider_events` row (with
  `is_sandbox=true, environment='sandbox'`), a
  `payment_reconciliation_events` row, and an `audit_logs` row.
- The RPC **never** invokes `wallet_hold`, `wallet_capture`,
  `wallet_release`, `wallet_settle_merchant_revenue`,
  `wallet_credit_mission_earning`, or `wallet_pay_merchant*`.

### Deterministic outcome map (server-authoritative)

`public.om_sandbox_reference_outcome(text)` immutable helper:

| Reference | Outcome | Intent state |
|---|---|---|
| `OM-SBX-SUCCESS-001` | `success` | `authorized` |
| `OM-SBX-REVIEW-001` | `review` | `needs_review` |
| `OM-SBX-REJECT-001` | `reject` | `failed` |
| `OM-SBX-DUPLICATE-001` | `duplicate` | `needs_review` (first), idempotent duplicate (subsequent) |
| `OM-SBX-EXPIRED-001` | `expired` | `expired` |
| `OM-SBX-REFUND-001` | `refund` | `needs_review` (refund RPC deferred to Slice B) |
| `OM-SBX-REFUND-REVIEW-001` | `refund_review` | `needs_review` |

`OM-SBX-FINALIZE-FAIL-001` intentionally not implemented in Slice A —
it requires the sandbox-aware source-module finalizer path, which lands
with Slice B (ride/repas/marché sandbox execution).

### Production guards

`confirm_payment_intent`, `fail_payment_intent`, and
`choppay_capture_payment_intent` now raise
`sandbox_intent_use_om_payment_submit_sandbox_reference` (and
`sandbox_intent_cannot_touch_master_wallet` for capture) when handed a
sandbox row. Sandbox intents can therefore only advance through the
sandbox RPC, and the master wallet is defensively protected even if
admin code mistakenly targets a sandbox intent.

### Financial isolation sweep (Slice A)

- `admin_preview_payment_intents` — added `p_include_sandbox boolean
  default false`. Sandbox rows filtered out for ordinary admins; only
  God Admin may pass `true`.
- `admin_preview_marche_payment_intents` — same treatment.
- Master wallet balance (`wallets.party_type='master'`), driver wallet
  balance / `held_gnf`, and merchant settlement math read
  `wallet_transactions` / `wallets` — none of which the sandbox path
  writes to. QA row A8 confirms `master_before == master_after` after
  a full sandbox run.
- `driver_cashout_create_request` reads
  `wallets.balance_gnf - wallets.held_gnf` and the sum of pending
  cashout requests. Sandbox never mutates either surface, so
  eligibility is unaffected without a signature change.

### Remaining gaps for full sandbox milestone lock

- Slice B: ride / repas / marché sandbox execution paths + sandbox
  source finalization + `OM-SBX-FINALIZE-FAIL-001`.
- Sandbox refund RPC + provider event lifecycle for `OM-SBX-REFUND-*`.
- God-Admin `/admin/payments` Sandbox tab and simulate/reset controls.
- `om_sandbox_purge(test_run_id, before_date)` archival RPC.
- `om-sandbox-simulate` Edge Function.