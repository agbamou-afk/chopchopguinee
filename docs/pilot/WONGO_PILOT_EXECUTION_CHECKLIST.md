> _Note: Previously referred to as WONGO during brand exploration. The consumer-facing brand has been restored to CHOPCHOP. File paths preserved to avoid breaking links._

# CHOPCHOP — Pilot Execution Checklist

**Owner:** CHOP GUINEE LTD
**Status:** Operator-facing execution checklist v1
**Companion to:** [`WONGO_PILOT_READINESS_PLAN.md`](./WONGO_PILOT_READINESS_PLAN.md)
**Purpose:** Day-to-day operational checklist to execute the pilot defined in the readiness plan. This is not a strategy document — it is a tick-box runbook.

> Read the readiness plan first. This checklist assumes its scope, district strategy, payment rules, and phase definitions.

**Owner categories used below:** Founder / Operator, Tech Lead, Ops Lead, Merchant Lead, Courier Lead, Support Lead, Payment Lead, Admin.

---

## Phase 0 — Internal QA + Setup

### Build & code health

- [ ] Production build green (no TS errors, no broken routes)
  Owner: Tech Lead
  Timing: T-21 days
  Dependency: clean main branch
  Notes: must be repeated before every phase transition.

- [ ] CHOPCHOP rebrand cleanup verified (no stale "Choper", legacy names, or placeholder copy in user-visible surfaces)
  Owner: Tech Lead
  Timing: T-21 days
  Dependency: build green
  Notes: spot-check home, onboarding, receipts, admin headers, email templates.

### Automated tests

- [ ] All e2e tests green (`tests/e2e/*`)
  Owner: Tech Lead
  Timing: T-21 days
  Dependency: build green
  Notes: 01-public-flows, 02-navigation, 03-merchant, 04-sandbox-ops, 05-wallet-smoke.

- [ ] Unit / vitest suite green
  Owner: Tech Lead
  Timing: T-21 days
  Dependency: build green
  Notes: blocks phase exit if red.

### Sandbox scenarios

- [ ] Repas rush scenario passes
  Owner: Tech Lead
  Timing: T-18 days
  Dependency: sandbox engine available
  Notes: see `src/lib/sandbox/scenarios.ts`.

- [ ] Marché delivery happy path passes
  Owner: Tech Lead
  Timing: T-18 days
  Dependency: sandbox engine available
  Notes: courier dispatch + seller confirm must fire.

- [ ] Courier rejection cascade passes
  Owner: Tech Lead
  Timing: T-18 days
  Dependency: sandbox engine available
  Notes: confirms fallback dispatch behavior.

- [ ] Merchant offline mid-order scenario passes
  Owner: Tech Lead
  Timing: T-18 days
  Dependency: sandbox engine available
  Notes: must surface a clear customer-facing state.

- [ ] Payment pending → expire scenario passes
  Owner: Payment Lead
  Timing: T-18 days
  Dependency: sandbox engine available
  Notes: confirms no wallet credit on expire.

- [ ] Payment failed scenario passes
  Owner: Payment Lead
  Timing: T-18 days
  Dependency: sandbox engine available
  Notes: failed intent surfaces in `/admin/payments`.

- [ ] Notification burst scenario passes
  Owner: Tech Lead
  Timing: T-18 days
  Dependency: sandbox engine available
  Notes: no duplicate spam, no crash.

- [ ] District mismatch scenario passes
  Owner: Tech Lead
  Timing: T-18 days
  Dependency: district config locked
  Notes: mission outside allowed pair must be blocked or warned.

### Core flows (manual QA)

- [ ] Client onboarding end-to-end (OTP → profile → home)
  Owner: Ops Lead
  Timing: T-15 days
  Dependency: build green
  Notes: test on low-end Android.

- [ ] Driver onboarding end-to-end (apply → docs → approved → driver home)
  Owner: Courier Lead
  Timing: T-15 days
  Dependency: admin verification queue available
  Notes: capture friction points.

- [ ] Repas order placed end-to-end (browse → cart → pay → courier → delivered → rating)
  Owner: Ops Lead
  Timing: T-14 days
  Dependency: at least 1 test restaurant live
  Notes: include cash and wallet path.

