# Marché — Customer shopping + bargaining v0

Lock candidate: `marche-customer-shopping-search-product-detail-bargaining-stable`

## What ships

- Customer Marché (`MarketView`) already lists / searches / filters real
  `marketplace_listings` rows (active + public + approved-store only via RLS).
  Product detail (`ListingDetail`) and merchant storefront (`StoreProfile`)
  remain the existing flows.
- Merchants can mark products as **négociable**, set the public **1er prix**
  (`asking_price_gnf` / `price_gnf`), a private **dernier prix**
  (`minimum_price_gnf`), and toggle `allow_offers`.
- Customers can submit one open offer per product where `allow_offers = true`
  and `pricing_mode = 'negotiable'`. They see their offer status, can withdraw
  while pending/countered, and can re-offer after a rejection/expiry.
- Merchants see all offers on their products in the Merchant Hub
  ("Offres reçues") and can accept / reject / counter.
- Admin Marché shows a marketplace offers table for moderation.

## Pricing fields on `marketplace_listings`

- `pricing_mode` — `fixed | negotiable | quote` (default `fixed`).
- `asking_price_gnf` — public 1er prix (backfilled from `price_gnf`).
- `minimum_price_gnf` — **private** dernier prix. Column SELECT is **revoked**
  from `anon` and `authenticated`. Only the owner and admins can read it,
  via `get_listing_minimum_price(p_listing_id)` SECURITY DEFINER.
- `allow_offers` — boolean gate.
- `offer_increment_gnf` — reserved, unused in UI.

## Offer table — `marketplace_offers`

Per-offer row: `listing_id`, `buyer_user_id`, `merchant_user_id`,
`merchant_store_id`, `offer_amount_gnf`, `counter_amount_gnf`, `status`
(`pending|accepted|rejected|countered|withdrawn|expired`), buyer/merchant
messages, `expires_at` (default 7 days), `responded_at`, timestamps, metadata.

RLS:
- Buyer reads own offers.
- Merchant reads offers on own listings.
- Admin reads all.
- No INSERT/UPDATE/DELETE policies — writes go through SECURITY DEFINER RPCs.

## RPCs

- `create_marketplace_offer(p_listing_id, p_amount_gnf, p_message)`
  Enforces: auth, not banned, not frozen, listing active+public, store
  approved+active, `allow_offers`, `pricing_mode in (negotiable,quote)`,
  `quantity_in_stock > 0`, buyer ≠ seller, positive amount, no existing open
  offer from same buyer. Returns offer id.
- `merchant_respond_marketplace_offer(p_offer_id, p_action, p_counter_amount_gnf, p_message)`
  Owner/admin only. `p_action ∈ accept|reject|counter`. Only when status is
  `pending` or `countered`.
- `withdraw_marketplace_offer(p_offer_id)` — buyer only, while open.
- `get_listing_minimum_price(p_listing_id)` — owner/admin only.
- `get_merchant_listing_full(p_listing_id)` — owner/admin row including
  private columns.

## Dernier prix privacy verification

- Column-level `REVOKE SELECT (minimum_price_gnf) ON marketplace_listings
  FROM anon, authenticated` makes any direct SELECT including that column
  fail with permission denied for both roles, regardless of RLS.
- Customer-facing queries (`MarketView`, `ListingDetail`, `ListingCard`) and
  the `products.ts` helpers all use explicit column lists that exclude
  `minimum_price_gnf`.
- Merchant editor loads minimum via `getListingMinimumPrice()` RPC, which
  rejects non-owners with `forbidden`.

## UX

- **Merchant — `ProductFormSheet`**: new "Prix négociable" block with
  `Accepter les offres` and an owner-only "Dernier prix (privé)" field.
- **Merchant — `MerchantOffersSection`**: list of offers with accept/reject/
  counter actions and inline counter form.
- **Customer — `ListingDetail`**: when product is negotiable + allows offers,
  shows a "Faire une offre" panel with current offer status (pending /
  accepted / rejected / countered / withdrawn / expired), counter amount,
  merchant message, and withdraw / re-offer controls. Accepted offers show
  "finalisation de la commande à connecter" — no fake checkout.
- **Admin — `MarcheAdmin`**: new "Offres marketplace" table for moderation.

## What did NOT change

- No wallet mutation. No payment processing. No fake checkout.
- No fake inventory or fake notifications.
- No RLS weakened.
- Merchant catalog creation flow (V0) intact — `select(*)` calls in
  `products.ts` were replaced with explicit column lists so the new column
  revoke does not break them.
- Public listings policy unchanged: customer browsing still requires
  `status=active`, `visibility=public`, and approved+active store.

## Hard-exit checklist

- [x] Customer search / category / store views unchanged and still real.
- [x] Pending/private products still invisible to customers.
- [x] Merchant can toggle fixed vs négociable, set 1er prix and dernier prix.
- [x] Customers cannot read `minimum_price_gnf` (column-level revoke).
- [x] Customers see "Faire une offre" only when `allow_offers && negotiable`.
- [x] Offer create / accept / reject / counter / withdraw via RPC.
- [x] Buyer cannot read other buyers' offers; merchant cannot read others'.
- [x] Buyer cannot offer on own product.
- [x] Banned/frozen users cannot create or respond to offers.
- [x] Admin sees all offers.
- [x] No wallet/payment mutation in this pass.