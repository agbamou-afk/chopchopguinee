# Sub-Admin Forced First-Login Password Change — Stable

Closes `subadmin-account-provisioning-production-stable`. Staff accounts created
with `must_change_password=true` cannot reach any `/admin/*` route until they
change their password.

## Enforcement
- `AdminGuard` queries `admin_users.must_change_password` for the current user
  on every admin route. If true → redirect to `/admin/change-password`.
- `/admin/change-password` is a sibling route, not nested under `AdminLayout`,
  so the locked staff cannot see any admin chrome / data.
- The change-password page is itself gated: only renders for the logged-in
  staff user whose `admin_users` row still has the flag.

## Password change flow
1. `supabase.auth.updateUser({ password })` — requires live session, never logs
   or stores plaintext.
2. RPC `admin_clear_must_change_password()` (SECURITY DEFINER, search_path=public,
   EXECUTE revoked from PUBLIC, granted to authenticated) clears the flag for
   `auth.uid()` only, stamps `changed_password_at`, and writes
   `audit_logs(action='staff.password_changed')`.
3. Client validation: ≥10 chars, mixed case + digit, blocks the temp default
   `Welcome%2026` and a small denylist.

## Invariants
- Service role still only in the edge function; no service key in `src/`.
- Flag can only be cleared via the RPC after a successful auth password update.
- God/super_admin creation still blocked by `admin-create-staff-user`.
- Existing admins with flag = false / null pass through unchanged.

## Files
- migration: `admin_users.changed_password_at` + `admin_clear_must_change_password()` RPC
- `src/pages/admin/AdminChangePassword.tsx`
- `src/components/admin/AdminGuard.tsx` (flag check + redirect)
- `src/App.tsx` (sibling `/admin/change-password` route)