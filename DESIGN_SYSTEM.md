# CHOP CHOP — Design System
## Conakry Contemporary · v1.1 (storyboard-anchored)

> Conakry Contemporary is the visual identity of the CHOP CHOP super-app.
> Warm modern African urbanism: lagoon emerald, saffron gold, ember red,
> warm cream surfaces, premium calm. Think *Grab × Linear × Conakry sun*.
> Do **not** use neon, crypto, cyberpunk, generic fintech blue, or
> Uber black/white.
>
> **Lock:** This document is the source of truth. v1.1 re-anchors the palette
> to the Storyboard v2 hex set (`#178A43 / #F2821B / #E4483C / #1F2328 /
> #F7F2E8 / #ECE9E2 / #D9F1E2`) and formalises the **Kinetic Utility** icon
> language and the **Urban Flow** motion language. Any change must be
> proposed against a new minor version (`v1.x`) and reflected here in the
> same commit. Tag the lock as `conakry-contemporary-v1`.

---

## 1 · Brand & naming

| Surface | Use |
|---|---|
| **CHOP CHOP** | Display brand, splash, marketing |
| **CHOP** | Short product mark inside compositions (CHOPWallet, CHOPPay) |
| **CHOP GUINEE LTD** | Legal documents only |
| **Choper** | ❌ never |

Tagline: *Tout, Part Tout, Pour Tout.* — Currency: **GNF** only.

---

## 2 · Color (HSL semantic tokens)

All colors live in `src/index.css` as HSL. Components reference Tailwind
semantic classes (`bg-primary`, `text-foreground`) — **never hex, never
arbitrary `bg-emerald-600`**.

| Token | HSL | Hex anchor | Use |
|---|---|---|---|
| `--primary` (CHOP green) | `142 71% 32%` | `#178A43` | Primary CTA, ride confirm, CHOPWallet, CHOPPay, earnings |
| `--primary-foreground` | `40 53% 96%` | cream | Ink on primary |
| `--secondary` (saffron) | `28 89% 53%` | `#F2821B` | Highlights, demand pulses, onboarding accents |
| `--destructive` (ember) | `4 76% 56%` | `#E4483C` | Urgency, destructive, live-ops alerts |
| `--background` (cream) | `40 53% 94%` | `#F7F2E8` | Page surface — never cold white |
| `--foreground` (graphite) | `213 13% 14%` | `#1F2328` | Ink — never pure black |
| `--muted` / `--muted-foreground` | `42 22% 90%` / `213 10% 38%` | `#ECE9E2` | Sand surfaces, helper text |
| `--border` / `--input` | `42 22% 88%` | — | Subtle warm outlines |
| `--brand-green-muted` | `141 50% 90%` | `#D9F1E2` | Soft green chips, money halos |
| `--brand-yellow-muted` | `32 90% 92%` | — | Soft gold chips |
| `--brand-red-muted` | `4 75% 94%` | — | Soft ember chips |
| Service accents | `--accent-{moto,toktok,repas,marche,envoyer,scanner}` | drawn only from green / saffron / ember / graphite | Service tile washes |

### 2.1 · Color usage rules

1. **Emerald = trust & money.** Reserve `--primary` for CTAs, wallet/pay
   surfaces, ride confirmation, and earnings.
2. **Saffron = attention.** Use sparingly — highlights, eyebrows, demand
   pulses, onboarding pacing dots. Never as a primary CTA color.
3. **Ember = risk.** Cancellations, alerts, offline drivers, refund failures.
   Never decorative.
4. **Warm cream over cold white.** Use `bg-background` / `bg-card`. The only
   exception is the admin console (calm slate via `.admin-shell`).
5. **No raw `text-emerald-*`, `bg-rose-*`, `bg-blue-*`, `bg-violet-*`** in
   product surfaces. Use semantic tokens or the `chip-*` classes (§ 9).
6. **Money rule:** wallet/pay surfaces use the lagoon language only —
   `gradient-wallet`, `surface-money`, `tx-halo-in/out`. Never `gradient-cta`
   on a money card.

