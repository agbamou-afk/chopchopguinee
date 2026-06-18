---
name: Product Critical Path Audit — Production Launch Readiness
description: Whole-product RED/YELLOW/GREEN readiness board (app shell, client, driver, merchant, Repas, Marché, wallet, support, maps, admin, RLS, mobile). No code changes, audit-only.
type: feature
---

# product-critical-path-audit-stable

Locked 2026-06-18. Audit-only pass. **No features added, no wallet
logic touched, no pricing changed, no RLS modified.** Findings are
classified RED / YELLOW / GREEN / DEFER against mission launch.

---

## A. Executive Summary

CHOPCHOP is past MVP. The locked subsystems (CHOP Maps pilot,
Marché merchant branch, Repas merchant dashboard, Repas order
messaging, driver signals, degraded map behavior, Repas vendor
routing) form a coherent product spine. The critical path —
client requests Moto → wallet hold → driver accepts → completes →
rates — is functional; the secondary paths (Marché shop discovery,
Repas order placement, merchant fulfillment, admin triage) are
functional with operator workarounds.

**Launch posture: conditionally launchable** once the RED items
below are closed. Most YELLOW items are acceptable with an operator
playbook and clear in-app messaging.

---

## B. RED — Launch Blockers

1. **Mobile-money top-up is operator-mediated only.** `topup_requests`
   + admin OM reconciliation queues are live; no live PSP webhook
   trust path beyond `payment-webhook-orange-money` scaffolding. Users
   MUST be told top-ups are reviewed manually before launch copy goes
   live. *(Owner: ChopWallet + Platform)*
2. **Wallet hold release on ride cancel.** Existing support-issue
   fallback on release failure protects the user, but there is no
   automated retry job; an operator must drain the queue. Document
   SLA + on-call before launch. *(Owner: ChopWallet + Admin Ops)*
3. **Driver supply in pilot zone.** "Aucun chauffeur proche" is the
   dominant client state in current sessions (see session replay).
   Not a code bug — a launch-readiness blocker for the pilot
   district. Field/Captain onboarding must seed N≥10 approved,
   online drivers in the launch polygon before go-live.
4. **Auto-confirm email path.** Confirm `auth-email-hook` branded
   templates render in production SMTP (not just preview). One
   misroute = no signup. *(Owner: Platform)*

## C. YELLOW — Launch Cautions

- **Repas live owner smoke** not yet executed end-to-end with a real
  restaurant account — `repas-vendor-dashboard-routing-stable`
  unblocked the dashboard; need one real signup → menu → order →
  message → courier handoff dry run before opening Repas publicly.
- **Mixed merchant (store + restaurant) layout** renders Marché tabs
  with Repas sections beneath. Acceptable; document for ops so
  mixed merchants are trained, not surprised.
- **Marché distance sorting** depends on user geolocation; fallback
  to alphabetical when permission denied is in place but the empty
  "Activez la localisation" CTA copy should be reviewed.
- **Degraded map panel** covers tile/provider failure and low-data;
  ride lifecycle continues to work without map, but the driver
  pickup-confirm UX in zero-tile mode is text-only — train field ops.
- **Realtime subscription count** on driver active screen (rides,
  signals, offers) is acceptable but should be re-measured on a
  low-end Android before launch (`useMapPerfMonitor`).
- **Account deletion** is implemented (locked previously) but the
  legal copy in `Privacy`/`Terms` should be re-read post-Repas/Marché
  additions to confirm scope statements are still accurate.
- **Mode toggle parity** for Repas-only merchants was just fixed via
  `useSwitchAppMode`. Needs one manual QA pass per device class.

## D. GREEN — Ready Systems

- App shell routing (`Index.tsx`, `MerchantHub.tsx`,
  `useAppMode`/`useSwitchAppMode` with session override + `?mode=`
  URL hint) — merchant→client bounce-back race resolved for both
  Marché and Repas branches.
