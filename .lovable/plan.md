# CHOPCHOP Launch Readiness Plan

Last updated: 2026-05-30

## Locked milestones (stable, do not regress)

- `chopchop-store-readiness-stable` (2026-05-28)
- `chopchop-guinea-phone-input-stable` (2026-05-30)
- `chopchop-om-receiving-accounts-stable` (2026-05-30)
- `chopchop-om-two-sided-reconciliation-queue-stable` (2026-05-30)
- `chopchop-admin-real-data-purge-stable` (2026-05-30)

## What each milestone guarantees

### Store Readiness
Onboarding/signup/ConversionGate verified, images optimized 92%, store foundation in place (account deletion, debug gating, docs).

### Guinea Phone Input
+224 prefilled signup phone, shared normalization helpers, profiles stored as +224XXXXXXXXX.

### OM Receiving Accounts
Admin-configured OM receiving accounts, sanitized customer RPC, topup_requests linked to account.

### OM Two-Sided Reconciliation Queue
Admin Reconciliation OM UI exposes 5 operational queues (Demandes, Codes clients, Reçus en attente, Réconciliés, Conflits) + Comptes OM + Import CSV. Manual receipt form prefills from customer-code queue. Exact match auto-credits wallet. Conflicts go to review queue. Duplicates cannot double-credit.

### Admin Real Data Purge
All fake/mock/demo data removed from admin UI. Replaced with real Supabase queries, honest empty states, or "À connecter" placeholders across Users, Merchants, Orders, Repas, Marché, Zones, Risk, Promotions, and Settings tabs.

## Remaining launch blockers (TODO)

### Security scan warnings (3)
1. **ADMIN_ROLE_INCONSISTENCY** — `is_admin()` checks `admin_users` while `is_any_admin()` checks `user_roles`. Standardize to single source of truth.
2. **MISSING_REALTIME_CHANNEL_SCOPING** — Realtime NULL topic branch may allow broadcast channel leakage.
3. **MISSING_RLS_PROTECTION** — Verify agent_profiles users do not hold `admin` role, else they can read raw confirmation_code values.

### Ops / infra
- Domain email verification `notify.chopchopguinee.com` (DNS pending)
- SMS / Twilio configuration
- Realtime financial events stay off (polling only) — confirm no regressions

## Build rule
Never degrade a locked milestone. Each new pass must leave all prior milestones intact.
