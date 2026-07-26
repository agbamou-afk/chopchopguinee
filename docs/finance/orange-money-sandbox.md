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