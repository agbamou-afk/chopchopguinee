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
