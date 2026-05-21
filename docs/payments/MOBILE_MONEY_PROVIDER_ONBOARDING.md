# WONGO — Mobile Money Provider Onboarding Pack

> Status: **Readiness only.** No live provider credentials, no real money movement, no public webhook endpoint is wired in this sprint. This document is the package WONGO will share with Orange Money Guinea, MTN Mobile Money, and future payment aggregators (PSPs) to begin technical and commercial onboarding.

Audience: provider technical teams, fintech partners, legal/compliance advisors, future investors.

---

## 1. WONGO Payments Architecture (today)

WONGO Wallet runs on an **internal ledger + provider adapter** model. No provider is privileged in the codebase — Orange Money, MTN, cash, agent, and manual rails all implement the same contract.

Core building blocks (already shipped, locked as `orange-money-provider-readiness-stable`):

- `payment_intents` — every money movement starts as an intent with a WONGO internal reference (`WNG-YYYY-NNNNNN`).
- `payment_reconciliation_events` — append-only audit log per intent.
- `payment_state` enum — `pending | processing | confirmed | failed | cancelled | refunded | reversed | expired`.
- `payment_provider` enum — `orange_money | mtn_money | cash | manual | internal | agent`.
- `PaymentProviderAdapter` TS contract — provider-agnostic normalization, webhook parsing, signature validation, and event simulation.
- SECURITY DEFINER RPCs — `confirm_payment_intent`, `fail_payment_intent`, `cancel_payment_intent`. Wallet balances change **only** through these.
- Sandbox simulator — drives the same validation path without DB writes.

### Intent lifecycle

```
pending ──► processing ──► confirmed ──► (wallet credited)
   │            │              │
   ├──► failed  ├──► failed    ├──► refunded
   ├──► expired ├──► expired   └──► reversed
   └──► cancelled
```

Wallet crediting happens **only** on `confirmed`, **only** server-side, **only** through `confirm_payment_intent`. Duplicate confirmations are idempotent.

### Provider adapter model

Each provider implements `PaymentProviderAdapter` (`src/lib/payments/providers/types.ts`):

- `createPaymentIntentRequest(input)` — builds the body our server would send.
- `normalizeProviderStatus(raw)` — maps provider vocabulary onto `PaymentState`.
- `parseWebhookEvent(payload)` — pulls a `NormalizedProviderEvent` from raw JSON.
- `validateSignature(payload, signature)` — HMAC/JWS check. Stubbed today, `TODO(live)`.
- `simulateProviderEvent(intent, kind)` — sandbox/admin only.

Adding a new provider = registering a new adapter. No wallet or UI code changes.

---

## 2. Information WONGO Needs From The Provider

| # | Item | Why WONGO needs it |
|---|------|-------------------|
| 1 | Merchant account requirements | Eligibility, onboarding documents |
| 2 | API documentation (PDF + online) | Implementation reference |
| 3 | API base URLs (sandbox + production) | Adapter wiring per environment |
| 4 | Sandbox access process | Test before live |
| 5 | Production access process | Go-live gating |
| 6 | Authentication method (OAuth2, API key, mTLS) | Server-side token handling |
| 7 | Webhook / callback payload schema | parseWebhookEvent implementation |
| 8 | Webhook signing method (HMAC-SHA256 / JWS / mTLS) | validateSignature implementation |
| 9 | Supported transaction types (collection, payout, refund, reversal) | Adapter capability flags |
| 10 | Supported currencies | Guard at intent creation (today: GNF only) |
| 11 | Min / max transaction amounts | Pre-validation in UI + server |
| 12 | Transaction fees (collection + payout) | Pricing, settlement accounting |
| 13 | Settlement timing (T+0, T+1, weekly) | Treasury planning |
| 14 | Refund / reversal rules and window | Failure playbook |
| 15 | Payout support (single + bulk) | Courier and merchant payouts |
| 16 | Dispute / chargeback process | Support runbook |
| 17 | Reconciliation report format (CSV/JSON, schedule) | Daily recon job |
| 18 | Rate limits | Backoff strategy |
| 19 | Technical support contact + SLA | Incident response |
| 20 | IP allowlist / egress requirements | Edge function deploy plan |

---

## 3. Provider Credential Checklist

> **Do not commit credentials.** Only environment variable **names** are documented here. Real values live in Lovable Cloud secrets, never in the repo or frontend.

### Orange Money Guinea (expected)

| Env var | Purpose |
|---------|---------|
| `ORANGE_MONEY_ENV` | `sandbox` or `production` |
| `ORANGE_MONEY_API_BASE_URL` | Per environment |
| `ORANGE_MONEY_CLIENT_ID` | OAuth2 client id |
| `ORANGE_MONEY_CLIENT_SECRET` | OAuth2 client secret |
| `ORANGE_MONEY_MERCHANT_ID` | Merchant identifier |
| `ORANGE_MONEY_WEBHOOK_SECRET` | HMAC signing secret |
| `ORANGE_MONEY_CALLBACK_URL` | Registered with provider |
| `ORANGE_MONEY_SIGNING_CERT` | If JWS/mTLS used |

