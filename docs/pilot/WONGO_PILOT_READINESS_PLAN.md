> _Note: Previously referred to as WONGO during brand exploration. The consumer-facing brand has been restored to CHOPCHOP. File paths preserved to avoid breaking links._

# CHOPCHOP — Pilot Readiness Plan

**Owner:** CHOP GUINEE LTD
**Status:** Draft v1 — pre-pilot operational roadmap
**Scope:** Move CHOPCHOP from coherent prototype to a controlled one-district pilot with real users, merchants, couriers, payments, and support.
**Non-goals:** New features, live mobile-money money movement, dispatch rule changes, wallet rule changes, public marketing, national rollout.

---

## 1. Executive Summary

CHOPCHOP is the CHOP GUINEE LTD super-app for Conakry: ride-hailing (Moto, TokTok), Repas (restaurant delivery), Marché (boutique browsing + delivery), Envoyer (parcels), and the ChopWallet (GNF). The platform foundation — districts, missions, payment intents, reconciliation admin, sandbox engine — is in place. **Live mobile-money is not yet connected.**

The pilot's purpose is **not** to prove the product works in code; it is to prove CHOPCHOP can be **operated** in one Conakry district with real couriers, real merchants, real customers, and real money — without losing user trust, mishandling payments, or overloading support.

This plan defines: which zone, which services, how many couriers/merchants/users, what readiness gates must close first, what metrics decide go/no-go for the next phase, and what risks must be mitigated.

---

## 2. Pilot Scope (Controlled)

| Dimension | Target |
|---|---|
| Districts | **1** (Phase 2), expanding to 2 only in Phase 4 |
| Couriers / drivers | 10–25 vetted |
| Merchants / restaurants | 10–30 onboarded |
| Early users | 100–500 invite-coded |
| Operating hours | Limited window (e.g. 09:00–21:00) |
| Delivery radius | Within pilot district + adjacent commune edge |
| Transaction cap | Per-user, per-day, per-merchant (set in pilot config) |
| Support coverage | Manual, human-staffed during operating hours |

Pilot must be **small enough to control** and **large enough to expose real operational pressure** (peak-hour Repas rush, courier no-shows, payment edge cases).

---

## 3. District Strategy

Pilot in **one** dense, operationally manageable district. Evaluate candidates against criteria below; do not assume nationwide launch.

| District | Merchant density | Restaurant density | Customer density | Courier supply | Roads | Safety | MoMo adoption | Ops manageability |
|---|---|---|---|---|---|---|---|---|
| Kaloum | High (admin/business) | Medium | Medium (workday) | Medium | Congested | Good | High | Medium |
| Dixinn | Medium | High | High | High | Good | Good | High | High |
| Madina | Very high (marché) | High | Very high | High | Congested | Medium | High | Medium |
| Ratoma | Medium | Medium | High | High | Mixed | Good | High | High |
| Kipé | Medium | Medium-high | High (residential) | High | Good | Good | High | **High** |

**Recommended primary candidate: Kipé** — residential density, good road access, strong courier supply, manageable footprint. **Secondary candidate: Dixinn** — strong restaurant base for Repas validation.

District metadata, chips, and hub model already exist in `src/lib/districts/` and `src/lib/districts/hubs.ts`.

---

## 4. Pilot Services (In Scope)

| Service | In pilot | Notes |
|---|---|---|
| Moto ride-hailing | ✅ | Primary mobility |
| TokTok ride-hailing | ⚠️ Optional | Only if vehicle supply exists |
| Repas (restaurant delivery) | ✅ | Limited to onboarded restaurants |
| Marché (browsing + delivery request) | ✅ | Manual courier dispatch acceptable |
| Envoyer (package delivery) | ⚠️ Limited | Same-district only, value-capped |
| ChopWallet (internal ledger) | ✅ | Test-mode / manual top-up / OM via reconciliation admin |
| Cash payment | ✅ | Fallback for every flow |
| Live mobile-money processing | ❌ | Not until provider approval |

