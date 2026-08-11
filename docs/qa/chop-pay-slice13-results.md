# Slice 13 — Final Full Financial Regression (results)

Harness: service_role-only `_qa_s13_run1..run4()`, results stored in `_qa_s13_results`.
Every part builds its own fixtures inside one transaction and rolls the whole block back.

| Part | Scope | Result |
| --- | --- | --- |
| 1 | Stage isolation / flag gating | PASS 17/17 |
| 2 | Ride / Bonbonna (Stage 1) | PASS 32/32 |
| 3 | Repas / Marché cash + Chop Pay orders (Stages 2–4) | PASS 54/54 |
| 4 | Envoyer declared value, custody, claims, sandbox isolation | **PASS 98/98** |
| 5 | Orange Money inbound reconciliation | **PASS 115/115** |

## Part 4 — closeout coverage

- C1 exact declared-value ceiling boundary (accepted at the ceiling, refused one GNF above).
- C2 evidence photo privacy: storage RLS probed as owner, assigned courier, unrelated user, ops.
- C3 courier cancellation before custody: exact collateral release plus replay idempotency,
  through the real `package_courier_cancel` RPC.
- C4 full claims compensation cap.
- C5 sandbox ↔ production financial isolation (J series), including cross-environment intents:
  the sandbox finaliser refuses a production intent (`not_a_sandbox_intent`) and the production
  confirmation path refuses a sandbox intent
  (`sandbox_intent_use_om_payment_submit_sandbox_reference`) while the caller really holds
  `super_admin`.
- I series three-way claim cap:
  `max_compensation = LEAST(accepted_declared_value, documented_actual_value, active_claim_limit)`
  with a non-vacuous binding fixture for each of the three constraints, plus refusal to pay any
  money before a God-Admin-investigated documented value is persisted
  (`CLAIM_DOCUMENTED_VALUE_REQUIRED`).

## Post-run live posture (re-proved after every run)

- Master wallet `b6858980-…` = **-100435 GNF / held 0**.
- Global ledger posting sum = **0**, imbalanced journals = **0**.
- Feature flags byte-identical; all Envoyer / Chop Pay stage rails remain OFF, `om_topup_enabled`
  is the only finance rail ON. The sandbox rail is enabled only inside the rolled-back fixture.
- No fixture residue: 0 QA packages, 0 QA intents, 0 sandbox intents, buffer table dropped.
- `_qa_s13*` helpers: anon/authenticated EXECUTE denied, service_role only.
- `package_courier_cancel`: authenticated + service_role only, assigned-courier check,
  custody lock, idempotent replay.

## Part 5 — Orange Money Inbound Reconciliation — **PASS 115/115**

Harness: `public._qa_s13_run5()` (service_role only, self-rolling-back), results in `_qa_s13_results(part=5)`.

Full matrix rerun from the beginning after the D8 closeout: **115 / 115 PASS, 0 failures.**

### Production defects found and fixed (canonical code)
1. **P1 — admin-first reconciliation was broken for participants.** When the operator recorded the provider receipt *before* the customer/driver pasted their Orange Money code, `submit_customer_om_code` → `om_auto_match` → `wallet_topup_om_credit` aborted with `forbidden` (the credit primitive rejected the non-admin `auth.uid()`), rolling back the whole submission so the code was not even saved. Fixed with a one-shot, event-scoped transaction-local marker (`chopchop.om_credit_internal`) set by `submit_customer_om_code` immediately before delegating to the matcher. The marker authorises the *call only*; `wallet_topup_om_credit` still independently revalidates reference, amount, payer phone, receiving account, environment and target at credit time, and remains EXECUTE-denied to `anon`/`authenticated`.
2. **P2 — `credit_failed` violated a CHECK constraint.** `admin_record_om_receipt` / `admin_retry_om_credit` and the reconciliation UI write `processing_status = 'credit_failed'`, which was not in `payment_provider_events_processing_chk`, turning a logged credit failure into a hard function abort. The state is now allowed.

