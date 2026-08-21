# Node 5 · A7 — Merchant Architecture Migration

**Status:** CERTIFIED — `_qa_node5_identity_a7` 130 / 130 · Full board 5,130 / 0 failed.

## Canonical question
"Is this account professionally a MERCHANT?" → **an ACTIVE `professional_identities` row of type `merchant`.**
Nothing else (store row existence, `app_role`, `user_preferences.app_mode`, restaurant ownership) answers it.

## Layered merchant law
1. **Active merchant class** — `_merchant_class_require()` / `_merchant_class_active(uid)` (internal, service-role only).
2. **Business asset ownership** — `_merchant_store_require(store_id)`, `_merchant_restaurant_require(restaurant_id)`.
3. **Asset operational state** — store `status`/`onboarding_status`, restaurant activity; unchanged R1–R14 law.
4. **Object authority** — per-object checks (`_marche_listing_authz`, settlement ownership, order ops) unchanged.

Layer 1 never replaces layers 2–4; it is an additional gate in front of them.

## Migrated surfaces
- Marché catalog mutation chokepoint `_marche_listing_authz` and the 8 merchant mutation RPCs
  (listing create/update/publish, fulfillment transitions, merchant order ops, settlement request,
  location submission, admin decision path).
- RLS write paths on `merchant_stores`, `food_restaurants`, `food_menu_items`, `listing_images`, `merchants`.

### RLS predicate naming
RLS policies call **`public.professional_merchant_active(uuid)`** (STABLE SECURITY DEFINER, granted to
`authenticated` only). The internal `_merchant_class_active` stays revoked from `anon`/`authenticated`,
preserving the S13 B9 law that raw `_merchant_%` primitives are service-role only.

## Safety path (J7)
`_professional_state_transition_guard` now requires a live lane **only for transitions into an
OPERATIONAL end state** (`merchant_stores.status='active' AND onboarding_status='approved'`, or
`driver_profiles.status='approved'`). Suspension, pause and de-approval always remain available so an
orphaned business can never be stuck live after its owner releases the professional lane.

## Non-goals
No change to approval semantics, orderability truth, fulfillment law, pricing, or settlement economics.
