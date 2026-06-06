# CHOPCHOP Marché — Merchant Onboarding Funnel

## Signup branch

`Auth.tsx` now offers three intents: **Client**, **Chauffeur**, **Marchand**.
- `signup_intent='merchant'` is written to `auth.users.user_metadata` and
  mirrored in `sessionStorage` (`cc_signup_merchant_intent`) for same-device
  routing.
- After session bootstrap, an authenticated user with merchant intent and no
  `merchant_stores` row is redirected to `/merchant/onboarding`. If the row
  already exists they go to `/merchant/hub`.
- Client and driver paths are unchanged.

## Onboarding form (`/merchant/onboarding`)

Required: business name, owner name, phone (normalized to `+224…`).
Optional: WhatsApp, business type, district / market, stall number, category,
operating hours, description.

Submitting inserts a `merchant_stores` row with:
- `status='pending'`, `onboarding_status='submitted'`,
- `verification_state='pending'`, `submitted_at=now()`,
- `owner_user_id=auth.uid()`, `created_by=auth.uid()`,
- `delivery_available=false`, `choppay_enabled=false`.

## Pending dashboard (`/merchant/hub`)

`MerchantHub` renders `MerchantPendingBanner` whenever
`onboarding_status !== 'approved'`. The merchant can still build a catalog —
`CatalogSection` continues to work — but products created while pending must
remain `visibility='private'` and never reach the public marketplace.

Copy:
- `submitted` / `in_review` → "Boutique en vérification. Vous pouvez déjà
  préparer votre catalogue pendant que notre équipe examine votre boutique."
- `needs_info` → "Informations requises" + admin-supplied reason.
- `rejected` → "Demande rejetée" + reason.

## Admin approval (`/admin/merchants`)

Tabs: Tous / En attente / Info requise / Approuvés / Rejetés / Restaurants /
Boutiques. Each Boutique row has an **Examiner** button that opens a sheet
with merchant detail and four actions: Approuver, Demander infos, Suspendre,
Rejeter.

Every action goes through the `public.admin_merchant_decision(_store_id,
_decision, _reason)` `SECURITY DEFINER` RPC, which:
- requires `has_role(auth.uid(),'admin')`,
- rejects when the admin is the store owner (`self_approval_forbidden`),
- writes the new status / onboarding_status / approved_at / approved_by /
  rejection_reason,
- logs the action via `public.log_admin_action('merchants',
  'merchant_decision', …)`.

## RLS posture

- `merchant_stores` public read = `status='active' AND
  onboarding_status='approved'` OR owner OR admin OR onboarding specialist.
- Owner can `INSERT` and `UPDATE` their own row (existing policies).
- Onboarding specialists can `INSERT` and can `UPDATE` only rows still in
  `draft|submitted|in_review|needs_info`.
- `marketplace_listings` public read requires `status='active' AND
  visibility='public'` AND, when `store_id` is set, the parent store must be
  `active + approved`.
- `admin_merchant_decision` is `REVOKE ... FROM PUBLIC; GRANT ... TO
  authenticated;` plus an in-body admin check, so anon cannot call it.

## What this does NOT change

- No wallet / OM logic touched.
- No driver / ride logic touched.
- No changes to legal consent, +224 phone normalization, or email
  confirmation behaviour.