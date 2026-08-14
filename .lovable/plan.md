# Node 3 R6 — INVALID_STATE Audit (read-only)

Audit only. No code, DB, grant, flag, or harness change was made.

## 1. Runtime state immediately after order create
`chop_pay_order_runtime.state = 'authorized'` (customer full-order hold secured, `driver_user_id` NULL, `mission_id` NULL for delivery until claim).

## 2. After merchant accept (`chop_pay_merchant_accept`)
`state = 'merchant_accepted'`, `funded_at` set, merchandise captured into `merchant_payables` (funded), `food_orders.state = 'confirmed'`.

Precondition (delivery / non-pickup): the runtime **must already be `accepted`**. Line: `ELSIF v_row.state <> 'accepted' THEN RAISE EXCEPTION 'INVALID_STATE' USING DETAIL = v_row.state;`
Only the pickup branch (`is_pickup` AND `mission_id IS NULL` AND `delivery_fee_gnf = 0`) may run from `authorized`.

## 3. After merchant prepare (`chop_pay_merchant_prepare`)
`state = 'preparing'`, `prep_locked_at` set, `food_orders.state = 'preparing'`.
Preconditions: state exactly `merchant_accepted`, payable fully funded, and — critically — driver collateral held (`DRIVER_COLLATERAL_NOT_SECURED` if `collateral_gnf > 0` and no live hold). That hold only exists after a courier accepted.

## 4. `mission_claim` effect / preconditions
Preconditions: authenticated, mission unclaimed, driver capability matches mission type.
Effect: sets `courier_id`, then for a Chop Pay source calls `_chop_pay_accept_internal`, which requires runtime `state = 'authorized'` and `missions.state = 'assigned'` (else `STALE_OFFER`), places the frozen collateral hold, creates the merchant payable, and moves runtime to **`accepted`**. Finally sets mission state `heading_to_pickup`.

## 5. State required by `_chop_pay_complete_internal`
`state IN ('preparing','merchant_accepted')` (or `disputed` when `p_from_dispute`). For `source_module = 'repas'` it additionally hard-requires `state = 'preparing'`, else `PREPARATION_REQUIRED_BEFORE_DELIVERY`. It also requires `pickup_confirmed` and mission state in picked_up / heading_to_dropoff / arrived_dropoff / delivered on the delivery path.

## 6. First call producing INVALID_STATE
`public.repas_merchant_transition(v_o1,'accept')` at harness line ~141 → `chop_pay_merchant_accept('repas', order)`.
- actual runtime state: `authorized`
- required runtime state (delivery path): `accepted`
- raised as `INVALID_STATE` with `DETAIL = 'authorized'`

The fixture currently runs `accept` → `prepare` → `ready` (lines ~141–143) and only calls `public.mission_claim(v_m1)` afterwards (line ~164). Before the previous reorder the symptom was the mirror image: completion ran while runtime was still `accepted`, so `_chop_pay_complete_internal` raised `INVALID_STATE`.

## 7. Defect classification
**Fixture ordering only — not a production lifecycle defect.**
The locked Slice 5 lifecycle is one consistent chain:
```text
authorized --mission_claim--> accepted --merchant_accept--> merchant_accepted
   --merchant_prepare--> preparing --ready(custody mint)--> handoff/delivery --> completed
```
Each guard is internally coherent: merchant funding capture is deliberately gated behind a committed courier (collateral first), and preparation behind funding + collateral. The harness asserts the reverse order. Widening `chop_pay_merchant_accept` to run from `authorized` on the delivery path, or letting `_chop_pay_complete_internal` accept `accepted`, would weaken locked R5 / Slice 5 semantics.

## 8. Smallest safe correction (proposed, not applied)
In `public._qa_node3_repas_r6_custody` only, move `PERFORM public.mission_claim(v_m1);` so it runs **before** `repas_merchant_transition(v_o1,'accept')`:

1. create order + mission (`authorized`, mission `assigned`)
2. A1.1 assert no credential yet
3. `mission_claim(v_m1)` → runtime `accepted`, collateral held, mission `heading_to_pickup`
4. `accept` → `merchant_accepted`; `prepare` → `preparing`; `ready` → mints `restaurant_handoff`
5. re-anchor A1.2 / A1.3: since claim already advanced the mission to `heading_to_pickup`, the "before arrival" negative case is proven by attempting `repas_custody_confirm_handoff` at `heading_to_pickup`; the existing `mission_set_state(v_m1,'heading_to_pickup')` line becomes redundant and only `arrived_pickup` remains
6. remaining A1.x / A2.x, delivery and economics assertions unchanged

Scope: one harness function body. No production function, grant, policy, flag, or file touched.

## Verification after the correction (when authorized)
Run `_qa_node3_repas_r6_custody`, then the frozen board: Node 0, Node 1, Node 2, Node 3 R1–R4 / pickup / R5 runtime, Slice 13.