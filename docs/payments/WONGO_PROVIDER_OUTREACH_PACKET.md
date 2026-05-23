# CHOPCHOP — Mobile Money Provider Outreach Packet

> External-facing summary for Orange Money Guinea, MTN Mobile Money, payment aggregators (PSPs), and fintech / legal advisors. Contains **no credentials** and describes **no live integration**.

Contact: ChopPayments (CHOP GUINEE LTD) — payments@wongo.app

---

## 1. What is CHOPCHOP

CHOPCHOP is a district-aware African urban operating platform connecting customers, drivers, couriers, and merchants in one app. It powers:

- Rides
- Food delivery (Repas)
- Marketplace commerce (Marché)
- Courier delivery
- Merchant tools (orders, QR, payouts)
- A consumer wallet in GNF
- District-aware local pricing, hubs, and operations

Legal entity: **CHOP GUINEE LTD**. Operating brand: **CHOPCHOP**. Initial market: **Republic of Guinea**. Currency: **GNF**.

---

## 2. Why Mobile Money Integration

The cash-first reality of Conakry makes mobile money the most accessible rail for daily CHOPCHOP usage. CHOPCHOP needs a regulated, reliable mobile-money partner to:

- Let customers fund their ChopWallet from Orange Money / MTN Money.
- Let merchants collect payments through CHOPCHOP without handling cash.
- Let CHOPCHOP disburse courier and driver earnings programmatically.
- Provide auditable reconciliation across thousands of small daily transactions.

CHOPCHOP is **not** asking to hold customer funds outside the agreed merchant account, and is **not** building remittance, lending, or crypto features.

---

## 3. Payment Flows CHOPCHOP Needs

| Flow | Description | Direction |
|------|-------------|-----------|
| A. Wallet top-up | Customer funds ChopWallet from Orange / MTN | Customer → CHOPCHOP |
| B. Merchant collection | Customer pays a restaurant / store via CHOPCHOP | Customer → CHOPCHOP (held for merchant) |
| C. Courier payout | CHOPCHOP disburses courier earnings | CHOPCHOP → Courier MSISDN |
| D. Merchant settlement | Merchant receives funds after order confirmation | CHOPCHOP → Merchant account |
| E. Refund / reversal | Failed or reversed transactions handled cleanly | Bidirectional |
| F. Manual / cash fallback | Cash and agent rails remain available during pilot | Offline reconciliation |

All flows are mediated by CHOPCHOP's internal `payment_intents` ledger — no flow credits the wallet on request creation.

---

## 4. Security & Reconciliation Statement

ChopWallet credits balances **only after** a payment is confirmed by the provider. Every inbound provider callback must pass **all** of these checks before any state change:

1. Provider signature verification (HMAC-SHA256 or JWS).
2. Internal reference (`WNG-YYYY-NNNNNN`) match against an existing intent.
3. Provider match (intent provider equals event provider).
4. Amount match (event amount equals intent amount).
5. Duplicate event protection on `(provider, provider_reference)`.
6. Terminal-state protection (confirmed / failed / cancelled intents are immutable).
7. Append-only reconciliation event logging for every accepted, rejected, or duplicate callback.

Wallet crediting only occurs through a server-side, idempotent `confirm_payment_intent` routine. The mobile client cannot credit balances. Sandbox simulators reuse the exact same validation path.

---

## 5. Expected Transaction Profile (pilot)

- Currency: **GNF** only.
- Typical top-up: 10 000 – 500 000 GNF.
- Typical merchant collection: 15 000 – 300 000 GNF.
- Typical courier payout: 20 000 – 250 000 GNF.
- Volume: low at launch, growing district by district.
- Manual admin review above a configurable threshold (e.g. > 500 000 GNF).

---

## 6. Pilot Proposal

CHOPCHOP proposes a controlled pilot before any scale-up:

- **One district** initially (Kaloum or Ratoma).
- **Limited merchants** (allow-list).
- **Limited couriers** (allow-list).
- **Per-user and per-intent transaction caps.**
- **Monitored wallet top-ups** only at first; payouts added after stability.
- **Manual review threshold** for higher-value movements.
- **Cash and agent fallback** remain available throughout the pilot.
- **Daily admin reconciliation** against the provider's settlement report.
- **Provider sandbox** validated end-to-end before any production credential is enabled.

Goal: prove reliability and reconciliation discipline before broader rollout.

---

## 7. Technical Questions for the Provider

1. Do you support merchant collection APIs?
2. Do you support wallet-to-wallet collection (customer MSISDN → merchant)?
3. Do you support disbursement / payout APIs (single + bulk)?
4. Do you support signed webhooks? Which algorithm (HMAC-SHA256, JWS, mTLS)?
5. What authentication method does the API use (OAuth2, API key, mTLS)?
6. What are the sandbox onboarding requirements and access process?
7. What are the production onboarding requirements?
8. What are transaction limits (per user, per merchant, per day)?
9. What are the fees per transaction type (collection, payout, refund)?
10. What is the settlement timing (T+0, T+1, weekly)?
11. Do you provide reconciliation reports? Format and cadence?
12. Do you support refunds and reversals? Time window and rules?
13. Do you provide transaction status lookup APIs?
14. Do callbacks include a unique event ID?
15. Do you support idempotency keys on requests?
16. Are callback URLs allowlisted on your side?
17. Are IP allowlists required for outbound calls to your API?
18. What is the rate-limit policy and retry guidance?

---

## 8. Business & Compliance Questions

1. What business registration and KYC documents are required to onboard CHOP GUINEE LTD?
2. What beneficial-owner documentation is required?
3. What merchant categories does the platform model fit (aggregator, marketplace, super-app)?
4. What settlement bank or mobile-money account types are accepted?
5. What dispute / chargeback workflow applies and what is the SLA?
6. What technical and commercial support contacts will CHOPCHOP have?
7. What AML / transaction-monitoring expectations does the provider have?
8. Are there per-region or per-district regulatory restrictions to be aware of?

---

## 9. What CHOPCHOP Can Provide Today

- CHOPCHOP business registration (CHOP GUINEE LTD).
- Beneficial owner documentation.
- Technical architecture document and provider adapter contract.
- Sandbox simulator that exercises the full lifecycle (pending → confirmed / failed / expired / duplicate / amount mismatch).
- Admin reconciliation workspace with daily monitoring and CSV export.
- A single technical and a single commercial point of contact.

---

## 10. Required Environment Variables (later, server-side only)

These will be stored as Lovable Cloud secrets — never committed, never exposed to the client.

- `ENABLE_ORANGE_MONEY_WEBHOOKS` — feature flag, `"true"` enables the webhook handler.
- `ORANGE_MONEY_ENV` — `sandbox` or `production`.
- `ORANGE_MONEY_API_BASE_URL`
- `ORANGE_MONEY_CLIENT_ID`
- `ORANGE_MONEY_CLIENT_SECRET`
- `ORANGE_MONEY_MERCHANT_ID`
- `ORANGE_MONEY_WEBHOOK_SECRET`

---

## 11. Out of Scope (for this conversation)

- Remittance, lending, or crypto products.
- Holding customer funds outside the agreed merchant account.
- Cross-border settlement.
- Live API integration before sandbox validation and contract signature.

---

_Maintained by ChopPayments. Pair with the internal `docs/payments/MOBILE_MONEY_PROVIDER_ONBOARDING.md` for full architecture and credential checklist._
