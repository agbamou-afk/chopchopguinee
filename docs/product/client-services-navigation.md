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
| Envoyer | Honest interim dialog → optional `handleAction("moto")` moto-coursier |
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

## Envoyer — temporary status (pending Slice 3)

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
(Course · Repas · Marché · Envoyer) with a `Voir tous les services` action into
Services. Wallet hero, promos, recent activity, nearby drivers, partner
recruitment and discovery content are unchanged.

## Regression scope

`BottomNav`, `Index` view state/actions, `QuickActions`, `UserHome` services
section header, new `ServicesView`. No pricing, wallet, payment, RLS, or edge
function changes.
