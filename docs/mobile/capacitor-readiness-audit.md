# Capacitor Readiness Audit — CHOPCHOP

Status: AUDIT ONLY — no production code, dependency, or config changes.
Lock candidate: `capacitor-readiness-audit-stable`
Target: Android first (Google Play), iOS after Android pilot.
Recommended app IDs:
- Client super-app: `com.chopchopguinee.app`
- Reserved future driver-only app: `com.chopchopguinee.driver`
Runtime architecture: **bundled Vite assets** in the native wrapper,
talking to Supabase / edge functions over HTTPS. No `server.url`
remote-wrapper in production.

## A. Executive summary
CHOPCHOP is architecturally close to Capacitor-ready. Single React/Vite
SPA, BrowserRouter, Supabase JS with localStorage session, PWA guarded
off in preview/iframe. Public wallet archived behind
`wallet_public_enabled=false`; Orange Money rail is server-authoritative
(no client-side payment success is possible). Maps have a
`DegradedMapPanel` + straight-line fallback already shipped.

Three engineering areas need work before a Play build:
1. Driver background location — current model is foreground-tab only;
   Play requires foreground-service + background-location disclosure to
   ship background tracking, or we split the driver app.
2. Service worker must be disabled in the Capacitor build to avoid
   colliding with the WebView asset pipeline.
3. Push notifications — no device-token model exists; Android v1 push
   requires token table, FCM sender, and deep-link routing.

No RED prevents starting `capacitor-foundation-stable`.

## B. Build foundation findings
| Item | Finding |
|---|---|
| Build command | `vite build` → `dist/` |
| Capacitor `webDir` | `dist` |
| Env vars | Only `VITE_SUPABASE_URL` + `VITE_SUPABASE_PUBLISHABLE_KEY`; both publishable, safe to bundle |
| Env separation | No `--mode staging` variant; add before closed pilot |
| PWA plugin | `vite-plugin-pwa` with `injectRegister: false`, guarded by `src/lib/pwa/registerPwa.ts` — must also treat Capacitor as a no-register host |
| Versioning | `package.json` version is `0.0.0`; need semver + CI-driven `versionCode` |
| Risky deps | Both `mapbox-gl` and MapLibre/Leaflet ship — audit for dead code (APK size); `html5-qrcode` uses `getUserMedia` |

## C. Routing / deep-link findings
BrowserRouter is native-safe. Deep links need `@capacitor/app`
`appUrlOpen` forwarded to React Router.

| Route | Classification |
|---|---|
| `/` | native-safe |
| `/auth`, `/auth/*`, `/~oauth`, `/auth/callback` | deep-link handling (Android App Link on `chopchopguinee.com`) |
| `/complete-profile`, `/confirm-profile` | native-safe |
| `/help`, `/help/issues`, `/legal`, `/privacy`, `/terms`, `/permissions`, `/unsubscribe` | native-safe (Play requires reachable) |
| `/wallet` (archived panel) | native-safe |
| OM proof / payment resume screens | back-button handling (confirm before pop) |
| `/admin`, `/admin/*`, `/admin/change-password` | admin-only, not exposed in native BottomNav (still reachable by URL) |
| `/field/*` | staff-only |
| `*` | native-safe |

Back-button today: none registered globally. Native shell needs
`App.addListener('backButton', …)` that respects open sheets/dialogs
before popping history and exits app only on root.

## D. Auth / session findings
- `src/integrations/supabase/client.ts` uses `localStorage`,
  `persistSession: true`, `autoRefreshToken: true` — works in WebView.
- Password recovery, email confirmation, and staff temp-password
  enforcement (`AdminGuard` → `/admin/change-password`) rely on Supabase
  deep links; App Links must be configured on the published domain.
- Splash race: `App.tsx` renders `SplashScreen` behind `AuthProvider`;
  hide the native splash on first React paint via
  `@capacitor/splash-screen`.
