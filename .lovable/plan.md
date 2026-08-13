# READ-ONLY SERVICE AUDIT — REPAS (Service Node 3 candidate)

Audit only. No code, DB, migration, flag, policy, test, doc, config, package or secret was changed.

## 1. Current architecture / lifecycle map

Client discovery
- `FoodView.tsx` → `listOpenRestaurants()` reads `food_restaurants` where `status='active'`, ordered by `is_open, name`. Non-"live" users are shown a hardcoded array of 6 fictional restaurants (`allRestaurants`) with fake ratings/distances/menus.
- `RepasRestaurantDetail.tsx` → `listMenu()` reads `food_menu_items`, groups by `category`, disables items when `!is_available || !restaurant.is_open`.
- Cart is `localStorage` only (`cc_repas_cart_v1`), single-restaurant, no server cart.

Order creation (`src/lib/repas/orders.ts`)
- Direct client `INSERT` into `food_orders` with client-computed `subtotal_gnf`, then a second `INSERT` into `food_order_items`. No RPC, no transaction, no idempotency key, no fee/snapshot.
- If `payment_method='wallet'`: best-effort `choppay_create_payment_intent` (repas / `repas_payment`), then client `UPDATE food_orders.payment_status`.
- If `fulfillment='delivery'`: best-effort `createMission({type:'food_delivery', ref_food_order_id})` with a hardcoded `REPAS_DEFAULT_COURIER_EARNING_GNF = 15000`. Failures are swallowed to `deliveryPending`.

Merchant operations (`src/lib/merchant/operations.ts`, `components/merchant/repas/*`)
- Linear state machine `placed → confirmed → preparing → ready → out_for_delivery → completed` via direct table `UPDATE`, except:
  - cash orders route to `cash_order_merchant_accept` / `cash_order_merchant_prepare` (Slice 4 engine) and refuse direct writes past `preparing`;
  - `completed` routes to `repas_complete_order()` (SECURITY DEFINER; capture + settle).
- No reject action, no sold-out/partial-item action, no cancel action in the merchant UI.

Driver
- Generic mission spine: `missions` + `mission_claim` / `mission_set_state`; `food_delivery` pipeline copy exists in `pipelines.ts`; `ActiveMissionCard` renders the cash/Chop Pay panel and the order thread.

Finance
- Cash: `cash_order_runtime` + `cash_order_*` RPCs (locked Slice 4).
- Chop Pay: `chop_pay_order_runtime` (locked Slice 5), plus `repas_capture_and_settle_order` / `admin_repas_capture_and_settle_order`.
- Guards: `prevent_unsafe_food_order_completion` (wallet only), `prevent_unsafe_food_order_payment_status_update` (blocks client `paid/refunded/captured/confirmed`).

Admin/support
- `RepasAdmin.tsx` (order list), `RepasPayments.tsx` (settlement preview + capture), `SupportAdmin` shows `related_food_order_id`, `OpsCommandCenter` counts.

Live database state (read-only)
- `feature_flags`: `repas=true`; `chop_pay_checkout_enabled=false`, `cash_order_funding_enabled=false`, `om_repas_checkout_enabled=false`, `chop_pay_enabled=false`.
- `food_restaurants`: 1 row — "Le bon coin", Dixinn, active, open, **0 menu items**, `delivery_available=false`, `choppay_enabled=false`, `verification_state='none'`, no `merchant_store_id`.
- `food_menu_items`: 0. `food_orders`: 0. `food_order_threads`: 0. `cash_order_runtime` / `chop_pay_order_runtime`: 0 Repas rows. `missions` of type `food_delivery`: 0.
- Driver supply: `driver_profiles` = 4 approved + 2 suspended, **all `vehicle_type='moto'`**; 0 `livraison`.

## 2. What is already strong

- Finance primitives exist and are locked/server-authoritative for both tenders (cash engine Slice 4, Chop Pay engine Slice 5), with the money-moving `_cash_order_*` internals restricted to `service_role`.
- Completion and `payment_status` are trigger-protected against client forgery; `repas_complete_order` enforces owner/admin authorization and `FOR UPDATE` locking.
- RLS isolation on read paths is coherent: customer / restaurant owner / admin scoping on `food_orders`, `food_order_items`, `food_order_threads`, `food_order_messages`; public read of menus limited to active restaurants.
- Order-bound messaging (client↔restaurant↔courier) exists with participant-scoped policies.
- Merchant dashboard (menu CRUD with photo upload, profile, orders) and a Repas-native MerchantHub layout exist.
- Mission spine reuse gives Repas driver dispatch, pickup/dropoff phases, and delivery copy for free.
- Admin has a settlement preview + capture surface and support ticket linkage.

## 3. Gap register

