# Day 5 — Driver System & Operational Flow

Goal: turn driver mode into a real operational tool — role-gated, onboarded, approvable, live-trackable, with trip lifecycle, earnings, cash-commission tracking, support, and live admin oversight. No design overhaul, no auth/wallet rewrites.

## Current state (from earlier days)
- `driver_locations` table exists with RLS (drivers upsert own; clients see assigned driver; admins see all).
- `rides` table + `ride_create / ride_accept / ride_complete / ride_cancel` RPCs already wired.
- Wallet + commission split already happen inside `ride_complete` (1500 bps to master).
- `useAuth.isAdmin` + `can_manage_operations(_user_id)` already exist.
- `DriverHome` exists but is mostly mock; no application flow, no incoming-request popup, no trip lifecycle, no earnings page beyond a stub.
- No `driver_profiles`, `driver_applications`, `driver_cash_ledger`, `ride_offers` tables yet.

## Phases (each phase is one approval gate)

### Phase 1 — Database foundations (single migration)
- `app_role` already has `driver`. Add new tables:
  - `driver_profiles` (user_id PK, status enum: pending/approved/rejected/suspended, vehicle_type enum: moto/toktok/livraison, plate, photo_url, id_doc_url, vehicle_photo_url, zones text[], rating numeric, accept_rate numeric, cash_debt_gnf bigint, debt_limit_gnf bigint, last_seen_at, approved_at, approved_by, rejected_reason, suspended_reason).
  - `driver_applications` (history of submissions; one driver can re-apply).
  - `ride_offers` (ride_id, driver_id, status enum: pending/accepted/declined/missed/expired, sent_at, responded_at, expires_at) — for incoming-request flow + accept/decline telemetry.
  - `driver_cash_ledger` (driver_id, ride_id, cash_collected_gnf, commission_owed_gnf, settled_at).
- RPCs:
  - `driver_apply(payload jsonb)` — creates/updates pending application + driver_profiles row with status=pending.
  - `driver_admin_decide(p_user_id, p_decision, p_reason)` — approve/reject/suspend; on approve grants `driver` role + creates driver wallet via `wallet_ensure('driver')`. Restricted to `god_admin` / `operations_admin`.
  - `driver_set_status(p_status)` — driver toggles online/offline; gates on approved + not suspended + cash_debt < limit.
  - `driver_offer_accept(p_offer_id)` / `driver_offer_decline(p_offer_id, p_reason)` — wraps `ride_accept` and updates offer row.
  - `driver_cash_settle(p_driver_id, p_amount_gnf)` — admin-only, decrements cash_debt and posts wallet entry.
- RLS: drivers RW their own row; admins (ops/god) full; clients only read approved+online location through existing policy.

### Phase 2 — Driver onboarding flow (frontend)
- New `/driver/apply` route with 6-step wizard: personal info → vehicle type → vehicle details → docs upload (Storage bucket `driver-docs` private) → zones → review/submit.
- Calls `driver_apply` RPC.
- Reusable `useDriverProfile()` hook returning {status, profile, refetch}.
- `BecomeDriverCTA` shown on profile + driver-mode toggle when no driver role.
- Status banner: "Votre demande est en cours de vérification." / rejected reason / suspended.

### Phase 3 — Driver mode gating + DriverHome rebuild
- Replace toggle in `AppHeader` so switching to driver mode requires `useDriverProfile().status === 'approved'`. If not, route to `/driver/apply`.
- `DriverHome` sections:
  - Status header (online/offline switch, daily earnings, wallet balance).
  - KPI grid (Aujourd'hui / Courses / Heures / Acceptation / Note).
  - Quick actions (Mes courses, Mes revenus, Support, Profil chauffeur).
  - Application-status card if not approved.
- Skeleton + empty + error states everywhere.

### Phase 4 — Online lifecycle + location updates + incoming requests
- `useDriverPresence()` hook:
  - Throttled `navigator.geolocation.watchPosition` (every 8 s, or 3 s on active trip).
  - Pauses on `document.hidden`, offline, or low-data mode (unless on_trip).
  - Upserts `driver_locations` and updates `driver_profiles.last_seen_at`.
- Realtime subscription on `ride_offers` filtered by `driver_id = me`.
- `IncomingRequestPopup`: service type, pickup/dest zone, fare estimate, driver earning (fare × (1-1500bps)), distance, 20 s countdown, big Accept / Decline.
  - Accept → `driver_offer_accept` → `DriverTripView`.
  - Decline → `driver_offer_decline`.
  - Timeout → marks `missed`.

### Phase 5 — Trip lifecycle + earnings + cash commission
- `DriverTripView` with state machine for moto and livraison (call client, open route via `geo:` URL, report issue, cancel-with-reason).
- `useDriverEarnings()` aggregates today/week from `wallet_transactions` + `rides` + `driver_cash_ledger`.
- `DriverEarningsView` shows today / week / wallet / cash collected / commission owed / payouts pending / completed rides.
- Cash-commission gate in `driver_set_status`: if `cash_debt_gnf >= debt_limit_gnf`, refuse going online and show warning toast.

### Phase 6 — Admin tools, notifications, analytics, mobile QA
- `Admin → Drivers`:
  - Tabs: Pending applications / Approved / Suspended / All.
  - Live operations panel: online / on_trip / offline counts, last-seen timestamps, cash debt column, suspend/reactivate actions, manual assign (later — out of scope, just wire the button to a stub).
- Notifications: insert into existing `notification_log` for application submitted / approved / rejected / suspended / missed request / commission warning. WhatsApp + push deferred (just rows in log).
- Analytics: register all `driver.*` events in `eventTaxonomy.ts` and emit from the relevant components.
- Driver support: pre-fills `support_messages` with tag in metadata `{ category: 'driver_support', kind }`.
- Mobile QA at 390×844: online toggle thumb-reachable, IncomingRequestPopup buttons ≥ 56 px, trip view padding-bottom 28, no horizontal overflow.

## Out of scope (explicit, to keep scope honest)
- WhatsApp / push delivery infra (just notification_log entries for now).
- "Auto" vehicle type (column accepts it but UI does not show it).
- Manual ride reassignment from admin (UI shell only).
- Driver document OCR / KYC integration.

## Approval ask
This plan touches DB structure (Phase 1) and a lot of frontend. Please confirm and I'll proceed phase by phase, pausing after each migration / major UI surface for a quick check.
