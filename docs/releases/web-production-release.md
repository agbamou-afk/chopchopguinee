# Web Production Release Instructions (`web-rc-1`)

## 1. Commit / tag

| Field | Value |
|---|---|
| RC identifier | `web-rc-1` |
| Commit | recorded in `.lovable/memory/milestones/web-production-release-candidate-stable.md` at lock time |
| Baseline milestone | `orange-money-sandbox-ecosystem-ready-stable` |

## 2. Environment variables (build-time, public by design)

`VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `VITE_SUPABASE_PROJECT_ID`.
No server-side secret may ever be present in the build environment. Runtime
secrets live in Project Settings → Secrets and are read only by Edge Functions.

## 3. Feature flags — required launch values

| Flag | Value | Meaning |
|---|---|---|
| `om_sandbox_enabled` | false | no simulated money |
| `om_environment` | false | production |
| `om_checkout_enabled` | false | OM orchestration master gate closed |
| `om_provider_mode` | false | manual operator verification |
| `om_ride_checkout_enabled` | false | |
| `om_repas_checkout_enabled` | false | |
| `om_marche_checkout_enabled` | false | |
| `wallet_public_enabled` | false | public balance surfaces archived; OM-first |
| `orange_money` | false | |
| `orange_money.merchant_msisdn` | true | |
| `moto`, `toktok`, `driver_mode` | true | |
| `repas`, `marche`, `marketplace_chat` | true | |
| `agent_topup`, `scanner`, `wallet` | true | |
| `merchant_portal` | false | |
| `boosted_listings` | false | |

## 4. Migrations

170 migration files, applied in filename order, deterministic, no staging-only
dependency. Migrations are **forward-only** — see the rollback document.

## 5. Edge Functions (23) — deploy at the release SHA

Auth/email: `auth-email-hook`, `process-email-queue`, `send-transactional-email`,
`preview-transactional-email`, `handle-email-unsubscribe`,
`handle-email-suppression`, `admin-email-resend`.
Payments: `payment-webhook-orange-money`, `om-import-csv`.
Maps: `maps-config`, `maps-route`, `maps-eta`, `maps-search`,
`driver-location-publish`.
Admin: `admin-create-staff-user`, `admin-delete-user`, `admin-driver-doc-url`.
Other: `ai-assistant`, `generate-ai-insights`, `clean-product-image`,
`send-message`, `qa-merchant-harness`.

## 6. Domain / DNS assumptions

- App: `chopchopguinee.com`, `www.chopchopguinee.com`, plus the `.lovable.app` URL.
- Email: `notify.chopchopguinee.com` delegated by NS records; SPF/DKIM/MX are
  managed inside the delegated zone. Do not add third-party mail records on the
  same subdomain.
- Auth redirect and email links must resolve to the production domain.

## 7. SMTP state

Gate must be GREEN per `docs/qa/smtp-inbox-test-results.md` before release.

## 8. Provider state

Orange Money, **manual operator verification** (`om_provider_mode=false`). No
automated provider confirmation is claimed. Finance confirms each payment.

## 9. Required admin accounts before go-live

- 1 God Admin (release owner), password already rotated (no `must_change_password`).
- ≥1 Finance Admin for OM verification, refunds, cashouts.
- ≥1 Operations Admin for support, driver approvals, live ops.
- Each staff account created via `admin-create-staff-user`, first login forced
  through `/admin/change-password`.

## 10. Deploy order

1. Migrations → 2. Edge Functions → 3. Feature flags → 4. Frontend publish.

## 11. Immediate post-deploy smoke tests

1. `/` loads, no console errors.
2. `/auth` sign-in → client shell.
3. Ride quote returns a fare (do not dispatch).
4. Repas and Marché lists load.
5. `/wallet` shows the OM-first archived panel, no balance.
6. Driver login → online toggle → offers surface.
7. Staff account with `must_change_password` is redirected to the change route.
8. `/admin/ops` readiness strip renders.
9. `/admin/payments/sandbox` reports sandbox OFF.
10. Repeat 1–6 at 390×844.

## 12. Monitoring (first 24h)

- `email_send_log`: `dlq` count, `pending` backlog growth.
- `payment_intents`: rows stuck in `proof_submitted` / `in_review`.
- `payment_refund_requests`: unresolved items.
- `support_issues`: recovery records from failed finalization.
- Master wallet delta vs expected fee capture only.
- Ops Command Center readiness strip.

## 13. Business owner signoff points

| Point | Role | Signature | Date |
|---|---|---|---|
| Orange Money real-money evidence accepted | Finance Admin | | |
| SMTP inbox evidence accepted | Operations | | |
| P2 register accepted | Release owner | | |
| Rollback rehearsal accepted | God Admin | | |
| Go-live authorised | Release owner | | |
