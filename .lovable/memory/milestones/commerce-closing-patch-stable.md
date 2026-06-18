---
name: Commerce Closing Patch — Stable
description: Marché shop distance sorting + Repas order-bound messaging foundation
type: feature
---
Locked 2026-06-18.

## Marché — Boutiques distance sorting
- `MarketView` Boutiques tab now sorts by "À proximité" (GPS) or "Récents".
- `useGeolocation` powers a soft-prompt "Activer ma position"; GPS denial never blocks browsing.
- `listStoresWithSummary` returns lat/lng (already part of `select *`); client computes haversine distance.
- `StoreCard` shows distance (`formatDistance`) when computable, otherwise "Distance à confirmer". Unverified coords are flagged "à confirmer". Verified stores rank first when distance is unknown.
- No map render required for shop discovery; no pricing change.

## Repas — Order-bound messaging
- New tables `food_order_threads` + `food_order_messages` with thread types `restaurant_client_order` / `restaurant_courier_order`.
- Participants: order client, restaurant owner, assigned courier (when a mission row links to the order). Admins read-only via `has_role`. No anon access.
- Thread creation goes through `open_food_order_thread(order, type)` security-definer RPC which validates caller is client or restaurant owner and best-effort attaches courier from missions.
- `food_order_messages` enforce sender = `auth.uid()` and thread participation via RLS.
- Trigger keeps `food_order_threads.last_message_at` fresh.
- Client helper: `src/lib/repas/orderMessaging.ts` (open/list/send/markRead/listThreadsForUser + quick replies).
- UI surfaces (client order screen + restaurant dashboard order detail) are intentionally deferred to a follow-up Repas patch; foundation is RLS-safe.

## Repas live smoke seed
- NOT performed: no demo seed pattern exists in the project, and the spec forbids fake successful submissions. Real smoke requires onboarding one real restaurant owner via the existing `RepasProfileSection` flow.

## Out of scope (unchanged)
- Wallet logic, CHOPPay capture/settlement, Moto/Repas/Marché pricing, Marché conversations/messages.

## Remaining work
- Wire `orderMessaging` helpers into `RepasOrdersSection` (merchant) and the client order detail.
- Seed first real restaurant owner for live dashboard smoke.