# Node 4 — Marché: Phase 1 Audit + Proposed R1

Audit only. No code, DB, flag, or activation changes were made.

## A. What Marché actually is today

Marché is a **real, working per-listing classifieds + merchant-catalog marketplace**, not a placeholder. It is **not** a commerce checkout node: there is no cart, no buy-now, no order object. Money only moves through a *negotiated offer* object.

### 1. Customer surfaces
- `src/components/views/MarketView.tsx` — Marché home: search (`title ilike`), category filter, tabs Annonces / Boutiques / Enregistrées, sort. Sub-screens are internal state (`detail`, `sell`, `inbox`, `store`, `mine`), not routes.
- `src/components/marche/ListingDetail.tsx` — gallery, seller/trust chips, chat/call/WhatsApp, save, report, interest requests, offer + payment block.
- `StoreProfile.tsx` / `StoreCard.tsx` / `StoreHeader.tsx`, `src/pages/PublicStorefront.tsx` (`/marche/boutique/:slug`), `CategoryGrid.tsx`, `InboxView.tsx`, `ChatThread.tsx`, `MyListingsView.tsx`, `SellFlow.tsx`, `OfferSheet.tsx`, `RequestMarcheDeliverySheet.tsx`, `ReportModal.tsx`.

### 2. Listing schema and publication truth
`marketplace_listings` (32 cols) carries **four overlapping publication/availability signals with no canonical derivation**:
- `status` (`listing_status`: active/sold/paused/removed)
- `visibility` (free `text`: public/private)
- `availability` (`listing_availability`: available/limited/to_confirm/reserved/sold)
- `quantity_in_stock` (nullable; NULL for all community listings)

Plus `pricing_mode` / `price_gnf` / `asking_price_gnf` / `minimum_price_gnf` / `allow_offers` / `offer_increment_gnf` with no server invariant tying them together.

Two **duplicate, divergent** publication triggers both run on the same table: `enforce_listing_visibility` (forces `visibility='private'` only) and `marche_enforce_pending_merchant_privacy` (forces private **and** downgrades `active`→`paused`). Both return early when `store_id IS NULL`, so **community listings bypass publication control entirely**.

### 3. Seller identity and write authority
Sellers write `marketplace_listings` **by direct table CRUD**, not through an RPC (`src/lib/marche/products.ts`, `SellFlow.tsx`, `ProductFormSheet.tsx`). `authenticated` and `anon` both hold table-level SELECT/INSERT/UPDATE/DELETE; RLS is the only gate. `prevent_seller_protected_columns` blocks `status`, `promoted`, `seller_id`, `store_id`, `kind`, `sold_count`, `view_count`, `photo_count` — but **`price_gnf`, `minimum_price_gnf`, `quantity_in_stock`, `availability`, `visibility`, `pricing_mode`, `allow_offers` remain fully client-authoritative**.

### 4. Cart / checkout
None. Confirmed absent — no `cart`/`panier` anywhere under `src/lib/marche` or `src/components/marche`. Purchase is one listing at a time via `OfferSheet` → `create_marketplace_offer`.

### 5. Fulfillment
`src/lib/marche/delivery.ts` → `createMission({ type: 'marketplace_delivery' })`, buyer types a free-text dropoff address. No landmark/quality model (Repas R11 has one), no Marché-side tracking UI, no pickup model, no ETA/fee (honest, deliberately blank).

### 6. Payment / tender
`create_marketplace_offer` stores tender only in `metadata.payment_method`; `marche_create_offer_payment_intent` → legacy `choppay_create_payment_intent`; `marche_complete_offer` captures and settles via `wallet_pay_merchant_store`, else `settlement_state='needs_review'`. **Marché does not use the Slice 13 canonical runtime**: `chop_pay_order_runtime` and `cash_order_runtime` have **0 rows for `source_module='marche'`**, and there is no cash engine, no collateral/hold, no cancellation-debt path, no commission policy key for Marché.

### 7. Lifecycle
Offer status `pending|accepted|rejected|countered|withdrawn|expired`, plus independent `payment_status`, `fulfillment_status`, `settlement_state`. Four parallel state fields, no single transition function, no event/audit timeline table (Repas has `repas_ops_events`).

### 8. Idempotency / recovery
**None on the client.** No `localStorage` request id, no fingerprint, no resume RPC — unlike `src/lib/repas/checkoutRequestId.ts`. Server-side, `create_marketplace_offer` dedupes only by "a pending offer exists"; there is no unique idempotency key.

### 9. Receipts / support / dispute
No Marché receipt, no order history, no dispute surface. Only `ReportModal` → `listing_reports` (0 rows).

### 10. Admin / ops
`src/pages/admin/MarcheAdmin.tsx`: real listing + offer tables, but a decorative `"Recherche à connecter..."` search box, filter chips referencing a `suspended` status that is **not in the `listing_status` enum** (always 0), and **no `listing_reports` moderation UI anywhere in `src`**.

### 11. RLS / grants / RPC exposure
- Public read policy on listings is sound (`active` + `public` + approved/active store), but only when `store_id` is set.
- `anon` holds EXECUTE on `marche_toggle_listing_save`, `marche_increment_listing_metric`, `withdraw_marketplace_offer`, `get_merchant_listing_full`, `get_listing_minimum_price` — metric inflation and a needless anon surface.
- `get_merchant_listing_full` / `get_listing_minimum_price` are SECURITY DEFINER and anon-executable; minimum-price exposure needs review against negotiation integrity.

