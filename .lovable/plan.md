# Repas Vendor Dashboard + Mode Toggle Fix

## Problem
1. Choosing "Vendre des repas" during merchant onboarding only creates a `merchant_stores` row (product-marketplace shape). No `food_restaurants` row is created, so `MerchantHub` renders the standard product-merchant tabs (Catalogue → product catalog, Commandes → product orders). The Repas dashboard surfaces exist (`RepasMenuSection`, `RepasOrdersSection`, `RepasProfileSection`) but are never shown unless the user later clicks "Créer mon restaurant" buried in the Store tab.
2. The "Passer en mode client" toggle does not work for users whose only identity is a fresh Repas signup — same race we previously fixed for product merchants needs to be applied to the Repas path.

## Goal
- If a user picks **only Repas** at signup, they land on a tailored Repas dashboard (menu / orders / restaurant profile / wallet), not the product-merchant layout.
- If a user picks **both** (Marché + Repas), both surfaces are available, but Repas tabs are first-class, not hidden behind a CTA.
- The mode toggle works identically for product merchants and Repas vendors.

## Changes

### 1. Onboarding: actually create the restaurant when `wants_food`
`src/pages/MerchantOnboarding.tsx`
- After the `merchant_stores` insert, if `biz.wants_food` is true, call `createOrUpdateRestaurant` (from `src/lib/repas/restaurants.ts`, already used by `RestaurantOnboardingSheet`) with the same name, district, phone, and captured location.
- If the user picked **only Repas** (`!wants_marketplace && wants_food && !wants_wallet_agent`), skip the `merchant_stores` insert entirely (or insert a minimal `business_type: "restaurant"` shell — to be confirmed during build by checking what `useMerchantIdentity` needs) so `MerchantHub` shows the Repas layout cleanly.
- Update the copy on the "Vendre des repas" checkbox to remove "(à venir)" — the module is live.

### 2. MerchantHub: Repas-first layout when a restaurant exists
`src/components/merchant/MerchantHub.tsx`
- Compute `isRepasOnly = !!restaurant && !store`. When true:
  - Tab labels switch to Repas-native wording: **Accueil · Commandes · Menu · Wallet · Restaurant** (icon for Menu = `ChefHat`).
  - Header title falls back to `restaurant.name` and shows a Repas badge.
  - Home snapshot uses Repas counters (today's orders, open/closed, prep time) — small new component `RepasSnapshot` reusing existing repas queries.
- When both exist (`store && restaurant`), keep current tabs but render Repas sections **above** product sections inside Commandes and Catalogue so the Repas vendor sees their food orders/menu first.
- Remove the "Vous proposez des repas? Créer mon restaurant" CTA when a restaurant already exists (already conditional; verify).

### 3. Mode toggle parity for Repas vendors
`src/components/merchant/MerchantHub.tsx` already passes `forceVisible` to `MerchantModeToggle`, so the toggle renders. The blocker is the same Index merchant-redirect race we fixed before — confirm `useSwitchAppMode` writes the session override SYNC and navigates to `/?mode=client` (it does).
- The likely remaining gap: `Index.tsx`'s `hasMerchantIdentity` check may re-bounce a Repas-only user back to `/merchant/hub`. Audit `useMerchantIdentity` + the Index redirect predicate; ensure a `?mode=client` URL OR a session override of `"client"` short-circuits the bounce **even when the user has a `food_restaurants` row**. This mirrors the existing product-merchant guard.
- Add a dev `console.debug("[repas-toggle]")` trace alongside the existing `[switch-mode]` log to confirm the path during smoke.

### 4. Memory + milestone
- Update `mem://index.md` to note the Repas-only dashboard branch.
- Add `mem://milestones/repas-vendor-dashboard-routing-stable.md` once smoke passes.

## Out of scope
- No wallet/pricing changes.
- No RLS changes (food_restaurants RLS already gates on `owner_user_id`).
- No new tables.
- Messaging UI untouched (already wired in prior milestone).

## QA
1. Fresh signup → pick Repas only → land on Repas dashboard (Menu tab visible, no product catalog).
2. Toggle "Passer en mode client" → navigates to `/?mode=client`, stays on client home, does not bounce back.
3. Toggle back to merchant → returns to Repas dashboard.
4. Existing product-only merchant → unchanged behavior.
5. Mixed signup (Marché + Repas) → both surfaces visible, no regression.
6. Build clean.

## Questions before I start
- For a Repas-only signup, do you want me to **skip** creating a `merchant_stores` row entirely (cleanest, restaurant is the sole identity), or keep a minimal store shell for shared admin/wallet plumbing? I lean toward **skip** — the existing `useMerchantIdentity` + `MerchantHub` already handle `restaurant && !store`.
