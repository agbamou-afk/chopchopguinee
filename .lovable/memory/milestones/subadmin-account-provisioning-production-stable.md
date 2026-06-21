---
name: Sub-Admin Account Provisioning — Stable
description: God Admin can spawn new staff accounts via secure edge function with temp password and forced reset
type: milestone
---
Locked 2026-06-21.

- Edge function `admin-create-staff-user` (service_role server-side only) creates: auth user (email_confirm), profile, admin_users row, parallel user_roles row, audit_logs entry.
- Caller must be God Admin (`user_roles.god_admin` OR legacy `admin_users.super_admin`). Finance/Operations admins blocked.
- Allowed roles: `ops_admin`, `finance_admin`. Creation of `super_admin`/`god_admin` via this endpoint is explicitly refused.
- Default temporary password: `Welcome%2026`. Never stored in plaintext, never logged in audit_logs. Returned once in API response, displayed once in UI.
- `admin_users.must_change_password` flag (default false) is set true on staff creation. UI exposes "force password change" checkbox (default on).
- Admin UI (`AdminsAdmin.tsx`) exposes two flows: "Promouvoir un utilisateur" (legacy phone lookup, ops/finance only) and "Créer un compte staff" (new account flow).
- Rollback: if `admin_users` insert fails, edge function deletes the freshly created auth user to avoid orphaned auth records.
- No service_role key in frontend bundle.