### Harness seams closed in this rerun (no product behaviour changed)
- **D8 reshaped into D8.0–D8.7 + D8F/D8G.** Reusing an already-credited provider reference is canonical *idempotency*, not an error: the replay returns the original transaction, moves 0 GNF and leaves the second request uncredited. A fresh, uncredited receipt force-pointed at the wrong request is refused at credit time (payer-phone/target revalidation) and also moves 0 GNF.
- **G1** now asserts zero *movement* on the target wallet instead of an absolute zero balance, so an earlier legitimate credit in the same fixture cannot make it false-fail. The sandbox receipt still never reaches `credited`.
- **H5B** added: `wallet_topup_cancel` canonically refuses to cancel a request whose code was already submitted, so the fixture forces the cancelled state and proves it before attempting the credit — H6 is therefore non-vacuous.
- **I-series baseline** corrected from `clock_timestamp()` to the transaction timestamp; the accounting reconciliation was previously matching zero rows. I3/I4 now reconcile real money: liabilities = wallet credits = master pass-through delta, with no revenue/fee posting.

### Post-rerun live posture (re-verified)
- Master wallet **-100435 GNF / held 0** (unchanged).
- Global ledger posting sum **0**, imbalanced journals **0**.
- Feature flags byte-identical; `om_topup_enabled` is the only finance rail ON, every OM checkout/sandbox rail OFF.
- No fixture residue: 0 sandbox intents, 0 QA rows outside the rolled-back block.
- `_qa_s13_run5`: `anon`/`authenticated` EXECUTE denied, `service_role` only.

### Verified in the latest run (non-exhaustive)
A1–A15 customer exact-match credit (liability, not revenue; zero-sum journal; terminal states; truthful requester history), B driver exact-match credit into unrestricted balance only, C required-evidence negative matrix (all 0 GNF), D credit-time revalidation / forced-match resistance, E idempotency + replay + advisory-lock concurrency, F cross-party/privilege matrix, G sandbox↔production isolation, I accounting truth, Z rollback posture (master exactly −100435 / held 0, global posting sum 0, zero imbalanced journals, feature flags byte-identical with `om_topup_enabled=true`, no fixture residue, `_qa_s13*` anon/auth EXECUTE denied).

### YELLOW register
- **YELLOW (not convertible to PASS): no actually observed live Orange Money receipt was used.** All Part 5 evidence is production-format *synthetic* receipt proof only. Live-provider receipt verification remains outstanding.

## Part 6 — Merchant Settlement + Manual Orange Money Payout — **PASS 87/87**

Harness: `public._qa_s13_run6()` (service_role only, self-rolling-back), results in `_qa_s13_results(part=6)`.
Final rerun after fixture corrections: **87 / 87 PASS, 0 failures.**

- **A (reservation)** — funded liability drives eligibility; one reservation per request; principal/fee/expected
  transfer frozen at reservation; over-reservation and cross-store requests refused; reserving moves no money.
- **B (manual OM operation)** — `finance_confirm_manual_om_payout` refuses with Stage 5 OFF, refuses ordinary
  users, the merchant itself and unauthenticated callers; refuses a blank reference, a missing attestation and an
  impossible transfer timestamp — each with zero evidence and zero movement. The exact confirmation settles once
  through the canonical engine; evidence facts (amount, fee, recipient, provider, environment) are server-derived
  from the frozen order, stored as `finance_manual_om` / `manual_operator_attested` with `provider_verified=false`
  and a traceable attesting operator. Payable, wallet and allocation each move exactly the frozen principal, and
  the settlement journal balances to zero against provider clearing.
- **C (mismatch / uniqueness / replay)** — incomplete, wrong-amount, wrong-recipient, wrong-environment,
  wrong-provider and unsuccessful-status evidence are all quarantined at 0 GNF; a provider reference already
  consumed anywhere is globally refused; replaying the manual confirmation returns `already_settled`, moves 0 and
  creates no second evidence row; `_payout_settle_internal` independently refuses mismatched evidence.
