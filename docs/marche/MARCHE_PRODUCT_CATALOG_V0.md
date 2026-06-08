# Marché — Product Catalog v0

Lock candidate: `marche-product-catalog-creation-ux-stable`

## Data model

Products = `marketplace_listings` rows with `kind = 'merchant'` and a `store_id`.
Fields already present and used:

- `seller_id`, `store_id`, `kind = 'merchant'`
- `title`, `description`, `category`
- `price_gnf`, `quantity_in_stock`, `barcode`
- `status` (`active|paused|sold|removed`) — `paused` = draft, `removed` = archived
- `visibility` (`public|private`)
- `photo_count` (auto via `listing_images` trigger)

Images stored in public bucket `marche-listings`, path `{user_id}/{listing_id}/{uuid}.{ext}`.
Recorded in `listing_images` (one row per uploaded image, with the public URL).
Verification docs (`merchant-docs`, ID/selfie) are NOT touched.

## Visibility enforcement

Trigger `marche_enforce_pending_merchant_privacy` (BEFORE INSERT/UPDATE):

- If linked `merchant_stores.onboarding_status <> 'approved'` OR store status not in (`active`, `paused`):
  - forces `visibility := 'private'`
  - downgrades `status` from `active` to `paused`

So pending merchants can prepare their catalog, but products are never visible
to the public marketplace until the admin approves the store.

Public marketplace SELECT policy already requires:
`status = 'active' AND visibility = 'public' AND store approved+active`.

## Merchant UX

Merchant Hub → "Catalogue / Produits" section:

- Add product (sheet form) with photo, name, price GNF, quantity, category,
  barcode, description.
- Filters: Tous / Brouillons / Publiés / Rupture / Archivés.
- Search by name or barcode.
- Quick stock controls (+1 / -1 / Rupture).
- Edit / Publish-Dépublier / Archiver per product.
- Pending merchants see an amber banner and cannot publish (button hidden).
- "Mode ajout rapide" keeps category between saves for field digitization.

## Placeholders

- AI background removal: visual label "Suppression d'arrière-plan — bientôt".
  No fake processing.
- Barcode scanner: manual entry only, placeholder "Scanner bientôt disponible".
  No fake product lookup.

## Admin

`MarcheAdmin` now shows real listings with kind, stock, visibility, and status
columns, so admins can see merchant catalogs (including pending/private ones).

## Security / RLS

- Sellers manage only their own listings (existing policies).
- Customers see only active + public + approved-store products.
- Pending merchants cannot bypass via direct UPDATE — trigger rewrites the row.
- Storage policy on `marche-listings` already scopes write to
  `auth.uid() = foldername[1]`.

## Hard-exit checklist

- [x] Merchant Dashboard has Catalogue / Produits section
- [x] Add product with photo, name, GNF price, quantity, category, barcode
- [x] Edit / stock / out-of-stock / archive
- [x] Pending products forced private/paused
- [x] Approved merchants can publish active/public
- [x] Customer marketplace policy unchanged (admin/seller/public read rules)
- [x] Admin sees real merchant catalog
- [x] No fake AI / fake barcode lookup
- [x] No RLS weakening; verification docs untouched