### 2.2 · Canonical gradients (do not invent new ones)

| Class / token | Use |
|---|---|
| `.gradient-cta` / `--gradient-primary` | Every primary CTA |
| `--gradient-wallet` | CHOPWallet hero only |
| `.gradient-money-deep` | QR scan + receipt headers (deeper money tone) |
| `.surface-warm` / `--gradient-ambient` | Page background washes |
| `.bg-app-conakry` | Onboarding stage, brand theater |
| `--gradient-secondary` | Saffron demand pulse (sparingly) |
| `--gradient-ember` | Live-ops urgency |
| `--gradient-map-overlay` | Map scrim only |

---

## 3 · Typography

Font: **Poppins** (Google Fonts). Fallback `system-ui, sans-serif`.
Mono (admin console & numerics only): `ui-monospace, SFMono-Regular, Menlo`.

| Role | Tailwind | Size / leading | Weight |
|---|---|---|---|
| Display | `text-3xl leading-tight` | 30 / 36 | 700 |
| H1 | `text-2xl leading-tight` | 24 / 32 | 700 |
| H2 | `text-lg leading-snug` | 18 / 24 | 600 |
| H3 / Card title | `text-base leading-snug` | 16 / 22 | 600 |
| Body | `text-sm leading-normal` | 14 / 20 | 400-500 |
| Caption | `text-xs` | 12 / 16 | 400-500 |
| Label / chip | `text-[11px] uppercase tracking-wide` | 11 / 14 | 600 |
| Admin eyebrow | `.admin-eyebrow` (mono, 10px, 0.14em) | — | 500 |

Numerics rule: any numeric column or KPI uses `tabular-nums`.

---

## 4 · Spacing, radius, elevation

**Spacing:** Tailwind 4-px scale. Page padding `px-4`. Section rhythm
`space-y-6` (consumer), `space-y-4` (admin).

**Radius:** base `--radius: 1.25rem`.
- Cards / sheets `rounded-2xl`
- Buttons / chips `rounded-xl`
- Service icons `rounded-xl`
- Mobile sheets `rounded-t-3xl`
- Inputs `rounded-xl`
- Admin cards `rounded-[0.625rem]` (denser)

**Elevation (warm-tinted, never harsh black):**

| Level | Class | Use |
|---|---|---|
| flat | `shadow-flat` | Inline rows |
| elevated | `shadow-card` | Default card |
| floating | `shadow-soft` / `shadow-elevated` | Sheets, sticky headers, FABs |
| island | `shadow-island` | Ride-request island, focus moments |
| money | `shadow-wallet` | CHOPWallet card only |

Never stack two shadows. Never use `shadow-2xl`.

---

## 5 · Iconography rules

### 5.1 · Service icons (CHOP icon family)

Eight services share one authored family:
**Moto · TokTok · Repas · Marché · Envoyer · Scanner · CHOPWallet · CHOPPay**

**Language:** *Kinetic Utility* — rounded geometry, low detail, warm cast,
highly legible at 24–88 px, slight forward motion DNA from the logo. Never
cartoon, never glossy fintech, never emoji, never rainbow gradient. Only
CHOP green / saffron / ember / graphite / cream may appear inside an icon.

- All eight live as PNGs in `src/assets/icons/`.
- Same visual size (square 1:1, equal padding).
- Same perspective (3⁄4 isometric front).
- Same shape language (rounded geometry, soft corners).
- Same motion-streak treatment (kente-tinted speed lines).
- Same shadow/halo system (warm cast under object).
- **No mixing** of emoji, cartoon, outline, or stock-style icons.
- Rendered inside service tiles via `PrimaryActionGrid` — never resized below
  56 px or above 96 px.

### 5.2 · Inline UI icons

- Library: **`lucide-react` only**. No FontAwesome, Material, etc.
- Default size `w-5 h-5` (inline) / `w-6 h-6` (service tile labels) /
  `w-3.5 h-3.5` (admin dense rows).
