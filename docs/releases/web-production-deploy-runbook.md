# Web Production Deploy Runbook (`web-rc-1`)

## Preflight (owner: God Admin)

| # | Check | How | Pass condition |
|---|---|---|---|
| 1 | Freeze SHA recorded | `git log -1 --format=%H` | matches RC record |
| 2 | Sandbox OFF | `select key,enabled from feature_flags where key in ('om_sandbox_enabled','om_environment')` | both `false` |
| 3 | Public wallet OFF | same query, `wallet_public_enabled` | `false` |
| 4 | Provider mode | `om_provider_mode` | `false` = manual operator verification (launch default) |
| 5 | Migrations applied | `supabase/migrations` count vs applied | no drift |
| 6 | Edge Functions deployed | `auth-email-hook`, `process-email-queue`, `send-transactional-email`, `payment-webhook-orange-money`, `admin-create-staff-user`, `maps-*` | all deployed at RC SHA |
| 7 | SMTP evidence | `docs/qa/web-production-release-matrix.md` §SMTP signed off | GREEN before lock |
| 8 | Orange Money evidence | same doc §OM signed off | GREEN before lock |
| 9 | Build | `npm ci && npm run build` | exit 0, `dist/sw.js` emitted |
| 10 | Tests | `npx tsgo --noEmit && bunx vitest run` | clean / 12 pass |

## Build

```bash
npm ci
npx tsgo --noEmit
bunx vitest run
npm run build     # → dist/ (index.html, assets/, sw.js, workbox-*.js, manifest.webmanifest)
```

Required environment variables (build-time, public by design):
`VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `VITE_SUPABASE_PROJECT_ID`.
No server-side secret may ever appear in the build environment.

## Deployment order

1. Database migrations (backward-compatible only — see rollback runbook §DB rule).
2. Edge Functions.
3. Feature flags set to launch values (see §Launch flag values).
4. Frontend publish (Lovable Publish → Update).
5. Cache/PWA: `registerType: autoUpdate`; returning users pick up the new
   `sw.js` on next navigation. No manual cache purge required.

## Launch flag values

| Flag | Value |
|---|---|
| `om_sandbox_enabled` | false |
| `om_environment` | false |
| `om_checkout_enabled` | false |
| `om_provider_mode` | false (manual operator verification) |
| `om_ride_checkout_enabled` | false |
| `om_repas_checkout_enabled` | false |
| `om_marche_checkout_enabled` | false |
| `wallet_public_enabled` | false |
| `moto` / `toktok` / `driver_mode` | true |
| `repas` / `marche` / `marketplace_chat` | true |
| `agent_topup` / `scanner` / `wallet` | true |
| `merchant_portal` | false |
| `boosted_listings` | false |
| `orange_money` | false / `orange_money.merchant_msisdn` true |

## Post-deploy smoke order

1. `/` loads, no console errors.
2. `/auth` sign-in as test client → `Index` client shell.
3. Ride quote renders a fare; do not dispatch.
4. Repas + Marché lists load.
5. `/wallet` shows OM-first archived panel (no balance).
6. Driver login → online toggle → offers surface.
7. `/admin` → forced password-change redirect for a staff account with the flag.
8. `/admin/ops` readiness strip green/known.
9. `/admin/payments/sandbox` shows sandbox OFF.
10. 390×844 viewport pass on 1–6.

## Post-deploy monitoring (first 24h)

- `email_send_log` status mix (`dlq`, `pending` backlog).
- `payment_intents` stuck in `proof_submitted` / `in_review`.
- `support_issues` created from failed finalization.
- Ops Command Center readiness strip.

## Sign-off

| Role | Name | Signature | Date |
|---|---|---|---|
| God Admin (release owner) | | | |
| Finance Admin (OM evidence) | | | |
| Operations Admin (mission smoke) | | | |