- CHOP Maps pilot stack (Phases 2A–2H + 2L): config, degraded panel,
  driver signals (admin-only), route observations (admin-only),
  merchant location submission, field captain tools, offline drafts.
- Marché merchant branch: listing image pipeline, shop discovery
  (category chips, sample photos), distance sort, buyer↔merchant
  messaging.
- Repas merchant dashboard: menu CRUD + photos, restaurant profile
  (logo/cover/prep/delivery), itemized order detail, order
  messaging UI surfaces (`OrderMessagingPanel` on client, restaurant,
  courier).
- Onboarding/signup branching, legal consent gate, Under Construction
  modal sequencing, branded transactional emails registry.
- Admin cockpit honesty: every tab is real data, honest empty state,
  or "À connecter" — no fake metrics (per admin-real-data-purge lock).
- Driver location signals + service-flow route observation (no
  pricing impact, admin-only trust).
- Guinea phone normalization (+224) across signup, profiles, OM.

## E. DEFER — Post-Launch

- Service-worker background sync for field drafts.
- Offline tile cache / offline media queue.
- Automated wallet hold release retry worker.
- Live PSP trust path (Orange Money / Wave) with webhook signature
  verification + automatic top-up credit.
- Driver auto-promotion of observed routes to trusted.
- Repas analytics dashboard for vendors.
- Marché bargaining counters surfaced in merchant inbox.
- Pilot health panel (operational dashboard for field ops).
- Real-time push notifications (currently in-app + email only).

## F. Role-by-Role Readiness