- [ ] Marché delivery request end-to-end (listing → request → seller confirm → courier → delivered)
  Owner: Merchant Lead
  Timing: T-14 days
  Dependency: at least 1 test boutique live
  Notes: validates the seller confirmation gate.

- [ ] Ride flow end-to-end (request → match → pickup → drop → receipt)
  Owner: Ops Lead
  Timing: T-14 days
  Dependency: at least 1 active test driver
  Notes: validate ETA + price preview before confirm.

- [ ] Driver mission acceptance flow verified (offer → accept → pickup → complete)
  Owner: Courier Lead
  Timing: T-14 days
  Dependency: incoming offers feed active
  Notes: includes rejection path.

- [ ] Wallet receipts render correctly (top-up, ride, repas, marché, refund)
  Owner: Payment Lead
  Timing: T-13 days
  Dependency: payment intents flowing
  Notes: GNF formatting, masked phone, CHOPCHOP ref visible.

### Admin / ops tools

- [ ] `/admin/payments` reconciliation surface verified (filters, search, review heuristics, CSV export)
  Owner: Payment Lead
  Timing: T-12 days
  Dependency: payment admin role assigned
  Notes: confirm normal users blocked.

- [ ] `/admin/wallet-reconciliation` ledger view verified
  Owner: Payment Lead
  Timing: T-12 days
  Dependency: admin role
  Notes: zero-discrepancy run on test data.

- [ ] Admin role matrix verified (admin, payment ops, support, merchant, courier admin)
  Owner: Admin
  Timing: T-12 days
  Dependency: `useAdminAuth` + `AdminGuard`
  Notes: each role can only access its own modules.

- [ ] Support issue reporting path verified in-app (per mission, per intent)
  Owner: Support Lead
  Timing: T-12 days
  Dependency: issues queue (lightweight) available
  Notes: every reported issue must land somewhere reviewable.

---

## Phase 1 — Closed Pilot Preparation

- [ ] Pilot district selected and locked (primary: Kipé; fallback per readiness plan)
  Owner: Founder / Operator
  Timing: T-21 days
  Dependency: Phase 0 sign-off
  Notes: district code recorded in pilot config.

- [ ] Operating radius defined (pilot district + adjacent commune edge)
  Owner: Ops Lead
  Timing: T-20 days
  Dependency: district locked
  Notes: enforced in district config / mission pairing.

- [ ] Operating hours published internally (e.g. 09:00–21:00)
  Owner: Ops Lead
  Timing: T-20 days
  Dependency: support schedule
  Notes: app outside hours shows informational state, not error.

- [ ] Support coverage scheduled for full operating window (phone + WhatsApp)
  Owner: Support Lead
  Timing: T-18 days
  Dependency: operating hours
  Notes: at least one backup on call.

- [ ] Internal pilot users list compiled (invite-coded, 100–500)
  Owner: Founder / Operator
  Timing: T-14 days
  Dependency: invite mechanism ready
  Notes: phones verified before invite send.

- [ ] Pilot merchant shortlist compiled (10–30)
  Owner: Merchant Lead
  Timing: T-14 days
  Dependency: district locked
  Notes: mix Repas + Marché.

- [ ] Pilot courier shortlist compiled (10–25)
  Owner: Courier Lead
  Timing: T-14 days
  Dependency: district locked
  Notes: prefer couriers residing in pilot district.

- [ ] Cash-fallback process documented and shared with all couriers + merchants
  Owner: Payment Lead
  Timing: T-12 days
  Dependency: payment rules confirmed
  Notes: cash is always-on during pilot.

- [ ] Rollback / kill-switch plan written (how to pause new orders by service & district)
  Owner: Tech Lead
  Timing: T-10 days
  Dependency: admin flags surface
  Notes: tested in staging.

---

## Phase 2 — Merchant / Courier Onboarding

### Merchant onboarding (each merchant)

- [ ] Restaurant / store profile collected (name, district, address, contact)
  Owner: Merchant Lead
  Timing: T-10 to T-3 days
  Dependency: shortlist
  Notes: photo of storefront for verification.

- [ ] Menus / listings uploaded with accurate GNF prices
  Owner: Merchant Lead
  Timing: T-10 to T-3 days
  Dependency: profile created
  Notes: at least one photo per item where possible.

