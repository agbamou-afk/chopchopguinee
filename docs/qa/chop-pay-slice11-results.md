# Chop Pay Slice 11 — Merchant settlement + future payout engine

Run date: 2026-08-11 · Harness: `public._qa_s11_run()` (rollback fixture)
Result: **33 / 33 PASS**

## Accounting boundary implemented

```text
eligibility -> request/reservation -> outbound evidence -> reconciliation -> settlement
```

A merchant payable is only ever debited at the last step, and only when the
server itself proved the outbound transfer agrees on provider, reference,
recipient MSISDN, amount, provider status and environment.

## What was added

| Object | Role |
| --- | --- |
| `payout_orders` | Generalized payout spine (`merchant` / `driver` party), frozen fee + policy snapshot, reservation and status |
| `payout_provider_evidence` | Outbound transfer proof, globally unique normalized reference, reconciliation state |
| `payout_settlement_allocations` | Exact per-payable debit trail |
| `merchant_settlement_schedule_runs` | Idempotent scheduled queue generation per store + period |
| `_payout_order_create_internal` | Reservation (never money), internal only |
| `_payout_settle_internal` | The only place a payable is debited and a journal posted; internal only |
| `payout_record_provider_evidence` | Finance/God: record proof; exact match settles, anything else parks |
| `payout_reconcile_evidence` | Finance/God: retry reconciliation of recorded proof |
| `payout_reject_release` | Finance/God: release reservation exactly once, no money moves |
| `merchant_settlement_schedule_generate` | Queue only, cadence + minimum from settlement policy |
| `finance_payout_queue` | Admin read model: requested / awaiting_proof / manual_review / settled / rejected |
| `merchant_settlement_receipt` | Merchant receipt, only from reconciled evidence + ledger journal |

`merchant_finance_overview` now also returns `reserved_for_settlement_gnf`;
eligibility subtracts the greater of open requests and active reservations.

## Anchor scenario (in harness)

Merchant payable 500 000 GNF funded, request 300 000 GNF.

- Reservation: payable untouched, wallet 500 000, eligibility 200 000.
- Stage 5 flag OFF → `STAGE_DISABLED:merchant_om_settlement_enabled`, nothing moves.
- Incomplete / amount / recipient / environment / non-success proof → parked,
  `moved_gnf = 0`, payable untouched.
- Exact proof → settled: payable settled 300 000 (remaining 200 000),
  merchant wallet 200 000, journal `payout-settle:<order>` balanced (2 lines, sum 0).
- Replay of the same reference → `moved_gnf = 0`.
- Reuse of the same reference on another order → `PROVIDER_REFERENCE_ALREADY_CONSUMED`.
- Reject/release of a second order → 200 000 released once, second call releases 0.

## Assertions

- A1 reservation moves no money — **PASS**
- A2 reservation reduces eligibility — **PASS**
- A3 over-reservation blocked — **PASS**
- A4 request idempotent — **PASS**
- A5 Stage 5 gate blocks settlement — **PASS**
- A6 gated attempt moved no money — **PASS**
- A7 incomplete evidence parks for review — **PASS**
- A8 amount mismatch parks, moves nothing — **PASS**
- A9 recipient mismatch parks — **PASS**
- A10 environment mismatch parks — **PASS**
- A11 non-success provider status parks — **PASS**
- A12 exact evidence settles exactly — **PASS**
- A13 request marked settled — **PASS**
- A14 settlement journal balanced — **PASS**
- A15 payable allocation is exact — **PASS**
- A16 replay is idempotent — **PASS**
- A17 reference reuse blocked — **PASS**
- A18 reject releases reservation once, no money moves — **PASS**
- A19 reject is idempotent — **PASS**
- A20 receipt only from reconciled evidence — **PASS**
- A21 unsettled request has no receipt — **PASS**
- A22 scheduler never double-queues a period — **PASS**
- A23 merchant cannot read payout queue — **PASS**
- A24 merchant cannot record own payout evidence — **PASS**
- A25 Stage 6 driver payout still gated — **PASS**
- A26 anon has no payout execute — **PASS**
- A27 settlement primitives are internal-only — **PASS**
- A28 payout tables are read-only / anon-denied — **PASS**
- A29 provider evidence never readable by clients directly — **PASS**
- A30 global ledger zero-sum — **PASS**
- A31 master wallet baseline unchanged — **PASS**
- A32 stage flags remain OFF after run — **PASS**
- A33 no QA rows persisted — **PASS**