**Do not overpromise:** instant delivery everywhere, perfect live tracking, full automation, nationwide availability.

---

## 5. Courier / Driver Readiness

### Onboarding requirements
- Verified phone number (OTP)
- ID document verification (admin-reviewed)
- Vehicle verification (moto/bike/TokTok photos + plate)
- Declared service capabilities (`rides_moto`, `rides_toktok`, `repas_delivery`, `marche_delivery`, `package_delivery`)
- Preferred operating district
- Declared operating hours
- Safety acknowledgement
- Payout method (wallet/cash reconciliation)
- Issue reporting protocol signed
- Support contact recorded

### Training checklist
- Accepting / declining missions
- Pickup confirmation flow
- Delivery confirmation flow
- Reporting issues (no-show, wrong address, item issue)
- Handling cash vs. wallet payments
- Customer communication etiquette
- Restaurant pickup etiquette
- Package security & dispute basics

---

## 6. Merchant Readiness

### Repas (restaurant)
- Restaurant name, district, contact
- Menu items with prices in GNF
- Realistic prep time per item / category
- Pickup instructions for courier
- Declared delivery availability windows
- CHOP/ChopPay acceptance ready (or cash fallback)

### Marché (boutique)
- Store/boutique profile
- Listing creation (photo, price, availability)
- Availability state toggle
- Fulfillment options (self-handoff, courier pickup)
- Delivery request acceptance flow
- Seller confirmation flow before courier dispatch

### Merchant training
- Receiving and acknowledging orders
- Confirming readiness to courier
- Handoff procedure
- Reporting problems (out-of-stock, delay)
- Payment expectations & reconciliation timing
- Listing quality (photo, accurate price, accurate availability)

---

## 7. Payment Readiness

| Rule | State |
|---|---|
| Cash supported | ✅ |
| ChopWallet internal ledger active | ✅ |
| Orange Money / MTN provider conversations | 🟡 In progress (see `WONGO_PROVIDER_OUTREACH_PACKET.md`) |
| Live mobile-money processing | ❌ Locked until provider approval |
| Admin-confirmed manual top-ups during pilot | ✅ via `/admin/payments` + `/admin/wallet-reconciliation` |
| Per-intent CHOPCHOP reference required | ✅ Enforced by `payment_intents` |
| Wallet credit only via `confirm_payment_intent` RPC | ✅ Enforced |
| Daily reconciliation review | ✅ Required during pilot |
| Transaction caps active | ✅ Per-user/day, per-merchant/day |

Pilot payment discipline: **no wallet credit without a confirmed intent**, no provider callback is trusted without validation, every payment has a CHOPCHOP ref, admins clear pending/failed/review-needed intents at end of each pilot day.

---

## 8. Support / Issue Handling

### Channels
- In-app issue reporting (per mission / per intent)
- Driver support line (phone)
- Merchant support line (phone)
- Admin review dashboard (`/admin/payments`, `/admin/wallet-reconciliation`, future issues queue)
- WhatsApp fallback (manned during pilot hours)

### Issue catalog & target response
| Issue | Target first response | Owner |
|---|---|---|
| Customer unreachable | < 5 min | Courier → support |
| Merchant not ready | < 5 min | Courier → support |
| Wrong address | < 5 min | Support |
| Courier no-show | < 10 min | Support → dispatch reassign |
| Payment pending > 10 min | Same day | Payment ops |
| Payment failed | Same day | Payment ops |
| Package issue / dispute | < 1 hr | Support + admin |
| Item unavailable | < 5 min | Merchant → support |
| Refund request | < 24 hr | Payment ops + admin |

Every issue must be logged. No verbal-only resolutions in pilot.

---

## 9. District Operations

Use existing district foundation (`src/lib/districts/`, `district_hubs` table).

