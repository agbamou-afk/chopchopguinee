# CHOP CHOP — Audit (Phase 0)

## Stack
- React 18 + Vite 5 + TypeScript 5
- Tailwind CSS v3 (semantic HSL tokens) + shadcn/ui + lucide-react
- Framer Motion for transitions
- Backend: Lovable Cloud (Supabase) — auth, Postgres, RLS, storage
- Routing: react-router-dom v6
- State: TanStack Query, local component state

## Routes (`src/App.tsx`)
- `/` → `pages/Index.tsx` (tabbed shell: home, orders, wallet, profile, market view)
- `/auth` → email + phone signup/login (auto-confirm enabled)
- `/admin`, `/agent`, `/agent/topup`
- `/profile`, `/help`, `/legal`
- `*` → `NotFound`

## Components by domain
- **Home:** `home/QuickActions`, `home/PromoCarousel`, `home/WalletCard`, `views/UserHome`
- **Marché:** `marche/{CategoryGrid, FeaturedBanners, ListingCard, ListingDetail, SellFlow, InboxView, ChatThread, ReportModal, SellerBadge}` + `views/MarketView`
- **Repas:** `food/{RestaurantCard, FoodCategories}` + `views/FoodView`
- **Ride:** `ride/RideBooking`, `tracking/{LiveTracking, RatingPrompt}`
- **Driver:** `driver/{DriverDashboard, DriverTripView, IncomingRequestPopup, LiveRidesPanel, OrderRequest}` + `views/{DriverHome, DriverOrdersView, DriverEarningsView}`
- **Wallet:** `wallet/{MyQrModal, PinSetup}` + `views/WalletView` + `hooks/useWallet`
- **Scanner:** `scanner/QrScanner`
- **Shared UI:** `ui/{AppHeader, BottomNav, ServiceCard}` + full shadcn set

## Styling system (current state)
- Semantic HSL tokens in `src/index.css` (`--primary` emerald, `--secondary` gold, `--destructive` red, light + dark themes)
- Service accents: `--accent-{moto,toktok,repas,marche,envoyer,scanner}`
- Gradients: `--gradient-{primary,secondary,hero,glass}`
- Shadows: `--shadow-{soft,card,elevated}`
- Radius base: `1.25rem`
- Font: Poppins (Google Fonts)
- Tailwind: dark-mode class strategy, semantic color mapping in `tailwind.config.ts`

## Backend integrations
- `src/integrations/supabase/client.ts` (auto-generated, never edit)
- `useAuthGuard` hook gates non-public actions → `/auth?next=...`
- Auth: email + phone, auto-confirm ON, anonymous OFF
- Roles: `app_role` enum + `user_roles` table + `has_role()` security-definer fn

## Database (Supabase)
- **Identity:** `profiles`, `user_roles`, `user_pins`
- **Wallet:** `wallets`, `wallet_transactions`, `agent_profiles`, `topup_requests`
- **Marché:** `marketplace_listings`, `listing_images`, `listing_reports`, `saved_listings`, `conversations`, `messages`
- **Mobility:** `rides`, `fare_settings`
- **Services:** `service_profiles`, `support_messages`
- All tables have RLS; admin-bypass via `has_role(auth.uid(),'admin')`

## Top 20 visual issues (chapter B item 1)
1. Hardcoded colors leak in places (`text-white`, hex literals) bypassing tokens
2. Header logo + greeting + wallet card cramped on 390px
3. Greeting text can truncate awkwardly when name is long
4. GNF amounts use inconsistent formatting (`2500000`, `2 500 000`, `2,500,000 GNF`)
5. Search bar lacks clear placeholder hierarchy
6. Service icons have unequal padding/visual weight across Moto/TokTok/Repas/Marché/Envoyer/Scanner
7. Recents row shows native scrollbar artifact on some viewports
8. PromoCarousel cards clip at small widths
9. RestaurantCard image aspect ratios drift between contexts
10. Bottom nav center scanner button vertical alignment shifts
11. Inactive bottom nav icons same weight as active — low contrast hierarchy
12. Action buttons hidden behind BottomNav on multiple flows (recently fixed only in SellFlow)
13. Section title sizes inconsistent across Home / Repas / Marché / Wallet / Driver / Profile
14. Card corner radius drift (1rem, 1.25rem, 1.5rem mixed)
15. Shadows feel heavy in some cards, missing in others
16. Drawer (side menu) sparse and unbranded; slogan missing
17. Driver dashboard not visually distinguished from client mode
18. Empty + loading states largely absent (lists pop in raw)
19. Wallet card uses generic "C" mark instead of CHOP CHOP logo lockup
20. PIN setup + sensitive-action confirmations lack consistent modal pattern

---
_End Phase 0._