## Stage status after Slice 11

| Stage | Flag | State |
| --- | --- | --- |
| 5 — merchant OM settlement | `merchant_om_settlement_enabled` | **OFF (HOLD)** |
| 6 — driver payout | `driver_cashout_enabled` | **OFF (HOLD)** |
| 7 — Chop Pay P2P | `chop_pay_p2p_enabled` | **OFF (HOLD)** |
| OM inbound top-up | `om_topup_enabled` | ON (unchanged) |

Master wallet baseline unchanged at **-100 435 GNF**. Global ledger sum = 0.
No harness rows persisted (`payout_orders` count = 0 after the run).

## Remaining requirement to unlock Stage 5

An outbound Orange Money rail (or a recorded operational process producing
authentic provider references) must exist. The engine is otherwise complete:
there is no "mark as paid" action anywhere in the product.

---

# Slice 11 — Final Hardening Closeout

Run date: 2026-08-11 · Harness: extended `public._qa_s11_run()` (rollback fixture)
Result: **65 / 65 PASS** · 0 failures · harness dropped after the run.

## Independent-audit findings and their fixes

### 1. P1 — Legacy merchant settlement escape path (CLOSED)
`merchant_settlement_hold`, `merchant_settlement_complete` and
`merchant_settlement_fail` no longer contain money-moving logic. Each raises
`LEGACY_PATH_DISABLED:<name>` before any mutation, and every EXECUTE grant
(`anon`, `authenticated`, `service_role`, `PUBLIC`) was revoked. Historical
migrations are untouched; no product or admin surface calls them (only the
generated `types.ts` still lists the signatures).

Exit proof: assertion **A63** scans `pg_proc.prosrc` across the whole `public`
schema and finds **zero** function bodies other than `_payout_settle_internal`
that write `merchant_payables.settled_gnf`. **A64** proves the three legacy
functions have no callable grants. **A34–A37** prove live invocation attempts
raise and move exactly zero.

### 2. P1 — Legacy driver payout bypass (CLOSED)
`driver_payout_hold_place`, `driver_payout_confirm` and
`driver_cashout_mark_paid` now evaluate the Stage 6 gate before any financial
mutation and raise `STAGE_DISABLED:driver_cashout_enabled`. `authenticated`
EXECUTE was revoked from `driver_payout_confirm`, `driver_payout_cancel` and
`driver_payout_hold_place`; they are internal-only and reachable solely through
gated wrappers. No driver money moved in this closeout.

Exit proof: **A25**, **A38**, **A39**, **A40**, **A65**.

### 3. P1 — Debit point now revalidates evidence (CLOSED)
A shared validator `_payout_evidence_mismatch_reason` is called **inside**
`_payout_settle_internal` before `_finance_evidence_claim`, allocation, wallet
debit or ledger posting. It independently re-proves linkage, provider,
normalized reference uniqueness, recipient MSISDN, exact expected transfer
amount, frozen provider fee, successful provider status and environment, and
raises `EVIDENCE_VALIDATION_FAILED:<reason>` with zero mutation — even when
called directly as `service_role`.

Amount semantics are now singular: `payout_orders.expected_provider_transfer_gnf`
is frozen at reservation time (recipient-borne → principal − fee;
platform-borne → principal) and is the only accepted evidence amount. The
previous "either net or principal" tolerance is gone. The field is protected by
`_payout_order_immutable` and surfaced in `merchant_settlement_receipt`.

Exit proof: **A41–A43**, **A45**, **A46**, **A49**, **A52**.

### 4. QA gaps — real scheduler and non-zero fee (CLOSED)
Both previously vacuous areas are now proven with self-rolling-back fixtures.

**Configured scheduler** (`merchant_settlement_policies` fixture, daily cadence):
first run creates exactly one run row and one request for the eligible store
and period (**A58**); a second run in the same period creates zero additional
rows (**A59**); the next period creates the next request (**A60**); and the
scheduler debits nothing and posts no settlement journal (**A61**).

**Non-zero provider fee**, both canonical branches with a 5 000 GNF fixed fee:

| Branch | Principal | Fee | Merchant liability debit | Expected provider transfer | Journal |
| --- | --- | --- | --- | --- | --- |
| recipient-borne | 100 000 | 5 000 | 100 000 | 95 000 | 2 lines, sum 0, no fee expense |
| platform-borne | 100 000 | 5 000 | 100 000 | 100 000 | 3 lines, sum 0, `E_PROVIDER_FEE` exactly once for 5 000 |

