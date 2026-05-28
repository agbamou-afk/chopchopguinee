# CHOPCHOP Permissions, Consent, Terms & Ads-readiness Foundation

A foundation pass for pilot launch. No ads UI is added, no ATT prompt, no tracking. Existing auth/onboarding/payments/wallet/dispatch/maps/admin flows are untouched except where explicitly listed.

## 1. Database (single migration, requires your approval)

Two new tables in `public`:

**`user_legal_consents`** — append-only consent log
- `user_id`, `terms_version`, `privacy_version`, `accepted_terms`, `accepted_privacy`, `accepted_at`, `ip_address` (nullable), `user_agent` (nullable), `source` (default `signup`)
- RLS: user can `INSERT`/`SELECT` own rows; no `UPDATE`/`DELETE` for users; `service_role` full; admins read via existing `has_role` check
- GRANTs: `authenticated` (SELECT/INSERT), `service_role` (ALL)
- Index on `(user_id, accepted_at desc)`

**`user_preferences`** — CHOPCHOP app-level preferences (distinct from device permissions)
- `user_id` (unique), `allow_urban_insights bool default true`, `allow_marketing_notifications bool default false`, `allow_personalized_offers bool default false`, `updated_at`
- RLS: user can `SELECT`/`INSERT`/`UPDATE` own row; `service_role` full
- GRANTs: `authenticated` (SELECT/INSERT/UPDATE), `service_role` (ALL)
- `updated_at` trigger

## 2. Legal version constants

**`src/lib/legal.ts`** — single source of truth.
```
TERMS_VERSION = "2026-05-27-v1"
PRIVACY_VERSION = "2026-05-27-v1"
LEGAL_LAST_UPDATED = "2026-05-27"
```
Plus helpers: `hasAcceptedCurrentLegal(userId)`, `recordLegalAcceptance({ source })`.

## 3. Pages

- **`/terms`** — `src/pages/Terms.tsx`. French-first content following the 22-section structure from the spec, with the draft notice ("These terms are a launch draft and should be reviewed by counsel before broad public launch.") and version line. SEO meta.
- **`/privacy`** — `src/pages/Privacy.tsx`. French-first privacy policy covering account data, location, ride/order/wallet/support/merchant data, device data, notifications, camera, aggregated urban intelligence, service providers, no third-party ad tracking at launch, `support@chopchopguinee.com`.
- **`/settings/permissions`** — `src/pages/PermissionCenter.tsx`. Two sections:
  1. **Permissions appareil** (Localisation, Notifications, Caméra, Photos/Documents) — live status via `navigator.permissions` where available, "Activer" / "Gérer dans les réglages" CTAs, French copy from spec.
  2. **Préférences CHOPCHOP** (Données urbaines agrégées, Notifications marketing, Offres personnalisées, Publicité & personnalisation [info-only: "CHOPCHOP n'utilise pas le suivi publicitaire inter-apps pour le moment."]) — bound to `user_preferences`.

Routes added in `src/App.tsx`.

## 4. Signup acceptance

**`src/pages/Auth.tsx`** — add required checkbox on signup form only (not login):
```
[ ] J'accepte les Conditions d'utilisation et la Politique de confidentialité.
```
Submit disabled until checked. On successful signup, write a `user_legal_consents` row with current versions, `source: "signup"`, best-effort `user_agent`. Failure to write is logged but doesn't block account creation (retry on next session via `useLegalConsentGate`).

## 5. Existing-user gate (no chaos)

**`src/hooks/useLegalConsentGate.ts`** — checks for a consent row matching current versions. If missing, exposes `needsAcceptance: true` and a `accept()` action.

**`src/components/legal/LegalAcceptanceModal.tsx`** — gentle one-time modal with the spec copy ("Nous avons mis à jour les Conditions d'utilisation…"), links to /terms and /privacy, single "J'accepte" button. Mounted at app shell level but only renders when `needsAcceptance` is true **and** the route is a sensitive surface (booking, wallet, driver mode, merchant actions, Repas order, Marché delivery, support issue creation). Public/home/onboarding/auth routes are NOT gated.

## 6. Profile / Settings integration

Add a "Légal & confidentialité" group in the existing Profile screen with rows:
- Conditions d'utilisation → `/terms`
- Politique de confidentialité → `/privacy`
- Permissions & préférences → `/settings/permissions`

## 7. Documentation

- **`docs/ads/CHOPCHOP_ADS_PIPELINE.md`** — future-ready, inactive. Lists Sponsored Restaurants, Marché listings, Featured Merchants, Chop Deals, Sponsored Delivery Promotions, Brand Partnership Banners. Rules: "Sponsorisé" label, no third-party networks, first-party only, no hidden tracking.
- **`docs/legal/STORE_DISCLOSURE_CHECKLIST.md`** — data categories, purposes, tracking statement (no third-party cross-app tracking, no IDFA, no ATT needed), data sharing (service providers + operational counterparties only, no sale).
- **`docs/legal/PERMISSIONS_AND_CONSENT.md`** — internal map of which surface triggers which prompt, where consent is recorded, and how the gate works.

## 8. Explicitly NOT in this pass

- No ad UI, no ad tables.
- No ATT prompt.
- No microphone/contacts requests.
- No changes to existing location prompts (the previous live-location pass already handles that).
- No admin legal dashboard (TODO noted in `docs/legal/PERMISSIONS_AND_CONSENT.md`).
- No re-consent enforcement on login for existing users beyond the sensitive-action gate.
- No changes to dispatch/payment/wallet/maps logic.

## Execution order

1. Run the migration (asks for your approval).
2. After migration is applied and types regenerate, write all code + docs in one pass.
3. Smoke: build is clean, /terms and /privacy load, signup checkbox blocks submit when unchecked, no ATT prompt, permission center renders both sections, profile links work.

## Open questions

If any of the following are wrong I'll adjust before step 1:
- Default for `allow_urban_insights`: **ON** (operational improvement) vs **OFF** (conservative). I propose ON. Confirm or override.
- Sensitive-action gate scope: I'll trigger the modal on `/wallet`, `/ride/*`, `/repas/checkout`, `/marche/checkout`, `/driver/*`, `/merchant/*`, support issue creation, and wallet top-up. Confirm or trim.
- Existing `/legal` route (if any) — I'll link rather than replace, and add `/terms` + `/privacy` as new routes. Will confirm by reading `src/App.tsx` before writing.
