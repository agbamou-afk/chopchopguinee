# Node 3 — Repas R4.5 Retrait / Pickup Enablement (STABLE)

Baseline HEAD before slice: `518fc49` (Node 3 R1–R4 locked)
Slice HEAD: `cd798c42886159e6df053d8c1bbfcfd93e09f013`

## Money shape (audited, then implemented)
Pickup is a real product shape, not a delivery order without a courier:
- no mission, no courier offer, no delivery fee, no driver collateral, no driver earning
- merchandise = server-repriced menu truth
- platform fee = current effective-dated `finance_policies` row for `repas`
  (`transaction_fee_bps = 100` → 1%, `fee_basis = merchandise_subtotal`), frozen
  in `policy_snapshot` on the runtime at commitment
- customer total = merchandise + fee

## R4.5-A / B — canonical economics + Chop Pay pickup
- `_chop_pay_facts` now exposes `fulfillment` / `is_pickup`.
- `_chop_pay_customer_hold_internal`: pickup allowed with `mission_id IS NULL`;
  fails closed on `PICKUP_MUST_HAVE_NO_MISSION` and
  `PICKUP_MUST_HAVE_ZERO_DELIVERY_FEE`; collateral forced to 0.
- `chop_pay_merchant_accept`: pickup funds the merchant payable directly from
  `authorized` (no courier accept step) — merchandise captured once.
- `_chop_pay_complete_internal`: pickup skips courier custody/mission checks and
  refuses corrupt pickup economics; captures fee, releases residual.
- `chop_pay_merchant_pickup_complete(text,uuid)`: merchant/finance-only handover
  confirmation, requires product state `ready`. anon EXECUTE revoked.
- `repas_merchant_transition`: `handoff` refused on pickup
  (`PICKUP_HAS_NO_COURIER_HANDOFF`); `complete` on a Chop Pay pickup routes to
  the canonical engine only from `ready`.

## R4.5-C — cash pickup: honest result
Cash pickup is REFUSED at commitment with `PICKUP_CASH_NOT_SUPPORTED` before any
row, mission or money. There is no canonical primitive that collects the
platform fee on a cash pickup (no courier float to net it from), and no
merchant-debt rail exists. Shipping it would have required either fake revenue
or an unbacked receivable. Deferred, not faked.

## R4.5-D — admin-editable fee
No new control was required: `admin_set_finance_policy` already accepts
`p_transaction_fee_bps` / `p_fee_basis` for `repas`, is God-Admin only, requires
a ≥5-char reason, is append-only and effective-dated (`BACKDATING_REJECTED`,
`EFFECTIVE_FROM_NOT_MONOTONIC`), and is surfaced in the finance policy admin UI.
Existing orders keep their frozen snapshot.

## R4.5-E — client / merchant truth
- `repas_quote_preview(uuid,jsonb,text)` — server-authoritative pre-commit quote
  (subtotal, delivery fee, platform fee, total, rail availability). anon revoked.
- `RepasRestaurantDetail`: Retrait is selectable when the restaurant supports it,
  forces Chop Pay, hides delivery address, and shows the server quote breakdown.
- Merchant dashboard: pickup shows "Client a récupéré" instead of a courier
  handoff step.

## R4.5-F — QA
`public._qa_node3_repas_pickup()` — 63 assertions, rollback-clean:
static security/shape, policy 1% truth + admin editability, cash-pickup
fail-closed with zero side effects, quote truth, commitment shape (no mission,
0 delivery, 0 collateral, fee 1500 on 150 000), lifecycle incl. negative
handoff/early-complete/stranger-confirm, conservation
(151 500 = 150 000 merchant + 1 500 platform + 0 driver), zero-sum journals.

## Regression at slice HEAD (all green)
- Node 3 Repas pickup: 63/63
- Node 3 Repas R1–R4: 147/147 (B0.13/B0.14/M1.1/M1.2 updated for the shipped rail)
- Node 0 Course 34/34 · Node 1 Bonbonna 78/78 · Node 2 Taxi 97/97
- Slice 13 parts 1–7: 507/507
- Vitest 28/28 · `bun run build` + PWA generateSW PASS

## Posture
No feature flag was activated. `cash_order_funding_enabled` unchanged;
`chop_pay_checkout_enabled` unchanged (only toggled inside rolled-back fixtures).