- Stroke: lucide default (1.5). Admin keeps 1.5 for clarity; consumer hero
  surfaces may bump to 1.75 for warmth.
- Color: `currentColor` only — never hex on an icon.
- Map markers: emerald primary; saffron for hotspots; ember for alerts.
  See `src/lib/maps/markerIcons.ts`.
- **Service-glyph rule:** any surface that *names* a CHOP service (Moto,
  TokTok, Repas, Marché, Envoyer, Scanner, CHOPWallet, CHOPPay) MUST use the
  PNG family — never a Lucide stand-in. Lucide is for utility (chevrons,
  status, ops controls) only.

---

## 6 · Motion rules

**Language:** *Urban Flow* — calm inertia, soft acceleration, minimal bounce,
continuity-first, low-friction transitions. Never gaming springs, never
parallax on small screens, never decorative video.

- **Library:** Framer Motion (consumer) — CSS transitions (admin, low-cost).
- **Single canonical easing:** `var(--ease-flow)` =
  `cubic-bezier(0.22, 1, 0.36, 1)`.
- **Durations:** micro 200 ms · default 300 ms · sheet 350 ms.
- **Tap:** `whileTap={{ scale: 0.985 }}`.
- **Hover (desktop only):** `whileHover={{ scale: 1.015 }}`.
- **Page transitions:** fade-in 200 ms.
- **Sheets:** slide-up 300 ms ease-out.
- **BottomNav active pill:** layout transition `tween` 350 ms (no spring).
- **Driver console:** no scale oscillations; alert state = static
  `border-destructive/50 ring` (no shake).
- **Avoid:** bouncy springs, gaming easings, spinning loaders on
  transactional UI, parallax on small screens, decorative video.
- **Prefer:** directional flow, opacity + subtle translate, restrained scale.
- **Low-data mode:** all animation paths must have a static fallback
  (`useLowDataMode`), and onboarding/map use a `low` branch with no motion.

---

## 7 · Maps (proprietary skin)

Maps must never look like raw Mapbox.

- Wrap every Mapbox container with `.chop-map-skin` and overlay
  `<div class="chop-map-wash" />`.
- Filter applied to canvas: `saturate(0.55) sepia(0.10) contrast(0.96)
  brightness(1.02)` — warm grayscale.
- Heatmap ramp: emerald → mint → saffron → ember (no rainbow, no blue).
- Driver markers: emerald body, saffron arrow indicator, `shadow-island`.
- Hotspots: saffron, never red.
- Controls: card-warm shell, scaled `0.85`, opacity `0.45` until hover.
- Low-data fallback: `.chop-map-fallback` warm city-block gradient with
  "Données réduites" label.

---

## 8 · Money surfaces (CHOPWallet / CHOPPay)

A single visual language across: WalletCard, WalletHero, ChopPaySheet,
ClientTripReceipt, QrScanner, MyQrModal, MerchantQR, transaction rows,
WalletView.

- **Hero**: `gradient-wallet` + `shadow-wallet`.
- **Headers** (scan/receipt): `.gradient-money-deep`.
- **Surfaces**: `.surface-money` for inner content.
- **Transaction halos**: `.tx-halo-in` (lagoon mint) for inflows,
  `.tx-halo-out` (warm sand) for outflows. Failures stay `destructive`.
- **Brand copy** is mandatory:
  - "Portefeuille" → **CHOPWallet** (UI, not legal)
  - "Payer" → **CHOPPay** on payment surfaces
- No neon, no crypto chrome. No dark mode glow on money cards.

---

## 9 · Status chips (single language)

Status across consumer + admin must use the dot-prefix chip family defined
in `index.css` — **never** raw color classes per status.

| Class | Meaning |
|---|---|
| `chip-status chip-ok` | active, online, completed, low-risk |
| `chip-status chip-warn` | pending, open, medium |
| `chip-status chip-info` | investigating, in-approach |
| `chip-status chip-err` | failed, suspended, high, escalated |
| `chip-status chip-mute` | offline, neutral |
| `chip-status chip-violet` | reversed |