- [ ] Phone / contact verified (OTP + callback)
  Owner: Merchant Lead
  Timing: T-10 to T-3 days
  Dependency: profile created
  Notes: primary + backup number.

- [ ] Delivery / pickup settings configured (windows, prep time, fulfillment options)
  Owner: Merchant Lead
  Timing: T-9 to T-3 days
  Dependency: menu/listing live
  Notes: prep times must be realistic.

- [ ] Payment expectations explained (cash, wallet, reconciliation cadence)
  Owner: Payment Lead
  Timing: T-7 days
  Dependency: profile created
  Notes: signed acknowledgement recorded.

- [ ] Handoff training delivered (order ack, ready signal, courier handoff, issue reporting)
  Owner: Merchant Lead
  Timing: T-5 days
  Dependency: payment briefing
  Notes: training checklist signed.

### Courier onboarding (each courier)

- [ ] ID document collected and verified (admin review)
  Owner: Admin
  Timing: T-10 to T-3 days
  Dependency: shortlist
  Notes: rejected ID → re-collect, do not skip.

- [ ] Phone verified (OTP)
  Owner: Courier Lead
  Timing: T-10 to T-3 days
  Dependency: shortlist
  Notes: number tied to account.

- [ ] Moto / vehicle info captured (type, plate, photos)
  Owner: Courier Lead
  Timing: T-10 to T-3 days
  Dependency: ID verified
  Notes: TokTok variant flagged separately.

- [ ] Preferred operating district set to pilot district
  Owner: Courier Lead
  Timing: T-7 days
  Dependency: profile created
  Notes: enforced for pilot dispatch.

- [ ] Capabilities declared (`rides_moto`, `rides_toktok`, `repas_delivery`, `marche_delivery`, `package_delivery`)
  Owner: Courier Lead
  Timing: T-7 days
  Dependency: profile created
  Notes: matches vehicle reality.

- [ ] Mission training delivered (accept/decline, pickup, delivery confirm, customer comms)
  Owner: Courier Lead
  Timing: T-5 days
  Dependency: capabilities set
  Notes: training checklist signed.

- [ ] Issue reporting protocol acknowledged (no-show, wrong address, item issue, dispute)
  Owner: Support Lead
  Timing: T-5 days
  Dependency: mission training
  Notes: acknowledgement recorded.

- [ ] Payout expectations explained (cadence, channel, reconciliation timing)
  Owner: Payment Lead
  Timing: T-5 days
  Dependency: mission training
  Notes: signed acknowledgement.

---

## Phase 3 — Soft Launch

- [ ] Activate one district only (pilot district flag ON; all others OFF)
  Owner: Tech Lead
  Timing: Day 0
  Dependency: Phase 0–2 complete
  Notes: verify no cross-district missions slip through.

- [ ] Open invites sent to internal pilot users
  Owner: Founder / Operator
  Timing: Day 0
  Dependency: district active
  Notes: staggered send (avoid burst).

- [ ] Monitor first real missions live (first 10 across services)
  Owner: Ops Lead
  Timing: Day 0, hour 0–6
  Dependency: live ops view
  Notes: one operator watching at all times.

- [ ] Monitor support issues live (channel inbox, in-app reports)
  Owner: Support Lead
  Timing: Day 0, full hours
  Dependency: support coverage
  Notes: triage within target response time.

- [ ] Monitor payments live (`/admin/payments` review queue)
  Owner: Payment Lead
  Timing: Day 0, full hours
  Dependency: admin role
  Notes: zero unresolved at end of day.

- [ ] Monitor merchant response (ack time, prep accuracy)
  Owner: Merchant Lead
  Timing: Day 0, full hours
  Dependency: merchant list
  Notes: call merchant if no ack in target window.

- [ ] Monitor courier acceptance (acceptance rate, no-shows)
  Owner: Courier Lead
  Timing: Day 0, full hours
  Dependency: courier list
  Notes: contact courier on first no-show.

---

## Phase 4 — First 7 Days Live (daily checklist)

Run every day during the first week.

- [ ] Completed missions count recorded (by service)
  Owner: Ops Lead
  Timing: End of day
  Dependency: ops dashboard / export
  Notes: split rides / Repas / Marché / Envoyer.