| ID | Gap | Sev | Evidence grade |
|----|-----|-----|----------------|
| REP-G1 | Order creation is a raw client `INSERT`; `subtotal_gnf` is computed in the browser and trusted. No `repas_order_create` RPC, no server re-pricing against `food_menu_items`, no availability/open-state re-check, no atomicity between order and items. | P0 | Verified (`src/lib/repas/orders.ts`, `food_orders` INSERT policy `auth.uid()=user_id` only) |
| REP-G2 | No idempotency/retry key. A double tap or network retry creates duplicate orders and duplicate payment intents. | P0 | Verified (no request-id column, no client persistence unlike `bookingRequestId.ts`) |
| REP-G3 | Customer `UPDATE` policy allows any column change while state is `placed`/`confirmed` (`with_check` only checks `user_id`) — a customer can mutate `subtotal_gnf`, `payment_method`, `restaurant_id`, `fulfillment`. | P0 | Verified (`Users cancel own pending orders` policy) |
| REP-G4 | No customer cancellation UI at all, and no cancellation engine binding for Repas (no `_cancellation_compute` path, no fee, no hold release). The "blocked after En préparation" rule holds only as a side effect of the RLS state filter for direct writes. | P0 | Verified (no cancel call in Repas client code; policy filter is the only guard) |
| REP-G5 | No merchant reject / sold-out / partial-item flow for non-cash orders. `cash_order_merchant_reject` exists but is not surfaced; nothing reverses a Chop Pay authorization on refusal. | P0 | Verified (`RESTAURANT_NEXT_STATE` is linear; no reject in `RepasOrdersSection`) |
| REP-G6 | Catalog is effectively empty: 1 restaurant, 0 menu items, delivery disabled, unverified. The service cannot be exercised end-to-end today. | P0 | Verified (DB counts) |
| REP-G7 | Zero delivery driver supply for food: all approved drivers are `moto`; no `livraison` vehicle type, and no food-specific eligibility/exclusion rules analogous to `_ride_required_vehicle`. | P0 | Verified (`driver_profiles` counts) |
| REP-G8 | Fake restaurant data still ships in `FoodView.tsx` (6 invented restaurants, invented ratings/ETAs/prices) for non-live users, plus non-factual `LiveStrip` claims ("Livraison en 15 min", "Restaurants notés 4.5+"). | P0 | Verified (source) |
| REP-G9 | Pricing model is incomplete: no delivery fee, no service/platform fee, no minimum order, no distance component; courier earning is a hardcoded 15 000 GNF constant, not a fare-settings row. | P1 | Verified (`orders.ts`) |
| REP-G10 | No economics snapshot on the order (no frozen fee/commission basis at placement) outside the two runtime engines, and no Repas entry in `fare_settings` / a `repas` finance policy identity check. | P1 | Verified (`food_orders` columns; no repas fare row observed) |
| REP-G11 | Payment authorization is best-effort and non-transactional: a failed wallet hold still leaves a placed order (only delivery dispatch is skipped), producing orders a restaurant can accept without funding. | P1 | Verified (`orders.ts` try/catch) |
| REP-G12 | No-driver recovery for Repas is absent — no timeout sweep, no expiry, no customer recovery sheet (Course/Bonbonna have `ride_expire_unfulfilled` + `NoDriverRecoverySheet`). `deliveryPending` is a silent client-side flag. | P1 | Verified (no food sweep function; `orders.ts`) |
| REP-G13 | No customer receipt: no order detail/tracking screen, no itemized receipt, no payment-truth line. Repas appears only as an activity row. | P1 | Verified (no Repas receipt component) |
| REP-G14 | No merchant or driver Repas receipt/statement: merchant order card shows no settlement truth; driver earning for food missions is not surfaced from ledger truth. | P1 | Verified (`RepasOrdersSection`, `ActiveMissionCard`) |
| REP-G15 | No admin "stuck order" queue: no age-based detection of orders stuck in `placed`/`preparing`/`out_for_delivery`, no dispute queue entry point specific to Repas beyond the Chop Pay dispute panel. | P1 | Verified (`RepasAdmin.tsx` is a flat list) |
| REP-G16 | Restaurant open-state is manual only — no hours model, no auto-close, no "closed" enforcement server-side at order time. | P2 | Verified (`is_open` boolean; client-side gate only) |
| REP-G17 | No restaurant verification gate: `verification_state='none'` restaurants are publicly listed and orderable, and any authenticated user can self-create a restaurant from the customer view. | P2 | Verified (`RestaurantOnboardingSheet` entry point, `status='active'` on create) |
| REP-G18 | Menu photos are stored in the Marché bucket (`marche-listings/{uid}/repas-menu/...`) — cross-service storage leakage and confusing ownership. | P2 | Verified (`merchantOps.ts` comment) |
| REP-G19 | `repas_complete_order`, `open_food_order_thread` and the food thread triggers are EXECUTE-granted to `anon`. Not exploitable today (internal auth checks fail closed on NULL `auth.uid()`), but inconsistent with the Slice 13 privilege posture. | P2 | Verified (privilege query) |
| REP-G20 | Cross-service naming/leakage: Repas cart and detail surfaces mix mock and live restaurant components; no explicit "Repas" mission-kind labelling audit equivalent to the Taxi label test. | P2 | Verified (`FoodView` dual render path) |
| REP-G21 | Low-data/offline and error states are thin: no offline queueing, no retry affordance on failed order, silent `console.warn` on dispatch failure, no menu image placeholder policy. | P2 | Verified (`orders.ts`, detail view) |
| REP-G22 | Zero Repas-specific automated evidence: no `_qa_node3_repas*` harness, no vitest/e2e covering Repas order, cancellation or settlement. | P1 | Verified (no matches in `src/test`, `tests/e2e`, `qa-node-harness`) |
| REP-G23 | Engagement/reuse surface is absent: no reorder, no favourites, no order history screen, no ratings, no promo, no push on state change. | P3 | Verified (no such code) |

