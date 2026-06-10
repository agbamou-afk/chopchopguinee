# Merchant Auth/Routing QA Harness

Dev/admin-only edge function used to prove the merchant signup → onboarding → MerchantHub
flow end-to-end without burning real emails or waiting on inbox confirmation.

**Lock candidate:** `merchant-auth-routing-dashboard-access-stable`

## Safety
- Service role stays server-side (edge function only).
- Caller must be authenticated AND have the `admin` app_role (`has_role(uid,'admin')`).
- Disabled unless edge secret `QA_HARNESS_ENABLED=true`. Do **NOT** set this in production.
- All QA users tagged: `user_metadata.qa_user=true`, `created_by=merchant_auth_routing_qa`.
- All QA stores tagged: `bio="[QA] merchant_auth_routing_qa"`.

## Enable (dev/preview only)
1. Project → Backend → Edge Function Secrets → add `QA_HARNESS_ENABLED=true`.
2. Sign in as an admin in the preview app (so your session token is forwarded).

## Create a confirmed QA merchant
```bash
curl -X POST \
  -H "Authorization: Bearer <ADMIN_USER_JWT>" \
  -H "Content-Type: application/json" \
  -d '{"action":"create"}' \
  https://<PROJECT>.functions.supabase.co/qa-merchant-harness
```
Response includes: `user_id`, `merchant_store_id`, `email`, `password`, `next_route`.

Use the returned email/password to sign in. App should land on `/merchant/hub`
(MerchantHub) with status badge **En vérification**.

## Cleanup
```bash
curl -X POST -H "Authorization: Bearer <ADMIN_JWT>" -H "Content-Type: application/json" \
  -d '{"action":"cleanup","user_id":"<UUID>"}' \
  https://<PROJECT>.functions.supabase.co/qa-merchant-harness
```
Cleanup refuses if the user has wallet transactions, rides, food orders, or topups.
QA marketplace listings are removed; merchant_store, user_preferences, profile, and
auth user are deleted.

## Removal before launch
1. Unset `QA_HARNESS_ENABLED` in all environments.
2. Delete `supabase/functions/qa-merchant-harness/` and the entry in `supabase/config.toml`.
3. Run cleanup for every remaining QA user (`SELECT id FROM auth.users WHERE email LIKE 'qa.merchant.%@chopchop.test'`).