# Global UI Cleanup — Icon Typology + Flag-Driven Product Exposure

Audit-and-plan only. No code, no assets, no DB changes in this pass.

## 1. Root files involved

Discovery surfaces
- `src/components/views/ServicesView.tsx` — the Services grid (11 tiles, local `tiles` array).
- `src/components/home/QuickActions.tsx` — home service rail (6 items, local `HOME_RAIL` array).
- `src/components/home/PrimaryActionGrid.tsx` — home primary tiles (wallet/course/repas/marché).
- `src/components/ui/BottomNav.tsx` — 4 client destinations, Lucide only (correct utility family).
- `src/pages/Index.tsx` — `handleAction(action)` is the single action router for all of the above.
- Recruitment/utility routes: `/devenir-marchand`, `/driver/apply`, `/help` (see `src/App.tsx`).

Icon assets
- `src/assets/icons/`: `moto.png`, `toktok.png`, `repas.png`, `marche.png`, `envoyer.png`, `scanner.png`, `wallet.png`, `choppay.png`.
- Rules already written in `docs/icon-inventory.md` (two families: branded service raster vs Lucide utility).

Flags
- `src/lib/flags/featureFlags.ts` — synchronous cache over `public.feature_flags`, 16 `KNOWN_FLAGS`, `DEFAULTS`, `loaded` boolean (not exported), listener emit.
- `src/lib/flags/useFeatureFlag.ts` — `useSyncExternalStore` hooks.
- `src/pages/admin/FlagsAdmin.tsx` — admin toggle list (reads `feature_flags` directly, RPC to set with reason).

## 2. Icon typology findings

Confirmed inconsistency in `ServicesView`: tiles carry either `img` (branded PNG, rendered `w-11 h-11 object-contain scale-[1.4]`) or `Icon` (Lucide/custom glyph at `w-5 h-5 text-primary`), both inside the same `w-11 h-11 rounded-xl bg-primary/10 ring-1 ring-primary/15` chip. Same chip, two very different fill ratios and two visual languages — that is the "mixed" look on screen.
- Branded: Course Moto, Bonbonna, Envoyer, Repas, Marché, Chop Pay, Scanner.
- Glyph: Course Taxi (`Car`), Devenir marchand (`Store`), Devenir chauffeur (`SteeringWheel`), Aide (`LifeBuoy`).

`PrimaryActionGrid` is already fully branded-PNG. `QuickActions` is fully branded-PNG with per-icon optical tuning (`SERVICE_ICON_TUNING`). `BottomNav` is fully Lucide. So the only mixed surface today is `ServicesView`; `docs/icon-inventory.md` items 1–2 of its replacement queue are already done.

### Canonical contract (proposed)

Family A — Service tile (transactional products only: Moto, Bonbonna, Taxi, Envoyer, Repas, Marché, Chop Pay, Scanner)
- Branded raster PNG in a `w-11 h-11 rounded-xl` chip, `bg-primary/10 ring-1 ring-primary/15`, `object-contain`, per-icon optical scale from one shared tuning map (lift `SERVICE_ICON_TUNING` out of `QuickActions` into `src/lib/services/serviceIcons.ts`).
- `alt=""` + `aria-hidden`; the accessible name lives on the button `aria-label`.

Family B — Entry/utility tile (Devenir marchand, Devenir chauffeur, Aide, and future account/support entries)
- Deliberately different so it reads as intentional: Lucide glyph at `w-5 h-5`, `strokeWidth={1.75}`, in a **circular** `rounded-full bg-muted/60 ring-1 ring-border` chip with `text-muted-foreground` — i.e. neutral chip, not the primary-tinted square used by products. This visually separates "things you buy" from "things you join / ask for".

Missing branded art (do NOT generate now; list only)
- `taxi.png` (Course Taxi) — currently the only *product* tile with no art. Placeholder strategy until art exists: reuse `moto.png` is wrong (different vehicle), so temporarily render Taxi with the Family-A chip + `Car` Lucide at `w-6 h-6 text-primary` and mark it in code as `TODO: awaiting taxi.png`. Given the exposure law below, Taxi is hidden while `taxi=false`, so this placeholder is currently invisible in production.
- Optional later: `aide.png`, `marchand.png`, `chauffeur.png` — NOT recommended; Family B is the deliberate answer for those.

## 3. Feature flag → UI exposure matrix

| Surface tile | Current flag | Current behaviour | Proposed |
|---|---|---|---|
| Course Moto | none | always visible | new `service_moto_enabled` (default ON) |
| Course Bonbonna (toktok) | none | always visible | new `service_toktok_enabled` (default ON) |
| Course Taxi | `taxi` | visible + "Bientôt disponible" | hide entirely when OFF |
| Envoyer | `envoyer_enabled` | visible + "Bientôt disponible" (also in `QuickActions`) | hide entirely when OFF |
| Repas | none | always visible | new `service_repas_enabled` (default ON) |
| Marché | none | always visible | new `service_marche_enabled` (default ON) |
| Chop Pay | `chop_pay_enabled` OR `wallet_public_enabled` | tile always visible, only label/subtitle changes | hide when both OFF |
| Scanner | none | always visible | new `service_scan_enabled` (default ON) |
| Devenir marchand | none | always visible | new `merchant_recruitment_enabled` (default ON) — recruitment axis, NOT `service_marche_enabled` |
| Devenir chauffeur | none | always visible | new `driver_recruitment_enabled` (default ON) — recruitment axis, NOT ride flags |
| Aide | none | always visible | never gated (support must always be reachable) |