## 4. Product-completeness judgment for real Conakry use

Not usable. Supply is one unverified restaurant with an empty menu and no delivery, and zero food-capable couriers. Even with content, the order path is client-priced, non-idempotent, non-atomic, uncancellable and unrecoverable, so a first real order would be an integrity and support incident rather than a transaction. The finance engines behind Repas are production-grade; the product layer in front of them is not.

## 5. Certification matrix required (Node 3 — Repas)

1. Identity/config: `repas` flag semantics, restaurant/menu counts, Repas fare + finance policy identity, tender gating flags.
2. Order truth: server-priced order creation, item snapshot, availability/open re-check, closed-restaurant rejection, unavailable-item rejection.
3. Idempotency: same request id → one order, one intent; duplicate tap and network retry.
4. Payment rails: cash engine binding, Chop Pay authorization/capture, failed-auth fail-closed, no client `paid`.
5. Merchant workflow: accept, reject, sold-out, prepare, ready, handoff; reject reverses funds; post-`preparing` cancellation blocked for every actor.
6. Cancellation/debt: customer cancel pre-prep, fee/hold semantics, blocked post-prep, dispute path.
7. Dispatch: food eligibility, offer copy, exclusion of ineligible/offline/suspended/frozen drivers, pickup handshake, delivery completion.
8. No-driver/timeout: expiry sweep, hold release, customer recovery outcome.
9. Receipts/history: customer, merchant, driver — all values from ledger/server truth.
10. Support/admin: stuck-order detection, dispute queue, ticket linkage.
11. Security: RLS negative tests (foreign order read/update), RPC privilege posture, no anon exposure.
12. UI truth: zero fake restaurants/metrics, correct Repas labelling, no cross-service leakage.
13. Regression: Node 0 / Node 1 / Node 2 / Slice 13 unchanged; rollback-clean fixtures.

## 6. Recommended remediation sequence

- R1 (P0, truth): delete mock restaurants and unfounded LiveStrip claims; honest empty state only.
- R2 (P0, spine): `repas_order_create` RPC — server re-pricing from `food_menu_items`, availability + open-state re-check, atomic order+items, economics snapshot, request-id idempotency; revoke direct client `INSERT`.
- R3 (P0, RLS): replace the permissive customer UPDATE policy with a column-scoped cancellation path; block all other client mutation.
- R4 (P0, workflow): merchant reject / sold-out with fund reversal; customer cancel pre-prep via engine; hard post-`preparing` block server-side.
- R5 (P0, supply): food-delivery driver eligibility model + real courier onboarding; restaurant verification gate before public listing.
- R6 (P1, money completeness): Repas fare settings (delivery fee, service fee, minimum), courier earning from settings not a constant, fail-closed on failed authorization.
- R7 (P1, recovery): no-driver expiry sweep + recovery sheet, mirroring Node 1.
- R8 (P1, receipts): customer order tracking/receipt, merchant settlement line, driver earning line — all ledger-sourced.
- R9 (P1, ops): admin stuck/disputed Repas queue.
- R10 (P1, evidence): `_qa_node3_repas_full()` harness + vitest label/truth tests, then full cross-node regression.
- R11 (P2/P3): dedicated Repas storage bucket, privilege cleanup, hours model, offline/error hardening, reorder/favourites/ratings.

## 7. Provisional Service Node verdict

**NOT STARTED AS A CERTIFIED NODE — P0 PRODUCT + SUPPLY + ORDER-TRUTH BLOCKERS.** Finance rails: reusable and locked. Product layer: pre-certification. Repas must not be exposed as launched while `repas=true` renders fake restaurants over an empty catalog.

## 8. HEAD and change confirmation

- HEAD: `69548fb6ed6c9a9a65d5f1f57562043e81b26506`
- `git status --short`: clean before inspection; only read-only queries and file reads were performed. Zero code, DB, migration, flag, policy, test, doc, config, package or secret changes.
