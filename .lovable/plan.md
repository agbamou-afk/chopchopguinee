# Account Control System — Delete / Ban / Freeze

## State of play (already in place)

- `account_bans` table, `admin_ban_user`, `admin_unban_user`, `is_user_banned`, `check_signup_allowed`, `admin_check_email_reuse_blocker` already exist.
- `admin-delete-user` edge function does pre-purge → hard delete → verify, or anonymize when financial history exists.
- `Auth.tsx` already calls `check_signup_allowed` before signup with generic copy.
- `AuthContext` signs the user out when `account_status` is `banned` or `deleted`.
- `UsersAdmin` already has separated Delete / Ban / Unban actions with required ban reason.

What is missing and what this plan delivers: the **Freeze** state, ban/freeze **notifications**, a shared **FrozenAccountScreen**, **required reason on unban**, freeze enforcement at sensitive write paths, and one tighter signup precheck (phone + email).

## 1. Database migration — freeze schema, notifications, hardening

New table `public.account_freezes` (lifecycle, audited, RLS admin-only read):

```text
id uuid pk
user_id uuid not null  → auth.users
reason text not null         (>= 3 chars enforced)
freeze_type text not null default 'admin_review'
                              (admin_review | payment_review | security_review | dispute | document_review)
status text not null default 'active'  (active | lifted)
frozen_by uuid not null
frozen_at timestamptz default now()
expires_at timestamptz null
lifted_by uuid null
lifted_at timestamptz null
lift_reason text null
metadata jsonb default '{}'
created_at / updated_at
```

Indexes on `user_id WHERE status='active'`, `status`, `expires_at`.

Add `'frozen'` as an allowed value for `profiles.account_status` (currently free-text but enforced by application; update guard if a CHECK exists).

RPCs (SECURITY DEFINER, `search_path=public`, REVOKE PUBLIC, GRANT to authenticated, internal `admin_users` role gate, audit_log row, returns `{ok, freeze_id|ban_id, error?}`):

- `admin_freeze_user(_target uuid, _reason text, _freeze_type text default 'admin_review', _expires_at timestamptz default null)` — requires `god_admin`/`super_admin`/`operations_admin`. Rejects empty reason. Closes any existing active freeze (idempotent), inserts new one, sets `profiles.account_status='frozen'`, sets driver offline if `driver_profiles` row exists, inserts an `inapp` row in `notification_log` with template `account_frozen`. Notification failure is logged, not fatal.
- `admin_unfreeze_user(_freeze_id uuid default null, _target uuid default null, _lift_reason text)` — lifts active freeze, restores `account_status='active'` only when no other freeze/ban is active. Notification `account_unfrozen`.
- `is_user_frozen(_user uuid) returns boolean` — STABLE, used by RLS/triggers and client.
- `current_freeze(_user uuid) returns table(...)` — returns active freeze with reason for the frozen screen.

Hardening:

- `admin_unban_user`: require `_lift_reason` length >= 3, also send `account_unbanned` notification (best-effort).
- `admin_ban_user`: also send `account_banned` notification (best-effort).
- `check_signup_allowed(_email, _phone_e164)`: already exists — extend to also block when an active ban exists for that **phone** (`phone_e164`). Freeze does **not** block signup of a new email.

Sensitive-action triggers (defense in depth — UI also blocks):

- Trigger on `rides`, `food_orders`, `topup_requests`, `marketplace_listings` (INSERT/UPDATE that publishes), `driver_locations` (going online) → raise `frozen_account` exception when `is_user_frozen(auth.uid())`.

All new tables: `GRANT` block per cloud-db rules. `account_freezes` is admin-only read (no `anon`, no `authenticated` self-read — use `current_freeze` RPC which the user can call for themselves only).

## 2. Edge function — `admin-delete-user`

Extend pre-purge to also clear active reuse blockers when a clean delete succeeds (no history):

- delete `profiles` row (already cascaded by auth.users delete in many cases — verify and add explicit cleanup of `user_preferences`, `user_pins`, `user_roles`, `user_legal_consents`, `saved_places`, `notification_preferences`, `driver_applications`, `merchant_stores` only when status is pending/none, `account_freezes`).
- Keep current anonymize path untouched when history exists.
- Response unchanged: `{mode:'deleted'|'anonymized', email_reusable}`.

## 3. Frontend

`src/contexts/AuthContext.tsx`:

- Load active freeze via `current_freeze` RPC alongside profile/roles. Expose `freeze: { id, reason, freeze_type, frozen_at, expires_at } | null` and `isFrozen` boolean on context.
- Banned/deleted handling unchanged.

`src/components/account/FrozenAccountScreen.tsx` (new):

- Full-screen replacement for the app shell when `isFrozen`.
- Shows title "Compte temporairement gelé", reason, freeze type, "Contacter le support" CTA → opens existing `ReportIssueButton` / mailto.
- No bottom nav, no navigation away.

`src/App.tsx`:

- After `AuthProvider` ready, if `isFrozen` and not on `/auth`, `/legal`, `/privacy`, `/help`, render `FrozenAccountScreen` instead of routed content.

`src/hooks/useAuthGuard.ts`:

- Block `requireAuth` when `isFrozen`, toast and route to `/account/frozen` (or stay).

`src/pages/admin/UsersAdmin.tsx`:

- Add **Geler** action button (snowflake/Lock icon) next to Bannir, visible when `account_status !== 'frozen'` and not banned/deleted.
- Add **Lever le gel** action button when `account_status === 'frozen'`.
- New **Freeze dialog**: required `reason` textarea (>=3 chars), `freeze_type` select with 5 options, optional `expires_at` date input, confirm button.
- New **Unfreeze dialog**: required `lift_reason`.
- Make **unban dialog** `lift_reason` required (currently optional).
- Add `frozen` to `StatusBadge` (amber/blue).
- Filter chip "Gelés".

`src/pages/Auth.tsx`:

- Already gated by `check_signup_allowed`. After migration extends phone check, no UI change needed.

## 4. QA matrix

A. Clean test delete → `mode=deleted`, email + phone reusable, signup succeeds.
B. Ban user → blocked at login, signup with same email blocked, same phone blocked, generic copy shown.
C. Unban (with reason) → signup/login restored.
D. Freeze → user sees `FrozenAccountScreen` with reason, no nav.
E. Unfreeze → app shell restored.
F. Frozen driver → forced offline, `driver_locations` insert raises `frozen_account`.
G. Frozen merchant → cannot publish listing (trigger + UI guard).
H. Frozen client → cannot insert ride / food_order / topup_request.
I. Notifications: `account_log` rows present for freeze/unfreeze/ban/unban.
J. Non-admin caller → `admin_freeze_user` rejects with `forbidden`.
K. History account → still anonymized, never hard-deleted.

## 5. Out of scope

- Email/SMS delivery for ban/freeze (in-app only, queued through existing notification pipeline if/when worker picks it up).
- Self-serve unfreeze.
- Per-vertical UX polish beyond the global frozen screen + RPC-level block.

**Lock candidate:** `account-control-delete-ban-freeze-stable`
