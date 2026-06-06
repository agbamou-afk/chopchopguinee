
# Merchant Signup, Onboarding, Approval & Mode Toggle

Extends the V0 merchant onboarding already shipped (`MerchantOnboarding.tsx`, `merchant_stores.onboarding_status`, `admin_merchant_decision` RPC) with the full disciplined flow that mirrors driver signup.

## Agent routing
- **Lead:** Marché Agent
- **Reviewers:** Platform/QA/Security (auth branching, RLS, private storage), Admin & Ops (approval queue)

## Flow target
```
Signup (Marchand) → Merchant Onboarding Slides → Merchant Application
  → Merchant Dashboard (pending) → Admin Approval → Approved Dashboard
  ↔ Client Mode toggle (status & catalog preserved)
```

## 1. Signup branch (Platform)
- `Auth.tsx` already exposes Client / Chauffeur-Coursier / Marchand. Verify Marchand sets `signup_intent='merchant'` in profile metadata and skips client onboarding/conversion gate.
- Post-signup redirect:
  - `merchant` + slides not completed → `/merchant/onboarding-slides`
  - `merchant` + slides done + no store → `/merchant/onboarding`
  - `merchant` + store exists → `/merchant`
- Persist `merchant_slides_completed_at` on `profiles` (or `user_preferences`).

## 2. Merchant onboarding slides (new)
`src/pages/MerchantOnboardingSlides.tsx` — 4 slides (Vendez / Catalogue / Vérification / Position) + CTA "Créer ma boutique". Same visual family as driver slides. Mark completion in DB; never re-show. Not shown to clients or drivers.

## 3. Merchant application form (extends existing `MerchantOnboarding.tsx`)
Required: business_name, owner_name, phone_e164 (+224), category, store location, ID photo, selfie.
Recommended: storefront photo, market_name, stall_number, landmark, description, opening_hours, whatsapp.

### Store location picker (new component `StoreLocationPicker`)
- Button "Utiliser ma position actuelle" → geolocation API, capture lat/lng/accuracy, reverse geocode, confirm.
- Button "Choisir sur la carte" → map with draggable pin (reuse existing map components).
- Saves `lat`, `lng`, `district`, `address_label`, `landmark`, `location_source` (`current_location`|`manual_pin`), `location_accuracy_m`, `location_confirmed_at`.
- No Kaloum default. Permission denial → manual pin fallback with clear copy.

## 4. Data model migration
Add to `merchant_stores` (if missing): `owner_name`, `lat`, `lng`, `district`, `address_label`, `landmark`, `location_source`, `location_accuracy_m`, `location_confirmed_at`, `id_photo_path`, `selfie_photo_path`, `storefront_photo_path`, `submitted_at`, `decided_at`, `decided_by`, `decision_reason`.
Keep existing `status` / `onboarding_status` / `visibility`. Default new merchants: `status='pending'`, `visibility='private'`, `onboarding_status='submitted'`.

## 5. Private storage bucket
Create **private** bucket `merchant-docs`. Paths: `merchant-docs/{user_id}/id-card.{ext}`, `/selfie.{ext}`, `/storefront.{ext}`.
RLS on `storage.objects`:
- INSERT/SELECT/UPDATE: `auth.uid()::text = (storage.foldername(name))[1]`
- SELECT also allowed for admins via `has_role(auth.uid(),'admin')` or `operations_admin`.
- No anon access. Never store ID/selfie in avatar or product image buckets.

## 6. Merchant dashboard pending state
Extend `MerchantHub` + `MerchantPendingBanner`:
- Title "Boutique en vérification" + body.
- Checklist (info / position / ID / selfie / storefront / produits).
- Actions: add product, edit info, add documents, view status, switch to client mode.
- Pending merchants CAN create products (drafts) but products are forced `status='draft'`, `visibility='private'` via DB trigger.

## 7. Product visibility enforcement
DB trigger on `marketplace_listings` insert/update:
- If owning store not `approved` → force `visibility='private'`, `status='draft'`.
- Public marketplace query (`get_public_listings` or RLS): require `store.status='approved'` AND `store.visibility='public'` AND `listing.visibility='public'` AND `listing.status='active'`.

## 8. Admin approval (extends `MerchantsAdmin.tsx`)
Detail panel shows: business + owner + phone, location map preview, ID photo, selfie, storefront, draft product count, notes.
Actions wired to existing `admin_merchant_decision` RPC: Approve / Reject / Request Info / Suspend / Reactivate. Reason captured. Audit log entry.
Approve → `status='approved'`, `onboarding_status='approved'`, `visibility='public'` allowed; merchant unlocks public publishing.
Reject → reason visible to merchant; products stay private.
Needs info → `onboarding_status='needs_info'`; dashboard surfaces request.

## 9. Mode toggle (new)
New hook `useAppMode` + UI toggle in header/menu:
- Stores `app_mode` in `user_preferences` (`merchant` | `client`) per user.
- Merchant users default to Merchant Mode after onboarding.
- "Passer en mode client" → routes to `/` client home; merchant store untouched.
- "Passer en mode marchand" → routes to `/merchant`.
- Toggle visible only to users with a `merchant_stores` row.
- Switching never deletes store or alters approval status.

## 10. Routing guard updates
`App.tsx` / `AuthContext`: post-login resolver checks intent + slides + store status to land on correct surface. Existing client / driver routing untouched.

## 11. Security / RLS verification
- Merchant: select/update own store only; insert/select own docs only; cannot set `status`/`decided_*`.
- Admin/ops: full read via `has_role`.
- Customers: cannot read pending stores, pending products, or any merchant doc.
- All sensitive writes via SECURITY DEFINER RPCs already in place.

## 12. QA matrix (A–L per spec)
Fresh merchant signup → slides → app → submit; current-location pin; manual map pin; ID/selfie upload to private bucket; pending dashboard; draft product invisible to clients; admin approve unlocks public; mode toggle round-trip; client and driver signup regression.

## Files to create
- `src/pages/MerchantOnboardingSlides.tsx`
- `src/components/merchant/StoreLocationPicker.tsx`
- `src/components/merchant/MerchantDocUpload.tsx`
- `src/components/merchant/ModeToggle.tsx`
- `src/hooks/useAppMode.ts`
- Migration: schema additions + bucket policies + visibility trigger
- `docs/marche/MERCHANT_SIGNUP_FLOW.md`

## Files to edit
- `src/pages/Auth.tsx`, `src/contexts/AuthContext.tsx`, `src/App.tsx`
- `src/pages/MerchantOnboarding.tsx` (extend with new fields, docs, location)
- `src/components/merchant/MerchantHub.tsx`, `MerchantPendingBanner.tsx`
- `src/pages/admin/MerchantsAdmin.tsx` (detail panel + doc previews via signed URLs)

## Out of scope (won't touch)
- Wallet credit logic, ride/repas verticals, driver flow, client conversion gate.

**Lock candidate:** `merchant-signup-onboarding-dashboard-approval-stable`
