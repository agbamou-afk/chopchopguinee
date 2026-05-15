# CHOP CHOP — Icon Inventory & Unification Audit

Phase: pre-replacement audit. **No icons changed yet.**
Goal: lock the icon language before any swap so the system stays coherent.

## 1. CHOP icon rules (canonical)

Two icon families coexist. Every icon belongs to exactly one.

### A. Service icons — kinetic, branded
- Custom raster/SVG (currently the PNGs in `src/assets/icons/`).
- Rounded geometry, low detail, mobile-legible at 24–88 px.
- Allowed motion: subtle float / motion streaks (already used via `float-soft`).
- Used **only** for: Moto, TokTok, Repas, Marché, Envoyer, Scanner — i.e. the user-facing service tiles.
- Tone: warm, African-urbanism, slight personality.

### B. Utility icons — Lucide-like
- `lucide-react` only. Stroke `1.75` (per DESIGN_SYSTEM.md), round caps/joins.
- No motion streaks, no fills, no custom hues — `currentColor` always.
- Sizes: `w-5 h-5` inline, `w-6 h-6` tiles, `w-[22px]` BottomNav.
- Used for: navigation, wallet, driver ops, admin, onboarding, status, chevrons.
- Custom SVGs in this family (e.g. `SteeringWheel`) MUST match Lucide's 24×24, stroke-1.75, round-cap contract.

### Hard rules
- Never mix families inside one row at the same visual weight (chevrons stay small/utility next to a service PNG).
- Never tint Lucide icons with hex; only semantic tokens (`text-primary`, `text-muted-foreground`, …).
- Never animate utility icons beyond opacity / subtle translate.
- Service motion streaks live on the icon halo, not on Lucide glyphs.

---

## 2. Surface-by-surface inventory

Legend — **Action**: `keep` (on-spec), `restyle` (right family, wrong stroke/size/tone), `replace` (wrong family or wrong glyph).

### BottomNav — `src/components/ui/BottomNav.tsx`
| Icon | Family | Use | Action | Note |
|---|---|---|---|---|
| `Home` | Lucide | Accueil / Tableau | keep | |
| `ShoppingBag` | Lucide | Client "Activité" | replace | Bag reads as "shop", not "activity". Swap to `Receipt` or `Activity` post-timeline Phase 2. |
| `Wallet` | Lucide | CHOPWallet | keep | |
| `User` | Lucide | Compte / Profil | keep | |
| `ScanLine` | Lucide | Center FAB scanner | keep | Utility glyph on branded surface — OK. |
| `SteeringWheel` (custom) | Lucide-like | Driver "Courses" | keep | Confirm stroke 1.75 in next pass. |

### Services grid — `src/components/home/QuickActions.tsx`
| Icon | Family | Action | Note |
|---|---|---|---|
| `moto.png`, `toktok.png`, `repas.png`, `marche.png`, `envoyer.png`, `scanner.png` | Service | keep | Branded set — canonical reference. |

### Primary action grid — `src/components/home/PrimaryActionGrid.tsx`
| Icon | Family | Action | Note |
|---|---|---|---|
| `Plus` (CHOPWallet topup) | Lucide | keep | |
| `Bike` (Course) | Lucide | replace | Should reuse `moto.png` to match service set. |
| `UtensilsCrossed` (Repas) | Lucide | replace | Should reuse `repas.png`. |
| `ShoppingBag` (Marché) | Lucide | replace | Should reuse `marche.png`. |

### WalletView — `src/components/views/WalletView.tsx`
| Icon | Family | Action | Note |
|---|---|---|---|
| `ArrowUpRight`, `ArrowDownLeft` | Lucide | keep | Tx direction. |
| `History`, `CreditCard`, `QrCode`, `Plus`, `Loader2`, `LogIn`, `ScanLine`, `Timer`, `Users` | Lucide | keep | Utility. |
| `ShieldCheck`, `AlertTriangle`, `Clock`, `XCircle` | Lucide | keep | Status. |
| `Sparkles` | Lucide | restyle | Reserve for AI / promo only. |

