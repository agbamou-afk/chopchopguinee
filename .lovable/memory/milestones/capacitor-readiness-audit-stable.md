---
name: Capacitor Readiness Audit — Stable
description: Audit-only readiness map for Capacitor / Android-first launch; RED/YELLOW/GREEN board, native capability matrix, and 12-phase launch sequence. No production code, dependency, or config changes.
type: feature
---

Locked 2026-07-25. Deliverables:
- `docs/mobile/capacitor-readiness-audit.md` — full audit A–U.
- `docs/mobile/native-capability-matrix.md` — plugin/API matrix.
- `docs/mobile/android-launch-sequence.md` — 12-phase sequence.

Product decisions locked by this milestone:
- Runtime architecture = **bundled Vite assets** in the native wrapper.
  No `server.url` in production.
- Android first (`com.chopchopguinee.app`), iOS after pilot.
- Driver-only app reserved as `com.chopchopguinee.driver` for any
  background-location work; consumer super-app stays foreground-only.
- OM checkout stays server-authoritative; no payment can succeed
  client-side inside a WebView.

RED blockers to clear in `capacitor-foundation-stable` and later:
1. Service-worker registration inside Capacitor.
2. Driver background-location policy (foreground-only in super-app).
3. Push infrastructure (`device_tokens` + FCM sender).
4. Public account-deletion URL.
5. `package.json` version + versionCode discipline.

Rollback: delete the three docs and this milestone. No code was
changed.

Next lock candidate: `capacitor-foundation-stable`.
