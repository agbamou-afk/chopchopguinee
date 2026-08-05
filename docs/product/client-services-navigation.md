# Client Shell & Services Navigation (RC amendment — Slice 2)

Status: implemented, approved amendment to `web-production-release-candidate-stable`
(RC remains **UNLOCKED**). Envoyer is Slice 3.

## Bottom navigation — old vs new

| | Old | New |
|---|---|---|
| Tabs | Accueil · Activité · (ChopWallet, flag-gated) · Compte | Accueil · Services · Activité · Compte |
| Center FAB | Large permanent scanner FAB | Removed |
| Wallet tab | Present only when `wallet_public_enabled` | Removed from nav; payments live in Services |
| Scanner | Center FAB | Services tile + compact Services-header shortcut |
| Driver nav | Tableau · Courses · Profil | Unchanged |

Touch targets are ≥48px, labels never wrap, and the bar keeps
`pb-[max(0.5rem,env(safe-area-inset-bottom))]` for Android/PWA safe area.

## Service directory action map

| Tile | Wired to |
|---|---|
| Course Moto | `handleAction("moto")` → existing `RideBooking` moto flow |
| Course TokTok | `handleAction("toktok")` → existing `RideBooking` toktok flow |
| Envoyer | `EnvoyerComposer` (Slice 3 parcel module, gated by `envoyer_enabled`, currently OFF) |
| Repas | `handleAction("food")` → `FoodView` |
| Marché | `handleAction("market")` → `MarketView` |
| OM Wallet | `handleAction("wallet")` → `WalletView` (Orange-Money-first surface per flags) |
| Scanner | `handleAction("scan")` → global `QrScanner` + payload router |
| Devenir marchand | `/devenir-marchand` (MerchantApply) |
| Devenir chauffeur | `/driver/apply` |
| Aide | `handleAction("support")` → `/help` |

Tile labels/subtitles for payments come from `usePublicPaymentProductName` /
`usePublicPaymentProductSubtitle`, so the Orange-Money-first pivot copy stays
consistent and no internal balance is exposed while `wallet_public_enabled` is off.

## Envoyer — Slice 3 status (superseded)

The tile has its final position (3rd) and visual identity (`envoyer.png`), but it
opens a dialog stating plainly that the dedicated parcel module (tracking, proof
of delivery, parcel pricing) is not open yet, and offers a normal moto-coursier
ride at normal ride pricing. The Home `Envoyer` shortcut raises the same honest
toast before opening the moto flow. No fake success, no invisible fallback.

## View state / deep links

- New `services` value in `ActiveView`, reachable via `?tab=services`.
- Home and Services are public; Activité and Compte still require auth.
- Payments (`wallet` view) keep Services highlighted since the wallet tab is gone.
- Scanner remains a modal overlay and closes back to the originating view.
- No router rewrite: the existing view-state architecture is extended only.

## Home cleanup

Home no longer depends on the center FAB and shows a compact subset
of services with a `Voir tous les services` action into
Services. Wallet hero, promos, recent activity, nearby drivers, partner
recruitment and discovery content are unchanged.

## Home quick-service rail

The dark-green "Plus de services" island is a horizontal, snap-scrolling rail
(`QuickActions`) fed by one centralized definition: Course · Bonbonna · Repas ·
Marché · Envoyer · Scanner. Every tile calls the canonical `Index.handleAction`
id used by the Services destination (`moto`, `toktok`, `food`, `market`,
`parcel`, `scan`), so Home and Services can never diverge. Envoyer stays visible
but shows the same honest `Bientôt disponible` gated state as Services while
`envoyer_enabled` is OFF. The archived public wallet is not present in the rail.
~3.5 cards are visible at 390px; the right-edge fade is decorative and
pointer-events-none.

## Regression scope

`BottomNav`, `Index` view state/actions, `QuickActions`, `UserHome` services
section header, new `ServicesView`. No pricing, wallet, payment, RLS, or edge
function changes.

## Envoyer update (Slice 3)

The interim dialog and the moto-coursier fallback are removed. The tile now
opens the real parcel composer (`EnvoyerComposer`) behind `envoyer_enabled`,
which is **OFF** in production. See `docs/product/envoyer-v1.md`.