- **D (rejection / scheduler)** — finance rejection releases the reservation exactly once and never touches the
  payable; the configured daily scheduler queues one settlement per store per period, is idempotent within a
  period, queues the next period, and never debits.
- **E (fees)** — recipient-borne: 100000 principal / 5000 fee / 95000 transferred / 100000 debited, no platform
  fee expense. Platform-borne: 100000 principal / 5000 fee / 100000 transferred / 100000 debited, with the 5000
  booked once to `E_PROVIDER_FEE`. `net_gnf` is the amount that reaches the recipient — never fee-deducted twice.
- **F (stage isolation)** — Stage 5 enablement leaves Stage 6 and Stage 7 hard-blocked; driver payout request,
  legacy hold and legacy `driver_cashout_mark_paid` (even as a finance operator) all refuse; no driver money
  moves; P2P refuses; no umbrella Chop Pay flag is opened.
- **G (security)** — anon cannot execute any payout/settlement function; internal primitives stay service-role
  only; every payout function pins a fixed `search_path`; participants cannot write payout orders, evidence,
  allocations or payables directly; the manual confirmation has no null-caller shortcut.
- **H / Z (posture)** — master wallet **-100435 GNF / held 0** unchanged, global posting sum **0**, zero
  imbalanced journals, feature flags byte-identical, Stage 5/6/7 OFF and `om_topup_enabled` ON in production,
  and no fixture residue of any kind.

### Production defects found and fixed in Part 6
1. `payout_provider_evidence.net_gnf` double-subtracted the provider fee; it now truthfully equals the amount
   that reaches the recipient.
2. Added `finance_confirm_manual_om_payout` as the only manual Stage 5 rail: staff-only, Stage-5 gated,
   attestation-required, with every financial fact derived server-side from the frozen payout order.

## Part 6 — Hardening Addendum (UI/client seam)

**DEF-FIN-S13-P6-001 — CLOSED.**
`/admin/wallet/payouts` still exposed the generic editable evidence form (recipient MSISDN,
amount, provider status) for merchant settlement orders and called
`payout_record_provider_evidence` directly.

Closure (UI/client only, no backend change):
- `src/lib/finance/payouts.ts`: queue type now carries `source_kind`,
  `expected_provider_transfer_gnf`, and evidence provenance
  (`evidence_source`, `evidence_kind`, `provider_verified`). Added
  `confirmManualOmPayout()` binding + `isManualOmMerchantPayout()` guard.
- `src/pages/admin/PayoutsAdmin.tsx`: for `source_kind = 'merchant_settlement'` and
  provider `orange_money`, the launch action is now "Confirmer le virement Orange Money":
  all financial facts read-only (store, provider, MSISDN, principal, fee, fee bearer,
  exact `expected_provider_transfer_gnf`, environment, request reference), ONE editable
  field (real OM transaction reference), explicit attestation checkbox, submit gated on
  both, calling ONLY `finance_confirm_manual_om_payout`.
- Generic evidence/reconcile/reject bindings retained for non-merchant/engine review only.
- Evidence rows with `evidence_kind = manual_operator_attested` are labelled as operator
  attested / not verified by Orange Money.

Backend harness result unchanged: `_qa_s13_run6()` **87/87 PASS**.
Frontend verification: typecheck (`tsgo -p tsconfig.app.json`) **PASS, 0 errors**.
No authenticated Finance visual QA performed (no Finance session) — YELLOW.
Stage 5/6/7 production flags untouched. Part 7 NOT STARTED.

## Part 7 — Finance control plane, treasury, security, retry/idempotency, sandbox isolation — **PASS 99/99**

Harness: `public._qa_s13_run7()` (service_role only, self-rolling-back), results in `_qa_s13_results(part=7)`.

### Coverage
- **A — treasury / control-plane truth.** `finance_treasury_overview` / `_exceptions` / `_drilldown` refuse anon and
  ordinary users, answer only Finance/God roles, and every displayed figure is server-derived. Ride accept →
  complete, commission reserve, collateral hold/release and cancellation-debt accrual each move the treasury
  aggregates by exactly the expected delta (A11 baseline now snapshotted immediately before debt creation).