Non-exposure flags (must never hide a discovery tile): `om_*` (checkout/topup/provider/sandbox/environment), `driver_balance_gate_enabled`, `envoyer_declared_value_enabled`, `envoyer_claims_enabled`. These are rail/sub-feature flags.

Gaps found
- No flag exists for Moto, Bonbonna, Repas, Marché, Scanner, or either recruitment funnel. New rows in the existing `feature_flags` table (data insert, not schema migration) + `FlagKey`/`DEFAULTS`/`KNOWN_FLAGS` entries.
- Recruitment is currently pure routing (`navigate("/devenir-marchand")`, `navigate("/driver/apply")`) with no exposure control — answering STEP 2.7: recruitment gets its own flags.
- Bypass risk: `Index.handleAction` routes `moto/toktok/auto/parcel/food/market/wallet/scan` with **no flag check at all**, and the routes `/devenir-marchand`, `/driver/apply` are directly linkable. Hiding a tile is therefore not a control today.

## 4. Exposure law (proposed)

1. A top-level product flag OFF ⇒ the entry is **not rendered** in any customer discovery surface (Services grid, home rail, primary grid, launchers). No placeholder, no disabled card, no "bientôt" tile. Grid reflows naturally (already `grid-cols-2/3/4`, so removal is free).
2. The existing "Bientôt disponible" pattern is retired for top-level products. (Owner decision — see §7.)
3. `handleAction` becomes the enforcement point: a disabled action is a no-op (with a dev warning), so deep links and stale clients cannot launch a hidden product. Server law already enforces Envoyer/Taxi independently; this is the client mirror, not a replacement.
4. Recruitment routes get a guard that redirects to `/` when their flag is OFF.
5. Admin surfaces (`/admin/flags` and all admin/ops pages) are never gated by product flags.

## 5. Anti-flicker

`featureFlags.ts` already has a `loaded` boolean but does not expose it. Plan: export `areFlagsLoaded()` + include load state in the store snapshot, add `useFlagsReady()`. Discovery grids render a lightweight skeleton (same tile count/height as the last-known set, or 6 neutral chips on cold start) until ready, so a disabled service is never briefly shown. Defaults stay conservative: new product flags default ON (they are live products), gated ones stay OFF.

## 6. Implementation sequence

- **S1 — Service registry.** New `src/lib/services/serviceRegistry.ts`: single declarative array of `{ id, label, desc, icon (asset|glyph), family: 'service'|'entry', action, order, flag }`, plus shared optical tuning. Pure data + types; no rendering change yet.
- **S2 — Shared tile component.** `src/components/services/ServiceTile.tsx` implementing Family A / Family B contracts. `ServicesView`, `QuickActions`, `PrimaryActionGrid` consume registry + tile. Visual-only; behaviour identical.
- **S3 — Flag plumbing.** Add the 7 new keys to `FlagKey`/`DEFAULTS`/`KNOWN_FLAGS`, insert matching `feature_flags` rows (data only), expose `useFlagsReady()`, add `useServiceExposure()` that returns the filtered registry.
- **S4 — Hide-not-disable.** Grids render only exposed entries; remove "Bientôt disponible" tiles for gated products.
- **S5 — Guards.** Flag checks inside `Index.handleAction` + redirect guards on the two recruitment routes.
- **S6 — Certify.** Focused tests + full Vitest, `bunx tsgo --noEmit -p tsconfig.app.json`, production build.

Risk boundaries: S1–S2 are presentation-only and independently revertable. S3–S5 change behaviour and are the only steps that need flag-state review. No Node 5 / auth / RLS / schema change anywhere. Existing `node2-taxi-labels.test.ts` asserts the current Taxi "bientôt" copy and will need updating in S4.

Test plan
1. Registry is the only source of tile definitions (no hardcoded service arrays remain in the three grids).
2. Flag OFF ⇒ tile absent from DOM in Services grid and home rail; grid has no empty cell.
3. Flag ON ⇒ tile present with the correct family chip.
4. Flags not yet loaded ⇒ no gated tile ever painted (skeleton assertion).
5. `handleAction("auto")` with `taxi=false` is a no-op — no booking sheet.
6. `/driver/apply` with recruitment flag OFF redirects home; with ON renders.
7. Aide is present regardless of flag state.
8. Family A tiles all use PNG assets; Family B tiles all use Lucide at stroke 1.75 (snapshot/class assertions).
9. Admin `/admin/flags` still lists and can re-enable every gated key.

## 7. Decisions needed from you before implementation

1. **Retire "Bientôt disponible" entirely?** Today Taxi and Envoyer show it. The proposed law hides them instead. Confirm — or keep an explicit `coming_soon` state for a named subset.
2. **Default state of the 7 new flags** — plan assumes ON for Moto, Bonbonna, Repas, Marché, Scanner, and both recruitment funnels.
3. **Chop Pay tile** — currently always visible with a degraded subtitle. Confirm it should disappear completely when the public payment product is off.
4. **Taxi art** — confirm `taxi.png` should be commissioned, or accept the Family-A + `Car` glyph placeholder permanently.
5. **Family B styling** — confirm the neutral circular chip as the deliberate secondary typology (vs forcing every tile into branded art).
