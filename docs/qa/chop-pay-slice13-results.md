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