- **R — Repas / Marché retry & lifecycle seams.** Duplicate accepts, duplicate completes, refused cancellations
  after custody, funding-hold replays and the Chop Pay merchant capture (courier claim → collateral hold →
  capture funding exactly the merchandise amount) are all idempotent: the second call moves 0 GNF.
- **OM inbound ordering.** Both orderings proved: customer-code-first and admin-receipt-first converge on the
  same single credit; replays return the original transaction and move 0 GNF.
- **Envoyer Storage isolation.** Private evidence objects probed as owner, assigned courier, unrelated user and
  ops — only entitled readers resolve an object.
- **C — manual OM payout provenance.** Manual merchant settlements carry
  `raw->>'source' = 'finance_manual_om'`, `evidence_kind = manual_operator_attested`, `provider_verified=false`
  and a traceable attesting operator; replay returns `already_settled`.
- **B — security posture.** Finance SECURITY DEFINER functions pin `search_path`; internal money-moving
  primitives, QA helpers and raw finance tables are unreachable by `anon`, and signed-in users cannot write
  finance truth tables directly.

### Production security fixes found by Part 7 (posture only, no financial behaviour change)
1. **`provider_fee_schedules` and `payment_provider_events` were granted to `anon`** (SELECT/INSERT/UPDATE/DELETE).
   RLS still gated the rows, but the grants were far wider than the policies. Now: `anon` has no privilege at all;
   `authenticated` keeps `SELECT` on fee schedules and `SELECT, UPDATE` on provider events (the admin-only
   reconciliation policies already scope those), `service_role` full.
2. **14 internal money-moving primitives** (`_ledger_*`, `_payout_*`, `_merchant_*`, `_chop_pay_*`,
   `_cash_order_*`, `_package_*`, `_driver_*`, `_customer_cancellation_*`) were EXECUTE-able by `anon` and/or
   `authenticated`. All revoked; `service_role` only. Full regression rerun after the revocation is green, so no
   product path depended on those grants.

### Documented exception (honest, not silenced)
`authenticated` retains `UPDATE` on `payment_provider_events` because the admin reconciliation screen writes
`processing_status` directly under the `is_any_admin(auth.uid())` policy. `INSERT`/`DELETE` remain denied.

### Harness seams corrected (no product change)
- A11 baseline snapshotted immediately before debt creation.
- C7 provenance read from `raw->>'source'` (Part 6 stores manual provenance in `raw`).
- Repas/Marché store activation performed by a real `admin` (the `merchant_stores` status trigger requires it).
- Chop Pay marketplace order now claimed by the courier before merchant capture.
- G1.4 (Part 1) accepts the stronger `not_authorized` refusal for an ordinary driver and adds an explicit
  unauthenticated refusal check (`G1.4x`) — legacy `driver_cashout_mark_paid` authorizes before gating.

## Slice 13 — Final release board

| Part | Scope | Result |
| --- | --- | --- |
| 1 | Stage isolation / flag gating | **PASS 18/18** |
| 2 | Ride / Bonbonna | **PASS 32/32** |
| 3 | Repas / Marché cash + Chop Pay orders | **PASS 54/54** |
| 4 | Envoyer declared value, custody, claims, sandbox isolation | **PASS 98/98** |
| 5 | Orange Money inbound reconciliation | **PASS 115/115** |
| 6 | Merchant settlement + manual Orange Money payout | **PASS 87/87** |
| 7 | Finance control plane, treasury, security, retry, sandbox | **PASS 99/99** |
| **Total** | | **503 / 503 PASS, 0 failures** |

### App regression (this head)
- Typecheck `tsgo -p tsconfig.app.json`: **PASS, 0 errors**
- Unit tests `vitest run`: **PASS, 20/20**
- Production build `vite build`: **PASS**; PWA service worker generated (134 precache entries).
  Warning: pre-existing chunk-size advisory (`mapbox-gl`, analytics) — unrelated to this slice.