Driver presence chip: `chip-ok` (En ligne) / `chip-err` (Hors ligne).
Phase chip in LiveOps: see `PHASE_META` in `LiveOps.tsx` — chips only.

---

## 10 · Component examples

### 10.1 · Primary CTA

```tsx
<button className="h-12 w-full rounded-xl gradient-cta text-primary-foreground
  font-semibold shadow-elevated active:scale-[0.985] transition-transform">
  Confirmer
</button>
```

### 10.2 · Service tile (CHOP icon family)

```tsx
<button className="rounded-2xl bg-card shadow-card p-4 flex flex-col items-start gap-3">
  <img src={motoIcon} alt="" className="h-14 w-14" />
  <div>
    <p className="text-base font-semibold">Moto</p>
    <p className="text-xs text-muted-foreground">Course rapide</p>
  </div>
</button>
```

### 10.3 · Wallet hero

```tsx
<div className="rounded-2xl gradient-wallet shadow-wallet p-5 text-primary-foreground">
  <p className="text-[11px] uppercase tracking-wide opacity-80">CHOPWallet</p>
  <p className="text-3xl font-bold tabular-nums mt-1">{formatGNF(balance)}</p>
  <span className="chip-status chip-ok mt-3">Sécurisé par CHOPPay</span>
</div>
```

### 10.4 · Status row

```tsx
<div className="flex items-center justify-between text-sm">
  <span>Wallet & paiements</span>
  <span className="chip-status chip-ok">ok</span>
</div>
```

### 10.5 · Admin KPI card

```tsx
<div className="admin-card p-3">
  <div className="flex items-center justify-between">
    <span className="admin-eyebrow">Courses du jour</span>
    <ClipboardList className="w-3.5 h-3.5 text-muted-foreground/70" />
  </div>
  <p className="text-[18px] font-semibold mt-1.5 tabular-nums">1 842</p>
  <span className="font-mono text-[10px] text-emerald-700/80">+5.6% · 24h</span>
</div>
```

### 10.6 · Driver dispatch chip (operational, low motion)

```tsx
<button className="h-9 px-3 rounded-xl bg-card shadow-card flex items-center gap-2
  text-[13px] font-medium tabular-nums">
  <span className="h-1.5 w-1.5 rounded-full bg-primary" />
  En ligne · 12 demandes
</button>
```

### 10.7 · Map shell

```tsx
<div className="chop-map-skin relative rounded-2xl overflow-hidden shadow-card">
  <ChopMap />
  <div className="chop-map-wash" />
</div>
```

### 10.8 · Onboarding scene (Conakry theater)

```tsx
<section className="bg-app-conakry min-h-[100dvh] flex flex-col">
  <div className="saffron-seam" />
  <div className="card-warm flex-1 m-4 p-6 flex flex-col items-center justify-center">
    <div className="halo-conakry rounded-full p-6">
      <UtensilsCrossed className="w-10 h-10 text-primary" />
    </div>
    <h2 className="text-2xl font-bold mt-6">Repas à Conakry</h2>
  </div>
</section>
```

---

## 11 · Money formatting

Always via `formatGNF(amount)` from `src/lib/format.ts` →
`2 500 000 GNF` (NBSP separators, suffix). Never inline.

---

## 12 · Versioning & lock

- **Version:** Conakry Contemporary v1.1 (palette re-anchor + icon/motion
  language naming). Behaviour and architecture unchanged from v1.
- **Tag:** `conakry-contemporary-v1` (apply via Lovable's GitHub integration —
  the agent sandbox cannot run `git tag`).
- **Change policy:** every change to color tokens, gradients, motion easings,
  status chips, money surfaces, or icon family **must** update this file in
  the same commit and bump the minor version (`v1.x`).
- **Audit:** see `AUDIT.md` for screen-by-screen conformance, and
  `icon-inventory.md` for the service icon family roster.
