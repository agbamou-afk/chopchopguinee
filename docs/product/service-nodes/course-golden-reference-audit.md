# Course (Moto / Bonbonna) — Golden Reference Audit

Node: **Node 0 — Course**
Scope: AUDIT ONLY. No runtime, finance, RLS, flag, or migration change was made.
Head at audit time: `26fe9a7e8658a14124526a39dbb48254fed45030`
Date: 2026-08-12 (UTC)

---

## A. Executive verdict

**REFERENCE WITH GAPS.**

Course is the only CHOPCHOP service with a complete, server-authoritative,
two-actor lifecycle from discovery to receipt, with idempotent accept/complete,
a customer-held pickup secret, canonical cancellation economics, and realtime
state propagation. It is therefore the correct benchmark for every other node.

It is *not* perfect. Three honest defects prevent a clean `REFERENCE` grade:

1. **Client-supplied fare** — `ride_create(p_fare_gnf ...)` accepts the fare the
   client computed from `fare_settings`; the server does not recompute or bound
   it at creation time (`src/pages/Index.tsx:863-872`, `public.ride_create`).
2. **Client-side hold construction** — the pre-authorisation is
   `Math.ceil(trip.fare * 1.1)` in the client (`src/pages/Index.tsx:852`).
   This is exactly the "client-side financial reconstruction" that Slice 7
   banned for balances; it survived here because it predates the ledger revival.
3. **No customer payment-mode selection** — `paymentMethod="wallet"` is
   hardcoded (`src/components/ride/RideBooking.tsx:571`). Cash exists in the
   server model (`_ride_payment_mode`, `driver_mission_commission_capture`)
   but is unreachable from the customer booking UI.

Everything downstream of ride creation (accept, pickup verification, completion,
commission, cancellation) is server-authoritative and idempotent.

---

## B. Current real flow

### Customer
```text
Home tile (PrimaryActionGrid / ServicesView)
  -> RideBooking: pickup pin + destination search (map + place search)
  -> route + fare band (EtaPricePreview, fare_settings, lib/maps/routing)
  -> [no payment selector: wallet hardcoded]
  -> wallet_hold(fare*1.1)  --(client-computed)-->  ride_create(...)
       |-- on ride_create failure: wallet_release; if that fails too ->
           createSupportIssue(payment_pending / high / role=payment)
  -> DriverSearchOverlay (waiting / matching)
  -> RealtimeTripScreen (useRideRealtime on rides) + ActiveTripMap
       - RidePhaseChip derives phase from rides.status + metadata.phase
       - RouteEstimateChip, TrustCues
  -> phase='arrived' -> PickupConfirmCard / RidePickupScanner
       -> ride_confirm_pickup(code)  [customer-only, code held by customer]
  -> in_progress / phase='on_trip'
  -> driver calls ride_complete -> status='completed'
  -> ClientTripReceipt (+ ride_rate)
  -> Activity feed / OrdersView; reopen active ride via "Dernière activité"
  -> cancellation: CancellationConfirmDialog -> ride_cancel -> wallet_release
```

### Driver
```text
DriverSessionProvider
  -> useDriverProfile (status must be 'approved')
  -> driver_set_status('online')  [blocked if cash_debt >= debt_limit]
  -> useIncomingOffers: realtime on ride_offers (driver_id), expires_at > now(),
     polling fallback 5s / 15s low-data, unsubscribes when hidden/offline
  -> IncomingRequestPopup -> driver_offer_accept
       -> internal ride_accept: FOR UPDATE + offer contract +
          UPDATE ... WHERE driver_id IS NULL AND status='pending'
  -> DriverActiveTrip: NavigationHud -> ride_set_phase('arrived')
  -> customer confirms code -> ride_start / phase='on_trip'
  -> navigate to destination -> ride_complete
       - chop_pay: wallet_capture(hold) + commission internal_transfer to master
       - cash: driver_mission_commission_capture, deficit recorded
       - driver_mission_hold_release('ride', ..., 'commission')
       - presence back to 'online', audit_logs row 'ride.settled'
  -> DriverTripReceipt (+ ride_rate); DriverEarningsView; operating balance card
```

