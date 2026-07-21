# Orange Money First — Public CHOP Wallet Archived (Stable)

## Decision
CHOPCHOP ships as an Orange Money-first product. The public CHOP Wallet
surface is archived behind a Super-Admin feature flag. The internal
ledger (`wallets`, `wallet_transactions`, master wallet, cancellation
fee, driver cashout) is **untouched** and continues to power holds,
credits, debits, and audit.

## Flag
- `feature_flags.wallet_public_enabled` — default **false** (seeded via migration).
- Toggle from **/admin/flags** (Super Admin only).
- Runtime accessor: `isPublicWalletEnabled()` / `usePublicWalletEnabled()` in `src/lib/flags/`.
- Fire-and-forget load from `App.tsx`; UI reads safe DEFAULTS until hydrated.

## Client UI when flag = false
- `BottomNav`: ChopWallet tab dropped; layout collapses to 4 columns (Accueil, Activité, Scanner, Compte).
- `PrimaryActionGrid` (home): "ChopWallet / Recharger" tile → "Orange Money / Payer par Orange Money".
- `WalletHero` (home): payment-first hero — "Payer avec Orange Money" as primary CTA.
- `/wallet` route: renders `WalletArchivedPanel` — OM-first messaging + operator-verification callout + Activité + Signalements shortcuts. Top-up sheet still reachable and is labeled "Paiement Orange Money".
- `TopUpOrangeMoney`: primary CTA renamed to "Continuer avec Orange Money". Reinforced disclaimer: "Aucun crédit automatique sans validation opérateur."

## Untouched (intentional)
- `wallets`, `wallet_transactions` ledger.
- `ride_cancel` 10% master-wallet fee.
- Driver cashout requests + admin `mark_paid` flow.
- Master wallet god-admin RPC + card.
- Admin finance surfaces (`WalletAdmin`, `WalletReconciliation`, `DriverCashouts`).
- RLS policies. No SECURITY DEFINER RPC signatures changed.

## Rollback
Toggle `wallet_public_enabled = true` in `/admin/flags`. All wallet UI
returns instantly on next flag refresh (page reload).

## Files
- migration: seed `wallet_public_enabled` in `feature_flags`
- created `src/lib/flags/featureFlags.ts`
- created `src/lib/flags/useFeatureFlag.ts`
- created `src/components/wallet/WalletArchivedPanel.tsx`
- created `docs/finance/orange-money-rail.md`
- edited `src/App.tsx`
- edited `src/components/ui/BottomNav.tsx`
- edited `src/components/views/WalletView.tsx`
- edited `src/components/home/WalletHero.tsx`
- edited `src/components/home/PrimaryActionGrid.tsx`
- edited `src/components/wallet/TopUpOrangeMoney.tsx`