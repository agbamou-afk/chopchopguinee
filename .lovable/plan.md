
# CHOP CHOP — Admin Dashboard Architecture (Phase 1: Scaffold)

This phase delivers the skeleton: data model, RBAC, layout, navigation, routing, and placeholder pages for all 20 modules. Functional logic for each module ships in later phases. **No changes to the public app UI.**

## Goals

- 3-tier admin RBAC enforced in DB (RLS) and UI (route guards + permission map)
- One scalable `AdminLayout` with collapsible sidebar, topbar, and breadcrumbs
- All 20 modules accessible via `/admin/*` routes with placeholder pages that already render headers, empty states, and access-gated controls
- Audit log + approval-request tables ready to be written to from any future action
- Existing `/admin` page (fares + agents) preserved and folded into the new shell

---

## 1. Data Model (migration)

**New enum**: `admin_role` = `super_admin | ops_admin | finance_admin` (separate from existing `app_role` so we don't break anything; the existing `admin` role auto-maps to `super_admin` initially).

**New tables** (all RLS-protected, only `super_admin` can write):

- `admin_users` — `user_id`, `admin_role`, `status` (active/suspended), `created_by`, `notes`
- `audit_logs` — `actor_user_id`, `actor_role`, `action`, `module`, `target_type`, `target_id`, `before` jsonb, `after` jsonb, `ip`, `user_agent`, `note`, `created_at`
- `approval_requests` — `requested_by`, `requested_role`, `action`, `module`, `payload` jsonb, `status` (pending/approved/rejected), `reviewed_by`, `review_note`, `created_at`, `reviewed_at`
- `feature_flags` — `key`, `enabled`, `description`, `updated_by`, `updated_at`
- `zones` — `country`, `city`, `commune`, `neighborhood`, `kind` (service/restricted/pricing), `metadata` jsonb

**New security-definer functions**:

- `is_admin(uid)` → boolean
- `has_admin_role(uid, admin_role)` → boolean
- `current_admin_role(uid)` → admin_role
- `log_admin_action(...)` — used by future RPCs to write `audit_logs`

**Seed**: feature flags for `moto`, `toktok`, `repas`, `marche`, `scanner`, `wallet`, `agent_topup`, `orange_money`, `driver_mode`, `merchant_portal`, `marketplace_chat`, `boosted_listings`.

## 2. RBAC — Permissions Map

`src/lib/admin/permissions.ts` exports a typed permissions matrix matching the user's spec (the "Access Matrix" table). Shape:

```ts
type Module = 'dashboard' | 'live_ops' | 'users' | 'drivers' | ...;
type Capability = 'view' | 'edit' | 'approve' | 'export' | 'delete';
const matrix: Record<AdminRole, Partial<Record<Module, Capability[]>>>;
export function can(role, module, cap): boolean;
```

Plus `requiresApproval(action)` for actions like large refunds, price changes, admin creation, etc.

`src/hooks/useAdminAuth.ts` — fetches current admin role + exposes `can()`.

## 3. Routing & Layout

- **New route prefix**: `/admin/*` (the existing `/admin` becomes `/admin` dashboard home; the old fares+agents UI moves into `/admin/pricing` and `/admin/vendors`).
- **`AdminLayout.tsx`** — uses shadcn `Sidebar` (collapsible icon mode), topbar with admin name + role badge + sign-out, `<Outlet />` content area, breadcrumbs.
- **`AdminGuard.tsx`** — redirects non-admins to `/`. Shows access-denied state for modules outside their permissions.
- **`AdminSidebar.tsx`** — grouped nav (Operations / Finance / Platform / System), active-route highlighting, hides items the role can't access.

## 4. Module Placeholder Pages

All under `src/pages/admin/`. Each placeholder includes: page header (title + subtitle), role-gated action buttons (disabled with tooltip if not allowed), and an `EmptyState` describing what will live there. This makes the structure immediately navigable.

```text
/admin                  → Dashboard (KPI cards stub + live status stub + quick actions)
/admin/live             → Live Operations (map placeholder)
/admin/users            → Users
/admin/drivers          → Drivers
/admin/merchants        → Merchants
/admin/vendors          → Top-Up Vendors (port existing AgentsPanel here)
/admin/wallet           → Wallet / Ledger
/admin/pricing          → Pricing (port existing FareRow UI here, expand tabs for Moto/TokTok/Envoyer/Repas/Marché/Wallet)
/admin/orders           → Orders / Rides / Deliveries
/admin/repas            → Repas Admin
/admin/marche           → Marché Admin
/admin/support          → Support / Disputes
/admin/risk             → Fraud / Risk
/admin/notifications    → Notifications / WhatsApp/SMS
/admin/promotions       → Promotions
/admin/reports          → Reports
/admin/zones            → Zones
/admin/flags            → Feature Flags (wired to feature_flags table)
/admin/settings         → Settings
/admin/admins           → Admin Users (super_admin only — wired to admin_users table)
/admin/audit            → Audit Logs (wired to audit_logs table, role-scoped)
```

## 5. Approval System

- `src/lib/admin/approvals.ts` — `requestApproval(action, payload)` writes to `approval_requests`.
- `/admin/admins` page includes an "Approval queue" tab visible only to super_admin.
- Future destructive actions in any module call `requireApprovalOr(execute)` — Phase 1 ships the helper, modules adopt it as they're built out.

## 6. Audit Logging

- All admin RPCs (existing `admin_create_agent`, `admin_adjust_agent_float`, `claim_first_admin`) get a follow-up migration that wraps them to call `log_admin_action`. Phase 1 ships the function + table; existing RPCs are updated in the same migration to log automatically.

## 7. What is NOT in this phase

- Real KPI queries, live map, ledger filters, ticket workflow, promo engine, message broadcaster, report exports — all stubbed with empty states.
- 2FA / device recognition / login alerts for super_admin (noted as Phase 3).
- Public app UI is untouched.

---

## Technical notes

- Sidebar uses `react-router-dom` `NavLink` + `useLocation` per the shadcn-sidebar guidance.
- Permissions enforced **both** in DB (RLS using `has_admin_role`) and UI (`can()` in `useAdminAuth`). Never trust the client.
- `super_admin` is bootstrapped from anyone already in `user_roles` with role `admin`. New admins are created exclusively via super_admin from `/admin/admins`.
- Existing `/admin` redirect-to-auth behavior preserved — admins must still sign in (the dev auth bypass in `useAuthGuard` does not apply to `/admin/*` because that route uses its own `AdminGuard` against the DB).
- Files added: ~1 migration, ~25 new files (layout, guard, sidebar, permissions lib, 20 placeholder pages, hooks). Existing `src/pages/Admin.tsx` is replaced by the new shell; its fares + agents content moves into `/admin/pricing` and `/admin/vendors` so nothing is lost.

After approval, I'll execute the migration first, then ship the code in a single pass.
