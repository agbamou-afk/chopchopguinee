---
name: Orange Money Public Surface Consistency — Stable
description: Public payment surface centralized on OM-first naming via publicPaymentProductName helper; home tile subtitle wired; rollback via wallet_public_enabled preserved
type: milestone
---

# Orange Money Public Surface Consistency — Stable

Locked Part 1 of the Orange Money Public Surface Cleanup phase.

## What shipped
- `publicPaymentProductName()` / `publicPaymentProductSubtitle()` in
  `src/lib/flags/featureFlags.ts` as the canonical public-payment naming.
- React hooks `usePublicPaymentProductName()` and
  `usePublicPaymentProductSubtitle()` in `src/lib/flags/useFeatureFlag.ts`.
- `PrimaryActionGrid` OM tile now composes label + subtitle + alt from the
  helper. Subtitle reads "Vos paiements Orange Money, vérifications et
  remboursements." when `wallet_public_enabled=false`.
- `QuickActions` "Plus de services" wallet tile confirmed to consume
  `usePublicWalletLabel()` — no hardcoded "ChopWallet" on the tile.
- `BottomNav` continues to drop the ChopWallet tab under OM-first mode
  (unchanged, verified).
- Documentation: `docs/finance/orange-money-public-surface.md`.

## Route behavior
Tile action `topup` → `/wallet` → `WalletView` → `WalletArchivedPanel`
(includes `OmPaymentsList`). `/payments` route does not exist yet; Part 2
will build the dedicated payment center and repoint the tile.

## Rollback
`wallet_public_enabled=true` in `/admin/flags` restores legacy `WALLET_TILE`
naming, `WalletHero` balance card, ChopWallet BottomNav tab, and the
internal ledger view. No in-place rename — rollback is atomic.

## Out of scope (do NOT re-open here)
- Payment authorization, holds, cancellation-fee, cashout, refunds.
- OM sandbox / provider automation logic.
- RLS or provider webhook code.
- Admin cockpit finance surfaces.
- Terms/Legal long-form wording — pending legal review sweep.

## Part 2 gap
- Build `/payments` + `/payments/:id` neutral payment center.
- Legal/Help/Notifications copy sweep for consistent OM-first voice.
