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
## Slice C (2026-07-26) — Refund lifecycle + authoritative ride fare

### Authoritative ride fare (production-safe correction)

Slice B's `om_sandbox_create_ride_intent` accepted a caller-supplied
`p_fare_gnf`. That is unsafe as a launch-grade pattern even for sandbox,
because it implies the same shape for the live checkout path. Slice C
replaces that signature.

- New helper `public.ride_compute_quote_gnf(mode, plat, plng, dlat, dlng)`
  — server-authoritative Haversine * `fare_settings.price_per_km` +
  `fare_settings.base_price` per ride mode. `SECURITY DEFINER`, no
  caller input other than coordinates and mode.
- New helper `public.ride_get_quote(...)` returns the JSON quote for
  display (`{fare_gnf, currency:'GNF', authoritative:true, source:'server:ride_compute_quote_gnf'}`).
- `om_sandbox_create_ride_intent(mode, plat, plng, dlat, dlng,
  checkout_session_id, test_run_id, client_display_fare_gnf DEFAULT NULL)`
  — server computes fare via `ride_compute_quote_gnf`. Intent amount is
  always the server value. `client_display_fare_gnf` is optional and
  only recorded as `metadata.client_display_amount_mismatch=true`
  when it disagrees with the server fare — never used as source of truth.
- QA row A proves that passing `p_client_display_fare_gnf=15000` when
  the server computes `16117` still produces an intent with
  `amount_gnf=16117` and `client_display_amount_mismatch=true`.

Parity limitation: `ride_compute_quote_gnf` currently reads only
`fare_settings` (base + per-km). Surge, waiting-time, and service-zone
multipliers are not yet expressed as server functions and are therefore
absent from both live and sandbox quotes. This matches production
behaviour today — no divergence.

### Refund model

New table `public.payment_refund_requests` — the single source of truth
for refund lifecycle across all modules.

Columns: `payment_intent_id`, `user_id`, `source_module` (ride /
repas / marketplace), `source_id`, `original_amount_gnf`, `fee_gnf`,
`amount_gnf`, `status`, `provider`, `provider_reference`,
`provider_event_id`, `reason`, `is_sandbox`, `environment`,
`test_run_id`, `metadata`, `support_issue_id`, timestamps.

Statuses: `pending`, `in_review`, `paid`, `rejected`, `needs_review`.

Guardrails:
- Unique partial index prevents more than one active
  (`pending|in_review|paid`) refund per intent — no double refund.
- Unique index on `(payment_intent_id, provider_reference)` prevents
  reusing the same provider reference on the same intent.
- RLS: customer reads own; admins read all; all writes go through
  `SECURITY DEFINER` RPCs.

### Sandbox refund request creators

- `om_sandbox_cancel_ride(ride_id, test_run_id DEFAULT NULL)` —
  owner or God Admin, sandbox flags active, ride must be sandbox.
  Applies the production cancellation policy:
  - Before assignment: `fee_gnf = 0`, `amount_gnf = intent.amount_gnf`.
  - After assignment: `fee_gnf = round(intent.amount * 10%)`,
    `amount_gnf = intent - fee`.
  Marks the ride cancelled with sandbox metadata, creates a
  `payment_refund_requests` row in `pending`, emits
  `sandbox.refund_requested` provider event and `refund_created`
  reconciliation event. Idempotent: replaying returns the same refund
  request.
- `om_sandbox_request_repas_refund(order_id, test_run_id, reason)` —
  owner-only, order must be `payment_status=paid` and
  `settlement_state='sandbox'`. Cancels order state (unless already
  terminal). Orders already in `out_for_delivery`/`completed` are
  routed to `needs_review` instead of `pending`.
- `om_sandbox_request_marche_refund(offer_id, test_run_id, reason)` —
  same shape for marketplace offers.
- `om_sandbox_assign_mock_driver(ride_id, driver_user_id)` — sandbox
  QA helper for exercising the "after assignment" fee split without
  the real dispatch pipeline.

### Sandbox refund reference orchestrator

`om_sandbox_submit_refund_reference(refund_request_id,
provider_reference, test_run_id)` — the single generic orchestrator
callers use. Behaviour:

1. Requires auth + both sandbox flags active.
2. Rejects non-`OM-SBX-*` references (`live_reference_not_allowed_on_sandbox_refund_rpc`).
3. Rejects unknown `OM-SBX-*` references (`unknown_sandbox_refund_reference`).
4. Locks refund row and intent row; enforces ownership (owner or God Admin).
5. Rejects any submission targeting a non-sandbox intent
   (`sandbox_reference_rejected_on_non_sandbox_intent`).
6. Idempotent: resubmitting the same reference on an already-resolved
   refund returns `idempotent=true`.
7. Rejects double-refund: same reference used on another refund row
   for the same intent (`duplicate_provider_reference_on_intent`).
8. `paid` outcome (`OM-SBX-REFUND-001`):
   - refund → `paid`, resolved_at set;
   - intent → `refunded`;
   - food order → `payment_status='refunded'`;
   - offer → `payment_status='refunded'`, fulfillment_status →
     `cancelled` unless already delivered/completed;
   - ride source is left `cancelled` (already done at request time);
   - provider event `sandbox.refund_paid`, recon `refund_completed`,
     audit `sandbox.refund.paid`.