### Operations
```text
OrdersAdmin (rides list) | LiveOps + AdminLiveOpsMap | OpsCommandCenter
DriversAdmin (approval/suspension) | DriverSignalsAdmin | DriverCashouts
FinancePolicyAdmin / PricingAdmin / TreasuryAdmin | CancellationDebtPanel
SupportAdmin (support_issues) | AuditAdmin (audit_logs, incl. 'ride.settled')
FlagsAdmin (moto, toktok, om_ride_checkout_enabled, cancellation_policy_enabled)
```

---

## C. Step -> source-of-truth map

| Step | UI | Server truth |
|---|---|---|
| Discovery | `home/PrimaryActionGrid.tsx`, `views/ServicesView.tsx` | `feature_flags` (`moto`, `toktok`) |
| Pickup/destination | `ride/RideBooking.tsx`, `map/DraggablePickupPin.tsx`, `lib/locations/searchPlaces.ts` | `map_places`, `landmarks`, `saved_places` |
| Route / quote | `booking/EtaPricePreview.tsx`, `lib/maps/routing.ts` | `fare_settings`, `map_fare_troncons` (client-side computation) |
| Payment mode | none (hardcoded `wallet`) | `_ride_payment_mode(ride)` |
| Request | `pages/Index.tsx:841-921` | RPC `wallet_hold`, `ride_create` -> `rides` |
| Matching | `booking/DriverSearchOverlay.tsx` | `ride_offers`, `ride_request_dispatch` |
| Offer | `driver/IncomingRequestPopup.tsx`, `hooks/useIncomingOffers.ts` | `ride_offers` (status, expires_at) |
| Accept | `contexts/DriverSessionContext.tsx:215` | RPC `driver_offer_accept` -> internal `ride_accept` |
| Navigation / arrival | `driver/NavigationHud.tsx`, `driver/DriverActiveTrip.tsx` | RPC `ride_set_phase`, `driver_location_signals` |
| Pickup verification | `trip/PickupConfirmCard.tsx`, `trip/RidePickupScanner.tsx` | RPC `ride_confirm_pickup` (`rides.metadata.pickup_code`) |
| Active trip | `trip/RealtimeTripScreen.tsx`, `trip/ActiveTripMap.tsx`, `hooks/useRideRealtime.ts` | `rides` realtime |
| Completion | `driver/DriverActiveTrip.tsx:284` | RPC `ride_complete` |
| Financial finalization | — | `wallet_capture`, `wallet_internal_transfer`, `driver_mission_commission_capture`, `driver_mission_hold_release`, `finance_policy_snapshot`, `ledger_journals` |
| Receipt / activity | `trip/ClientTripReceipt.tsx`, `driver/DriverTripReceipt.tsx`, `lib/activity/useActivityFeed.ts` | `rides`, `wallet_transactions`, `audit_logs` |
| Cancellation | `finance/CancellationConfirmDialog.tsx` | RPC `ride_cancel` -> `_cancellation_compute`, `customer_cancellation_debts` |
| Rating | `ClientTripReceipt.tsx:45`, `DriverTripReceipt.tsx:56`, `tracking/RatingPrompt.tsx` | RPC `ride_rate` -> `ride_ratings` |
| Support | `support/ReportIssueButton.tsx`, `lib/support/issues.ts`, `pages/MyIssues.tsx` | `support_issues` |

---

## D. Evidence classification per step