### MTN Mobile Money (expected, mirror shape)

`MTN_MOMO_ENV`, `MTN_MOMO_API_BASE_URL`, `MTN_MOMO_SUBSCRIPTION_KEY`, `MTN_MOMO_API_USER`, `MTN_MOMO_API_KEY`, `MTN_MOMO_WEBHOOK_SECRET`, `MTN_MOMO_CALLBACK_URL`.

### Aggregator / PSP (placeholder)

`PSP_ENV`, `PSP_API_BASE_URL`, `PSP_API_KEY`, `PSP_WEBHOOK_SECRET`, `PSP_CALLBACK_URL`.

Operational checklist before any production key is added:

- [ ] Sandbox credentials issued and tested end-to-end
- [ ] Callback URL registered with provider
- [ ] IP allowlist coordinated (if required)
- [ ] Webhook secret rotated post-issuance
- [ ] Production credentials stored as Lovable Cloud secrets (never in `.env`, never in client bundle)
- [ ] On-call rotation defined

---

## 4. Webhook Security Requirements

Every inbound provider callback must pass **all** checks before any state transition. Today the validation is encoded in `validateProviderEvent` (`src/lib/payments/webhooks.ts`); the live Edge Function will reuse it.

1. **Provider signature** — HMAC-SHA256 (or JWS) verified against the registered secret. Reject `invalid_signature`.
2. **Timestamp freshness** — reject events older than 5 minutes (replay protection).
3. **Event idempotency** — `(provider, provider_reference)` deduped. Duplicate ⇒ no state change, append `duplicate_event` for audit.
4. **Internal reference match** — `internal_reference` must resolve to an existing `payment_intent`. Else `unknown_reference`.
5. **Provider match** — intent's `provider` must equal event provider. Else `provider_mismatch`.
6. **Amount match** — event `amount_gnf` must equal intent `amount_gnf`. Else `amount_mismatch`.
7. **Terminal state protection** — intents in `confirmed | failed | cancelled | refunded | reversed | expired` are immutable. Any non-duplicate event ⇒ `already_terminal` + manual review.
8. **Provider payload is never trusted blindly** — only normalized fields flow downstream.

Rejected events are still **logged** to `payment_reconciliation_events` for forensic review.

---

## 5. Edge Function Readiness

Planned (not yet deployed):

- `supabase/functions/payment-webhook-orange-money/`
- `supabase/functions/payment-webhook-mtn-money/`
- `supabase/functions/payment-webhook-psp/`

Each will:

```
inbound provider callback
  → verify signature (adapter.validateSignature)
  → parse payload      (adapter.parseWebhookEvent)
  → load intent by internal_reference
  → validateProviderEvent(event, intent)
  → append reconciliation event (always)
  → on confirmed → confirm_payment_intent RPC (wallet credit)
  → on failed/expired → fail_payment_intent RPC
  → respond 2xx fast (idempotent)
```

Hard constraints:

- No credential or signing logic in the React app.
- No frontend may call confirm/fail RPCs except through admin UI for sandbox.
- Until a provider is live, the function is either absent or returns `503 not_enabled`.

---

## 6. Settlement Models

| Model | Flow | Status |
|-------|------|--------|
| **A. Wallet top-up** | customer → Orange Money → WONGO wallet credit on `confirmed` | Scaffolded, sandbox only |
| **B. Merchant payment** | customer → WONGO → merchant inflow ledger → settled later | Internal ledger ready, provider rail pending |
| **C. Courier payout** | WONGO → payout intent → provider payout → confirm | Intent shape ready, payout RPC pending |
| **D. Manual / cash fallback** | admin reconciles offline movements | Available via `manual` provider |

Settlement timing, fees, and FX (none today — GNF only) will be captured per provider when contracts are signed.

---

## 7. Reconciliation Model

Daily job (future) compares WONGO `payment_intents` against the provider's settlement report.

Buckets to surface:

- Pending intents older than threshold (e.g. > 30 min)
- Provider-confirmed but wallet **not** credited (alert — should be impossible given RPC, but verify)
- Wallet credited but no provider confirmation (alert — investigate)
- Duplicate provider references
- Failed / reversed transactions
- Amount mismatches
- Orphan provider events (no matching intent)

Output: CSV export per day, retained for audit. Admin UI surface comes later.

---

## 8. Payment Failure Playbook

| Scenario | WONGO behavior |
|----------|----------------|
| Provider timeout | Intent stays `pending`; auto-expire after TTL; user sees calm "en attente" copy |
| Wrong amount on callback | Reject `amount_mismatch`; intent untouched; flag for admin |
| Duplicate confirmation | Idempotent; no double credit; append `duplicate_event` |
| Confirmed late | Apply normally if not terminal; if expired, route to admin review |
| Failed after pending | Transition to `failed`; user notified once (deduped) |
| Reversed after confirmed | New intent of purpose `refund`; wallet debit via reverse RPC |
| User claims paid, no callback | Admin lookup by phone + WONGO ref; reconcile against provider report |
| Provider outage | Disable provider in registry (`liveEnabled: false`); fall back to cash / agent |
| Webhook delayed | Same validation path; terminal-state protection handles late arrivals |
| Webhook replayed | Dedupe on `(provider, provider_reference)` |

