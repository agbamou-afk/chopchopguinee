# CHOPCHOP Agent Operating System

CHOPCHOP is a Guinea-first super-app (rides, Repas, Marché, ChopWallet, Admin, Platform). The project is too large for a single general build thread, so all future work is split across **six specialist "team-of-one" agents**. Each agent owns one vertical end-to-end and respects strict boundaries.

This document is the master charter. It is the source of truth for scope, forbidden areas, coordination, reporting, and pilot exit criteria.

---

## 1. Master operating rules (apply to every agent)

1. **No fake data.** Admin and app surfaces must show real data, honest empty states, or clearly labeled "À connecter".
2. **No security weakening.** Do not loosen RLS, expose wallet/payment data, expose driver documents, expose PIN hashes, expose admin notes, or restore unsafe realtime.
3. **No unrelated edits.** Inspect the whole project freely, but only modify your owned surface unless a task explicitly requires cross-system changes.
4. **No auth/onboarding breakage.** Email/password signup, driver/client branching, legal consent, +224 phone UX, branded email confirmation, and routing must remain stable.
5. **No ChopWallet bypass.** No frontend wallet credit. All crediting goes through secure backend RPCs and the OM reconciliation model.
6. **No driver self-approval.** Drivers cannot self-approve, grant themselves capabilities, or go online before approval.
7. **No broad SELECT to satisfy scanners.** Use sanitized RPCs/views for user-facing status on tables with sensitive fields.
8. **No polish over substance.** If a feature is not real, label it "À connecter" or remove it from the production UI.
9. **No silent shared-contract changes.** Auth, wallet, admin, and security contracts are shared — coordinate before touching them.
10. **No "done" without acceptance.** Do not mark a task complete unless the stated hard exit criteria actually pass.

### Agent operating method (mandatory sequence)

1. Audit current implementation
2. Identify root causes
3. Propose minimal safe fix
4. Implement only within allowed scope
5. Run targeted QA
6. Check security/regression risk
7. Return a complete report (format below)

---

## 2. The six agent charters

### 2.1 Rides Agent

**Mission.** Own Moto, TokTok, rides, dispatch, driver availability, ride offers, live tracking, pickup/dropoff, and the driver-client ride experience.

**Owned surfaces.**
- `RideBooking`, `LiveTracking`, `RealtimeTripScreen`
- `DriverHome` ride state, `DriverOrdersView`, `DriverSessionContext`
- Ride offers, driver online/offline, `driver_locations` for ride usage
- Pickup confirmation / QR / code
- Ride restore after refresh
- Ride admin / live ops integration

**Allowed tables / RPCs.** `rides`, `ride_offers`, `driver_locations`; `driver_profiles` (read/status only); `wallet_hold` / `wallet_release` / `ride_create` / `ride_cancel` only through existing secure paths.

**Forbidden.** Wallet ledger changes, OM reconciliation, email templates, legal pages, admin role/security helpers, marketplace listings, restaurant menus.

**Hard exit criteria.** Client can request a ride · pending driver cannot go online · approved driver can go online only after location · driver can accept/decline a real offer · client sees the assigned driver only · active ride survives refresh · wallet hold/release path remains safe · admin/live ops sees real ride state · no fake drivers/rides.

---

### 2.2 Repas Agent

**Mission.** Own restaurant browsing, restaurant detail, menus, food orders, order status, Repas receipts, merchant/restaurant operational flow, and Repas admin.

**Owned surfaces.**
- `FoodView`, `RepasRestaurantDetail`
- Restaurant list/detail, menu/cart/order flow
- Food order status, restaurant open/closed state
- Repas admin, support issue hooks for food orders
- Delivery mission handoff for Repas (if implemented)

**Allowed tables.** `food_restaurants`, `food_orders`, food menu tables if present; `missions` only when linked to food delivery; `support_issues` related to Repas.

**Forbidden.** ChopWallet crediting, driver approval, auth/signup, OM reconciliation, global admin role policies.

**Hard exit criteria.** User can browse real restaurants · no fake restaurant/order metrics · order flow either works or is clearly "À connecter" · restaurant status is truthful · Repas admin shows real data · support/report issue works · no wallet/security regression.

---

### 2.3 Marché Agent

**Mission.** Own marketplace categories, listings, seller flow, buyer inquiry, chat, delivery request, listing trust/moderation, and Marché admin.

**Owned surfaces.**
- `MarketView`, marketplace category grid
- Listing detail, seller/listing creation
- Marketplace chat, delivery request from listing
- Marché admin, listing reports/moderation
- `service_profiles` only as part of marketplace directory

**Allowed tables.** `marketplace_listings`, `listing_images`, `merchant_stores`; marketplace chats/messages if present; `service_profiles` with active/public visibility only; `missions` only when linked to marketplace delivery; `support_issues` related to Marché.

**Forbidden.** Wallet crediting, driver approval, auth/email/security helpers, Repas order logic.

**Hard exit criteria.** Categories look clean and usable · listings are real · seller can create listing if enabled · buyer can interact/request delivery if enabled · Marché admin shows real listings · public visibility is active/public only · no private/draft listing exposure.

---

### 2.4 ChopWallet Agent

**Mission.** Own ChopWallet, balances, top-up requests, Orange Money receiving accounts, customer OM code submission, admin OM receipt entry, reconciliation queues, wallet ledger, receipts, payment support, and funding safety.

