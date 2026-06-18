---
name: Commerce Phase 2 — Repas Merchant Dashboard MVP
description: Restaurant owners can manage menu (CRUD + photo), profile (name/cuisine/quartier/prep/delivery/pickup/logo/cover), and orders (itemized detail, customer info, delivery + mission context) from MerchantHub. No POS, no checkout, no wallet/pricing changes.
type: feature
---
# repas-merchant-dashboard-mvp-stable

## Scope locked
- Menu CRUD with image upload (`food_menu_items`).
- Restaurant profile editor with logo + cover (`food_restaurants`).
- Itemized order detail card with customer phone, delivery address, mission
  status, payment method/status (read-only).
- Reused existing MerchantHub tabs (Accueil / Commandes / Catalogue /
  Wallet / Boutique). No new shell, no second dashboard.

## Storage
- New buckets are blocked by workspace policy (public_buckets_blocked).
- Reused public `marche-listings` bucket under prefix
  `{owner_user_id}/repas-menu/{restaurant_id}/{uuid}.{ext}`. Existing
  storage RLS (`auth.uid() = foldername[1]`) already scopes writes to the
  owner; public reads are fine for menu/restaurant photos.

## Files added
- `src/lib/repas/merchantOps.ts` — `createMenuItem`, `updateMenuItem`,
  `deleteMenuItem`, `uploadMenuItemPhoto`, `updateRestaurantProfile`,
  `uploadRestaurantImage`, `getRestaurantOrderDetail`,
  `REPAS_MENU_CATEGORIES`, `RESTAURANT_STATE_LABEL`,
  `RESTAURANT_MISSION_LABEL`.
- `src/components/merchant/repas/RepasMenuSection.tsx` — menu CRUD with
  bottom sheet, image upload, availability switch.
- `src/components/merchant/repas/RepasOrdersSection.tsx` — active +
  recent order cards, advance button, detail sheet with items,
  customer, payment, delivery/mission context, 30s polling refresh.
- `src/components/merchant/repas/RepasProfileSection.tsx` — profile
  editor with logo/cover upload, prep time, pickup/delivery toggles.
- `src/components/merchant/MerchantHub.tsx` — wires the three new
  sections in when `restaurant` is present; preserves existing
  Marché behaviour.

## Security / RLS
- No new tables, no policy edits.
- `food_restaurants` UPDATE policy already scopes to `owner_user_id`.
- `food_menu_items` ALL policy already scopes to owning restaurant.
- `food_orders` SELECT/UPDATE policy already scopes to owning restaurant.
- `food_order_items` SELECT policy already scopes to owning restaurant.
- `missions` ref read uses existing `ref_food_order_id` column; mission
  state is only shown via a safe label map (no route observations or
  driver idle location exposed).
- Storage writes scoped to `auth.uid()` first folder; public reads OK.

## Pricing / wallet
- No mutation of `payment_status`, `settlement_state`, `paid_at`, or
  wallet rows. `payment_status` shown read-only via existing
  `FOOD_PAYMENT_STATUS_LABEL`.
- Completion goes through existing `repas_complete_order` RPC unchanged.

## Deferred (explicitly not in MVP)
- Order-bound messaging (restaurant ↔ client ↔ courier) is now LIVE
  via `food_order_threads` / `food_order_messages` and surfaced through
  `src/components/repas/OrderMessagingPanel.tsx` in three places:
  RepasOrdersSection detail (restaurant), RepasRestaurantDetail
  confirmation (client), and ActiveMissionCard (assigned courier).
- Restaurant announcements / "plat du jour" social posts. Out of MVP.
- Live realtime push for new orders (currently 30s polling, no
  realtime spam).

## Owner bootstrap
- If user owns a Marché store but no restaurant, the Store tab now
  shows a "Créer mon restaurant" CTA opening the existing
  `RestaurantOnboardingSheet`. The no-merchant case already exposes
  Repas creation through `MerchantActivationPanel`. No silent seeding.

## Hard exit checklist
- [x] Restaurant owner sees Repas dashboard via existing MerchantHub
- [x] Add menu item with image + price + category
- [x] Edit / delete / toggle availability
- [x] Incoming orders list with state badges + advance button
- [x] Order detail with items, customer phone, delivery address, mission
- [x] Pickup orders fulfillable without courier mission
- [x] Delivery orders show linked mission state (when present)
- [x] Restaurant cannot see other restaurants' orders (existing RLS)
- [x] Pricing / CHOPPay / wallet unchanged
- [x] No fake metrics, no fake messages
- [x] Build clean