# CHOPCHOP — App Store / Google Play Readiness Plan

CHOPCHOP remains web/PWA-first for fast iteration. The store path is a
thin native wrapper around the existing web build, used to gain
credibility, distribution, and native permission prompts in Guinea.

## 1. Wrapper strategy

- **Recommended wrapper:** Capacitor (Ionic).
- The wrapper bundles a built copy of the web app for App Store / Play
  submission; production runtime can either load bundled assets or be
  pointed at `https://chopchopguinee.com` once the published build is
  stable. Bundled assets are required for store review.
- Keep all business logic in the existing React/Vite/Supabase codebase.
  The wrapper is shell only.
- Use native icon, splash, and permission prompts; nothing else needs
  to change at app level.

## 2. Sequencing

1. **Android (Google Play closed test)** — fastest review, large Guinea
   audience, easier iteration during pilot.
2. **iOS TestFlight** — internal + external testers for App Store
   pre-flight.
3. **App Store public listing** — after pilot polish, real wallet
   provider live (or wallet clearly marked "pilot manuel"), and
   moderation rules in place.
4. **Google Play public listing** — graduate from closed → open test →
   production.

## 3. Required assets

- App icon (1024×1024, no transparency, no rounded corners baked in).
- Adaptive icon foreground/background for Android.
- Splash screen image set (light + dark).
- Feature graphic for Play (1024×500).
- Screenshots: see `STORE_SCREENSHOT_CHECKLIST.md`.
- App store metadata: see `CHOPCHOP_STORE_LISTING_DRAFT.md`.
- Privacy/data-safety form answers: see
  `../legal/STORE_DISCLOSURE_CHECKLIST.md`.

## 4. Legal / compliance

- `/terms`, `/privacy`, `/permissions`, `/help` reachable from the
  store listing AND inside the app (already in place).
- Account deletion entry point inside the app (Profil → "Demander la
  suppression du compte"). Required by both stores.
- Permission usage strings in `Info.plist` / Android manifest — see
  `CHOPCHOP_STORE_LISTING_DRAFT.md` § "Native permission copy".
- No App Tracking Transparency prompt needed at launch (no
  cross-app/cross-site tracking, no IDFA).
- No third-party ads at launch.

## 5. Known blockers before submission

| Area | Blocker | Status |
|---|---|---|
| Account deletion | In-app request flow | ✅ Implemented (`AccountDeletionRequestSheet`) |
| Debug UI | Orange Bug button + sandbox panels must be hidden in prod | ✅ Gated to `isSandboxMode()` / `?sandbox=1` / dev |
| Wallet/payments | Live provider not yet active in production | Mark as "pilot manuel" in store description until live |
| Marketplace moderation | Self-promo / illegal goods rules | Pending — see § 7 |
| Push notifications | Native push wiring | Pending (Capacitor `@capacitor/push-notifications`) |
| Camera / QR | Native fallback when web camera fails inside wrapper | Verify during TestFlight |
| Splash screen | Native splash matching CHOPCHOP brand | Pending |
| App icon | Final 1024 master icon | Pending |
| Service worker | Disable inside Capacitor wrapper (already PWA-safe in browser) | Verified — service worker is guarded against iframes / preview hosts |

## 6. TestFlight / closed-testing path

- iOS: TestFlight internal group (CHOP team) → external testers
  (selected drivers, merchants, support, pilot customers).
- Android: Play internal testing track → closed test (~20 testers) →
  open test → production. Internal testing tolerates daily uploads.
- Crash reports: rely on store-native crash reporting initially; do not
  add third-party SDKs for pilot.

## 7. Marketplace moderation

- Block seller self-promotion in listings titles/descriptions.
- Block contraband, weapons, alcohol/tobacco where regulated, illegal
  wildlife, counterfeit goods.
- Provide a "Signaler" entry on every listing (already supported via
  `support_issues`).
- Admin review queue: `MarcheAdmin` + `VendorsAdmin`.

## 8. Submission sequence (recommended)

1. Lock current web build as v1.0.0 production candidate.
2. Run full QA pass: onboarding, ride, repas, marché, wallet, tracking,
   support, driver mode, account deletion request.
3. Generate final screenshots from prod build (see screenshot checklist).
4. Initialize Capacitor wrapper, point to bundled web assets.
5. Configure native permission strings, splash, icon.
6. Build signed `.aab` (Android) → Play Internal Testing.
7. Build signed `.ipa` (iOS) → TestFlight Internal.
8. Iterate based on reviewer feedback, then move to closed test /
   external test.
9. Submit for public release.

## 9. Risks

- **App Store rejection** if wallet copy reads as a live payment
  service before provider integration is real. Mitigation: ship with
  "pilot manuel" / "bientôt disponible" language until live.
- **Play rejection** for in-app reporting if marketplace lacks a
  moderation pathway. Mitigation: keep "Signaler" + admin review.
- **Service-worker collisions** inside Capacitor WebView. Mitigation:
  detect Capacitor context and skip SW registration in the wrapper.