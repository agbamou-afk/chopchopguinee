
# Orange Money First Pivot — Public Wallet Archive

**Non-goals:** delete wallet tables/RPCs, alter pricing, change hold/capture/release semantics, weaken RLS, remove driver cashout or master wallet, fake OM automation.

## 1. Feature flag foundation
- Seed `feature_flags` row `wallet_public_enabled` = `false` (existing table, admin UI already exists at `/admin/flags`).
- Add `src/lib/flags/useFeatureFlag.ts` + `isPublicWalletEnabled()` helper (with sync cached read from a lightweight context loaded once at app boot). Single source of truth — no scattered DB reads.
- Wrap it in `FeatureFlagsProvider` mounted in `App.tsx`.

## 2. Client OM-first UI (flag = false)
- **BottomNav / AppShell**: replace "Wallet" tab with "Activité" (routes to a lightweight view showing recent payment/top-up/cashout records reusing existing tx query); keep icon change. If activity view is heavy, fall back to hiding the tab and elevating "Aide/Signalements".
- **WalletHero / PrimaryActionGrid / UserHome**: hide "Recharger le wallet" primary CTA; replace with "Payer avec Orange Money" (opens OM top-up sheet re-labeled as "Paiement Orange Money").
- **WalletView (`/wallet`)**: when flag off, render `WalletArchivedPanel` with the three-line OM-first copy from the brief, plus a filtered read-only list of OM payment requests + cashouts (no balance hero, no "recharger" CTA). When flag on, render current WalletView unchanged.
- **TopUpOrangeMoney sheet**: relabel headings/CTAs to "Paiement Orange Money", "Envoyer preuve", explicit "Aucun crédit automatique sans validation." (Wire copy through `src/lib/wallet/labels.ts`.)
- **Ride booking flow (`RidePickupScanner`, booking sheet, active ride)**: audit and swap balance/hold copy to "Paiement Orange Money requis" / "Réservation sécurisée par CHOPCHOP". Keep `wallet_hold` mechanics untouched; only label internal balance as "solde CHOP interne" where technically shown.

## 3. Driver-facing
- `DriverEarningsView` + `DriverCashoutSheet`: relabel to "Retrait Orange Money", "Paiement envoyé manuellement après validation", keep 5 000 GNF increments. Cashout stays visible regardless of flag.

## 4. Repas / Marché / Rides copy sweep
- Update payment status labels in `RepasRestaurantDetail`, food order components, marché offer/order components, and receipt sheets to lead with "Orange Money" for public copy. Keep admin-side language unchanged.

## 5. Admin & Ops Command Center
- No structural change: WalletAdmin, DriverCashouts, MasterWalletCard, Reconciliation all stay.
- Ops Command Center: rename public-facing labels to "Orange Money / Vérification opérateur / Retraits OM". God-only master balance already gated.
- Add a small "Wallet public archivé" indicator sourced from the flag on WalletAdmin / Ops so finance sees the mode.

## 6. Support / Recovery
- Add OM-specific issue categories/quick-labels in `ReportIssueButton` + `SupportAdmin` filter (paiement OM en attente, preuve envoyée non créditée, retrait OM en attente, frais d'annulation, paiement refusé). No wallet mutation.

## 7. Docs
- `docs/finance/orange-money-rail.md`: manual launch mode, future automation, ledger source of truth, no frontend provider secrets, no direct wallet mutation.
- Update `.lovable/memory/index.md` + create milestone `.lovable/memory/milestones/orange-money-first-wallet-archive-stable.md`.

## Migration
Single insert-only migration to seed the flag:
```sql
INSERT INTO public.feature_flags(key, enabled, description)
VALUES ('wallet_public_enabled', false, 'When false, hides public CHOP Wallet UI and leads with Orange Money; internal ledger remains active.')
ON CONFLICT (key) DO NOTHING;
```

## Files (planned)
- **New**: `src/lib/flags/featureFlags.ts`, `src/lib/flags/FeatureFlagsProvider.tsx`, `src/components/wallet/WalletArchivedPanel.tsx`, `docs/finance/orange-money-rail.md`, milestone doc.
- **Edited**: `src/App.tsx`, `src/components/ui/BottomNav.tsx`, `src/components/ui/AppShell.tsx`, `src/components/views/WalletView.tsx`, `src/components/home/WalletHero.tsx`, `src/components/home/PrimaryActionGrid.tsx`, `src/components/views/UserHome.tsx`, `src/components/wallet/TopUpOrangeMoney.tsx`, `src/components/views/DriverEarningsView.tsx`, `src/components/wallet/DriverCashoutSheet.tsx`, `src/lib/wallet/labels.ts`, `src/pages/admin/OpsCommandCenter.tsx`, `src/pages/admin/WalletAdmin.tsx`, `.lovable/memory/index.md`, plus a targeted Repas/Marché/receipt copy pass.

## QA
Manual pass A–N per the brief, plus `tsgo` build check.

## Risks
- Copy sweep across Repas/Marché is broad; keep changes to visible strings only.
- Activity view for the replaced tab may need light scaffolding — if too heavy, prefer hiding the tab and surfacing OM history inside Orders/Profile.

Approve and I execute end-to-end.