| Step | Grade | Basis |
|---|---|---|
| Discovery / entry tiles | CODE-VERIFIED + VISUAL-YELLOW | flags `moto`/`toktok` ON; no authenticated visual pass this cycle |
| Pickup selection | CODE-VERIFIED | never substitutes `CONAKRY_FALLBACK` as a real pickup (`RideBooking.tsx:65-67`) |
| Destination selection | CODE-VERIFIED | place search + map pick |
| Quote / fare band | CODE-VERIFIED, **GAP on authority** | computed client-side from `fare_settings`; not server-bounded |
| Payment mode | **GAP** | no selector; wallet hardcoded |
| Request creation | REGRESSION-PROVEN (Slice 13 P1/P2) + CODE-VERIFIED | hold + create + compensating release + support-issue fallback |
| Waiting / matching | CODE-VERIFIED | `DriverSearchOverlay`, dispatch RPC |
| Offer generation / staleness | REGRESSION-PROVEN | expiry enforced in `driver_offer_accept` (`OFFER_EXPIRED`) and filtered client-side |
| Accept (single-winner) | REGRESSION-PROVEN | `FOR UPDATE` + conditional UPDATE + `MISSION_NO_LONGER_AVAILABLE` |
| Driver balance gate | CODE-VERIFIED, flag OFF | `driver_balance_gate_enabled=false` today |
| Arrival / phase | CODE-VERIFIED | `ride_set_phase` |
| Pickup verification | REGRESSION-PROVEN | `ride_confirm_pickup`: customer-only, phase must be `arrived`, wrong code raises |
| Active trip realtime | CODE-VERIFIED + FIELD-YELLOW | realtime path verified; Conakry network behaviour unproven |
| Completion authority | REGRESSION-PROVEN | `ONLY_ASSIGNED_DRIVER_CAN_COMPLETE`, `PICKUP_CONFIRMATION_REQUIRED` |
| Financial finalization | REGRESSION-PROVEN (Slice 13, 507/507) | snapshot-driven commission, no silent overdraft (`SETTLEMENT_REQUIRED_INSUFFICIENT_HOLD`) |
| Receipt / activity | CODE-VERIFIED | receipt renders on `status='completed'` |
| Rating | CODE-VERIFIED | `ride_rate` wired both sides |
| Cancellation | REGRESSION-PROVEN (Slice 8) | canonical `_cancellation_compute` |
| Support / recovery | CODE-VERIFIED | `support_issues` + `/help/issues` |
| Offline / reopen | CODE-VERIFIED + FIELD-YELLOW | polling fallback, reopen from activity |
| Notifications / deep link | CODE-VERIFIED, **push GAP** | in-app + email only; no native push |
| Mobile 390x844 | VISUAL-YELLOW | no fresh authenticated visual pass |
| Live end-to-end two-device | **FIELD-YELLOW** | no live Conakry two-actor run recorded this cycle |

---

## E. Failure / recovery matrix

| Scenario | Behaviour | Grade |
|---|---|---|
| Insufficient driver balance | `driver_mission_hold_place` gate; `driver_balance_gate_enabled` currently OFF -> not enforced in production today | CODE-VERIFIED / flag-gated |
| Duplicate accept (two drivers) | offer contract + row lock + `UPDATE ... WHERE driver_id IS NULL` -> loser gets `MISSION_NO_LONGER_AVAILABLE`; same-driver replay returns the offer idempotently | REGRESSION-PROVEN |
| Stale offer | filtered client-side by `expires_at`; server marks `expired` and raises `OFFER_EXPIRED` | REGRESSION-PROVEN |
| Duplicate completion | `ride_complete` early-returns the completed row, no double capture | REGRESSION-PROVEN |
| Wrong pickup code | `Code de prise en charge invalide`; ride stays pre-pickup, completion still blocked | REGRESSION-PROVEN |
| Cancel before dispatch | `_cancellation_compute` stage `before_dispatch`; hold released | REGRESSION-PROVEN |
| Cancel after dispatch | fee computed from frozen snapshot, captured to master wallet; cash path creates `customer_cancellation_debts` | REGRESSION-PROVEN |
| Customer cancel while `in_progress` | rejected: `ride_in_progress_cancel_not_allowed` | CODE-VERIFIED |
| Driver-caused cancellation | `responsible='driver'`, commission hold released, no customer fee | CODE-VERIFIED |
| Provider/platform-caused | admin cancel -> `responsible='platform'` | CODE-VERIFIED |
| Hold created but ride_create fails | compensating `wallet_release`; if release also fails -> high-severity `support_issues` row | CODE-VERIFIED (good pattern) |
| Offline / reconnect | `useConnectionRestored`, offer polling fallback, ride reopenable from activity | CODE-VERIFIED / FIELD-YELLOW |
| GPS denied | map centres on Conakry fallback but pickup is never auto-filled; `PermissionCenter` explains | CODE-VERIFIED |
| Route service failure | `routeError` state + fare band still shown from `fare_settings` | CODE-VERIFIED |
| Session restart (driver) | `DriverSessionContext` restores active ride from `rides` (`status in pending,in_progress`) | CODE-VERIFIED |
| Session restart (customer) | reopen via "Dernière activité" -> `ActiveRideTile` | CODE-VERIFIED |
| Support escalation | `ReportIssueButton` / `createSupportIssue` -> `SupportAdmin` | CODE-VERIFIED |

