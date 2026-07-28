# Web Production RC — Defect Registry

Severity: P0 launch blocker / security / money corruption. P1 major critical-path
failure without acceptable workaround. P2 non-blocking with documented workaround.

## DEF-001 — Sandbox mode left ENABLED in production database — **P0 — FIXED**
- Role/module: Finance / Orange Money / all payment paths
- Repro: `select key, enabled from feature_flags where key in ('om_sandbox_enabled','om_environment')`
- Expected: both `false` in production. Actual: both `true` (set 2026-07-26 during Slice D QA and never restored, despite the Slice D report claiming restoration).
- Severity rationale: `isOmSandboxActive()` returns true when both flags are set, which exposes sandbox affordances and deterministic `OM-SBX-*` fixtures to production surfaces. Production/sandbox contamination = P0 by definition.
- Fix: migration `UPDATE feature_flags SET enabled=false WHERE key IN ('om_sandbox_enabled','om_environment')`.
- Regression test: pre-deploy flag assertion in the deploy runbook preflight; re-verified `false/false`.
- Status: **CLOSED**

## DEF-002 — AuthProvider test suite masked role loading — **P2 — FIXED**
- Role/module: QA harness / `src/test/auth.test.tsx`
- Repro: `bunx vitest run` → "loads profile + roles for an admin session" fails, `isGodAdmin=false`.
- Expected: god_admin role resolves. Actual: mocked supabase client had no `rpc`, so `Promise.all([...profile, roles, rpc('current_freeze')])` rejected and `AuthContext`'s catch cleared roles.
- Severity: P2 — test-harness only; production client has `rpc`. But it hid role-loading regressions, so it blocked release confidence.
- Fix: added `rpc: () => Promise.resolve({ data: [], error: null })` to the mock.
- Status: **CLOSED** (12/12 green)

## DEF-003 — Production console emitted driver offer payload — **P2 — FIXED**
- Role/module: Driver / `DriverSessionContext.tsx:269`
- Repro: create a debug driver offer in production → full offer row logged to browser console.
- Expected: no mission/PII payloads in production console.
- Fix: wrapped in `import.meta.env.DEV`.
- Status: **CLOSED**

## DEF-004 — Main bundle 2.07 MB (598 kB gzip) — **P2 — ACCEPTED**
- Module: build. `dist/assets/index-*.js` 2,071 kB; `mapbox-gl` 1,781 kB already split.
- Impact: slow first load on Guinean 2G/3G. Mitigated by service-worker precache on repeat visits and low-data mode.
- Workaround: accepted for 1.0; chunk-splitting deferred post-1.0 (not an Android 1.0 blocker — Android ships bundled assets).
- Status: **ACCEPTED**

## DEF-005 — Supabase linter: 451 warn-level findings — **P2 — ACCEPTED**
- Mostly `function_search_path_mutable`, `anon_security_definer_function_executable`, `extension_in_public`, one `public_bucket_allows_listing`.
- No error/critical findings. No cross-user data exposure identified in the RC sweep.
- Deferred: search_path hardening sweep post-1.0.
- Status: **ACCEPTED** (tracked, not launch-blocking)

## DEF-006 — Self-serve read gaps flagged by scanner — **P2 — ACCEPTED**
- `driver_applications`, `driver_referrals`, `topup_requests` have no applicant/owner SELECT policy; users depend on push/notification for status.
- Workaround: status surfaced via notifications and `/help/issues`; admins can answer.
- Status: **ACCEPTED**, scheduled post-1.0 as sanitized RPCs (not raw SELECT policies).

**Open P0: 0 — Open P1: 0 — Accepted P2: 3 (DEF-004/005/006)**
