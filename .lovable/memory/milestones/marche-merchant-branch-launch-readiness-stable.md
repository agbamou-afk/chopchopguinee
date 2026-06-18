---
name: Commerce Phase 1 — Marché Merchant Branch Launch Readiness
description: Marché audited and patched for launch — item photo pipeline verified, shop discovery enhanced with category filter / listing counts / sample photos, messaging + interest + distance helpers confirmed intact.
type: feature
---
# marche-merchant-branch-launch-readiness-stable

Locked scope (no rebuild, no checkout, no wallet/pricing changes):

## Confirmed already in place (no changes)
- Item photo pipeline: `marche-listings` is a public bucket; `listing_images`
  has `Anyone can view` SELECT, `Sellers manage own listing images`
  INSERT/UPDATE/DELETE scoped to `marketplace_listings.seller_id = auth.uid()`.
  `uploadProductImage` writes original under `{user_id}/{listing_id}/{uuid}`,
  inserts a `listing_images` row with the public URL and `is_primary` on
  position 0. `ListingCard` renders `cover_url` with `loading="lazy"` and a
  clean "Aucune photo" fallback.
- Merchant dashboard: `ProductCatalogSection`, `ProductFormSheet`,
  `AvailabilitySection`, `MerchantOffersSection`, `SellerRequestsSheet`
  already cover add/edit/photo/stock/availability/messages.
- Buyer ↔ merchant messaging: `conversations` + `messages` tables, RLS
  scoped to buyer/seller participants + admin, realtime via
  `postgres_changes`, quick-reply chips, delivery escalation already wired.
- Buyer interest pipeline: `listing_interests` table + `SellerRequestsSheet`
  already surfaces availability/delivery/save signals to merchant.
- Distance / map integration: trusted merchant `map_place` coordinates via
  the locked CHOP Maps service-locations helper; submitted/unverified
  locations stay "À confirmer".

## Surgical Phase 1 patch
- `listStoresWithSummary(opts)` in `src/lib/marche/stores.ts` — aggregates
  active-public listing count + up to 3 sample cover photos per store, with
  optional `category` / `q` / `district` filters. RLS keeps draft/private
  rows out.
- `StoreCard` now renders the shop category chip, listing count and a
  3-thumb sample strip with safe `onError` hide for broken URLs.
- `MarketView` Boutiques tab: horizontal category chip strip
  (`MARCHE_CATEGORIES`) drives `storeCategory` state; replaced `listStores`
  call with `listStoresWithSummary`; threads `listingCount` + `samplePhotos`
  into `StoreCard`.

## Privacy / RLS
- No new tables, no policy changes.
- No service-role bypass, no driver signal exposure, no route observation
  exposure, no wallet/pricing mutation.
- Storefront/listing reads continue to use public RLS (active + public +
  approved store).

## Hard exit checklist
- [x] Item photo upload → listing card + detail (existing pipeline retained)
- [x] Graceful fallback when image missing/broken
- [x] Merchant dashboard catalog/messages/interests intact
- [x] Shop discovery by category + search + (existing) district
- [x] Sample item photos + listing count on store cards
- [x] Messaging + quick replies + delivery escalation intact
- [x] No pricing/wallet changes
- [x] No RLS weakening
- [x] Build clean

## Deferred (out of Phase 1 scope)
- Geo-sorted store list (requires user location consent integration in
  MarketView). Distance helper already exists on shop profile context.
- Per-store "open/closed" hours surfaced in the store list card.
- Buyer-side "Demander livraison" surfaced directly from store card
  (currently lives on listing + chat).