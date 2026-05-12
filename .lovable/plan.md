Your message is essentially the full product spec for CHOP CHOP. It's far too much to ship in a single iteration without losing quality, so I'm proposing a phased plan. Each phase ends with a working, testable app. Confirm or tell me which phase to start with (or to reorder).

# Phase 0 — Foundations (small, do first)
- Tighten the design system (semantic tokens, soft cards, large tap targets, calmer spacing) so every new screen inherits the right "Google-for-West-Africa" feel.
- Add a global `ServiceAccent` token map (Moto=green/yellow, TokTok=yellow/green, Repas=red/warm, Marché=green, Envoyer=yellow/black, Scanner=black/green) used by all service screens.
- Bottom nav restructure: `Accueil · Activité · Scanner (center, elevated) · Portefeuille · Compte`.

# Phase 1 — Home screen rebuild
- Header (menu, compact logo, notifications, avatar shortcut).
- Greeting block ("Bonjour, {prénom} 👋 Prêt à vous déplacer ?").
- Wallet card with `Recharger / Envoyer / Historique`.
- Universal search ("Où allez-vous ? Que voulez-vous faire ?").
- Services grid: Moto, TokTok, Repas, Marché, Envoyer, Scanner.
- Promo/recommendation cards.
- Recent activity (Maison, Travail, last order, last parcel).

# Phase 2 — Moto (extend existing RideBooking)
- Landmark assist field ("près de la station Total…").
- Ride tier cards: Standard / Plus / Nuit with ETA, fare range, description.
- Payment selector (Cash default, Wallet, Promo).
- Matching → Driver found (photo, plate, call, WhatsApp) → Tracking (share trip, emergency) → Completion (rating, tip, report).

# Phase 3 — TokTok
- New service screen mirroring Moto but with: purpose selector (Me déplacer / Courses / Petit chargement / Famille), load + volume + passenger count, fare range, driver screen.

# Phase 4 — Repas
- Browse: search, category chips, featured vendors, "Cuisine locale près de vous".
- Restaurant page, dish customization (quantité, piment, sauce, instructions), cart, checkout, order tracking timeline with friendly copy.

# Phase 5 — Marché
- Categories + featured bundles (Pack Cuisine / Famille / Semaine / Étudiant).
- Product cards with unit + estimated price ranges, quantity selector.
- Substitution preferences, delivery windows, shopper tracking + chat.

# Phase 6 — Envoyer
- Pickup + drop-off forms with landmark + recipient.
- Package type/size/value, speed (Standard/Express/Programmé).
- Delivery code as proof, tracking timeline, "Envoyer pour mon commerce" stub.

# Phase 7 — Scanner
- Camera scanner (QR) with manual code entry + flash.
- Action handlers: payment, driver verification, promo, delivery confirmation. Always confirm before pay.

# Phase 8 — Wallet, Activity, Support, Profile
- Wallet: balance card, top-up flows (agent / driver cash / promo), transaction history with statuses.
- Activité tabs: En cours / Passé / Annulé with reorder + help.
- Aide center with WhatsApp + call + in-app form, emergency button on active trips.
- Profil: saved addresses with landmark + instructions, payment methods, language, become a driver, business account.

# Phase 9 — Driver/Courier mode polish
- Per-service flows (Moto, Envoyer, Repas, Marché shopper).
- Earnings (today / semaine / cash collected / commission).
- Verification + safety badges.

# Phase 10 — Admin console with 3 tiers
Roles (DB enum `app_role`): `super_admin`, `ops_admin`, `support_admin`.
- `super_admin`: everything (manage admins, fares, financial settings, ban/unban, refunds any amount, feature flags).
- `ops_admin`: fares, promos, bonuses, driver verification/ban, dispatch overrides, refunds up to a cap.
- `support_admin`: investigate orders/users, issue small promos/credits, escalate to ops/super, view logs only.

Admin screens:
1. Dashboard — KPIs (rides today, GMV, active drivers, open incidents).
2. Investigations — search any order/user/driver, full timeline, attached messages, escalate.
3. Drivers — verify, suspend, ban, reinstate, view earnings + complaints.
4. Users — view, credit, suspend, reset.
5. Fares — current `fare_settings` editor (already exists), plus surge windows.
6. Promos & Bonuses — create codes, target audiences, expiry, budget caps.
7. Refunds & Wallet adjustments — with role-based caps + audit log.
8. Audit log — every admin action recorded with actor, target, before/after.

Backing tables (added in one migration when we reach Phase 10): `admin_actions`, `promos`, `bonuses`, `driver_status`, `investigations`, with RLS keyed off `has_role(auth.uid(), …)` and a new `has_min_role()` security-definer helper.

# Technical notes (for the developer)
- Keep all colors as HSL semantic tokens; add `--accent-moto`, `--accent-toktok`, `--accent-repas`, `--accent-marche`, `--accent-envoyer`, `--accent-scanner`.
- Reuse Leaflet + Nominatim + OSRM patterns already in `RideBooking.tsx` for TokTok and Envoyer.
- Scanner uses `@zxing/browser` (small, no native deps).
- All admin mutations go through SECURITY DEFINER RPCs that check `has_min_role()` and write to `admin_actions`.
- French microcopy exactly as specified; avoid jargon.

# What I need from you
Pick one:
- **A. Ship in order, Phases 0→10** (recommended; ~10 iterations).
- **B. Start with a specific phase** (tell me which).
- **C. Compress: ship Phase 0 + 1 + 10 first** (visual reset, new home, admin tiers) and then fill services.