---

## F. Strengths worth copying to every other node

1. **Two-party secret**: the pickup code lives with the customer; only the
   customer can burn it. Completion is blocked until it is burned.
2. **Server-only state transitions**: `rides` exposes SELECT-only RLS
   (`Clients view own rides`, `Drivers view assigned rides`, `Admins view all`);
   every mutation is a `SECURITY DEFINER` RPC.
3. **Idempotent-by-construction**: replay of accept/complete/cancel is inert.
4. **Snapshot economics**: `finance_policy_snapshot` frozen on the mission;
   cancellation and completion re-derive from the same snapshot.
5. **No fake success**: `SETTLEMENT_REQUIRED_INSUFFICIENT_HOLD` refuses to
   pretend a partial settlement succeeded.
6. **Compensating action + support issue** when a money step half-fails.
7. **Degrading transport**: realtime -> polling -> low-data polling; unsubscribe
   when hidden/offline.
8. **Reopenable mission**: closing the trip screen never abandons the mission.
9. **Audit provenance**: `audit_logs` `ride.settled` / `ride.settled.admin_override`.

## G. Course quirks that must NOT become universal requirements

- **Pickup code / QR** — meaningful for ride and package custody; nonsense for
  a Marché browse session or a pickup-only Repas order.
- **Presence toggle (`online`/`on_trip`)** — supply model for drivers only;
  merchants have opening hours, not presence.
- **Offer fan-out with expiry** — dispatch concept; commerce nodes accept
  orders, they are not offered them.
- **`fare*1.1` pre-authorisation hold** — a ride-specific legacy artefact, and
  itself a defect (see H1). Do not replicate.
- **Single mission per driver** — Course assumes one active trip; delivery
  batching nodes may not.
- **Full-screen takeover trip UI** — appropriate for navigation, not for
  commerce nodes where browsing must continue.

## H. Genuine remaining Course gaps (NOT fixed in Node 0)

| ID | Gap | Severity |
|---|---|---|
| CRS-G1 | `ride_create` trusts the client-supplied `p_fare_gnf`; no server recompute/bounding | P1 (finance authority) |
| CRS-G2 | Hold amount `fare*1.1` computed in the client | P1 (client-side financial reconstruction) |
| CRS-G3 | No customer payment-mode selector; cash unreachable from the ride booking UI | P1 (product completeness) |
| CRS-G4 | Fare band is computed client-side from `fare_settings`; no server quote RPC | P2 |
| CRS-G5 | No native push; trip alerts rely on in-app/foreground state | P2 (Android node) |
| CRS-G6 | No driver no-show flow for the customer (only cancel) | P2 |
| CRS-G7 | No persisted "recent destinations"; only `saved_places` | P3 (engagement) |
| CRS-G8 | `PromoCarousel` is hardcoded marketing, not a promo engine | P3 (must not be presented as a feature) |
| CRS-G9 | Weak-GPS accuracy is recorded but never surfaced to the driver as degraded mode | P3 |
| CRS-G10 | No fresh authenticated visual QA at 390x844; no live two-device Conakry run | VISUAL-YELLOW / FIELD-YELLOW |
| CRS-G11 | `driver_balance_gate_enabled` OFF: the eligibility gate exists but is not live | Documented, intentional (staged activation) |

### Engagement honesty classification
- **Required transactional completeness**: PRESENT (discover -> receipt).
- **Operational completeness**: PRESENT (admin visibility, audit, support, cancellation debt).
- **Engagement/retention layer**: PARTIAL. Saved places PRESENT, ratings PRESENT,
  activity/receipts PRESENT, predictable pricing PARTIAL (band, client-side),
  trust cues PRESENT. Recent places GAP, promos GAP (fake UI), loyalty/referral
  for riders FUTURE, favourite driver FUTURE.