Proven by **A44–A50** (recipient-borne, including principal-amount evidence now
rejected as `amount_mismatch` and fee mismatch parking) and **A53–A56**
(platform-borne). **A51** proves a later fee-schedule change does not alter an
already-reserved order. **A50**/**A56** prove replay moves zero. **A57** proves
one-reference-one-settlement holds across orders and namespaces.

## Assertion summary

- A1–A33: original Slice 11 suite, preserved unweakened (A22 retitled to
  "unconfigured scheduler never queues or double-queues"; the non-vacuous
  scheduler proof is A58–A61).
- A34–A37: legacy merchant settlement paths disabled and inert.
- A38–A40: legacy driver payout paths stage-gated.
- A41–A43: direct `service_role` settle attempts with bad evidence rejected, zero movement.
- A44–A50: recipient-borne non-zero fee economics.
- A51–A52: snapshot immutability.
- A53–A56: platform-borne non-zero fee economics and provider-fee expense posting.
- A57: cross-order reference uniqueness.
- A58–A61: configured scheduler, non-vacuous idempotency, pays nothing.
- A62: ledger zero-sum inside the run.
- A63: `_payout_settle_internal` is the only merchant-payable debit writer.
- A64–A65: legacy function grant matrix.

**Total: 65 assertions, 65 PASS, 0 FAIL.**

## Privilege matrix

- `anon`: no EXECUTE on any payout RPC (**A26**), no SELECT on payout tables (**A28**).
- `authenticated`: participant wrappers only, self-scoped; no INSERT/UPDATE/DELETE
  on payout tables; no SELECT on `payout_provider_evidence` (**A29**).
- Finance / God admin: queue, evidence recording, reconciliation, rejection — role-gated (**A23**, **A24**).
- Raw primitives (`_payout_settle_internal`, `_payout_order_create_internal`,
  `_merchant_settlement_request_queue_internal`, `_payout_evidence_mismatch_reason`):
  service-role only (**A27**). No `auth.uid() IS NULL` shortcut anywhere.

## Live post-state (verified after harness drop)

| Check | Value |
| --- | --- |
| `payout_orders` | 0 |
| `payout_provider_evidence` | 0 |
| `payout_settlement_allocations` | 0 |
| `merchant_settlement_schedule_runs` | 0 |
| `merchant_settlement_requests` | 0 |
| QA fee-schedule / policy fixture residue | 0 / 0 |
| Global ledger sum | 0 |
| Master wallet | **-100 435 GNF**, held 0 (unchanged) |
| `_qa_s11%` objects (tables + functions) | **0 / 0** |
| `merchant_om_settlement_enabled` | false |
| `driver_cashout_enabled` | false |
| `chop_pay_p2p_enabled` | false |
| `om_topup_enabled` | true (unchanged) |

## Build evidence

- `tsgo --noEmit -p tsconfig.app.json` — clean, zero diagnostics.
- Vitest — 4 files, **20/20 passing**.
- `vite build` — success in 24.35s.

## YELLOW register (honest, non-blocking)

- **PWA / chunk size**: production build emits the standard Vite warning that
  `index` (2.17 MB) and `mapbox-gl` (1.78 MB) exceed 500 kB after minification.
  PWA precache is 133 entries / ~11.9 MB. Pre-existing, unchanged by this
  closeout, tracked as a performance item.
- **Authenticated visual QA**: not performed — no real authenticated session is
  available in this environment. Stage 5/6/7 are OFF, so the payout console has
  no live queue to render regardless. **YELLOW**, not proven green.
- **Database linter**: 535 pre-existing INFO/WARN entries (RLS-enabled-no-policy
  on internal tables, mutable search_path on legacy functions). None introduced
  by this closeout.
- **Stage 5 remains blocked** by the absence of a real outbound Orange Money
  rail, exactly as recorded in the original Slice 11 report.

## Verdict

**PASS** — Slice 11 closeout complete. No merchant payable or merchant wallet
balance can be reduced for an external settlement except inside
`_payout_settle_internal`, and that primitive independently proves a unique,
successful, environment-matched provider evidence record with the exact
recipient and exact frozen transfer economics before any debit. Legacy merchant
and driver payout paths cannot bypass the Stage 5/6 gates. Scheduled queueing
and non-zero fee pass-through are non-vacuously proven. Replay moves zero.

Stopping after Slice 11.