### 12. Media
Public bucket `marche-listings`, path `{user_id}/{listing_id}/{uuid}`, MIME + 5MB validated client-side only; `listing_images` SELECT is `true` for everyone including images of private/draft listings.

### 13. Realtime / offline
One realtime channel total (`ChatThread`). No offline/low-data handling anywhere in Marché.

### 14. Tests / QA
No Marché unit test, no `_qa_node4_*` harness (54 `_qa_*` functions exist, none for Marché). Only `tests/e2e/03-merchant.spec.ts` blank-screen smoke.

### 15. Supply reality
53 listings, all `active`+`public`. ~44 are **seeded demo community listings from a single seller** (`0451600f…`, batch-dated 2026-05-14: "iPhone 13 Pro", "Villa 4 chambres Kipé", …). Real merchant supply is ~5 listings across 3 sellers. 0 offers ever created, 0 reports, 2 interests, 3 conversations.

## B. Proposed R1 — Canonical Listing & Publication Truth + Write Authority

The root dependency is not payments: nothing downstream (orders, courier, finance) can be certified while *what a listing is, whether it is orderable, and who may change its price/stock* are client-authoritative and split across four unreconciled fields and two duplicate triggers.

### Exact scope
1. **One canonical publication/orderability derivation** — a server function deriving `is_orderable` + refusal reason (`STORE_NOT_APPROVED`, `LISTING_PAUSED`, `OUT_OF_STOCK`, `NO_PHOTO`, `SELLER_UNVERIFIED`, `DEMO_SUPPLY`) from `status`/`visibility`/`availability`/`quantity_in_stock`/store state — the Repas R8 pattern.
2. **Collapse the duplicate triggers** into one publication guard that also covers `store_id IS NULL` community listings.
3. **Server-authoritative listing mutation RPCs** (`marche_listing_upsert`, `marche_listing_set_stock`, `marche_listing_publish`/`unpublish`) owning price/stock/availability/visibility invariants; migrate `products.ts` and `SellFlow.tsx` to them, then revoke direct INSERT/UPDATE on `marketplace_listings` from `authenticated`/`anon`.
4. **Canonical discovery read model** (`marche_listings_discover`, `marche_listing_public`) returning only orderable supply plus honest refusal reasons; `MarketView`/`ListingDetail`/`StoreProfile` read from it.
5. **Demo-supply quarantine** — mark the 2026-05-14 seeded batch as non-public demo data so discovery shows only real supply.
6. **Anon surface trim** — revoke anon EXECUTE on the save/metric/withdraw RPCs.
7. **QA harness** `public._qa_node4_marche_r1()` recording into `_qa_s13_results`.

### Server-authoritative invariants
- A listing is publicly visible **iff** the canonical derivation says orderable; no client field alone can publish.
- Community listings obey the same publication guard as merchant listings.
- `price_gnf > 0`; `minimum_price_gnf <= asking_price_gnf`; `allow_offers` only with `pricing_mode in ('negotiable','quote')`; `quantity_in_stock >= 0`.
- Only the owning seller or an admin may mutate a listing, and only via RPC.
- Media of a non-public listing is not enumerable through `listing_images`.

### Explicit non-goals (R1)
Cart/checkout, buy-now, Marché order object, Slice 13 runtime adoption, cash tender, commission/finance policy, courier/mission changes, offer economics, receipts, dispute/ops console, realtime/offline, Repas/Course/Bonbonna/Taxi edits, any activation or deployment.

### Likely files / functions / tables
- DB: `marketplace_listings`, `listing_images`, `merchant_stores`, `listing_metrics`; triggers `enforce_listing_visibility`, `marche_enforce_pending_merchant_privacy`, `prevent_seller_protected_columns`; new `marche_listing_*` RPCs + `_qa_node4_marche_r1`.
- Client: `src/lib/marche/products.ts`, `stores.ts`, `src/components/marche/SellFlow.tsx`, `ListingDetail.tsx`, `ListingCard.tsx`, `StoreProfile.tsx`, `src/components/views/MarketView.tsx`, `src/components/merchant/ProductCatalogSection.tsx`, `ProductFormSheet.tsx`, `src/pages/admin/MarcheAdmin.tsx` (status-chip truth only).

### Proposed runtime QA matrix
- **B — structure/privilege**: single publication trigger present; direct INSERT/UPDATE revoked; anon EXECUTE trimmed; RPC identities + SECURITY DEFINER + `search_path`.
- **P — publication truth**: pending store → forced private/paused; approved store → publishable; community listing obeys guard; unpublish is idempotent.
- **O — orderability**: each refusal reason reproduced from real state; out-of-stock and photoless listings excluded from discovery.
- **W — write authority**: non-owner mutation denied; seller price/stock via RPC only; invariant violations rejected.
- **D — discovery**: demo batch absent from `marche_listings_discover`; counts match canonical derivation.
- **R — regression**: no listing/store rows mutated outside the RPC path; Slice 13 and Nodes 0–3 harnesses re-run unchanged.

### Risks to frozen layers
Low. R1 touches no finance primitive, no ledger, no mission, no Repas/Course/Bonbonna/Taxi path. The two real risks: (a) revoking direct table writes breaks any un-migrated seller write path — mitigated by migrating all call sites in the same pass before revoking; (b) demo-supply quarantine visibly empties the Marché grid — intended, and honest.

### Recommendation
**GO** for R1 as scoped, implemented as: migration → client migration → revoke → QA harness → full board regression.