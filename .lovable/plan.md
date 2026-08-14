# Node 3 Repas R7 — Tracking + Receipt Truth (read-only audit + surgical plan)

Baseline audited at certified R6 HEAD. No files, migrations, DB objects, flags, grants, policies or data were changed during this audit.

## 1. Customer tracking today

- There is **no dedicated Repas tracking screen**. After checkout, `src/components/food/RepasRestaurantDetail.tsx` switches to a local `stage = "confirmed"` panel holding `lastOrderId` / `lastMissionId` in component state; leaving the sheet loses it.
- Ongoing visibility comes only from the generic activity feed: `src/lib/activity/useActivityFeed.ts` does a one-shot `listMyFoodOrders` (`select *` on `food_orders`, limit 20) plus `listCustomerMissions`. **No realtime subscription and no polling** on `food_orders` or the Repas mission — the customer must leave and re-enter to see a state change.
- `src/hooks/useCustomerMissionAlerts.ts` subscribes to `missions` UPDATE for toasts only; it never feeds a tracked view, and it does not cover `food_orders.state` (merchant-side transitions are invisible in realtime).
- Order and mission produce **two separate activity rows** (`food:<id>` and `mission:<id>`) with different titles/statuses — the customer sees the same delivery twice with potentially divergent status.
- Courier identity, phone, live location and ETA are **not surfaced at all** on the customer side for Repas (unlike Course). Cancellation/dispute/failed states are only reachable as a generic status word.
- Pickup (Retrait) has no distinct tracking: the same generic rows are shown; only the R6 `CustodyCodeCard` in `ActivityDetailSheet` distinguishes it, and it renders **both** delivery and pickup code cards unconditionally for any non-completed order.

## 2. Merchant tracking today

`src/components/merchant/repas/RepasOrdersSection.tsx` polls every 30s via `listRestaurantOrders`, and detail comes from `getRestaurantOrderDetail` (`src/lib/repas/merchantOps.ts`) which reads `food_orders` `select *`, `food_order_items`, `profiles`, `missions` as four direct table reads.

Transitions correctly go through the canonical `repas_merchant_transition` RPC, but the **next-action affordance is a local assumption**: `restaurantNextState` / `RESTAURANT_NEXT_STATE` in `src/lib/merchant/operations.ts` plus a local `custodyBoundary()` heuristic in the component. The server state machine is never asked "what may I do now?", so button availability can drift from server truth.

## 3. Courier tracking today

`src/components/driver/ActiveMissionCard.tsx` derives Repas behaviour from `mission.type === "food_delivery"` and `mission.state`, and routes both handovers through the R6 `RepasCustodySheet` (real photo + one-time code). This is the healthiest of the three: custody truth is server-owned. Remaining gap: it reads mission rows directly and keeps local `custodyPhase`; it does not read `repas_custody_status` to reflect what is actually still pending, so a code consumed on another device is not reflected until refresh.

## 4. Receipts today

There is **no Repas receipt**. `src/components/activity/ActivityDetailSheet.tsx` shows only: amount (`-subtotal_gnf`), status, date, reference. It shows **no line items, no quantities, no frozen unit prices, no delivery fee, no promo, no platform fee, no order total, no payment method, no fulfillment, no restaurant name, no custody timeline**.

The frozen truth already exists server-side and is unused by the client: `food_orders` carries `base_delivery_fee_gnf`, `delivery_fee_gnf`, `promo_discount_gnf`, `platform_fee_gnf`, `order_total_gnf`, `courier_payout_gnf`, `pricing_policy_id`, `promotion_id`, `delivery_distance_km`, `pricing_snapshot`, `paid_at`, `completed_at`; `food_order_items` carries `name_snapshot`, `unit_price_gnf`, `qty`.

## 5. Client-side recomputation

The activity row shows `-o.subtotal_gnf` as the customer amount — that is **merchandise only**, not `order_total_gnf`, so the displayed amount is already wrong for any delivery order with a fee. No live-menu recomputation was found (checkout is fully server-priced via `repas_quote_preview` / `repas_order_create`), so the defect is *wrong field selection*, not recomputation.

## 6. Spoofing / drift risk

- RLS on `food_orders` and `food_order_items` is SELECT-only for the customer and the restaurant owner; there is **no client INSERT/UPDATE path**, so tracking values cannot be spoofed by writes.
- However the customer's SELECT policy is **row-level, not column-level**, and the app uses `select *`. `courier_payout_gnf`, `pricing_policy_id`, `promotion_id` and `pricing_snapshot` are therefore **already retrievable by the customer** today. Nothing renders them, but the exposure is real and R7 must not build on `select *`.
- `missions` exposes `estimated_earning_gnf` to `customer_id` rows through "Customer reads own missions" — same class of private-finance exposure.

