# Orange Money Public Surface — Naming & Routing

## Purpose
Keep every customer-facing payment surface consistently Orange Money-first while the
public CHOP Wallet is archived behind `wallet_public_enabled=false`. Internal ledger,
master wallet, cancel-fee, cashout, settlement, refund, RLS and provider logic are
**not** covered by this document.

## Canonical naming
All new client-facing components MUST import the label + subtitle from the flag
helper — never hardcode the name.

```ts
import {
  usePublicPaymentProductName,      // "OM Wallet" (flag off) | "ChopWallet" (flag on)
  usePublicPaymentProductSubtitle,  // "Vos paiements Orange Money, vérifications et remboursements."
} from "@/lib/flags/useFeatureFlag";
```

Non-React call sites use the synchronous accessors:

```ts
import {
  publicPaymentProductName,
  publicPaymentProductSubtitle,
} from "@/lib/flags/featureFlags";
```

## Home tile
`src/components/home/PrimaryActionGrid.tsx` renders the primary payment tile.
When `wallet_public_enabled=false` it uses `OM_TILE_BASE` composed with the
dynamic name/subtitle. Icon stays visually aligned with the current grid
(same wallet artwork, same halo, same 116px min height).

`src/components/home/QuickActions.tsx` ("Plus de services" grid) reads the
name via `usePublicWalletLabel()`.

## Routing
Tapping the tile calls `onAction("topup")`, which navigates to `/wallet`
(handled by `WalletView`). When `wallet_public_enabled=false`, `WalletView`
renders `WalletArchivedPanel`, which embeds `OmPaymentsList` — the OM-first
payment center showing pending Orange Money submissions, operator-verification
callouts, confirmed / rejected / expired payments, refunds and support
escalation.

A dedicated `/payments` route does **not** exist yet. Part 2 will introduce
`/payments` and `/payments/:id` and migrate the tile destination.

## Bottom navigation
`BottomNav` drops the payment tab entirely when the flag is off (see
`userTabsOmFirst`). No stub "OM Wallet" tab is shown because Activity
already covers payment history and the primary payment CTA lives on Home.

## Rollback (flag on)
Flipping `wallet_public_enabled=true` in `/admin/flags` restores the legacy
ChopWallet naming (`WALLET_TILE`, `WalletHero` balance card, `BottomNav`
ChopWallet tab, `WalletView` internal balance). No component was renamed in
place, so rollback is atomic.

## Legacy surfaces intentionally NOT touched
- Admin surfaces (`/admin/wallet`, `/admin/payments`, `SupportAdmin`).
- Internal ledger copy in driver earnings and cashout screens.
- Terms / Legal wording (audited separately when legal review runs).
- Notification topic labels — settings copy, not navigation.

## Part 2 gap
- Build `/payments` and `/payments/:id` as the neutral OM-first payment
  center and switch the home tile + WalletArchivedPanel to link there.
- Sweep Terms, Notifications, Help and any long-form copy that still says
  "ChopWallet" so it matches the OM-first public voice.