Pilot defines:
- 1 active pilot district
- Preferred courier home district (matches pilot district)
- Allowed mission district pairs (within pilot + adjacent edge)
- District hub candidate(s) — local partner anchor
- Vendor partner candidates
- Support point candidate (where couriers can rest / report issues in person)

**No physical CHOPCHOP HQ in pilot.** Identify local partner hubs only: café, fuel station, boutique, pharmacy, restaurant, kiosk. Track via `district_hubs.partner_type`.

---

## 10. Trust & Safety

| Audience | Trust requirements |
|---|---|
| Customers | Clear price up-front, confirmed pickup/dropoff, reliable support, payment clarity, visible courier identity |
| Couriers | Clear earnings per mission, fair payout cadence, issue protection, realistic mission distance, working escalation path |
| Merchants | Order clarity, payment clarity & timing, courier handoff confidence, customer communication channel |

Trust must be **operational**, not decorative. Every "Trust cue" in UI must be backed by a real workflow.

---

## 11. Admin / Ops Readiness

| Capability | State |
|---|---|
| Payment reconciliation admin (`/admin/payments`) | ✅ |
| Wallet reconciliation (`/admin/wallet-reconciliation`) | ✅ |
| Sandbox ops panel | ✅ |
| Mission infrastructure | ✅ |
| District foundation + hubs | ✅ |
| Merchant hub | ✅ |
| Wallet receipts | ✅ |
| Active mission visibility (live ops) | 🟡 Verify coverage |
| Issues queue (unified) | 🔴 Needed (lightweight) |
| Merchant verification queue | 🟡 Verify |
| Courier verification queue | 🟡 Verify |
| Payment review queue | ✅ (in `/admin/payments`) |
| Basic support notes per entity | 🔴 Needed (lightweight) |
| Pilot metrics dashboard | 🟡 Later (post-Phase 1) |

Keep admin tools lightweight. **Do not build a national ops cockpit before the pilot.**

---

## 12. Pilot Metrics

### Operational
- Completed rides / day
- Completed deliveries / day (Repas, Marché, Envoyer)
- Failed missions (and reason)
- Average mission duration
- Issue rate (% of missions)
- Cancellation rate (customer / courier / merchant)
- Courier acceptance rate

### Merchant
- Active merchants / day
- Orders per merchant
- Prep delay (declared vs. actual)
- Merchant week-over-week retention

### Customer
- Repeat usage (D1, D7, D30)
- Browse → order conversion (Repas, Marché)
- Support complaints / 100 orders
- Trust feedback (post-ride/post-order rating + free text)

### Payment
- Wallet top-ups (count, GNF)
- Pending payments (count, age)
- Failed payments (count, reason)
- Reconciliation mismatches
- Manual review count / day

---

## 13. Sandbox / Testing Before Pilot

### Required sandbox scenarios (must pass)
- Repas rush
- Marché delivery happy path
- Courier rejection cascade
- Merchant offline mid-order
- Payment pending → expire
- Payment failed
- Notification burst
- District mismatch (mission outside allowed pair)

### Required e2e (must be green)
- Onboarding (client + driver)
- Repas order end-to-end
- Marché delivery end-to-end
- Merchant activation
- Driver mission acceptance
- Wallet receipt rendering
- `/admin/payments` & `/admin/wallet-reconciliation` access control

**Do not launch pilot until critical tests are green.**

---

## 14. Pilot Phases (Staged Rollout)

| Phase | Audience | Exit criteria |
|---|---|---|
| **Phase 0** | Internal QA only | All sandbox + e2e green; admin tools verified |
| **Phase 1** | Closed: team + friends + test merchants | < 5% issue rate; zero unreconciled payments; positive courier feedback |
| **Phase 2** | Small real-user pilot, 1 district | Metrics within target for 2 consecutive weeks |
| **Phase 3** | Expanded district pilot (same district, more users/merchants/couriers) | Stable metrics; support load manageable |
| **Phase 4** | Second district expansion | Phase 3 stability sustained 4 weeks |

