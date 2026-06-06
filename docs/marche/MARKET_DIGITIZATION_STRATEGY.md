# CHOPCHOP Marché — Market Digitization Strategy

_Living document. Owners: Marché agent (lead), Admin & Ops (review), Platform / QA / Security (review)._

## Vision

CHOPCHOP Marché does not wait for merchants to onboard themselves. We deploy
onboarding teams directly into Conakry's major commercial hubs and digitize
entire physical markets stall-by-stall. The output is instant marketplace
density and a searchable digital twin of real markets that customers can
browse, compare, and order from.

## Three interfaces

- **Customer dashboard** — browse categories, search, compare merchants, place
  or request orders.
- **Driver dashboard** — pickups, deliveries, earnings (owned by Driver agent).
- **Merchant dashboard** — manage storefront, products, inventory, orders, and
  visibility (`/merchant/hub`).

## Field campaign model

One physical market → one one-week campaign → ~10 onboarding specialists →
stall-to-stall coverage. Every merchant gets a `merchant_stores` row, an
initial product catalog, photos, and a published storefront once approved.

Data model:
- `physical_markets` — one row per real market (Madina, Niger, etc.).
- `market_onboarding_campaigns` — time-boxed effort against a market.
- `market_onboarding_assignments` — specialist ↔ campaign ↔ zone, with
  `merchants_targeted` / `merchants_completed` counters.

Specialist role (`onboarding_specialist` in `app_role`) can create stores and
update them while they are still in onboarding (`draft|submitted|in_review|needs_info`).
They cannot touch approved stores — only the merchant owner and admins can.

## Product photo workflow

V0:
1. Specialist takes a photo with the phone camera.
2. Uploads it as the product image.
3. Enters name, price (GNF), quantity in stock.
4. Saves as draft until the merchant is approved.

V1+ (clearly marked "bientôt" in UI — never faked):
- AI background removal once a real provider is wired.
- Product recognition / auto-categorization.
- Barcode → global catalog lookup.

## Barcode scanning

V0 ships a **manual barcode field** on `marketplace_listings.barcode`. No
scanner widget. No fake global product database.

V1 will add the actual camera scanner UI and, optionally, a supplier catalog
lookup. Until then, manual entry is enough to start building inventory.

## Merchant ranking & sponsored placement

Customer search will combine: relevance, distance, availability
(`quantity_in_stock > 0`), merchant verification, freshness, ratings, and —
later — sponsored placement.

**Sponsored placement is documented as future monetization, not active.**
When it ships it MUST be visibly labeled "Sponsorisé" on every surface.
Secret biasing of search is forbidden.

## Phased roadmap

- **V0 (this milestone)**
  - Strategy + onboarding funnel docs.
  - `merchant_stores` extended with onboarding lifecycle.
  - `marketplace_listings.quantity_in_stock`, `barcode`, `visibility`.
  - `physical_markets`, `market_onboarding_campaigns`,
    `market_onboarding_assignments` tables + RLS.
  - Merchant signup branch, onboarding funnel, pending dashboard.
  - Admin approve / reject / request info / suspend via
    `admin_merchant_decision` RPC, audit logged.
  - Customer marketplace shows only approved + active + public.

- **V1**
  - Onboarding specialist field app (campaign list, assignments, progress).
  - Real barcode scanner widget.
  - Bulk product upload.
  - Better storefront layouts.

- **V2**
  - AI background removal.
  - Product recognition.
  - Sponsored placement with explicit "Sponsorisé" labels.
  - Search ranking optimization & merchant analytics.

## Non-goals (do not regress)

- No fake merchants, no fake products, no fake counts.
- No public exposure of draft / private / pending stores or products.
- No weakening of RLS to satisfy a scanner.
- No self-approval — `admin_merchant_decision` rejects when actor owns the store.
- No changes to wallet, ride, driver, OM, or auth contracts.