- Logout: `supabase.auth.signOut()` is sufficient inside WebView.
- Secure native storage: **not required for v1**. Session tokens are
  refresh JWTs, not long-lived secrets; localStorage in an app-scoped
  WebView is Play-acceptable. Plan `@capacitor/preferences` only if we
  later add offline signed operations or a payout PIN.

## E. Browser API inventory (highlights)
Ripgrep matched 177 occurrences across 64 files. Selected mapping:

| API | Representative files | Purpose | WebView behavior | Plugin | v1 priority |
|---|---|---|---|---|---|
| `navigator.geolocation` | `src/lib/location/useLiveUserLocation.ts`, `src/hooks/useGeolocation.ts`, `src/components/merchant/StoreLocationPicker.tsx` | user/merchant/driver location | Works with runtime permission | `@capacitor/geolocation` | HIGH |
| `navigator.onLine` | `src/lib/maps/connectivity.ts`, `src/hooks/useConnectionRestored.ts` | degraded map / reconnect | Works | `@capacitor/network` | MED |
| `serviceWorker` | `src/lib/pwa/registerPwa.ts` | PWA | Must be disabled in native | none | HIGH |
| `beforeinstallprompt` | `src/components/system/InstallPrompt.tsx` | web install banner | Never fires; guard behind `!isNative` | none | LOW |
| `window.open` | `src/lib/maps/external.ts`, admin exports | external links | Opens in WebView by default; use in-app browser | `@capacitor/browser` | MED |
| localStorage | auth, wallet cache, feature flags | session/prefs | Works | none | HIGH (no change) |
| `document.visibilityState` | polling hooks | pause background polling | Works | none | reuse |
| File / image upload | merchant listings, `RepasProfileSection`, OM proof | photos → storage | `<input type=file capture>` works; native picker preferred | `@capacitor/camera` + `@capacitor/filesystem` | HIGH |
| Camera / QR | `html5-qrcode` (QR scanners) | merchant QR, agent flow | OEM-dependent in WebView | `@capacitor-community/barcode-scanner` (fallback) | MED |
| `Notification` API | none | — | not used | `@capacitor/push-notifications` (FCM) | HIGH |
| Audio playback | `src/lib/sound/driverSounds.ts` | driver offer sound | Works; autoplay policy | none | LOW |
| Clipboard | `AdminsAdmin.tsx` (staff temp password) | copy creds | `navigator.clipboard` works | `@capacitor/clipboard` (fallback) | LOW |
| download/blob | admin CSV exports | admin only | Works | admin-only |

## F. Native capability matrix summary
See `native-capability-matrix.md`. Android v1 plugins: App, Status Bar,
Splash Screen, Keyboard, Network, Geolocation, Camera, Filesystem, Push
Notifications, Browser, Device, Preferences (+ Haptics/Share/Clipboard
optional).

## G. Driver location findings (critical)
Reviewed: `src/hooks/useDriverLocationSignal.ts`,
`src/hooks/useDriverPresence.ts`, `src/lib/maps/useDriverLocation.ts`,
`src/contexts/DriverSessionContext.tsx`.

Current behavior:
- Publish only while driver tab is foreground; screen-lock / background
  stops updates.
- Cleanup on `signOut`, `setStatus('offline')`, hook unmount.
- Cadence adapts to `saveData` / 2G.

Native risk:
- Play requires foreground-service + `ACCESS_BACKGROUND_LOCATION`
  disclosure + Data Safety declaration + demo video for any app that
  reads location while backgrounded.
- A unified super-app with background driver tracking invites
  rejection.

Recommendation:
- **Android v1**: keep foreground-only. Add persistent in-app banner
  when driver is online. No `ACCESS_BACKGROUND_LOCATION`.
- **Android v2**: reserve `com.chopchopguinee.driver` and ship
  background tracking there so the consumer app avoids the disclosure.
- Add now (no behavior change): route all driver location start/stop
  through a single `driverLocationTransport` module so the driver-only
  app can swap in a native foreground-service implementation.

## H. Push readiness findings
- No `device_tokens` table. No FCM sender. Notifications today are DB
  rows read by in-app hooks (`useCustomerMissionAlerts`,
  `useTopupNotifications`, etc.).

