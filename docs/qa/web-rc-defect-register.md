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

### DEF-009 — P1 — Wallet / feature-flag rollback — production
- **Steps:** flip `wallet_public_enabled` while a user is on `/wallet` (i.e. any
  forward-enable or rollback of the public wallet surface).
- **Expected:** the view re-renders into the other surface cleanly.
- **Actual:** `WalletView` returned early on `!publicWalletEnabled` *before*
  three `useMemo` calls. The flag resolves asynchronously through
  `useSyncExternalStore`, so the hook count changed between renders and React
  threw "Rendered more hooks than during the previous render" — a white-screen
  crash on the wallet surface at the exact moment a flag rollback is executed.
- **Evidence:** `react-hooks/rules-of-hooks`, `WalletView.tsx:149/163/177`.
- **Root cause:** conditional hooks introduced by the Orange Money First early
  return; latent because the flag has been `false` since seeding.
- **Fix:** the three memos were hoisted above the early return, with a comment
  pinning the ordering requirement.
- **Regression test:** `npx eslint .` → `react-hooks/rules-of-hooks` count 0
  (was 5); added to the release checklist preflight.
- **Status:** CLOSED.

### DEF-010 — P2 — Merchant product form — production
`ProductFormSheet` defined a plain async handler named `useImageAsPrimary`,
which the hook linter (correctly) read as a hook called inside a callback.
Renamed to `applyImageAsPrimary`. No runtime behaviour change. **Status:** CLOSED.

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

**P0 open: 0 · P1 open: 0.** (DEF-001 P0 and DEF-009 P1 were found and closed
in this phase.)

Note: zero open P1 reflects everything *observable in this environment*. The
Orange Money and SMTP gates are unexecuted, not passed — a real failure there
would be a new P0/P1 and is the reason the lock is withheld.

### DEF-011 — P2 — Lint baseline — dev
602 ESLint errors remain, dominated by `@typescript-eslint/no-explicit-any`
(520) and `no-empty` (71). All hook-rule errors are now 0. These are typing and
style debt with no known runtime impact; burning them down is a post-1.0
refactor and is explicitly out of scope under the RC freeze. **Accepted-by:** _________

### DEF-012 — P1 — `/admin/repas/payments` — CLOSED
**Symptom:** the Repas settlement admin page failed on every load with
`column li.merchant_store_id does not exist`.
**Root cause:** inside `admin_preview_repas_payment_settlement`, alias `li` is
the `latest_intent` CTE over `payment_intents`, which has no `merchant_store_id`
column — the store link lives on `food_restaurants.merchant_store_id`, with
`payment_intents.related_store_id` as fallback. The sibling Marché preview had
already been corrected; the Repas copy was never patched.
**Fix:** `CREATE OR REPLACE` of the preview function replacing all three
`li.merchant_store_id` references with
`COALESCE(fr.merchant_store_id, li.related_store_id)`. Read-only preview
function only — no pricing, capture, settlement or wallet logic touched.

### DEF-013 — P2 — No welcome email on signup — CLOSED
**Symptom:** a new account received no CHOPCHOP email after registration.
**Root cause:** two independent gaps, neither an SMTP fault. (a) Auto-confirm is
ON, so GoTrue never generates a `signup` confirmation email — every account has
`email_confirmed_at = created_at` and `confirmation_sent_at = NULL`. (b) The
`welcome` template was registered and `NotificationService.welcome()` existed,
but nothing ever called it. Sender domain `notify.chopchopguinee.com` is
verified with a healthy queue throughout.
**Fix:** signup now fires the registered `welcome` template once, fire-and-forget,
keyed `welcome-<userId>` so retries cannot duplicate. Auto-confirm stays ON —
account creation and login remain non-blocking. Turning confirmation into a
blocking step must not happen before live inbox delivery is observed, or new
signups would be locked out.
**Note:** this is the first real send attempt since 2026-06-06 and is the
cheapest source of evidence for the still-YELLOW SMTP gate.