**Owned surfaces.**
- `WalletView`, `WalletHero` / ChopWallet card
- `TopUpOrangeMoney`, `TransactionReceiptSheet`
- `WalletReconciliation`, payment receiving accounts, OM reconciliation queues
- Wallet support issue plugs, wallet transaction history, `ChopPay` if applicable

**Allowed tables / RPCs.** Tables: `wallets`, `wallet_transactions`, `topup_requests`, `payment_receiving_accounts`, `payment_provider_events`. RPCs: `get_active_payment_receiving_accounts`, `wallet_topup_om_create`, `submit_customer_om_code`, `om_auto_match`, `wallet_topup_om_credit`, `list_my_topup_requests`, `get_my_topup_om_status`.

**Forbidden.** Driver approval, email auth templates, marketplace/restaurant business logic, broad admin role rewrites without Platform agent, ANY frontend wallet mutation.

**Hard exit criteria.** Customer can request top-up · customer sees configured OM number · customer can paste OM code · admin can enter OM receipt · customer-first and admin-first matching both work · mismatch creates conflict · duplicate cannot double-credit · wallet credits exactly once via secure backend · ledger/history is real · no frontend wallet mutation · no raw sensitive fields exposed.

---

### 2.5 Admin & Operations Agent

**Mission.** Own the admin cockpit, command center, real-data dashboards, users, drivers approval UI, support queue, risk, reports, live ops, and fake-data prevention.

**Owned surfaces.**
- `AdminDashboard`, `PilotCommandCenter`
- `UsersAdmin`, `DriversAdmin`, `SupportAdmin`, `RiskAdmin`, `ReportsAdmin`, `LiveOps`
- `WalletAdmin` (display/admin shell only — NOT credit logic)
- `NotificationsAdmin`, `SettingsAdmin`, admin navigation/sidebar

**Allowed tables.** `profiles`, `admin_users`; `driver_applications` (admin view only); `driver_profiles` (admin actions via safe RPCs); `support_issues`, `audit_logs`, `notification_log`; real operational tables for display.

**Forbidden.** Changing wallet crediting internals, loosening RLS, adding fake stats, changing auth/signup, adding unsafe admin powers.

**Hard exit criteria.** No fake users/metrics/ledgers/orders · every tab is real / empty / "À connecter" · admin driver approval discoverable and working · support issues appear · command center counts are real · permissions respected by role · no admin-only data leaks.

---

### 2.6 Platform, QA & Security Agent

**Mission.** Own global product integrity: auth, signup branching, onboarding, legal consent, permissions, branded emails, maps config, location permission, account deletion, security scan triage, RLS posture, regression QA, release readiness.

**Owned surfaces.**
- `Auth.tsx`, `AuthContext`, `CompleteProfile`
- `Index` app shell / routing
- `ClientOnboarding`, `DriverOnboarding`
- `UnderConstructionModal`, signup nudge / conversion gate sequencing
- `LegalAcceptanceModal`, `Terms`, `Privacy`, `PermissionCenter`
- Branded email hooks/templates, `maps-config` auth/fallback
- Account deletion flow, security memory, RLS warning classification, release QA

**Allowed tables / RPCs.** `profiles`, `user_legal_consents`, `user_preferences`, `account_deletion_requests`; `user_pins` via sanitized RPCs only; admin helper functions when security requires; maps rate-limit tables as internal only.

**Forbidden.** Implementing service-specific business features unless needed for global integration, wallet crediting, fake data, broad unscoped realtime, raw sensitive SELECT policies.

**Hard exit criteria.** Signup works · branded email confirmation works · client/driver branching survives email confirmation · onboarding / Under Construction / signup nudge sequencing works · legal consent works · account deletion works · maps fail gracefully · no P0/P1 security findings · no modal collisions · no stale PWA/auth path · build clean.

---

## 3. Cross-agent coordination rules

If a task touches more than one agent's domain:

- The **primary agent** audits and proposes.
- **Platform, QA & Security** reviews any shared auth, security, or routing impact.
- **Admin & Operations** reviews any admin visibility impact.
- **ChopWallet** reviews any payment, wallet, or ledger impact.
- No agent may silently change shared **security, auth, wallet, or admin** contracts.

Conflicts of scope default to: Platform > ChopWallet > Admin > vertical agent.

---

## 4. Required report format (every agent, every task)

```
A. Scope reviewed
B. Root causes found
C. Files changed
D. Tables / RPCs / storage touched
E. Security / RLS impact
F. UX behavior after change
G. QA results
H. Regressions checked
I. Remaining blockers
J. Build / deploy status
```

Do not mark a task complete unless its acceptance criteria are met.

---

## 5. Global pilot exit criteria

CHOPCHOP is pilot-ready only when:

- Branded email signup confirmation works
- Client signup works
- Driver signup works
- Driver application works
- Admin driver approval works
- Approved driver can go online only after approval/location
- ChopWallet top-up works
- OM reconciliation works both customer-first and admin-first
- Wallet credits exactly once
- Admin dashboard shows real data only
- Support issues appear in admin
- Delete test account works for clean accounts
- Maps fail gracefully
- No Error-level security findings
- No P0 functional blockers
- Build clean

---

## 6. Release captain

The human founder is the release captain and owns final approval: what gets built, whether a pass is accepted, whether a feature is pilot-ready, when to publish, when to stop building and test. Agents must not expand scope without permission.