Reusable: `notifications` table + notifier helpers; server triggers on
ride/mission/order/topup/cashout/support state.

Missing for v1:
- `device_tokens(user_id, platform, token, app_version, last_seen_at)`
  with RLS.
- Edge function `push-send` (FCM v1 HTTP).
- Deep-link map: ride status → `/`, mission → `/`, OM outcome →
  `/wallet`, support reply → `/help/issues`, cashout status → driver
  earnings.

Min v1 events: new ride offer (driver), ride status (client), new food
order (restaurant), order status (client), mission handoff (courier),
Marché new message, OM top-up/payment verified or rejected, cashout
paid/rejected, support reply.

## I. Orange Money native-risk findings
No payment logic changed. Risks in a WebView shell:

| Risk | Planned mitigation |
|---|---|
| WebView reload / process death mid-checkout | Persist `payment_intent_id` in localStorage + show "Reprendre le paiement" banner on cold start; server is authoritative |
| Deep link from support email opens fresh WebView with no session | App Link → `/auth/callback?next=/payments/<id>`; resume after session hydrate |
| Proof image capture | Route through `@capacitor/camera` in native; keep `<input type=file>` in web |
| Polling drains battery when backgrounded | Pause on `visibilityState=hidden` + `@capacitor/app` `appStateChange`; refresh on resume |
| Back button cancels intent unexpectedly | Intercept `backButton` on OM proof screens, require confirm |

Hard invariant preserved: no payment can succeed client-side; all
authorization goes through `om_payment_authorize` server RPC.

## J. Maps / offline findings
- MapLibre GL / Leaflet in WebView is acceptable for v1 on Android 10+.
- `DegradedMapPanel` + `StraightLineFallback` already ship.
- `src/lib/maps/clientCache.ts` TTL memory cache — good.
- MapTiler / OSM keys stay server-issued via
  `supabase/functions/maps-config`.
- No tile predownload in v1.

## K. Mobile UI / safe-area findings
- `index.html` sets `viewport-fit=cover`.
- BottomNav needs `env(safe-area-inset-bottom)` verified on Android
  gesture-nav (spot-check in shell phase).
- `vaul` bottom sheets: verify Android keyboard `resize` behavior.
- Confirm `useHasNotch` uses `env()` not UA sniffing.
- No orientation locks — recommend `portrait` in `capacitor.config.ts`.

## L. Android compliance gaps (engineering only)
| Gap | Status |
|---|---|
| Privacy policy in-app + URL | ✅ `/privacy` |
| Account deletion in-app | ✅ `AccountDeletionRequestSheet` |
| Public account-deletion URL for Play form | ❌ needed |
| Precise-location disclosure copy | needed on driver online toggle + first-run |
| Foreground-service disclosure | N/A for v1 |
| Notification permission rationale (Android 13+) | needed pre-prompt |
| Camera/photo rationale | needed on listing photo + OM proof upload |
| Play Data Safety inventory | audit outputs the inventory; form filling is ops |
| Review demo account (client + merchant + driver) | ops task |
| OM physical-services explanation | Play-listing paragraph |
| Marketplace UGC reporting | ✅ `support_issues` |
| Content rating | ops task |

## M. iOS future-readiness findings
Decisions to preserve now:
- Auth callbacks stay as universal-link-friendly HTTPS on
  `chopchopguinee.com` (already true).
- Push abstraction accepts both FCM (Android) and APNs (iOS) tokens
  keyed by `platform`.
- Location wrapper API is platform-agnostic (`start`, `stop`, `onFix`).
- Permission rationale strings in one i18n file (feeds both
  `Info.plist` and Android manifest).
- Camera wrapper exposes same `pickPhoto()` cross-platform.
- Payment resume is state-machine driven, not history-based.
- Account-deletion path remains in-app (Apple 5.1.1(v)).

## N. RED blockers (must resolve before Play launch)
1. Service worker registration inside Capacitor — extend
   `registerPwa.ts` guard to detect Capacitor
   (`window.Capacitor?.isNativePlatform?.()`) and unregister any
   pre-existing SW.