### Post-run live posture (re-verified after the full rerun)
- Master wallet **-100435 GNF / held 0**.
- Global ledger posting sum **0**; zero imbalanced journals.
- Feature flags byte-identical; `om_topup_enabled` is the only finance rail ON.
- No fixture residue: 0 QA packages, 0 sandbox intents.
- `_qa_s13_run1..run7`: `anon` / `authenticated` EXECUTE **denied**, `service_role` only.

### Final staged readiness verdict — NO FLAGS ACTIVATED

| Stage | Rail | Verdict |
| --- | --- | --- |
| 1 | Ride / Bonbonna internal ledger | GREEN — regression-proved, currently OFF |
| 2–3 | Repas / Marché cash orders | GREEN — regression-proved, currently OFF |
| 4 | Chop Pay orders + Envoyer declared value / claims | GREEN — regression-proved, currently OFF |
| 4b | Orange Money inbound top-up (`om_topup_enabled`) | **LIVE** — green, YELLOW on live-provider receipts |
| 5 | Merchant settlement + manual OM outbound | GREEN on synthetic evidence — OFF; activation is a business decision |
| 6 | Driver cashout | GREEN as *blocked* — OFF, no driver payout rail proved live |
| 7 | P2P transfer | GREEN as *blocked* — OFF |

### YELLOW register (carried, not convertible)
- No live Orange Money receipt has ever been used: all inbound (Part 5) and outbound (Parts 6–7) provider
  evidence is production-format **synthetic** proof.
- No authenticated Finance-operator visual QA session was performed against `/admin/wallet/payouts` or
  `/admin/treasury`.

## Final closeout — `sandbox_exec` disposition + single atomic 1→7 sweep (2026-08-11)

### Phase A — `sandbox_exec` disposition

**What it is.** `sandbox_exec` is the platform-managed maintenance/debug database login used by the
shell `psql` access path — not a project-authored role and not an application role. Attributes:
`LOGIN`, `INHERIT`, `BYPASSRLS`, **not** superuser, **not** createrole/createdb, **not** replication.
It is a member of nothing; only `postgres` may `SET ROLE` to it. No PostgREST/API role
(`anon`, `authenticated`, `service_role`) can reach it, and no application code path uses it.

**Privileges found.** Uniform `SELECT, INSERT` on all 278 `public` tables (plus `SELECT` on `auth.*`),
i.e. the finance grants on `provider_fee_schedules` and `payment_provider_events` were not a
finance-specific decision — they were the blanket exec grant. No `UPDATE`, no `DELETE`, and **no
`EXECUTE` on any function** (including every `_qa_s13_*` helper — the harness runs as `postgres`
/ `service_role`, never as `sandbox_exec`).

**RLS.** `provider_fee_schedules` and `payment_provider_events` both have RLS enabled, policies scoped
to `authenticated` admins only. `sandbox_exec` holds `BYPASSRLS`, so RLS is *not* a constraint on it —
table grants are the only boundary. That is why the grant, not a policy, is the correct control.

**Pre-fix probe (rolled back).** `sandbox_exec` could `INSERT` a `environment='production'`,
`is_sandbox=false` row into `payment_provider_events` and into `provider_fee_schedules`. It could not
update or delete any wallet, ledger, evidence or flag row, and could not execute
`finance_treasury_overview`, `_ledger_*`, `wallet_topup_om_credit` or any `_qa_s13_run*`. So it could
fabricate an uncredited provider *fact* an operator might act on, but could not move money itself.

