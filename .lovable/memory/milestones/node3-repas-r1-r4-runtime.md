---
name: Node 3 Repas — R1–R4 canonical runtime
description: Repas order creation, idempotency, RLS lockdown and merchant/customer state machine moved to server-authoritative RPCs wired to the locked Slice 4/5 engines; 77/77 certification PASS
type: feature
---

# Node 3 Repas — R1–R4 canonical runtime (certified, flags OFF)

## Canonical behaviour
- `repas_order_create` is the only commitment path. It reprices from
  `food_menu_items`, ignores every client-supplied price/name, enforces
  availability, restaurant-ownership of items, open state, positive quantity,
  and delivery location. Tender is `cash` or `choppay` only — `wallet` is
  rejected as `UNSUPPORTED_TENDER`.
- Idempotency is by `client_request_id` + `request_fingerprint`. Identical
  replay returns the same order (`replay: true`); a contradictory replay is
  denied with `IDEMPOTENCY_CONFLICT` and commits nothing.
- Delivery orders create the `food_delivery` mission server-side with the
  courier earning frozen from `repas_delivery_earning_gnf()` (15 000 GNF).
- Cash orders stay financially inert until courier engagement; the runtime is
  created by `mission_claim` through the locked Slice 4 engine.
- Chop Pay orders authorize the full order total at commitment through the
  locked Slice 5 engine, inside the same transaction as the order row.
- `repas_merchant_transition` owns accept / prepare / ready / handoff /
  reject / complete. Illegal jumps raise `ILLEGAL_TRANSITION` and mutate
  nothing; accept and reject are idempotent.
- `repas_customer_cancel_order` is owner-only and locked once `preparing`.

## Security posture
- No customer/merchant `INSERT` or `UPDATE` policies remain on `food_orders`
  or `food_order_items`; participant reads preserved.
- `anon` holds no EXECUTE on any Repas commitment, transition, cancel or
  completion RPC. Slice 1–5 money primitives stay closed to app roles.

## Certification
`public._qa_node3_repas_r1_r4()` — expanded to **147 assertions, 147/147
PASS** after the R1–R4 micro-closeout (MC1 full idempotency fingerprint
incl. coordinates/notes, MC2 cash-rail fail-closed, MC3 pickup fail-closed,
MC4 pre-dispatch cash cancellation through Slice 8 + unpaid-debt cash block,
MC5 full positive Chop Pay lifecycle with exact reconciliation, MC6 contract
expansion). Fully rolled back (master wallet, feature flags, orders,
restaurants, cash / Chop Pay runtimes and cancellation debts residue-free).
Allowlisted in the `qa-node-harness` edge function; service-role only.

Micro-closeout regression sweep: Node 0 Course 34/34, Node 1 Bonbonna full
78/78, Bonbonna matrix 39/39, Node 2 Taxi 97/97, Slice 13 parts 1–3 104/104,
Vitest 28/28, typecheck clean.

Reconciliation proven end-to-end: customer out 166 500 = merchant 150 000 +
driver 15 000 + platform 1 500. Pre-dispatch cash cancellation fee = 8 250
(5% of 165 000).

Regression sweep re-run after the last edit:
Node 0 Course 34/34, Node 1 Bonbonna full 78/78, Bonbonna matrix 39/39,
Node 2 Taxi 97/97, Slice 13 parts 1–3 104/104. Slice 13 parts 4–7 could not
be executed from the available roles (those harnesses are not SECURITY
DEFINER; pre-existing environment limitation, unrelated to this pass).
Vitest 28/28, typecheck clean, production build + PWA PASS (26.39s).

## Flags
No flag was changed. `cash_order_funding_enabled`, `chop_pay_checkout_enabled`
and `chop_pay_enabled` remain OFF; the harness flips them only inside the
rolled-back fixture subtransaction and asserts they are byte-identical after.

## Out of scope (still open)
R5 pricing redesign (delivery/service fee model), R6 custody codes,
R7 customer tracking + receipts, R8 discovery cleanup (demo restaurants in
`FoodView.tsx`), R9 recovery, R10 ops tooling, R11 address/offline hardening.
Supply is still 0 approved `livraison` couriers, so Repas is
**ENGINEERING R1–R4 CLOSED / HOLD — SUPPLY + FLAGS**.