9. `needs_review` outcome (`OM-SBX-REFUND-REVIEW-001`):
   - refund → `needs_review`; high-severity `payment_failed`
     support issue linked with `test_run_id` and fixture metadata;
   - provider event `sandbox.refund_review`; audit
     `sandbox.refund.needs_review`.

### Deterministic refund fixture registry

`om_sandbox_refund_reference_outcome(text)` returns `paid` for
`OM-SBX-REFUND-001` and `needs_review` for
`OM-SBX-REFUND-REVIEW-001`. Case-insensitive, whitespace-tolerant.

### Financial isolation (Slice C)

- `payment_refund_requests` write path never invokes `wallet_*`.
- Ride cancellation fee is recorded on the refund row
  (`fee_gnf`, `sandbox_fee_gnf`), NOT captured into the master wallet.
- QA row R confirmed `master delta = 0` and
  `wallet_transactions delta = 0` after the full ride / repas /
  marché refund cycle including a 10% fee split case.
- No driver earning, no merchant payable, no cashout eligibility
  change on any sandbox refund.

### Remaining gaps for full sandbox milestone lock

- God-Admin `/admin/payments` Sandbox tab: refund inspector +
  simulate/reset controls; must be explicit and audited.
- `om_sandbox_purge(test_run_id, before_date)` archival RPC and
  admin trigger for test-run cleanup.
- Optional `om-sandbox-simulate` Edge Function for CI harness.
- Long-form checkout UX surface for refund request / status /
  needs_review — currently exposed only through the internal
  archived-wallet payments list.

## Slice D (2026-07-26) — God-Admin control plane + archival + wallet refund UX

### Test-run registry

- Table `public.sandbox_test_runs` — `id` reuses `test_run_id`. Status:
  `active | completed | archived | needs_review`. Fields: `label`,
  `created_by`, `started_at`, `completed_at`, `completed_by`,
  `archived_at`, `archived_by`, `notes`, `metadata`.
- RLS: God Admin + Finance Admin `SELECT`; all writes through
  `SECURITY DEFINER` RPCs.
- Backfilled from existing sandbox `payment_intents.test_run_id`
  (marked `metadata.backfilled=true`).

### RPCs

- `om_sandbox_complete_test_run(uuid, text)` — God Admin; active → completed. Idempotent.
- `om_sandbox_archive_test_run(uuid, text)` — God Admin. Refuses any
  test run containing non-sandbox / production rows. Marks
  `payment_intents`, `payment_refund_requests`,
  `payment_provider_events`, `payment_reconciliation_events` with
  `sandbox_archived_at`. Returns per-table counts. Idempotent.
  Never deletes.
- `om_sandbox_admin_metrics()` — sandbox-only aggregates for the admin
  cockpit. God + Finance.
- `om_sandbox_admin_list_runs(int)` — per-run counts + module coverage
  + last activity. God + Finance.
- `om_sandbox_admin_run_detail(uuid)` — correlated intents, refunds,
  provider events, reconciliation events, support issues. God + Finance.
- `om_sandbox_assign_mock_driver(uuid, uuid)` — **tightened to God Admin
  only** (Slice C used ownership; Slice D removes that path).

### Archive lockout trigger

`_om_sandbox_block_archived` — BEFORE INSERT/UPDATE on
`payment_intents` and `payment_refund_requests`. If the row is
`is_sandbox=true` and its `test_run_id` maps to an archived run, the
statement is rejected with `sandbox_test_run_archived` (unless the
archive RPC itself is running, indicated by the `om.archiving` GUC).

### Admin route

`/admin/payments/sandbox` (added to the Finance sidebar as
"Sandbox OM"). Renders overview cards (runs, intents by state,
refunds by state, needs_review, module counts, provider events),
list of test runs, and per-run detail sheet with correlated logs and
inline simulation controls (auth fixtures for pending intents,
finalize for authorized intents, refund fixtures for pending refunds,
complete / archive actions for the run). Every control is disabled
when either sandbox flag is off or when the run is archived.

### OM Wallet refund UX

`OmPaymentsList` now co-loads the customer's own
`payment_refund_requests` (RLS-scoped) and renders — under each intent
— a neutral refund line: status label (`En cours de vérification`,
`Remboursé`, `Révision requise`), refunded amount, cancellation fee
when > 0, requested date, resolved date, and — for `needs_review` —
the same "Ouvrir un signalement" link that already covered failed
intents. Sandbox intents keep the existing amber "Sandbox" badge.
No internal balance, no master wallet, no raw provider payload, no
admin notes.

### Financial isolation (Slice D)

- No new `wallet_*` calls introduced.
- Archive RPC only mutates sandbox rows and the registry; it never
  touches production rows or `wallet_transactions`.
- Frontend read paths query `payment_intents` and
  `payment_refund_requests` under existing RLS — customer sees own,
  God/Finance Admin see via SECURITY DEFINER read RPCs.

### Not delivered by design

- Broad `om_sandbox_purge(before_date)` — intentionally omitted;
  archival is the only cleanup surface.
- `sandbox_test_admin` sub-role — omitted per instruction ("God Admin
  only for this release rather than introducing a broad new role").
- `om-sandbox-simulate` Edge Function — remains optional; the
  transactional path is already fully server-authoritative.
