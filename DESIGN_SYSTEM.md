# CHOP CHOP — Design System

> **2026 evolution pass — warm modern African urbanism.**
> Visual language inspired by the new logo: movement, warmth, ecosystem flow,
> premium simplicity. Think *Grab × Linear × African warmth*. Avoid neon,
> crypto, cyberpunk, generic fintech blue, or Uber black/white.

## Colors (HSL semantic tokens)
Defined in `src/index.css`. Always reference via Tailwind classes (`bg-primary`, `text-foreground`, etc.) — never hex.

| Token | Light HSL | Use |
|---|---|---|
| `--primary` (deep CHOP green) | `152 58% 34%` | Primary CTAs, ride confirm, CHOPWallet, CHOPPay, earnings |
| `--primary-foreground` | `0 0% 100%` | Text on primary |
| `--secondary` (warm saffron) | `38 92% 58%` | Highlights, demand pulses, onboarding accents |
| `--destructive` (soft ember) | `12 78% 56%` | Urgency, destructive, live ops moments |
| `--success` | `152 58% 34%` | Success states (mirrors primary) |
| `--warning` | `38 92% 58%` | Warnings |
| `--background` (cream) | `36 30% 98%` | Page surface — never cold white |
| `--foreground` (warm slate) | `160 18% 12%` | Ink — never pure black |
| `--muted` / `--muted-foreground` | `38 25% 95%` / `160 10% 38%` | Sand surfaces, helper text |
| `--border` / `--input` | `38 18% 90%` | Subtle warm outlines |
| `--brand-green-muted` | `152 35% 92%` | Soft green chips |
| `--brand-yellow-muted` | `38 85% 93%` | Soft gold chips |
| `--brand-red-muted` | `12 70% 95%` | Soft ember chips |

### Gradients
**Three canonical gradients only — do not invent new ones.**
- `--gradient-primary` / `.gradient-cta` — vertical emerald, every primary CTA
- `--gradient-wallet` — radial emerald, CHOPWallet surfaces only
- `--gradient-ambient` / `.surface-warm` — soft warm wash for page backgrounds

Reserved accents (use sparingly):
- `--gradient-secondary` — saffron pulses for demand/highlight moments
- `--gradient-ember` — live-ops urgency
- `--gradient-map-overlay` — map scrim only

### Elevation
Four-level elevation system, warm-tinted, never harsh black:
- **flat** — `shadow-flat` (none) — inline surfaces
- **elevated** — `shadow-card` — default card lift
- **floating** — `shadow-soft` / `shadow-elevated` — drawers, sticky headers, modals
- **island** — `shadow-island` — ride request island, focus moments

Specials: `shadow-wallet` for the CHOPWallet card; `--shadow-glow-primary` for focus rings on confirm actions.

## Motion
Single canonical easing: `var(--ease-flow)` = `cubic-bezier(0.22, 1, 0.36, 1)`.
Standard durations: micro `200ms`, default `300ms`, sheet `350ms`. No springs on transactional UI.
Tap response: `whileTap={{ scale: 0.985 }}`. Hover (desktop only): `whileHover={{ scale: 1.015 }}`.

Service accents already exist: `--accent-{moto,toktok,repas,marche,envoyer,scanner}`.

## Typography
Font: **Poppins** (Google Fonts), fallback `system-ui, sans-serif`.

| Role | Tailwind | Size / leading | Weight |
|---|---|---|---|
| Display | `text-3xl leading-tight` | 30/36 | 700 |
| H1 / Page title | `text-2xl leading-tight` | 24/32 | 700 |
| H2 / Section | `text-lg leading-snug` | 18/24 | 600 |
| H3 / Card title | `text-base leading-snug` | 16/22 | 600 |
| Body | `text-sm leading-normal` | 14/20 | 400-500 |
| Caption | `text-xs leading-normal` | 12/16 | 400-500 |
| Label / chip | `text-[11px] uppercase tracking-wide` | 11/14 | 600 |