**Do not skip phases.** Phase exit is a deliberate go/no-go.

---

## 15. Risk Matrix

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Payment distrust (customers fear losing money) | High | High | Cash fallback always; visible CHOPCHOP ref; daily reconciliation; clear receipts |
| Courier unreliability (no-shows, late) | High | High | Vetted onboarding; acceptance-rate tracking; backup courier pool; rest hub |
| Merchant delays (long prep, out-of-stock) | High | Medium | Prep-time training; availability toggle; courier wait protocol |
| Support overload | Medium | High | Hours-bounded pilot; capped users; WhatsApp fallback; issue catalog |
| Incorrect addresses | High | Medium | Saved places; landmark search; courier→customer call protocol |
| Fake listings | Medium | Medium | Merchant verification queue; admin spot checks |
| Theft / package disputes | Medium | High | Value caps on Envoyer; ID-verified couriers; dispute logging |
| Mobile data / GPS limitations | High | Medium | Low-data mode; offline banner; tile cache; SMS fallback for OTP |
| App instability | Medium | High | Phase-0 QA gate; e2e green requirement; sandbox engine pre-flight |
| Overexpansion (too many districts/services too fast) | Medium | Very High | Phase gating; one district until Phase 4; service scope locked per phase |
| Live MoMo enabled before provider approval | Low | Very High | Webhook stub disabled by default; no live credentials committed; admin-only manual confirms |

---

## 16. Go / No-Go Checklist (Phase 2 launch)

### Product
- [ ] All required e2e tests green
- [ ] All required sandbox scenarios pass
- [ ] No P0/P1 known bugs open
- [ ] Offline + low-data modes verified
- [ ] Receipts render correctly for all payment states

### Couriers
- [ ] ≥ 10 vetted couriers onboarded for pilot district
- [ ] All couriers trained (training checklist signed)
- [ ] Issue reporting protocol acknowledged
- [ ] Payout method confirmed

### Merchants
- [ ] ≥ 10 merchants onboarded (mix Repas + Marché)
- [ ] Menus / listings live and accurate
- [ ] Prep times calibrated
- [ ] Merchant training complete

### Payments
- [ ] Cash fallback verified
- [ ] Wallet ledger reconciles to zero discrepancy in test
- [ ] No live MoMo credentials committed
- [ ] Daily reconciliation owner assigned
- [ ] Transaction caps configured

### Support
- [ ] Support staff scheduled for full pilot hours
- [ ] Driver + merchant support lines live
- [ ] WhatsApp fallback manned
- [ ] Issue catalog distributed

### Ops
- [ ] Pilot district selected and locked
- [ ] District hub partner(s) identified
- [ ] Operating hours published internally
- [ ] Delivery radius enforced in config
- [ ] Admin tools accessible to ops team only

### Trust
- [ ] Pricing visible pre-confirmation
- [ ] Courier identity visible to customer
- [ ] Receipts emailed/visible in-app
- [ ] Rating prompt functional

**If any box is unchecked → no-go.**

---

## 17. Out of Scope for Pilot

- New product features
- Live mobile-money processing
- Dispatch algorithm changes
- Wallet rule changes
- Public marketing campaigns
- National rollout assumptions
- Performance guarantees / SLAs to customers
- Heavyweight admin dashboards

---

## 18. References

- `docs/payments/MOBILE_MONEY_PROVIDER_ONBOARDING.md`
- `docs/payments/WONGO_PROVIDER_OUTREACH_PACKET.md`
- `docs/field-testing-conakry.md`
- `src/lib/districts/`, `src/lib/districts/hubs.ts`
- `src/pages/admin/PaymentsAdmin.tsx`, `src/pages/admin/WalletReconciliation.tsx`
- `src/lib/sandbox/scenarios.ts`, `tests/e2e/`

---

_End of CHOPCHOP Pilot Readiness Plan v1._