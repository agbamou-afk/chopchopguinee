# CHOPCHOP Permissions & Consent

## Versioning

Legal versions are centralized in `src/lib/legal.ts`:

- `TERMS_VERSION`
- `PRIVACY_VERSION`
- `LEGAL_LAST_UPDATED`

Bumping either version causes the global `LegalAcceptanceModal` to
re-prompt logged-in users when they next touch a sensitive surface.

## Data Model

- `user_legal_consents` — append-only log. One row per acceptance.
- `user_preferences` — current value of CHOPCHOP-managed toggles
  (`allow_urban_insights`, `allow_marketing_notifications`,
  `allow_personalized_offers`).

## Gate Behavior

- **Logged out**: never prompted. Public marketing/onboarding screens
  remain accessible.
- **Logged in, accepted current versions**: no prompt.
- **Logged in, missing current versions, on a sensitive route**: blocking
  modal until accepted. Sensitive routes are defined in
  `SENSITIVE_ROUTE_PREFIXES` (`useLegalConsentGate.ts`): `/wallet`,
  `/ride`, `/repas/checkout`, `/marche/checkout`, `/driver`, `/merchant`,
  `/support/new`, `/agent`.
- **Logged in, missing versions, on a non-sensitive route**: no prompt.

Read flow is fail-open: while the check is loading or on error, the UI is
not blocked. Acceptance write is fail-closed (errors surface a toast).

## Signup

`/auth` signup requires a checkbox accepting both documents. The accepted
versions are passed via `options.data` and a `user_legal_consents` row is
inserted via `recordLegalAcceptance({ source: "signup" })` after the
session is established.

## Permission Center

`/settings/permissions` is the user-facing surface. It separates:

1. **Device permissions** (browser/OS): location, notifications, camera.
   These cannot be flipped from JS — we show current status and a CTA
   that triggers the browser prompt or deep-links to OS settings.
2. **CHOPCHOP preferences**: persisted in `user_preferences`. Defaults:
   - `allow_urban_insights = true` (operational improvement)
   - `allow_marketing_notifications = false`
   - `allow_personalized_offers = false`

## What We Do *Not* Do

- No App Tracking Transparency (no IDFA/AAID access).
- No third-party ad SDKs.
- No background location.
- No contact-list upload.
- No microphone access at launch.