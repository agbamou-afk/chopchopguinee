# Chop Pay — Slice 3 closeout report

Covers Slice 3 (ride + Bonbonna runtime), Slice 3B hardening, and the Slice 3C
micro-closeout (driver-targeted OM top-up recovery). Both milestones remain
**UNLOCKED**.

---

## Part 1 — Slice 3B hardening (prior run)

Harness: `_qa_s3b_run()` (self-rolling-back, raises `QA_S3B_RESULT`).

## Outcome — 60/61 assertions PASS

Key money proofs
- 100 000 GNF cash ride → commission reserve 10 000, captured exactly once (replay adds zero).
- Chop Pay ride → customer debited 100 000, driver net +90 000, platform +10 000.
- Bonbonna mission type resolves to `bonbonna`, reserve 10 000.
- Insufficient hold → `SETTLEMENT_REQUIRED_INSUFFICIENT_HOLD`, no capture, no driver credit, ride not completed.
- Cancellation: before dispatch 5 000, after dispatch 10 000, replay creates no duplicate debt.
- Snapshot survives a post-acceptance policy edit (commission split and cancel bps unchanged).
- Driver-caused cancellation: zero fee and **no** customer debt row.
- Ledger journals zero-sum; posting update / journal delete denied.

Security matrix
- `wallet_internal_transfer`: anon denied, authenticated denied, service_role allowed.
- `ride_accept` / `ride_dispatch`: anon + authenticated denied; only `driver_offer_accept_for_ride`
  and `ride_request_dispatch` are public entrypoints.
- Cross-driver offer acceptance and cross-driver completion denied; premature completion denied
  (`PICKUP_CONFIRMATION_REQUIRED`).
- Enabled finance flags: `om_topup_enabled` only.

## Defects fixed during this run
- DEF-FIN-002 — cancellation fee resolved from live policy instead of the ride's frozen snapshot.
  `customer_cancellation_debt_create` now accepts `p_policy_snapshot` and `ride_cancel` passes the
  ride snapshot.
- DEF-FIN-003 — non-customer-caused cancellations created a zero-amount debt row. They now create none.
- `ride_complete` called `_is_god_admin()` with no argument (runtime failure on admin override path).

## Known harness gap (not a product defect)
- `E2.eligible_after_topup` — the OM top-up pathway credits the **client** wallet and requires a
  `payment_provider_events` row; the harness calls it against a driver with no client wallet, so it
  reports `Wallet not found`. Driver funding via top-up + client→driver internal transfer must be
  re-tested in the Slice 4 harness.

> **Superseded.** Read-only verification proved this was a *real product gap*, not a harness
> artefact — see Part 2.

---

## Part 2 — Slice 3C: driver OM top-up recovery

### Why E2 was a real product gap
- `wallet_topup_om_create` resolved and required the caller's `party_type='client'` wallet.
- `wallet_topup_om_credit` credited only that client wallet.
- Ride/Bonbonna eligibility reads the `party_type='driver'` operating wallet.

A driver could therefore complete a confirmed Orange Money top-up and stay financially
ineligible. There was no path — automatic or manual — from a confirmed provider event to the
driver operating balance.

### Fix (extend, do not break)
- `topup_requests.target_party_type text NOT NULL DEFAULT 'client'`, `CHECK (in ('client','driver'))`.
  Legacy rows resolve as `client`.
- `wallet_topup_om_create` unchanged in behaviour; now writes `target_party_type='client'` explicitly.
- New `driver_wallet_topup_om_create(p_amount_gnf, p_receiving_account_id)` — self-only
  (no user parameter), requires `driver_profiles.status='approved'`, `_driver_finance_eligible`,
  and an existing **active** `party_type='driver'` wallet. `EXECUTE` revoked from `PUBLIC`/`anon`,
  granted to `authenticated`/`service_role`.
- `wallet_topup_om_credit` credits the wallet the request explicitly targeted (master → target
  contra), never guessing from driver-profile existence. No client→driver internal transfer is used.
- UI: `TopUpOrangeMoney` accepts `target="client" | "driver"`; the driver earnings screen opens a
  driver-targeted sheet instead of routing into the customer wallet.

### E-series proof — harness `_qa_s3c_run()` (self-rolling-back, real `om_auto_match` path)