| Role            | Status   | Notes |
|-----------------|----------|-------|
| Public visitor  | GREEN    | Public storefront + onboarding gated correctly. |
| Client          | YELLOW   | Blocked end-to-end only by driver supply (RED #3) and top-up clarity (RED #1). |
| Driver (Moto)   | YELLOW   | Lifecycle is solid; needs field-seeded approved drivers + map-degraded training. |
| Marché merchant | GREEN    | Locked branch readiness. |
| Repas vendor    | YELLOW   | Dashboard ready; needs one live owner smoke before public toggle. |
| Hybrid merchant | YELLOW   | Works; document layout for ops. |
| Admin / Ops     | GREEN    | Honest admin, real queues, OM reconciliation live. |
| Field captain   | GREEN    | Pilot tools locked. |

## G. Critical Path Smoke Test (Pre-Launch)

1. New email signup → branded confirm email → complete profile →
   legal consent → lands on client home.
2. Client requests Moto in pilot zone → wallet hold created →
   driver accepts → pickup → drop → rating recorded. Verify
   `support_issues` empty for happy path.
3. Client cancels mid-search → wallet hold released → balance
   restored. If release fails → support_issue auto-filed.
4. Marché: browse → distance-sorted shops → open shop → message
   merchant → merchant replies from MerchantHub.
5. Repas: client orders → restaurant receives in dashboard →
   accepts → courier assigned → client/restaurant/courier exchange
   messages via `OrderMessagingPanel` → delivered.
6. Merchant signup as Repas-only → lands on Repas dashboard (Menu /
   Restaurant tabs, not Catalogue) → toggle to client mode → toggle
   back → no bounce.
7. Merchant signup as Marché-only → lands on Marché dashboard →
   toggle parity verified.
8. Driver online in client mode → receives no offers. Driver online
   in driver mode → receives offers; offline → none.
9. Force low-data mode → DegradedMapPanel shown on active ride /
   active mission, lifecycle still completes.
10. Admin opens OM reconciliation queue, approves a top-up request,
    customer wallet credits, audit log written.
11. Admin approves a pending driver → driver receives branded
    approval email → driver can go online.
12. Account deletion request from user → confirmation → financial
    history anonymized, profile purged.

## H. Security / RLS Findings

- `driver_location_signals`, `map_route_observations`,
  `driver_route_traces` — admin/owner only. Verified.
- `food_order_threads` / `food_order_messages` — participant-scoped
  (client, restaurant owner, assigned courier). Verified via
  `commerce-closing-patch-stable` migration.
- `marketplace_listings` + `listing_images` — public listings only,
  owner writes. Verified.
- `merchant_stores`, `food_restaurants` — owner-scoped writes,
  public reads of active rows only.
- `user_pins` — accessed only via sanitized RPC. Verified.
- `wallet_transactions`, `wallets` — owner-scoped read; writes via
  security-definer credit RPCs. **No client write surface.**
- Frontend secret audit: `rg "SERVICE_ROLE|PRIVATE_KEY|SECRET" src/`
  expected clean (re-run pre-launch).
- No findings warrant RLS modification in this pass.

## I. Wallet / Payment Truth Table

| Surface              | Live | Stubbed | Operator-assisted | Notes |
|----------------------|:----:|:-------:|:-----------------:|-------|
| Ride wallet hold     | ✅   |         |                   | Hold + release + support-issue fallback. |
| Ride completion debit| ✅   |         |                   | Via security-definer RPC. |
| Top-up (OM manual)   |      |         | ✅                | Admin reconciliation queues. |
| Top-up (OM auto)     |      | ✅      |                   | Webhook scaffolded, not trusted. |
| Repas payment        |      |         | ✅                | Display-only; cash on delivery or wallet. |
| Marché payment       |      |         | ✅                | Buyer/merchant arrange; no in-app charge. |
| Driver settlement    |      |         | ✅                | Cash ledger + admin reconciliation. |
| P2P transfer         | ✅   |         |                   | Sender/receiver RLS verified. |

**Launch copy MUST NOT claim instant mobile-money credit.**

## J. Support / Recovery

- Entrypoints present from: ride active screen, wallet errors, Repas
  order detail, Marché listing, merchant hub, driver active mission,
  map failure (via degraded panel "Signaler"). Admin
  `SupportAdmin` surfaces all issues with metadata.
- Auto-filed `support_issues` on wallet hold release failure
  (verified). No silent failure observed in critical path.

## K. Files Inspected (representative)

- `src/pages/Index.tsx`, `src/pages/Auth.tsx`, `src/pages/CompleteProfile.tsx`
- `src/components/merchant/MerchantHub.tsx`, `src/components/merchant/ModeToggle.tsx`
- `src/hooks/useAppMode.ts`, `src/hooks/useMerchantIdentity.ts`
- `src/components/map/ChopMap.tsx`, `src/components/map/DegradedMapPanel.tsx`
- `src/components/repas/OrderMessagingPanel.tsx`,
  `src/components/merchant/repas/*`
- `src/lib/repas/orderMessaging.ts`, `src/lib/marche/stores.ts`
- `src/pages/MerchantOnboarding.tsx`
- `supabase/migrations/20260618032116_*.sql` (Repas order messaging RLS)
- Locked milestone docs under `.lovable/memory/milestones/`
- `docs/maps/pilot/CHOPMAP_*` (pilot launch bundle)

## L. Recommended Execution Order

1. Close RED #4 (auth email path) — verify production SMTP delivery.
2. Close RED #1 (top-up copy) — adjust customer-facing wallet/top-up
   wording to state manual review SLA.
3. Close RED #3 (driver supply) — field captain onboarding drive in
   pilot polygon.
4. Run smoke G.1–G.12 on a real device (low-end Android + iOS).
5. Document operator playbook for RED #2 (wallet release queue
   drain) and YELLOW top-up reconciliation.
6. Execute Repas live owner smoke (YELLOW).
7. Re-run security scan; triage any new findings.
8. Lock this milestone; tag release candidate.

## M. Build / Deploy Status

No code changes in this audit pass. Build status inherits from the
last green state of `repas-vendor-dashboard-routing-stable`.

## N. Lock Recommendation

**Lock `product-critical-path-audit-stable`** as the authoritative
pre-launch readiness board. Re-open only when a RED item changes
state or a new vertical is added.