- [ ] Failed missions reviewed with reason codes
  Owner: Ops Lead
  Timing: End of day
  Dependency: mission logs
  Notes: failure trends flagged to Tech Lead.

- [ ] Payment review cleared (pending, failed, review-needed → all triaged)
  Owner: Payment Lead
  Timing: End of day
  Dependency: `/admin/payments`
  Notes: zero left in review-needed overnight.

- [ ] Support issues triaged and logged
  Owner: Support Lead
  Timing: End of day
  Dependency: issue catalog
  Notes: no verbal-only resolutions.

- [ ] Merchant delays reviewed (declared vs actual prep)
  Owner: Merchant Lead
  Timing: End of day
  Dependency: order timeline data
  Notes: recalibrate prep times where needed.

- [ ] Courier problems reviewed (no-show, late, complaint)
  Owner: Courier Lead
  Timing: End of day
  Dependency: courier logs
  Notes: 1:1 with any courier flagged twice.

- [ ] Customer complaints reviewed
  Owner: Support Lead
  Timing: End of day
  Dependency: support log
  Notes: pattern → escalate to Founder / Operator.

- [ ] Bug log updated and prioritized
  Owner: Tech Lead
  Timing: End of day
  Dependency: support + ops feeds
  Notes: P0 fixed same day; P1 within 48h.

---

## Phase 5 — First 30 Days Operating Rhythm (weekly checklist)

Run every Monday for the first 4 weeks.

- [ ] Active users count (D1, D7, D30 cohorts)
  Owner: Ops Lead
  Timing: Weekly
  Dependency: analytics
  Notes: track repeat usage.

- [ ] Repeat users count
  Owner: Ops Lead
  Timing: Weekly
  Dependency: analytics
  Notes: leading indicator of trust.

- [ ] Active merchants count + per-merchant order volume
  Owner: Merchant Lead
  Timing: Weekly
  Dependency: merchant dashboard
  Notes: contact merchants with zero orders.

- [ ] Active couriers count + per-courier mission volume
  Owner: Courier Lead
  Timing: Weekly
  Dependency: courier dashboard
  Notes: rebalance shifts if needed.

- [ ] Completed rides volume
  Owner: Ops Lead
  Timing: Weekly
  Dependency: analytics
  Notes: vs previous week.

- [ ] Completed deliveries volume (Repas, Marché, Envoyer)
  Owner: Ops Lead
  Timing: Weekly
  Dependency: analytics
  Notes: split by service.

- [ ] Failed missions rate
  Owner: Ops Lead
  Timing: Weekly
  Dependency: analytics
  Notes: target < 5%.

- [ ] Cancellation rate (customer / courier / merchant)
  Owner: Ops Lead
  Timing: Weekly
  Dependency: analytics
  Notes: investigate any source > 10%.

- [ ] Courier acceptance rate
  Owner: Courier Lead
  Timing: Weekly
  Dependency: courier dashboard
  Notes: target ≥ 80%.

- [ ] Merchant response rate (order acknowledgement time)
  Owner: Merchant Lead
  Timing: Weekly
  Dependency: merchant dashboard
  Notes: target < 2 min ack.

- [ ] Payment pending rate
  Owner: Payment Lead
  Timing: Weekly
  Dependency: `/admin/payments`
  Notes: target near 0% at end of day.

- [ ] Support volume (issues per 100 missions)
  Owner: Support Lead
  Timing: Weekly
  Dependency: support log
  Notes: investigate spikes by category.

---

## Phase 6 — Expand / Pause / Fix Decision

Run at end of Week 4. Decision = Founder / Operator, informed by all leads.

- [ ] All Phase 5 metrics compiled in one review document
  Owner: Ops Lead
  Timing: Day 28
  Dependency: weekly checklists
  Notes: include charts vs targets.

- [ ] Risks reviewed against risk matrix (readiness plan §15)
  Owner: Founder / Operator
  Timing: Day 28
  Dependency: review doc
  Notes: any "High / High" unmitigated → no expand.

- [ ] Decision recorded: Expand / Hold / Pause / Fix
  Owner: Founder / Operator
  Timing: Day 30
  Dependency: review meeting
  Notes: written justification required.