| ID | Assertion | Result |
| -- | --------- | ------ |
| E1 | Approved driver, 0 available → ineligible for 100 000 GNF ride (required 10 000, available 0) | PASS |
| E2 | Driver-targeted request created via real RPC — `target_party_type='driver'`, owner = caller, 50 000 | PASS |
| E3 | Customer OM code + `payment_provider_events` fixture → `om_auto_match` = `credited` (`code_match`) | PASS |
| E4 | Driver wallet +50 000 | PASS |
| E5 | Same user's client wallet unchanged (+0) | PASS |
| E6 | Master/treasury −50 000 contra only; single `topup` txn master→driver; no revenue txn | PASS |
| E7 | `driver_financial_eligibility('ride',100000)` becomes eligible automatically (available 50 000) | PASS |
| E8 | No `unblocked` flag; eligibility equals `balance_gnf - held_gnf` from wallet truth | PASS |
| E9 | Replay of `wallet_topup_om_credit` returns the same txn, zero delta, exactly 1 txn per event | PASS |
| E10 | Self-only signature (2 args); non-driver caller denied (`driver_profile_not_found`) | PASS |
| E11 | Ordinary customer top-up still targets `client`, credits client wallet, no driver wallet created | PASS |

### Slice 3 critical regression (re-run, `_qa_s3b_run()`)
All previously green money/security assertions re-confirmed PASS:
100k cash ride → reserve 10 000, captured once, no 90 000 wallet credit, replay zero ·
Bonbonna 10 000 · Chop Pay −100 000 / +90 000 / +10 000, replay zero ·
insufficient hold blocks settlement (`SETTLEMENT_REQUIRED_INSUFFICIENT_HOLD`) ·
`PICKUP_CONFIRMATION_REQUIRED` enforced · customer / cross-driver / premature completion denied ·
cancellation 5 % before dispatch, 10 % after, driver-caused zero fee and no debt row ·
journals zero-sum, posting update and journal delete denied.
The only non-PASS remained the harness's own client-wallet `E2` stub, now superseded by Part 2.

### Privilege matrix (unchanged from 622067bd)

| Function | anon | authenticated | service_role |
| -------- | ---- | ------------- | ------------ |
| `wallet_internal_transfer` | denied | denied | allowed |
| `ride_accept` | denied | denied | allowed |
| `ride_dispatch` | denied | denied | allowed |
| `driver_offer_accept` | denied | allowed | allowed |
| `ride_request_dispatch` | denied | allowed | allowed |
| `driver_wallet_topup_om_create` | denied | allowed | allowed |

### Cleanup — read-only counts after rollback
- `pg_proc` matching `_qa_s3%`: **0** (`_qa_s3b_run`, `_qa_s3b_ok`, `_qa_s3b_guards`, `_qa_s3c_run` dropped).
- `audit_logs` for `qa.slice3` / `qa.slice3b`: **0**.
- QA provider events (`raw_payload->>'source'='qa_sandbox'`): **0**.
- `topup_requests` with `target_party_type='driver'`: **0**; with NULL target: **0**.
- Orphan synthetic driver profiles: **0**.
- Canonical finance flags enabled: **`om_topup_enabled` only** (all 10 others verified OFF).

### Build / type / test / PWA evidence
- `tsgo --noEmit` — clean (exit 0), after `types.ts` regeneration (10 hits for
  `driver_wallet_topup_om_create` / `target_party_type`).
- Vitest — **12 passed / 12** (2 files).
- `vite build` — green in 23.06 s.
- PWA `generateSW` — precache **129 entries (11 855.71 KiB)**; largest single asset
  `index-*.js` **2 131.94 kB**, under the 4 MiB per-file constraint.

### Visual QA — **YELLOW**
No authenticated preview session was available (`signed_out`), so the driver Ride/Bonbonna flow and
the new driver top-up CTA were **not** visually verified. No visual PASS is claimed.

### Standing items
- DEF-FIN-001 (negative platform balance) — unchanged, still open.
- Milestones `chop-pay-ledger-revival-stable` and Slice 3 lock candidate — **UNLOCKED**.

### Exit verdict — Slice 3 PASS
Automatic driver top-up recovery is demonstrated end-to-end through a confirmed Orange Money
provider event into the driver operating wallet, with idempotency, isolation, and cleanup proven.

---

## Part 3 — Slice 3D: inbound-OM privilege micro-closeout

### Defect (P1)
`om_auto_match(uuid)` and `wallet_topup_om_credit(uuid,uuid)` were `EXECUTE`-able by `anon`
and `authenticated`. Both are `SECURITY DEFINER`; `om_auto_match` had no caller guard and
`wallet_topup_om_credit` treated `auth.uid() IS NULL` as the trusted/service branch, so an
anonymous invocation entered the path intended for `service_role`.

