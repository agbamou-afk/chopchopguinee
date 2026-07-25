# CHOPCHOP — Native Capability Matrix (Android v1 → v2 → iOS)

Status: audit only. No plugins installed. No production code touched.
Companion to `capacitor-readiness-audit.md`.

Legend:
- v1 = required for first Android Play release
- v2 = required for second Android release or driver split
- fallback = current web behavior is sufficient
- ✅ = official Capacitor plugin exists
- ⚙️ = custom / native work needed
- 🌐 = keep web implementation

| Capability | Current CHOPCHOP touch-points | Android v1 need | Plugin / approach | Notes |
|---|---|---|---|---|
| App lifecycle (foreground/background/resume) | polling hooks respect `visibilityState` | v1 | `@capacitor/app` ✅ | Wire `appStateChange` to pause polling + refresh session on resume |
| Hardware back button | not handled globally today | v1 | `@capacitor/app` ✅ | Close open sheets/dialogs first; confirm on OM proof; exit at root |
| Network status | `src/lib/maps/connectivity.ts` uses `navigator.onLine` | v1 | `@capacitor/network` ✅ | More reliable than `onLine` on Android |
| Geolocation (client) | `useLiveUserLocation`, `useGeolocation`, `StoreLocationPicker` | v1 | `@capacitor/geolocation` ✅ | Thin wrapper so web + native share one interface |
| Driver location — foreground | `useDriverLocationSignal`, `useDriverLocation`, `DriverSessionContext` | v1 | `@capacitor/geolocation` ✅ | Foreground-only in super-app; persistent online banner |
| Driver location — background | not implemented | v2 (driver-only app) | ⚙️ foreground service + `ACCESS_BACKGROUND_LOCATION` | Ship in `com.chopchopguinee.driver`, not consumer app |
| Push notifications | none — all in-app DB rows | v1 | `@capacitor/push-notifications` ✅ + FCM | Requires `device_tokens` table + push edge function |
| Camera / photo picker | merchant listings, `RepasProfileSection`, OM proof, avatar | v1 | `@capacitor/camera` ✅ | Also handles gallery picking |
| File upload | `<input type=file>` in merchant + Repas + OM proof screens | v1 | `@capacitor/filesystem` ✅ (companion to Camera) | Native picker preferred over `<input>` for Play polish |
| Keyboard | forms across the app | v1 | `@capacitor/keyboard` ✅ | Adjust viewport resize mode; hide accessory bar |
| Status bar | brand-green theme | v1 | `@capacitor/status-bar` ✅ | Match `#118338` |
| Splash screen | web SplashScreen component | v1 | `@capacitor/splash-screen` ✅ | Hide on first React paint |
| Haptics | none today | fallback (nice-to-have v1) | `@capacitor/haptics` ✅ | Optional |
| Clipboard | staff temp-password copy in `AdminsAdmin.tsx` | fallback | `@capacitor/clipboard` ✅ | `navigator.clipboard` works in WebView |
| Share | Marché / storefront share buttons (if enabled) | fallback | `@capacitor/share` ✅ | LOW priority |
| In-app browser | external links, OSM `external.ts` | v1 | `@capacitor/browser` ✅ | Avoid opening external URLs inside the app WebView |
| Deep links / App Links | Supabase auth callbacks, OM resume, support links | v1 | `@capacitor/app` `appUrlOpen` ✅ | Host `assetlinks.json` on `chopchopguinee.com` |
| Device / app version | none today | v1 | `@capacitor/device` ✅ | Report `app_version` on device-token registration |
| Secure storage | localStorage today (session, prefs) | fallback for v1 | `@capacitor/preferences` ✅ | Escalate to secure storage only if we add offline signed ops or payout PIN |
| Screen orientation | none | v1 | Config in `capacitor.config.ts` | Lock consumer app to portrait |
| Permissions (runtime) | web `navigator.permissions` | v1 | Per-plugin request APIs | Show rationale sheet before each request |
| Foreground service | none | v2 (driver) | ⚙️ | Not required for consumer app |
| QR scan | `html5-qrcode` in merchant QR + agent flow | v1 (fallback OK) | `@capacitor-community/barcode-scanner` optional | Keep web path first; add native fallback only if OEM issues appear |
| Contacts / SMS | tel: links only | fallback | 🌐 | `href="tel:"` works inside WebView |
| Download folder | admin CSV exports | admin-only | ⚙️ (later) | Not on consumer path |
| Audio playback | driver offer sound | fallback | 🌐 | Verify autoplay policy after user gesture |
| Web share target | none | out of scope | — | — |

## Abstraction guidance for cross-platform reuse
- One geolocation module: `src/lib/native/geolocation.ts` chooses
  Capacitor plugin when `isNativeShell()`, `navigator.geolocation`
  otherwise.
- One camera module: `src/lib/native/photo.ts` exposes `pickPhoto()`,
  `takePhoto()`; both platforms return a `Blob` for existing upload
  helpers.
- One push module: `src/lib/native/push.ts` registers device token by
  `platform: 'android' | 'ios'`, forwards `notification tap` to a
  central deep-link router that maps `{ type, id } → path`.
- One connectivity module: extend `src/lib/maps/connectivity.ts` to
  prefer `@capacitor/network` when native.
- One "am I native?" helper: `src/lib/runtime/native.ts` → `isNativeShell()`.