2. Driver background-location policy decision — commit to
   foreground-only in super-app (recommended) OR split driver app.
3. Push infrastructure absent — `device_tokens` + FCM edge function +
   deep-link routing.
4. Public account-deletion URL (Play form).
5. App version + `versionCode` discipline (`package.json` = `0.0.0`).

## O. YELLOW risks
- Two map GL stacks (`mapbox-gl` + MapLibre) — dead-code audit before
  native build to reduce APK size.
- `html5-qrcode` OEM fragility in WebView — plan native fallback.
- No `--mode staging` Vite variant — native binaries risk pointing at
  prod Supabase during pilot.
- Admin routes reachable inside consumer bundle (not a security issue
  because RLS enforces, but a listing-surface concern).
- BottomNav bottom-inset padding not verified on Android gesture-nav.

## P. GREEN reusable systems
- BrowserRouter + code-split admin routes.
- Supabase JS with localStorage session persistence.
- Feature flag loader (`loadFeatureFlags`) — perfect native rollout
  gate.
- OM checkout server-authoritative model.
- `DegradedMapPanel` + straight-line fallback.
- `connectivity.ts` bus + `useConnectionRestored`.
- Support-issue and report pipelines (`support_issues`, `MyIssues`).
- Runtime mode helpers (`isSandboxMode`, `runtimeMode`) — extend with
  `isNativeShell()`.
- PWA registration guard pattern — extend, don't replace.

## Q. Recommended plugin list (not installed)
Core: `@capacitor/core`, `@capacitor/cli`, `@capacitor/android`,
`@capacitor/app`, `@capacitor/status-bar`, `@capacitor/splash-screen`,
`@capacitor/keyboard`, `@capacitor/network`, `@capacitor/device`,
`@capacitor/preferences`, `@capacitor/haptics`, `@capacitor/browser`.

Feature: `@capacitor/geolocation`, `@capacitor/camera`,
`@capacitor/filesystem`, `@capacitor/push-notifications`,
`@capacitor/share`, `@capacitor/clipboard`.

Deferred (iOS time): iOS configs for the same plugin set.

## R. Post-audit phase sequence
1. `capacitor-foundation-stable` — install Capacitor, add
   `capacitor.config.ts` (bundled `webDir: dist`, no prod `server.url`),
   extend PWA guard with Capacitor detection, add `isNativeShell()`,
   introduce package.json version discipline.
2. `capacitor-android-shell-stable` — `npx cap add android`, splash,
   status bar, back-button handling, safe-area verification.
3. `android-native-services-production-stable` — Geolocation, Camera,
   Filesystem, Network, Browser behind existing web APIs.
4. `android-push-production-stable` — FCM, `device_tokens`, push edge
   function, deep-link routing.
5. `android-driver-location-production-stable` — foreground-only
   hardening + persistent online banner.
6. `android-play-readiness-stable` — public account-deletion page,
   Data Safety inventory, permission rationales, review scripts.
7. `play-closed-pilot-stable`.
8. `play-store-launch-stable`.
9. `android-pilot-stabilization-stable`.
10. `capacitor-ios-shell-stable`.
11. `ios-testflight-readiness-stable`.
12. `ios-app-store-launch-stable`.

## S. Files changed
- `docs/mobile/capacitor-readiness-audit.md` (new)
- `docs/mobile/native-capability-matrix.md` (new)
- `docs/mobile/android-launch-sequence.md` (new)
- `.lovable/memory/milestones/capacitor-readiness-audit-stable.md` (new)
- `.lovable/memory/index.md` (updated)

No source, migration, edge-function, config, or dependency changes.

## T. Build status
No build changes performed. `vite build` → `dist/` unchanged.

## U. Lock recommendation
**LOCK: `capacitor-readiness-audit-stable`.** Audit is complete,
file-specific, and made zero production behavior changes. Next run
should open `capacitor-foundation-stable` and resolve RED #1 (SW guard)
+ RED #5 (version discipline) first.
