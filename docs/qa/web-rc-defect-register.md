# Web RC Defect Register (`web-rc-1`)

Fields: ID · severity · role/module · environment · steps · expected · actual ·
evidence · root cause · fix · regression test · status · accepted-by.

## Closed

### DEF-001 — P0 — Payments / feature flags — production
- **Steps:** query `feature_flags` after the sandbox QA phase.
- **Expected:** `om_sandbox_enabled=false`, `om_environment=false` in production.
- **Actual:** both `true`; sandbox references (`OM-SBX-*`) would have been
  honoured against real customers.
- **Evidence:** flag rows, `updated_at` prior to 2026-07-28.
- **Root cause:** the previous phase reported "sandbox restored OFF" without
  writing the flag rows back.
- **Fix:** migration setting both to `false`.
- **Regression test:** `feature_flags` assertion in the deploy runbook preflight
  (step 2) and the release checklist.
- **Status:** CLOSED — verified `false`, `updated_at 2026-07-28T17:17Z`.

### DEF-002 — P2 — QA harness — dev
- **Steps:** `bunx vitest run` on the auth suite.
- **Expected:** role-loading tests exercise the real `AuthProvider` path.
- **Actual:** the Supabase mock had no `rpc`, so `Promise.all` rejected and
  roles silently fell back to `[]`, masking role regressions.
- **Fix:** added `rpc` mock in `src/test/auth.test.tsx`.
- **Regression test:** 12/12 passing.
- **Status:** CLOSED.

### DEF-003 — P2 (privacy-adjacent) — Driver — production
- **Steps:** open the browser console as an online driver.
- **Expected:** no mission payload in the production console.
- **Actual:** `[driver_offer_debug]` logged the full offer object.
- **Fix:** gated behind `import.meta.env.DEV` in `DriverSessionContext.tsx`.
- **Status:** CLOSED.

## Accepted P2 (documented, awaiting release-owner signature)

### DEF-004 — P2 — Performance — production
Main chunk 2.07 MB (598 kB gzip); `mapbox-gl` 1.78 MB (490 kB gzip). Mitigated
by code-splitting of admin/map routes, PWA precache and low-data mode. Accepted
for 1.0; revisit in the Android performance phase. **Accepted-by:** _________

### DEF-005 — P2 — Database linter — production
451 warn-level Supabase linter findings, **0 error-level**. Predominantly
function-search-path and RLS-policy style advisories on legacy objects. No
unauthorized-access finding. **Accepted-by:** _________

### DEF-006 — P2 — Self-serve reads — production
`driver_applications`, `driver_referrals` and `topup_requests` have limited
self-serve read exposure; users rely on support for status. Must be closed with
sanitized RPCs/views post-1.0 — never with a raw sensitive `SELECT` policy.
**Accepted-by:** _________

### DEF-007 — P2 — Email infra functions — production
Four Lovable-managed queue functions (`enqueue_email`, `read_email_batch`,
`delete_email`, `move_to_dlq`) are `SECURITY DEFINER` without a pinned
`search_path`. They are platform-managed (must not be hand-edited) and carry no
`PUBLIC` execute grant. Accepted as platform-owned. **Accepted-by:** _________

### DEF-008 — P2 — `merchant_ensure_wallet` — production
`SECURITY DEFINER`, `search_path` pinned, but carries `PUBLIC` execute and has
no internal caller guard. It only idempotently creates an empty merchant wallet
row for an existing merchant's owner and returns its id — no balance mutation,
no data disclosure. Add an explicit guard post-1.0. **Accepted-by:** _________

## Open

**P0 open: 0 · P1 open: 0.**

Note: zero open P1 reflects everything *observable in this environment*. The
Orange Money and SMTP gates are unexecuted, not passed — a real failure there
would be a new P0/P1 and is the reason the lock is withheld.