User-facing copy stays calm and FR-localized. No technical error codes shown to end users.

---

## 9. Provider Test Matrix

Aligned with `src/lib/sandbox/scenarios.ts`.

| # | Case | Sandbox | Live sandbox |
|---|------|---------|--------------|
| 1 | Successful top-up | ✅ | pending |
| 2 | Pending top-up | ✅ | pending |
| 3 | Failed top-up | ✅ | pending |
| 4 | Expired top-up | ✅ | pending |
| 5 | Duplicate confirmation (idempotent) | ✅ | pending |
| 6 | Wrong amount | ✅ | pending |
| 7 | Unknown reference | ✅ | pending |
| 8 | Confirmation after failure | ✅ | pending |
| 9 | Reversal after confirmation | doc | pending |
| 10 | Invalid webhook signature | doc | pending |
| 11 | Delayed webhook | doc | pending |
| 12 | Payout success | doc | pending |
| 13 | Payout failure | doc | pending |

Each case must be re-run against provider sandbox before go-live.

---

## 10. Admin Readiness Notes

Already in `/admin/payments`:

- List of intents with WONGO ref, provider, purpose, amount, state, timestamp.
- Masked MSISDN for Orange Money.
- Super Admin: manual confirm / fail, plus Orange sandbox simulations (confirm, fail, expire, duplicate, wrong amount).

Pending (later sprints):

- Filters by state / provider / date range.
- Reconciliation events drawer per intent.
- CSV export.
- Discrepancy dashboard (driven by §7 buckets).

No additional admin UI is built in this sprint — only documented.

---

## 11. Compliance / KYC Notes

> **Requires legal / payment advisor review. Nothing here claims regulatory compliance.**

Operational items likely required:

- WONGO business registration (CHOP GUINEE LTD) shared with provider.
- Provider merchant onboarding form + supporting documents.
- Beneficial owner identification.
- Settlement bank or mobile money account in WONGO's name.
- Transaction monitoring (volumes, velocity, anomaly detection).
- Customer phone verification at signup.
- Merchant verification before payouts.
- AML / KYC policy aligned with BCRG (Banque Centrale de la République de Guinée) expectations.
- Documented support and dispute process.

---

## 12. Pilot Rollout Constraints

First live pilot must respect:

- Single district (e.g. Kaloum or Ratoma) only.
- Transaction cap per user per day.
- Top-up cap per intent.
- Manual admin review above threshold (e.g. > 500 000 GNF).
- Limited merchant set (allow-list).
- Limited courier set (allow-list).
- Provider **sandbox** validated end-to-end before any production key is enabled.
- Admin on-call monitoring during pilot window.
- Cash + agent rails remain available as fallback at all times.

---

## 13. Questions For Orange Money / MTN / Aggregator

1. Do you support wallet top-ups into a platform ledger (WONGO as merchant of record)?
2. Do you support merchant collections on behalf of sub-merchants?
3. Do you support bulk payouts (courier disbursements)?
4. Do you provide signed webhooks? Which algorithm (HMAC-SHA256, JWS, mTLS)?
5. What is settlement timing (T+0, T+1, weekly)? Which account types?
6. What are transaction fees per type (collection, payout, refund)?
7. What are refund and reversal rules and time windows?
8. What are daily / monthly transaction limits per user and per merchant?
9. What is the sandbox testing process and how do we graduate to production?
10. What documentation is required to onboard (legal, KYC, technical)?
11. What is the rate limit policy and retry guidance?
12. What is the dispute / chargeback workflow and SLA?
13. What reconciliation report format do you provide, and at what cadence?
14. Is IP allowlisting required? What egress IPs should we register?
15. Who is our technical contact and what is the support SLA?

---

## 14. Out Of Scope (this sprint)

- Live provider API integration
- Committing credentials
- Public webhook endpoint
- Frontend wallet crediting
- Changing settlement rules
- Remittance, lending, crypto, banking features

---

## 15. Acceptance Checklist

- [x] Provider onboarding document exists
- [x] Required provider info checklist
- [x] Credential / env var checklist (names only)
- [x] Webhook security requirements
- [x] Reconciliation model
- [x] Failure playbook
- [x] Provider test matrix aligned with sandbox scenarios
- [x] Compliance / KYC notes flagged for legal review
- [x] Pilot rollout constraints
- [x] Provider questions list
- [x] No live money movement added
- [x] No credentials added
- [x] Build remains clean (docs-only change)

---

_Maintained by WONGO Payments. Update alongside any change to `src/lib/payments/**` or new provider adapter._