- [ ] If Expand → Phase 3 readiness gate (same district, more users/merchants/couriers) re-run
  Owner: Ops Lead
  Timing: Day 30+
  Dependency: decision
  Notes: do not jump straight to second district.

- [ ] If Pause / Fix → freeze new invites, list root causes, assign owners
  Owner: Tech Lead
  Timing: Day 30
  Dependency: decision
  Notes: re-entry requires fresh Phase 0 + Phase 3 soft launch.

---

## Go / No-Go Checklist (gate to Phase 3 soft launch)

**Go only if ALL true:**

- [ ] Automated tests pass (e2e + unit)
- [ ] All required sandbox scenarios pass
- [ ] Support contact exists and is staffed for operating hours
- [ ] ≥ 10 couriers fully onboarded and trained
- [ ] ≥ 10 merchants fully onboarded with live menus/listings
- [ ] Payment fallback (cash) verified end-to-end
- [ ] Mission dispatch works in pilot district
- [ ] Wallet receipts render correctly for all payment states
- [ ] Rollback / kill-switch plan written and tested

**No-Go if ANY true:**

- [ ] Payment rules unclear to merchants, couriers, or customers
- [ ] Dispatch unstable (missions not reaching couriers reliably)
- [ ] Support unavailable during operating hours
- [ ] Onboarding broken for clients, merchants, or couriers
- [ ] Merchant or courier flow has a known P0/P1 blocker
- [ ] Admin cannot monitor payments, issues, or live ops

_If any No-Go condition is true → stop. Fix. Re-run Phase 0._

---

## Risk Response Checklist

Operator playbook for the most common live issues.

### Payment pending (intent > 10 min unresolved)
- [ ] Owner: Payment Lead. Open `/admin/payments`, filter pending. Confirm provider status. Manual reconcile or expire. Notify user.

### Courier no-show (no pickup after target time)
- [ ] Owner: Courier Lead → Support Lead. Call courier. If unreachable, dispatch backup. Log incident. 2nd no-show → suspend courier pending review.

### Merchant not ready (no ack within target)
- [ ] Owner: Merchant Lead. Call merchant. If unreachable, set merchant offline. Notify customer with apology + option to cancel/refund. Log incident.

### Customer unreachable
- [ ] Owner: Support Lead. Courier retries call (3 attempts, 5 min apart). Support attempts. If still unreachable → mission closed per protocol, courier compensated per cancellation rule.

### Wrong address
- [ ] Owner: Support Lead. Courier → customer call. Update address if reachable. If not reachable → return-to-merchant protocol (Repas/Marché) or close (ride).

### App bug (user-impacting)
- [ ] Owner: Tech Lead. Log in bug tracker. P0 → hotfix same day, consider kill-switch for affected service/district. Notify Support Lead so support has correct messaging.

### Failed payment
- [ ] Owner: Payment Lead. Surface in `/admin/payments` review. Offer cash fallback. Do not credit wallet. Notify user with clear message.

### Package dispute
- [ ] Owner: Support Lead + Admin. Freeze related payout. Collect statements from customer, courier, merchant. Review within 24h. Decision logged. Refund/payout per outcome.

---

## References

- [`WONGO_PILOT_READINESS_PLAN.md`](./WONGO_PILOT_READINESS_PLAN.md) — strategy, scope, metrics, risk matrix
- [`../payments/MOBILE_MONEY_PROVIDER_ONBOARDING.md`](../payments/MOBILE_MONEY_PROVIDER_ONBOARDING.md)
- [`../payments/WONGO_PROVIDER_OUTREACH_PACKET.md`](../payments/WONGO_PROVIDER_OUTREACH_PACKET.md)
- [`../field-testing-conakry.md`](../field-testing-conakry.md)

---

## Support / Issues review (daily)

- Support issues are the operational log for pilot incidents. Review **daily** in `/admin/support` and `/admin/pilot-command`.
- Triage open + escalated issues by district. Critical issues (safety, payment integrity, app-breaking, serious disputes) must be acknowledged within 1h.
- Status / severity / assigned role updates happen only in `/admin/support`. Payment state changes remain in `/admin/payments`.

---

_End of CHOPCHOP Pilot Execution Checklist v1._