## Spacing scale
Use Tailwind defaults (already 4-px based):
`1 (4) · 2 (8) · 3 (12) · 4 (16) · 5 (20) · 6 (24) · 8 (32) · 10 (40)`.
Page horizontal padding: `px-4`. Section vertical rhythm: `space-y-6`.

## Border radius
Base `--radius: 1.25rem` → Tailwind `rounded-lg`.
- Cards / sheets: `rounded-2xl` (1.5rem)
- Buttons / chips: `rounded-xl` (1.25rem)
- Service icons: `rounded-xl`
- BottomNav: top corners none (sticks to bottom), inner items `rounded-xl`
- Modals: `rounded-3xl` top only on mobile sheets
- Inputs: `rounded-xl`

## Shadows (soft, never heavy)
- `shadow-card` — default surface lift
- `shadow-soft` — secondary lift (drawers, sticky headers)
- `shadow-elevated` — modals, FABs, primary CTAs

Avoid stacking multiple shadows. Never use Tailwind's `shadow-2xl`.

## Icons
- Library: `lucide-react` only
- Default size: `w-5 h-5` (inline) or `w-6 h-6` (service tiles)
- Stroke: default (1.5)
- Color: inherit `currentColor` — never hex

## Cards
- Surface: `bg-card`
- Radius: `rounded-2xl`
- Shadow: `shadow-card`
- Padding: `p-4` (compact) / `p-5` (default) / `p-6` (hero)

## Buttons
- Primary: `gradient-primary text-primary-foreground`, `rounded-xl`, `h-12`, `font-semibold`
- Secondary: `bg-muted text-foreground`, `rounded-xl`, `h-12`
- Action (icon + label tile): square `rounded-xl bg-card shadow-card`, icon in colored chip
- Destructive: `bg-destructive text-destructive-foreground`
- Ghost: transparent, hover `bg-muted`

## Motion
- Library: Framer Motion
- Easing: `cubic-bezier(0.22, 1, 0.36, 1)` — flowing, infrastructural
- Tap: `whileTap={{ scale: 0.98 }}` (was 0.97 — calmer)
- Hover (desktop only): `whileHover={{ scale: 1.015 }}`
- Page transitions: `fade-in` 200ms
- Sheets: `slide-up` 300ms, ease-out
- BottomNav active pill: layout transition `tween` 350ms (no spring bounce)
- Avoid: bouncy springs, gaming easings, spinning loaders on transactional UI
- Prefer: directional flow, opacity + subtle translate, restrained scale

## Branding copy
- **CHOPWallet** replaces "Portefeuille" everywhere user-facing.
  Examples: *Solde CHOPWallet*, *Recharger CHOPWallet*, *Historique CHOPWallet*.
- **CHOPPay** is the payments mark. *Payer avec CHOPPay*, *Reçu CHOPPay*.
- Keep usage premium and subtle — do not spam the brand on every label.
- Legal documents keep formal "Portefeuille" terminology.

## Map styling accents
- Heatmap gradient: warm green → saffron (no red unless surge urgent)
- Driver markers: emerald arrow with subtle pulse ring (see `DriverPositionMarker`)
- Overlays use `--gradient-map-overlay` for legibility scrims
- Demand zones: `hsl(var(--secondary) / 0.25)` fill, `hsl(var(--primary))` stroke

## Iconography direction
- Library: `lucide-react` only — keep stroke 1.75 (was default 1.5) for warmer presence
- Rounded geometry, soft corners, transportation-inspired motion glyphs
- Client tiles: lifestyle tone, `bg-brand-green-muted` chips
- Driver tiles: operational tone, `bg-muted` chips with `text-foreground`
- Service accent backgrounds use `--accent-{moto,toktok,repas,marche,envoyer,scanner}`

## Money formatting
Always via `formatGNF(amount)` from `src/lib/format.ts` → `2 500 000 GNF` (NBSP separators, suffix).