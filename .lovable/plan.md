## CHOP CHOP Marché — Living Commerce Build Plan

Phase 1 (Conakry Contemporary category icons) shipped last turn. This plan covers Phases 2–11. The work is large (DB schema, ~10 new UI components, ~4 existing surfaces rewritten). I'll execute it in 4 grouped shipments to keep each diff reviewable.

### Guiding constraints

- No Amazon / Shopify clone. No enterprise dashboards.
- Mobile-first 390×844. Warm cream surfaces, kinetic utility icons, restrained motion.
- "Lighter than posting a WhatsApp status." Listing creation ≤ 30 s with photos ready.
- Both regular users and merchants can sell. Store identity is optional, not required.
- Native messaging first; WhatsApp = optional escape hatch.
- Feed architecture must already support promoted tiles (not activated yet).

---

### Shipment A — Data foundation (Phases 2, 10, 11 schema)

New / extended Supabase tables (migration):

- `merchant_stores` — `id, owner_user_id, slug, name, avatar_url, cover_url, bio, district, category, delivery_available, choppay_enabled, verification_state ('none'|'pending'|'verified'), member_since, created_at, updated_at`. RLS: anyone reads active stores; owner upserts own row; admins manage.
- Extend `marketplace_listings`: add `store_id uuid null`, `condition text` (already exists check), `promoted boolean default false` (future ad flag), `district text` (alias of neighborhood if needed — reuse existing), `sold_count int default 0`.
- `listing_metrics` (lightweight, append-only-ish):  `listing_id pk, views int, clicks int, saves int, messages int, updated_at`. RLS: owner reads own; admins read all; service writes via RPC.
- `listing_saves` — `user_id, listing_id, created_at` (PK pair). RLS: user manages own; owner reads aggregate via metrics.
- `listing_events` (optional, deferred unless needed for view counting) — skip for now, derive views from a single `increment_listing_view` RPC that bumps `listing_metrics.views`.
- Reuse existing `conversations` + `messages` tables for native messaging (already RLS-correct for buyer/seller pair).

RPCs:
- `increment_listing_metric(_listing_id uuid, _kind text)` — security definer, validates kind in ('view','click','save','message').
- `toggle_listing_save(_listing_id uuid)` — security definer, flips row in `listing_saves` and updates metric.

### Shipment B — Stores (Phase 2)

- `src/lib/marche/stores.ts` — typed helpers: `getStoreBySlug`, `getStoreByOwner`, `listStores`, `upsertOwnStore`.
- `src/components/marche/StoreCard.tsx` — compact: avatar, name, district, listing count, CHOPPay chip.
- `src/components/marche/StoreHeader.tsx` — used on merchant profile page (avatar, cover, bio, badges).
- `src/components/marche/StoreOnboardingSheet.tsx` — minimal "Créer votre boutique" sheet (name + district + avatar + delivery toggle + CHOPPay toggle). Lazy, opens from Profil or auto-suggested after N listings.
- New route `/marche/boutique/:slug` rendered via existing app shell — merchant profile page with header + active listings grid (reuses ListingCard).
- `MarketView.tsx` — add "Boutiques" tab/segmented control next to Annonces (lightweight, not a redesign). Search bar now matches both listings (title) and stores (name).

### Shipment C — Lightweight listing flow + feed realism (Phases 3, 4, 10)

- Rewrite `SellFlow.tsx` as a 5-step flow (photos → title+price+condition → guided description → category → district+publish), no harsh min-char warning. Guided prompts are chips that prepend to description on tap.
- Detect "no store yet": still allow publish as regular user (`store_id = null`). After 3 listings, post-publish toast offers "Créer votre boutique" (links to StoreOnboardingSheet). Implements Phase 10 auto-upgrade path.
- `ListingCard.tsx` — add district, merchant attribution (store name or "Vendeur communauté"), CHOPPay chip when store has `choppay_enabled`, `promoted` slot rendering a subtle "Sponsorisé" pill.
- Feed in `MarketView.tsx` — staggered 2-col masonry-ish via CSS columns, lazy `<img loading="lazy" decoding="async">`, support an interleaver that drops a `<PromotedSlot>` placeholder every 6 listings (component currently renders nothing; ready for ad fill).
- "Publié récemment" sort default; relative time chip on each card.

### Shipment D — Native messaging + analytics + empty states (Phases 6, 7, 11)

- `ChatThread.tsx` — already wired to messages; add listing context header (image, title, price, store/seller chip), quick replies (existing constants), and a single subtle "Continuer sur WhatsApp" link in the kebab menu (not a primary CTA).
- `InboxView.tsx` — empty state copy + lightweight listing thumbnails.
- Listing detail: trigger `increment_listing_metric('view')` once per session per listing. "Contacter le vendeur" creates/opens conversation (already partly wired). Save (heart) calls `toggle_listing_save`.
- Seller analytics: `MyListingsView` (new, opened from Profil → "Mes annonces") shows per-listing chips: `128 vues · 14 intéressés · 6 sauvegardes · Publié il y a 3 j`. No charts. Plus aggregated store-level chip strip on the merchant profile if owner.
- Buyer trust signals on ListingDetail: same chip family, subtle. Only show when value > threshold (no fake urgency).
- Canonical empty-state component `MarcheEmpty` reused across feed / stores / inbox / search with the four copy variants from the spec.

### Out of scope for now

- Image upload pipeline for store avatars/covers — reuse existing listing image bucket; defer dedicated store-media bucket.
- Promoted-tile bidding/ad-serving logic — only the slot is reserved.
- Push notifications for new messages — relies on existing notification infra.
- Story/reel/live features — explicitly excluded by spec.

### Technical notes (collapsed for non-technical reader)

```text
DB:        1 migration, ~5 statements + 2 RPCs
New UI:    StoreCard, StoreHeader, StoreOnboardingSheet, MyListingsView,
           PromotedSlot, MarcheEmpty
Touched:   MarketView, SellFlow, ListingCard, ListingDetail, ChatThread,
           InboxView, marche.ts, App.tsx routing
Perf:      lazy img, no extra animation libs, no shadow stacking
```

### Acceptance map

- Phase 2 ✓ stores as first-class entities, profile page, store search.
- Phase 3 ✓ 5-step lightweight flow, guided prompts, no friction.
- Phase 4 ✓ feed shows district + merchant + relative time; staggered.
- Phase 5 ✓ `PromotedSlot` placeholder reserved every 6 items.
- Phase 6 ✓ native chat with listing context header; WhatsApp optional.
- Phase 7 ✓ unified `MarcheEmpty` copy across all empty surfaces.
- Phase 8 ✓ lazy images, no heavy animation, single-shadow cards.
- Phase 9 ✓ inherits Conakry Contemporary tokens (no new colors).
- Phase 10 ✓ regular users sell without store; auto-upgrade nudge.
- Phase 11 ✓ lightweight chips for seller + buyer signals, no dashboards.

If you approve, I'll ship in order A → B → C → D so each step compiles and you can review live.