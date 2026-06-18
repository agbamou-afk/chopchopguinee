---
name: Repas Vendor Dashboard Routing
description: Repas vendors land on a dedicated restaurant dashboard; mode toggle works the same as Marché merchants.
type: feature
---

## Scope
- `src/pages/MerchantOnboarding.tsx`: if `wants_food` is checked, call `createOrUpdateRestaurant` after store insert. If the user picks Repas only (no Marché, no wallet agent), skip the `merchant_stores` insert entirely so the dashboard renders the restaurant-native layout. Categories are not required for Repas-only.
- `src/components/merchant/MerchantHub.tsx`: introduces `isRepasOnly = !!restaurant && !store`. Tabs switch to `REPAS_TABS` (Accueil · Commandes · Menu · Wallet · Restaurant) with `UtensilsCrossed` / `ChefHat` icons. Header prefers `restaurant.name`. Home shows a Repas snapshot (open/closed, district, cuisine + quick links). The existing `RepasMenuSection` / `RepasOrdersSection` / `RepasProfileSection` continue to render in Catalogue / Commandes / Store tabs.
- Mode toggle (`MerchantModeToggle` with `forceVisible`) uses the same `useSwitchAppMode` path as Marché merchants — session override + `/?mode=client` navigation prevents Index merchant-redirect from bouncing the user back.

## Out of scope
- No wallet, pricing, or RLS changes.
- No new tables; `food_restaurants` already exists with `owner_user_id` policies.
- Order messaging UI already wired in the previous Repas closing patch.

## QA
1. Fresh signup, Repas only → MerchantHub renders Menu/Restaurant tabs, no product catalog.
2. "Passer en mode client" → lands on `/?mode=client`, no bounce-back.
3. Mixed signup (Marché + Repas) → both surfaces visible; Repas shown alongside product orders/catalog.
4. Marché-only signup → unchanged.