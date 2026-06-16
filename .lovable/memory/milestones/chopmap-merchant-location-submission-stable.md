---
name: CHOP Maps Phase 2B — Merchant Location Submission (Stable)
description: Locked 2026-06-16. Merchants can submit/edit store coordinates via MerchantHub; admins approve in /admin/map/places → Soumissions marchands; RPCs `merchant_submit_location` + `admin_set_merchant_location_status` enforce ownership/admin guards; nearby (<100m) duplicate flips fresh submissions to needs_review; trusted/admin_verified places are never downgraded by resubmission.
type: feature
---

## Scope locked
- Merchant UI: `MerchantLocationCard` integrated into MerchantHub Store tab. GPS or manual lat/lng, address, landmark, entrance, pickup, operational notes. Read-only after submission with status pill; "Modifier la position" reopens form.
- Admin UI: `/admin/map/places` → "Soumissions marchands" tab. Filter by status, approve (`admin_verified` / `trusted`), request changes (`needs_review`), reject.
- Schema (existing `merchant_stores`): `map_place_id`, `latitude`, `longitude`, `location_submission_status` enum-like text (`none`|`submitted`|`needs_review`|`admin_verified`|`trusted`|`rejected`), `location_submitted_at`, `location_verified_at`, `location_verified_by`, `location_notes`.
- Canonical link: each submission creates/updates a row in `map_places` with `source='merchant_submission'`. `merchant_stores.map_place_id` is the FK.

## RPC contract
- `merchant_submit_location(p_store_id, p_lat, p_lng, p_address_text, p_landmark_note, p_entrance_note, p_pickup_note, p_operational_note)` — `SECURITY DEFINER`, requires `auth.uid()`, enforces `owner_user_id = auth.uid()`. Creates `map_places` row if missing, otherwise updates it. Never downgrades `trusted`/`admin_verified` on resubmit. After write, if another active `map_places` row exists within ~100m, flips current place to `needs_review` (unless trusted/admin_verified).
- `admin_set_merchant_location_status(p_store_id, p_status, p_note)` — `SECURITY DEFINER`, requires `has_role(auth.uid(),'admin')`. Maps merchant status to `map_verification_status` (rejected → closed + `active=false`). Sets `verified_at/by` on admin_verified/trusted. Writes audit log `admin.merchant.location.<status>`.

## Verified behavior (DB smoke test)
- Merchant submit → `merchant_stores.location_submission_status='submitted'`, `map_places.verification_status='submitted'`.
- Admin verify → `admin_verified`, `location_verified_at` set, mirrored to `map_places`.
- Resubmit by merchant on a place already `admin_verified` → status preserved.
- Fresh store submitting at coords <100m of another active place → `map_places.verification_status='needs_review'` (no auto-merge).
- Non-owner calling `merchant_submit_location` → raises `not store owner`.
- Non-admin calling `admin_set_merchant_location_status` → raises `admin required`.

## Out of scope (still)
- Auto-merge / dedupe of nearby places (manual admin only).
- Customer-facing display of merchant pins on the map.
- Routing / ETA tied to merchant pins.
- Bulk import of merchant locations.

## Files of record
- `src/components/merchant/MerchantLocationCard.tsx`
- `src/components/merchant/MerchantHub.tsx`
- `src/hooks/useMerchantIdentity.ts`
- `src/lib/maps/canonical.ts` (`merchantSubmitLocation`, `adminSetMerchantLocationStatus`, `listMerchantLocationSubmissions`, `MERCHANT_LOC_LABEL`)
- `src/pages/admin/MapPlacesAdmin.tsx` (Soumissions marchands tab)
- Migrations: `20260616033518_*.sql` (schema + RPCs), `20260616-034553_*.sql` (admin RPC enum cast fix)

## Predecessor lock
- `chopmap-canonical-map-namespace-service-zones-tarifs-stable`