### DriverHome — `src/components/views/DriverHome.tsx`
| Icon | Family | Action | Note |
|---|---|---|---|
| `Power`, `Radar`, `Users`, `AlertTriangle`, `Clock`, `ShieldCheck`, `FileWarning`, `Wallet`, `Navigation` | Lucide | keep | Ops/status. |
| `Sparkles` | Lucide | restyle | Same overuse caution. |

### DriverEarningsView — `src/components/views/DriverEarningsView.tsx`
| Icon | Family | Action | Note |
|---|---|---|---|
| `TrendingUp`, `Calendar`, `Download`, `ChevronRight`, `Wallet`, `ShieldCheck`, `AlertTriangle` | Lucide | keep | |
| `Bike` | Lucide | restyle | Acceptable in inline list (utility context). Confirm stroke 1.75. |

### DriverOrdersView — `src/components/views/DriverOrdersView.tsx`
| Icon | Family | Action | Note |
|---|---|---|---|
| `Users`, `Timer`, `BellRing`, `Flame`, `Navigation`, `Plus`, `Minus`, `LocateFixed` | Lucide | keep | |

### ClientOnboarding — `src/components/onboarding/ClientOnboarding.tsx`
| Icon | Family | Action | Note |
|---|---|---|---|
| `Bike`, `ShoppingBag`, `UtensilsCrossed` | Lucide | replace | Showcases the service set — should use service PNGs for brand recall. |
| `Wallet`, `MapPin`, `Truck`, `Plus`, `Receipt`, `ChevronRight`, `X` | Lucide | keep | Supporting utility. |

### DriverOnboarding — `src/components/onboarding/DriverOnboarding.tsx`
| Icon | Family | Action | Note |
|---|---|---|---|
| `Power`, `Bell`, `MapPin`, `Flag`, `Flame`, `ChevronRight`, `X`, `Wallet`, `QrCode`, `Check` | Lucide | keep | Driver onboarding is operational — utility-only is correct. |

### AdminSidebar — `src/components/admin/AdminSidebar.tsx`
| Icon | Family | Action | Note |
|---|---|---|---|
| `LayoutDashboard`, `Activity`, `Users`, `Store`, `Wallet`, `Coins`, `Tag`, `ClipboardList`, `LifeBuoy`, `ShieldAlert`, `MessageSquare`, `Megaphone`, `BarChart3`, `MapPin`, `ToggleLeft`, `Settings`, `UserCog`, `ScrollText`, `Scale` | Lucide | keep | |
| `Bike`, `UtensilsCrossed`, `ShoppingBag` | Lucide | keep | Service PNGs would be too noisy in a dense sidebar. |
| `Sparkles` | Lucide | restyle | Reserve for AI sections only. |

### Map markers — `src/lib/maps/markerIcons.ts`
- Custom inline SVG paths with branded colors. Governed by map style guide. **keep.**

---

## 3. Cross-cutting findings

1. **Service-tile inconsistency** — `PrimaryActionGrid` and `ClientOnboarding` use Lucide outlines for the same services that `QuickActions` shows as branded PNGs. Single biggest inconsistency.
2. **Activity tab glyph** — `ShoppingBag` no longer matches meaning post-Phase 2 timeline. Replace with `Receipt` or `Activity`.
3. **`Sparkles` overuse** — appears in WalletView, DriverHome, AdminSidebar. Restrict to AI / promo surfaces.
4. **Stroke width drift** — DESIGN_SYSTEM mandates 1.75; most call sites use Lucide default 2. Sweep via a shared `<Icon>` wrapper later.
5. **`SteeringWheel`** — already matches the Lucide-like contract. Use as the template for any future custom utility glyph.

## 4. Replacement queue (do NOT execute yet)

1. Swap `PrimaryActionGrid` Bike / UtensilsCrossed / ShoppingBag → service PNGs.
2. Swap `ClientOnboarding` service icons → service PNGs.
3. Replace BottomNav `ShoppingBag` (Activité) → `Receipt` (or finalized timeline glyph).
4. Sweep `strokeWidth={1.75}` onto Lucide usages via a shared wrapper.
5. Demote `Sparkles` to AI-only surfaces.

## 5. Acceptance

- [x] Inventory exists (this file).
- [x] Icon rules defined (section 1).
- [x] No icons replaced in this pass.
