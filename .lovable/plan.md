## CHOP Repas Foundation Sprint — Plan

Transform Repas from a placeholder tab into a lightweight food vertical that inherits CHOP's ecosystem (wallet, ChopPay, trust, activity, notifications) — without cloning DoorDash.

### Scope split

Big sprint, so I'll batch it into three landings:

**Landing A — Data foundation (DB + lib)**
- Migration: `food_restaurants`, `food_menu_items`, `food_orders`, `food_order_items`
  - restaurants: name, slug, owner_user_id, avatar_url, cover_url, district, cuisine, is_open, choppay_enabled, delivery_available, pickup_available, verification_state, prep_time_min, status
  - menu items: restaurant_id, name, photo_url, description, price_gnf, category, is_available, prep_time_min
  - orders: user_id, restaurant_id, fulfillment (pickup/delivery), state (placed/confirmed/preparing/ready/completed/cancelled), notes, subtotal_gnf, payment_method, created_at
  - order items: order_id, menu_item_id, qty, unit_price_gnf, name_snapshot
- RLS: public read open restaurants/available items; owners manage own; users CRUD own orders; admins manage all
- `food_order_state` enum, `food_fulfillment` enum
- New activity event kind: `food_order`
- New lib: `src/lib/repas/restaurants.ts`, `src/lib/repas/menu.ts`, `src/lib/repas/orders.ts`, `src/lib/repas/cart.ts` (localStorage cart hook)

**Landing B — UI: home + detail + cart**
- Rewrite `FoodView.tsx`: search, cuisine chips, "Disponible maintenant" strip, restaurant grid from DB; empty state when none; demo/public sees showroom (existing behavior preserved)
- New `RestaurantDetailV2.tsx` (or refactor existing `RestaurantDetail.tsx`): header with trust chips (Ouvert, Préparation ~X min, Livraison/Retrait, ChopPay), menu grouped by category, add-to-cart
- New `CartSheet.tsx`: items, qty +/-, subtotal, fulfillment choice, notes, clear, "Commander"
- Reuse `TrustChips`, `AvailabilityChip` patterns from Marché where sensible (food variants)

**Landing C — Order flow + activity/notifications**
- `ConfirmOrderSheet.tsx`: review, pickup/delivery, pay with CHOPWallet/CHOPPay; public hits `ConversionGateSheet`
- Insert into `food_orders` + items; create activity event; trigger notification log entry ("Commande envoyée")
- Extend `useActivityFeed` + `ActivityRow` to render `food_order` events with restaurant name + state
- "Livraison à confirmer" copy when delivery chosen (no fake courier dispatch)

### Out of scope (explicitly)
- Courier dispatch, live tracking, ratings/reviews, coupons, restaurant admin dashboards, restaurant chat (later-ready hook only)

### Technical notes
- Cart = client-side only (localStorage keyed `cc_repas_cart`), single-restaurant at a time (clear-on-switch prompt)
- Payment: reuse `useWallet` debit + existing `ChopPaySheet` pattern; for v1, mark order `payment_method='wallet'|'choppay'|'cash_on_delivery'`, no actual settlement edge function yet (mirrors Marché's lightweight approach)
- No fake trust data for live users (`isLiveUser` gate stays); demo/public keeps showroom restaurants

I'll start with Landing A (migration) once approved, then B and C in follow-up turns.