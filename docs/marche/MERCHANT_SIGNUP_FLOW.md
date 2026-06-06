# Merchant Signup, Onboarding & Approval Flow

## Flow
1. Signup with "Marchand" intent → `signup_intent='merchant'`.
2. Routed to `/merchant/onboarding-slides` (4 slides). Completion stored on `user_preferences.merchant_slides_completed_at`.
3. Routed to `/merchant/onboarding` (application form).
4. Application collects: business/owner info, phone, category, store location, ID photo, selfie, optional storefront photo.
5. On submit: `merchant_stores` row created with `status='pending'`, `onboarding_status='submitted'`, `visibility` controlled per RLS.
6. Routed to Merchant Dashboard pending state.
7. Pending merchants can create products (forced `visibility='private'` via DB trigger until store approved).
8. Admin reviews under Admin → Marchands → Examiner (sees location map link + signed-URL doc previews) and uses `admin_merchant_decision` RPC.
9. Approved merchant can publish public products.
10. Mode toggle (`MerchantModeToggle`) lets merchant switch to client view; status/catalog preserved.

## Storage
- Bucket `merchant-docs` (private). Path `{user_id}/{kind}-{ts}.{ext}`.
- RLS: owner read/write own folder only; admin/onboarding_specialist may read all.

## DB
- `merchant_stores`: added `address_label`, `landmark`, `location_source`, `location_accuracy_m`, `location_confirmed_at`, `id_photo_path`, `selfie_photo_path`, `storefront_photo_path`. Default `onboarding_status='submitted'`.
- `user_preferences`: added `app_mode` (client/merchant/driver) and `merchant_slides_completed_at`.
- Trigger `enforce_listing_visibility_trg` on `marketplace_listings` forces `visibility='private'` when owning store is not `(status=active, onboarding_status=approved)`.

## Lock candidate
`merchant-signup-onboarding-dashboard-approval-stable`