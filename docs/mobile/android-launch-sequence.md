# CHOPCHOP — Android Launch Sequence

Status: audit output. Executes AFTER `capacitor-readiness-audit-stable`
is locked. Every phase below has a single lock candidate. No phase runs
in parallel with the next.

Recommended app IDs:
- Consumer super-app: `com.chopchopguinee.app`
- Reserved driver app: `com.chopchopguinee.driver` (v2)

## Phase 1 — capacitor-foundation-stable
Deliver:
- `bun add @capacitor/core @capacitor/cli`
- `capacitor.config.ts` with `appId: com.chopchopguinee.app`,
  `appName: CHOPCHOP`, `webDir: dist`, **no `server.url` in prod**.
- Extend `src/lib/pwa/registerPwa.ts` guard to detect Capacitor
  (`window.Capacitor?.isNativePlatform?.()`) and unregister any
  pre-existing SW.
- Add `src/lib/runtime/native.ts` → `isNativeShell()`.
- Introduce `package.json` `version` (semver) + CI-derived
  `versionCode`.
- Gate `InstallPrompt`, `beforeinstallprompt`, and any web-only
  affordance behind `!isNativeShell()`.

Exit: `bun run build` clean, PWA still registers on web, no SW
registration in a mocked Capacitor context.

## Phase 2 — capacitor-android-shell-stable
Deliver:
- `bun add @capacitor/android` + `@capacitor/app @capacitor/status-bar
  @capacitor/splash-screen @capacitor/keyboard @capacitor/network
  @capacitor/device @capacitor/preferences @capacitor/browser`.
- `npx cap add android` (executed by user locally per Lovable
  Capacitor guidance — Lovable sandbox never adds native platforms).
- Configure status bar (`#118338`), splash, portrait lock.
- Global back-button handler that closes open Radix/vaul sheets first.
- Safe-area audit on Pixel 5 + small-screen Android.

Exit: dev build on a physical Android device via `npx cap run android`.

## Phase 3 — android-native-services-production-stable
Deliver:
- Wrap geolocation, camera+filesystem, network, in-app browser behind
  the abstraction modules from the matrix.
- Replace web camera path in merchant listings + OM proof upload when
  `isNativeShell()`.
- Route external links through `@capacitor/browser`.

Exit: photo capture + geolocation + external links work natively;
existing web flows untouched.

## Phase 4 — android-push-production-stable
Deliver:
- Migration: `device_tokens` table (RLS `auth.uid()`-scoped) +
  `upsert_device_token`, `disable_device_token` RPCs.
- Edge function `push-send` (FCM v1 HTTP with service account).
- Server triggers on ride/mission/order/topup/cashout/support state to
  enqueue push jobs.
- Native registration via `@capacitor/push-notifications`.
- Central deep-link router in `src/lib/native/push.ts`.
- Android 13+ notification permission rationale sheet.

Exit: end-to-end push from ride status change → notification →
correct in-app deep link.

## Phase 5 — android-driver-location-production-stable
Deliver:
- Introduce `driverLocationTransport` seam.
- Persistent in-app "En ligne" banner while driver is online.
- Auto-offline on `appStateChange=background` after N minutes.
- No `ACCESS_BACKGROUND_LOCATION` in consumer app.

Exit: driver online session survives 30 min in foreground; offlines
cleanly on background.

## Phase 6 — android-play-readiness-stable
Deliver:
- Public `/account-deletion` landing page (URL for Play form).
- Location + camera + notification rationale strings centralized.
- Data Safety inventory (repo review of everything leaving the device).
- Review demo account scripts (client + merchant + driver).
- OM physical-services listing paragraph.

Exit: internal-test AAB uploaded, form filled, no policy warnings.

## Phase 7 — play-closed-pilot-stable
Internal → closed track with real pilot testers. Crash + ANR triage
via Play Console. Feature flags gate risky paths.

## Phase 8 — play-store-launch-stable
Production release. Rollout at 10% → 50% → 100%.

## Phase 9 — android-pilot-stabilization-stable
Post-launch: crash rate, ANR rate, OM checkout success rate, driver
online-session duration, push delivery rate.

## Phase 10 — capacitor-ios-shell-stable
Reuse Phase 1-5 abstractions. Add `@capacitor/ios`, iOS-specific
splash / status bar / permission strings.

## Phase 11 — ios-testflight-readiness-stable
Internal + external TestFlight groups.

## Phase 12 — ios-app-store-launch-stable
App Store submission, staged rollout.