**Disposition applied (posture only, no financial semantics changed).** `INSERT` revoked from
`sandbox_exec` on all 38 money-bearing tables: `wallets`, `wallet_transactions`, `ledger_accounts`,
`ledger_journals`, `ledger_postings`, `ledger_account_totals`, `payment_intents`,
`payment_provider_events`, `payment_reconciliation_events`, `payment_refund_requests`,
`payment_receiving_accounts`, `payout_orders`, `payout_provider_evidence`,
`payout_settlement_allocations`, `provider_fee_schedules`, `merchant_payables`,
`merchant_settlement_requests/policies/schedule_runs`, `finance_policies`, `finance_evidence_refs`,
`claims_reserves`, `customer_cancellation_debts`, `driver_cash_ledger`, `driver_cashout_requests`,
`driver_payout_policies`, `driver_promo_credits`, `driver_starter_credit_policies`,
`driver_group_commissions`, `driver_group_payout_statements(_items)`, `mission_financial_holds`,
`cash_order_runtime`, `chop_pay_order_runtime`, `package_runtime`, `topup_requests`,
`agent_topup_requests`, `feature_flags`. `SELECT` retained for read-only troubleshooting.

No product RLS policy, no `service_role` boundary and no `anon`/`authenticated` grant was touched.

**Post-fix proof (rolled back probes).** Production-mode inserts into `payment_provider_events`,
`provider_fee_schedules`, `ledger_postings` and `wallets` all fail with `permission denied for table`.
`sandbox_exec` finance-table `INSERT` count = **0**; `payment_provider_events` grant set is now
`SELECT` only. It still holds `SELECT, INSERT` on non-financial operational tables (unchanged
platform behaviour).

**Residual, stated honestly:** `sandbox_exec` retains `BYPASSRLS` and blanket `SELECT` (including
`auth.users` and finance tables) — it is a platform maintenance login, credentials held outside the
app, unreachable from any application path. It is *not* an app-surface exposure.

### Phase B — single untouched atomic sweep

Run once, in one transaction, after the last edit: `_qa_s13_run1() … _qa_s13_run7()`.
All seven result rows carry the identical transaction timestamp **2026-08-11 23:43:16.779052+00**
(prior historical batch max was 23:19:26), which is the final-batch identifier.

| Part | Result |
| --- | --- |
| 1 | **18 / 18** |
| 2 | **32 / 32** |
| 3 | **54 / 54** |
| 4 | **98 / 98** |
| 5 | **115 / 115** |
| 6 | **87 / 87** |
| 7 | **99 / 99** |
| **Total** | **503 / 503 PASS, 0 failures** |

Stale historical `_qa_s13_results` rows (including the `part=55` experiment rows) are **excluded** from
this board and were deliberately not deleted — they are historical, not release evidence.

### Post-sweep live posture (re-verified)
- Master wallet **-100435 GNF / held 0** (unchanged; deliberately not normalised — DEF-FIN-001 stands).
- `ledger_postings` sum **0** over **0 rows**, imbalanced journals **0**. Honest reading: production
  ledger tables are *empty*, so this is **rollback cleanliness** (the harness left nothing behind),
  not a proof of balanced live volume.
- Feature flags byte-identical; among finance rails only `om_topup_enabled` is **ON**. Stage 1–7 rails
  (`chop_pay_*`, `cash_order_funding_enabled`, `envoyer_enabled`, `merchant_om_settlement_enabled`,
  `driver_cashout_enabled`, `driver_balance_gate_enabled`, `driver_starter_credit_enabled`) all OFF.
- No financial fixture residue: 0 sandbox payment intents, 0 QA packages, 0 sandbox provider events.
- `_qa_s13_run1..run7`: `anon`/`authenticated` EXECUTE **denied**, `service_role` only.
- Internal money-moving primitives exposed to `anon`/`authenticated`: **0**.

### App regression (same final head)
- `tsgo -p tsconfig.app.json`: **PASS, 0 errors**
- `vitest run`: **PASS, 20/20**
- `vite build`: **PASS**, PWA service worker generated (134 precache entries).
  YELLOW: pre-existing chunk-size advisory (`mapbox-gl`, `index`) — unchanged, unrelated.

### YELLOW register (carried, unchanged)
- No live Orange Money provider receipt has ever been exercised — all inbound and outbound provider
  evidence remains production-format **synthetic**.
- No authenticated Finance-operator visual QA of `/admin/wallet/payouts` or `/admin/treasury`.

**No feature flag was activated. Slice 13 is closed.**