## 7. Existing surfaces reusable by R7

RPCs: `repas_quote_preview`, `repas_order_create`, `repas_merchant_transition`, `repas_customer_cancel_order`, `repas_complete_order`, `repas_custody_status`, `repas_custody_code_view`, `repas_custody_confirm_handoff/_delivery/_pickup_collection`, `repas_pricing_effective`.
Client: `src/lib/repas/orders.ts`, `merchantOps.ts`, `custody.ts`, `types.ts`, `src/lib/missions/missions.ts`, `useActivityFeed.ts`.
There is **no** read model RPC or view for tracking or receipts.

## 8. Gaps blocking R7 certification

1. No canonical participant-scoped read model → three surfaces each assemble their own truth.
2. No realtime/reconnect-safe tracking for `food_orders` state.
3. Duplicate order/mission activity rows; terminal states (cancelled / failed / dispute) not distinctly rendered.
4. No pickup-specific tracking path.
5. No itemized immutable receipt; customer amount uses the wrong field.
6. No tender / promotion / policy-snapshot truth on any surface.
7. Courier payout and mission earning are reachable by the customer via `select *` / broad row policies.
8. Merchant next-action derives from local tables rather than server truth.

## 9. Proposed smallest surgical R7 implementation

**Server (additive only, no change to R1–R6 behaviour):**
- `public.repas_order_tracking(p_order_id uuid)` — SECURITY DEFINER, read-only, participant-authorized (customer / restaurant owner / assigned courier / finance-privileged), returning a role-shaped JSON: canonical order state, fulfillment, restaurant identity, mission state + courier display name/phone only when assigned and only for the customer, custody pending flags from `repas_custody_status`, terminal/cancellation reason, allowed next actions for the merchant. **Never** returns `courier_payout_gnf` or `estimated_earning_gnf` to the customer.
- `public.repas_order_receipt(p_order_id uuid)` — SECURITY DEFINER, read-only, participant-authorized, returning frozen persisted truth only: line items (`name_snapshot`, `qty`, `unit_price_gnf`, line total), merchandise subtotal, `base_delivery_fee_gnf`, `promo_discount_gnf` + promotion name, `delivery_fee_gnf`, `platform_fee_gnf`, `order_total_gnf`, payment method + payment status, fulfillment, restaurant, `created_at` / `paid_at` / `completed_at`, custody event timeline. Courier payout and policy internals are exposed **only** to the courier's own payout view and finance roles.
- Grants: `EXECUTE` to `authenticated` only; revoke from `anon`/`PUBLIC`.

**Client (French-first, no redesign):**
- `src/lib/repas/tracking.ts` — typed wrappers + French label maps for both RPCs.
- `src/components/repas/RepasOrderTrackingSheet.tsx` — one tracking sheet for delivery and pickup, subscribed to `food_orders` (filter `id=eq.`) and `missions` (filter `ref_food_order_id=eq.`) with a refetch-on-reconnect/visibility fallback.
- `src/components/repas/RepasReceiptSheet.tsx` — itemized receipt rendered strictly from `repas_order_receipt`.
- `src/lib/activity/useActivityFeed.ts` — dedupe the food-order/mission pair into one row and use `order_total_gnf` instead of `subtotal_gnf`; stop selecting `*`.
- `src/components/activity/ActivityDetailSheet.tsx` — open tracking for live orders, receipt for terminal ones; render only the custody card matching the actual fulfillment.
- `src/components/merchant/repas/RepasOrdersSection.tsx` — drive next-action from the server-returned allowed actions instead of `restaurantNextState`.
- `src/components/driver/ActiveMissionCard.tsx` — read pending custody phase from tracking truth instead of local-only state.

**Harness:** `public._qa_node3_repas_r7_tracking_receipt()`, rollback-clean, non-vacuous, asserting: participant authorization (customer / owner / courier allowed; stranger denied), courier-payout absence in every customer payload, receipt equals frozen persisted values and is unaffected by mutating `food_menu_items` prices afterwards, promotion and tender truth, delivery vs pickup shape, terminal-state truth for completed and cancelled orders, idempotent/read-only behaviour (repeat calls byte-identical, no rows written, no custody credentials burned), and `anon` EXECUTE denial. Then the full frozen board (R6, R5 static/runtime, R4.5, R1–R4, Nodes 0/1/2, Slice 13, Vitest, typecheck, build).

## Operational, not code-blocking
- Live Repas courier supply is 0, so live delivery tracking cannot be exercised in production regardless of this work.
- Finance flags remain OFF; R7 changes nothing about activation.
- Column-level exposure of `courier_payout_gnf` via `select *` is pre-existing; R7 removes the client dependency on it, but a follow-up hardening pass (column-restricted view or narrowed policy) is recommended and is out of R7 scope unless you want it folded in.
