## CHOP Merchant Operations Layer — v1

Goal: ship a single, mobile-first **Merchant Hub** surface that gives Repas restaurants and Marché sellers/stores lightweight operational control. No ERP, no dashboards, no kitchen-display complexity. One scroll, calm tone, Conakry Contemporary.

### Scope (this iteration)

Build the hub shell + 6 stacked operational sections, gated to verified merchants only. Wire to existing tables (`merchant_stores`, `marketplace_listings`, `listing_interests`, `food_restaurants`, `food_orders`, `food_order_items`, `missions`). No new tables.

### Surface

New route mounted inside the existing app shell (entry from ProfileView + auto-detected on UserHome if the signed-in user owns a store or restaurant):

```
/merchant  →  <MerchantHub />
```

Single vertical scroll, each section is a calm card:

```
[Identity strip]   name · type chip · Ouvert/Fermé toggle
[Commandes]        Repas: order queue by state pill
                   Marché: listing interests + delivery requests
[Disponibilité]    Ouvert · Livraison · Retrait · Stock limité
[Produits / Menu]  list + quick toggle is_available, edit later
[Livraison]        active missions tied to this merchant (read-only)
[CHOPPay]          recent incoming activity (light)
[Activité]         vues · sauvegardes · commandes · revenus estimés
```

### Files

New:
- `src/components/merchant/MerchantHub.tsx` — shell + section composition
- `src/components/merchant/MerchantIdentityStrip.tsx`
- `src/components/merchant/OrdersSection.tsx` — branches Repas vs Marché
- `src/components/merchant/AvailabilitySection.tsx` — toggles
- `src/components/merchant/CatalogSection.tsx` — listings or menu items
- `src/components/merchant/DeliverySection.tsx` — missions list
- `src/components/merchant/ChopPayActivitySection.tsx`
- `src/components/merchant/AnalyticsStrip.tsx`
- `src/hooks/useMerchantIdentity.ts` — resolves whether the current user has a store, restaurant, or both
- `src/lib/merchant/operations.ts` — small read/update helpers (toggle open, availability, advance order state, mark listing reserved/sold)
- `src/pages/Merchant.tsx` — route entry

Edited:
- `src/App.tsx` — add `/merchant` route (lazy)
- `src/components/views/ProfileView.tsx` — show "Espace marchand" entry when `useMerchantIdentity` returns a merchant
- `src/components/views/UserHome.tsx` — optional small "Tableau marchand" chip when merchant detected (non-intrusive)

### Data model use (no migrations)

- Availability:
  - Repas → `food_restaurants.is_open`, `delivery_available`, `pickup_available`
  - Marché → `merchant_stores.delivery_available`, `marketplace_listings.availability`/`status`
- Orders:
  - Repas → `food_orders` filtered by `restaurant_id IN (owner)` with state transitions `placed → confirmed → preparing → ready → handed_off → completed` (use existing `food_order_state` enum values; only expose those that exist)
  - Marché → `listing_interests` joined to owner's listings (states: pending / accepted / declined / fulfilled)
- Delivery → `missions` where `merchant_id = auth.uid()` (read-only list, status chips reuse `MISSION_IDENTITY`)
- CHOPPay activity → existing wallet/transactions read for incoming credits tagged to merchant (best-effort; render empty state when unavailable)
- Analytics → `listing_metrics` aggregated for the seller; Repas: counts from `food_orders` last 7d

### Gating

`useMerchantIdentity` returns `{ store, restaurant }`. Hub renders nothing (redirect to `/`) if neither exists. Profile entry hidden otherwise. No new roles table.

### UX

- Cream surfaces, soft elevation, large operational CTAs (use existing tokens, no new colors)
- All state changes optimistic with toast on error
- No maps, no charts, no spreadsheet grids
- French copy throughout

### Out of scope (explicit)

- Payouts, accounting, invoicing
- Inventory math, low-stock alerts
- Ad/promotion management
- Kitchen display, prep timers
- Live courier map
- Multi-staff roles
- Desktop layouts

### Acceptance check

After build:
1. Signed-in store owner sees "Espace marchand" in profile and `/merchant` renders Marché orders, availability, listings, delivery, CHOPPay, analytics.
2. Signed-in restaurant owner sees Repas orders queue with state advance buttons.
3. Toggling Ouvert/Fermé updates the relevant row and reflects in client surfaces on next read.
4. Non-merchant users see no merchant surfaces.
5. No changes to rides, dispatch, or demo layers. Build clean.

Proceed?