# CHOP CHOP — Plan de refonte global (A→M)

Cette demande couvre ~300 items répartis en 13 chapitres (A→M) touchant design system, refactor, nouvelles pages, wallet, ride, marché, repas, scanner, profil, auth, notifications. C'est l'équivalent de plusieurs sprints. Je propose de la livrer en **6 phases séquentielles** approuvables une à une, plutôt que tout en bloc (risque de régression massif et impossible à QA).

## Phase 0 — Audit (lecture seule, ce message)
Livrable : `AUDIT.md` à la racine résumant :
- Stack (React 18 + Vite + TS + Tailwind + shadcn + Supabase/Lovable Cloud)
- Routes (`/`, `/auth`, `/admin`, `/agent`, `/agent/topup`, `/profile`, `/help`, `/legal`)
- Composants existants par domaine (home, marche, food, ride, wallet, driver, scanner)
- Tokens actuels dans `index.css` + `tailwind.config.ts`
- Tables Supabase + RLS (déjà connues)
- Top 20 problèmes visuels observés (chapitre B item 1)

## Phase 1 — Design system foundation (chapitre A)
- `PROJECT_RULES.md`, `DESIGN_SYSTEM.md`
- Tokens couleurs CHOP CHOP (vert/jaune/rouge + variantes muted) dans `index.css`
- Échelle d'espacement, radius, shadows, typo Poppins normalisés
- Audit + remplacement des couleurs hardcodées (`text-white`, `bg-black`, hex bruts)
- Primitives réutilisables : `AppShell`, `PageHeader`, `ActionButton`, `PrimaryButton`, `SecondaryButton`, `SearchBar`, `EmptyState`, `LoadingState`, `ErrorState`, `StatusTimeline` (les autres — `BottomNav`, `ServiceCard`, `WalletCard`, `ListingCard`, `RestaurantCard` — existent déjà, je les normalise sur les nouveaux tokens)

## Phase 2 — Polish visuel global (chapitre B + C + D)
- Home : header, greeting, wallet preview, search, services, recents, offers, restaurants
- Skeletons + empty states
- Drawer latéral redesigné avec slogan exact "Tout. Partout. Pour Tous."
- Format GNF unifié `2 500 000 GNF`
- BottomNav polish + bouton scanner central
- Padding bas global pour ne plus masquer le contenu

## Phase 3 — Wallet + Driver (chapitres E + F)
- Wallet : toggle visibilité solde, PIN 6 chiffres, actions Envoyer/Recevoir/QR/Recharger, page recharge agent + Orange Money "Bientôt", références `CC-RC-000001`, alerte solde bas
- Driver : Tableau chauffeur, états Hors ligne / En ligne / Recherche, stats normalisées, ride-request bottom sheet avec timer, pages earnings detail + trip history

## Phase 4 — Services transport + repas (chapitres G + H)
- Moto + TokTok : map+sheet responsive, repère utile, estimation tarif, sélecteur paiement, écrans confirmation/assigné/en cours/terminé/annulation
- Repas : restaurant detail, menu, panier, checkout, tracking timeline, états closed/unavailable

## Phase 5 — Marché + Scanner (chapitres I + J)
- Marché : badges (Vérifié, Livraison CC, Négociable, Urgent), filtres+tri, saved listings, chat acheteur-vendeur avec quick replies, signalement, flow livraison + code de confirmation
- Scanner : page dédiée avec frame QR, saisie manuelle, écrans success/error pour paiement, top-up, livraison, vérification chauffeur

## Phase 6 — Profil + Auth + Notifications (chapitres K + L + M)
- Profil refondu (téléphone-first, adresses, langue, sécurité, danger zone, applications driver/merchant)
- Auth : `+224` phone-first, OTP screen + timer (NB : actuellement auto-confirm activé sur ta demande précédente — l'OTP UI sera en mock jusqu'à activation Twilio/SMS provider)
- Onboarding 4 slides + permissions
- `notifications.ts` + `sms.ts` (templates centralisés), notification center, mock SMS adapter, table de log

## Détails techniques
- Tous les nouveaux composants utilisent uniquement les tokens HSL semantic (jamais `text-white` direct)
- Pas de migration DB en Phase 0–2 ; les phases 3–6 ajouteront migrations ciblées (notifications, addresses, sms_logs) au cas par cas, chacune approuvée séparément
- Aucun composant fonctionnel existant n'est cassé : on ajoute des primitives à côté puis on migre les écrans progressivement

## Question avant de démarrer
Je commence par **Phase 0 (audit lecture seule, livre `AUDIT.md`)** maintenant, puis tu valides phase par phase ? Ou tu veux que j'enchaîne automatiquement Phase 0 → Phase 1 sans pause ?