### Fix (internal primitives only)
- `REVOKE ALL` on both functions from `PUBLIC`, `anon`, `authenticated`; `GRANT EXECUTE` to
  `service_role` only. No behavioural change to amount, status, matching, rate/high-value,
  `target_party_type` or idempotency checks.
- Direct-caller audit found exactly one authenticated caller: the admin Reconciliation OM
  "approve candidate" action in `src/pages/admin/WalletReconciliation.tsx`.
  New `admin_manual_om_credit(uuid,uuid)` — `SECURITY DEFINER`, `SET search_path = public`,
  requires `can_manage_wallet(auth.uid())`, granted to `authenticated`/`service_role` — now
  fronts that call. The UI calls the wrapper.
- Trusted internal callers unchanged and still work because they are `SECURITY DEFINER`:
  `submit_customer_om_code`, `admin_record_om_receipt`, `admin_retry_om_credit`,
  `om_import_csv` edge function (service_role).

### Targeted QA — harness `_qa_s3d_run()` (self-rolling-back, dropped after the run)
**23/23 assertions PASS.**

| ID | Assertion | Result |
| -- | --------- | ------ |
| A1 | `anon` cannot execute `om_auto_match` | PASS |
| A2 | `authenticated` cannot execute `om_auto_match` | PASS |
| A3 | `anon` cannot execute `wallet_topup_om_credit` | PASS |
| A4 | `authenticated` cannot execute `wallet_topup_om_credit` | PASS |
| A5 | `service_role` can execute both primitives | PASS |
| A6 | `submit_customer_om_code` still open to the customer | PASS |
| A7 | `admin_record_om_receipt` / `admin_retry_om_credit` / `admin_manual_om_credit` still open to authorized admins | PASS |
| E1 | Approved driver, 0 available → ineligible for 100 000 GNF ride | PASS |
| E2 | `driver_wallet_topup_om_create(50 000)` → `target_party_type='driver'`, owner = caller | PASS |
| E3 | Real `submit_customer_om_code` + provider event → `om_auto_match` = `credited` (`code_match`) | PASS |
| E4 | Driver wallet +50 000 | PASS |
| E5 | Same user's client wallet +0 | PASS |
| E6 | Master −50 000 contra only; exactly 1 `topup` txn master → driver | PASS |
| E7 | `driver_financial_eligibility('ride',100000)` becomes eligible automatically | PASS |
| E8 | No `unblocked` flag — eligibility is pure `balance_gnf - held_gnf` | PASS |
| E9 | Replay of `wallet_topup_om_credit` adds zero (1 txn, balance unchanged) | PASS |
| E10 | Non-driver caller denied by `driver_wallet_topup_om_create` | PASS |
| E11 | Ordinary customer top-up still targets `client` | PASS |
| G1 | `ride_accept` authenticated = false | PASS |
| G2 | `ride_dispatch` anon = false | PASS |
| G3 | `ride_dispatch` authenticated = false | PASS |
| G4 | `wallet_internal_transfer` authenticated = false | PASS |

### Cleanup — read-only proof after rollback
- `pg_proc` matching `_qa_s3%`: **0**
- Slice 3 QA audit rows (`module like 'qa.slice3%'`): **0**
- QA provider events (`raw_payload->>'source'='qa_sandbox'`): **0**
- `topup_requests` with `target_party_type='driver'`: **0**; NULL target: **0**
- Synthetic QA auth users: **0**
- Canonical finance flags: **`om_topup_enabled` only**; all 16 others (`chop_pay_*` ×5,
  `om_*` ×10, `driver_cashout_enabled`, `merchant_om_settlement_enabled`,
  `merchant_wallet_enabled`, `wallet_public_enabled`) false. Legacy non-canonical `wallet`
  flag unchanged.
- DEF-FIN-001 master wallet: **−100 435 GNF**, unchanged after rollback.

### Build / type / test / PWA evidence (this commit)
- `tsgo --noEmit` — clean (exit 0); `types.ts` regenerated (`admin_manual_om_credit` present).
- Vitest — **12 passed / 12** (2 files).
- `vite build` — green in 18.65 s.
- PWA `generateSW` — precache **129 entries (11 855.71 KiB)**; largest single asset
  `index-*.js` **2 131.94 kB**, under the 4 MiB per-file constraint.

### Visual QA — **YELLOW**
Preview session remains signed out; the admin Reconciliation OM approve action was not
visually exercised. No visual PASS claimed.

### Slice 3D verdict — PASS
Both inbound-OM primitives are now internal (`service_role` only), the legitimate customer
and admin entrypoints are intact, and the full driver recovery E1–E11 path still passes
through the real matching flow. Milestones remain **UNLOCKED**; Slice 4 not started.
