# CHOP CHOP — Design System

## Colors (HSL semantic tokens)
Defined in `src/index.css`. Always reference via Tailwind classes (`bg-primary`, `text-foreground`, etc.) — never hex.

| Token | Light HSL | Use |
|---|---|---|
| `--primary` (CHOP green) | `138 64% 39%` | Primary actions, brand accents |
| `--primary-foreground` | `0 0% 100%` | Text on primary |
| `--secondary` (CHOP gold) | `45 90% 62%` | Highlights, ratings, badges |
| `--destructive` (CHOP red) | `2 75% 56%` | Errors, danger, urgent badge |
| `--success` | `138 64% 39%` | Success states |
| `--warning` | `45 90% 62%` | Warnings |
| `--background` / `--foreground` | `0 0% 100%` / `0 0% 7%` | Page surfaces |
| `--card` / `--card-foreground` | `0 0% 100%` / `0 0% 7%` | Card surfaces |
| `--muted` / `--muted-foreground` | `0 0% 96%` / `0 0% 40%` | Subtle surfaces, helper text |
| `--border` / `--input` | `0 0% 92%` | Borders & input outlines |
| `--brand-green-muted` | `138 35% 92%` | Soft green chips, success bg |
| `--brand-yellow-muted` | `45 85% 92%` | Soft gold chips |
| `--brand-red-muted` | `2 70% 94%` | Soft red chips, urgent bg |
| `--brand-gray` | `0 0% 96%` | Neutral light surface |

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
- Tap: `whileTap={{ scale: 0.97 }}`
- Hover (desktop only): `whileHover={{ scale: 1.02 }}`
- Page transitions: `fade-in` 200ms
- Sheets: `slide-up` 300ms, ease-out
- Never use spinning/bouncy easings on transactional UI

## Money formatting
Always via `formatGNF(amount)` from `src/lib/format.ts` → `2 500 000 GNF` (NBSP separators, suffix).