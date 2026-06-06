## Scope

Two combined requests, delivered as one coherent V0. Far too large to ship end-to-end in a single pass safely, so this plan splits work into a documented strategy + minimal-safe-implementation slice that satisfies the hard exit criteria without breaking existing Marché, client, or driver flows.

## Audit summary (current state)

- `merchant_stores` exists: owner_user_id (unique), slug, name, district, category, verification_state (none/pending/verified), status (active/paused/suspended). No `pending`/`draft` status, no onboarding fields, no `created_by`, no `business_type`, no market FK.
- `marketplace_listings` exists with status/visibility and optional `store_id`. No `quantity_in_stock`, no `barcode`, no `visibility` separate from status.
- No tables for physical markets, onboarding campaigns, assignments.
- Merchant UI exists: `MerchantHub`, `MerchantActivationPanel`, `StoreOnboardingSheet`, `CatalogSection`, etc. Activation today is opt-in inside an existing client account, not a signup branch.
- `Auth.tsx` currently branches Client / Driver via `signup_intent`. No merchant branch.
- `MerchantsAdmin` lists restaurants + stores but has no approval actions.

## Deliverables (V0 — this pass)

### 1. Docs (no code risk)
- `docs/marche/MARKET_DIGITIZATION_STRATEGY.md` — market-by-market onboarding strategy, specialist workflow, photo/AI/barcode roadmap, ranking & sponsored-placement model (clearly marked future), phased roadmap V0/V1/V2.
- `docs/marche/MERCHANT_ONBOARDING_FUNNEL.md` — signup branch, onboarding fields, pending-merchant rules, approval lifecycle, RLS posture.

### 2. Schema migration (additive, non-breaking)
- `merchant_stores`: add `business_name`, `owner_name`, `phone`, `business_type`, `stall_number`, `onboarding_status` (`draft|submitted|in_review|needs_info|approved|rejected`), `created_by`, `submitted_at`, `approved_at`, `approved_by`, `rejection_reason`, `market_id`. Extend status check to include `pending`, `draft`, `rejected`, `archived`. Default new stores to `status='pending'`, `onboarding_status='draft'`.
- `marketplace_listings`: add `quantity_in_stock int`, `barcode text`, `visibility text default 'private'`. Existing rows backfilled to `visibility='public'` so current marketplace UI does not break.
- New tables: `physical_markets`, `market_onboarding_campaigns`, `market_onboarding_assignments`, plus `app_role` enum value `merchant` and `onboarding_specialist` (additive). Full GRANTs + RLS per project rules.
- Tighten "Anyone read active stores" policy so only `status='active' AND onboarding_status='approved'` is public; owner + admin keep full read.
- Listings public-read policy tightened to require approved store + `visibility='public'` + `status='active'`.
- New `has_role(..., 'merchant')` / specialist policies for store + product self-management.

### 3. Auth signup branch
- `src/pages/Auth.tsx`: add third card "Marchand" with French copy. `signup_intent='merchant'`, stored in `user_metadata` + sessionStorage handoff identical to driver path.
- `src/components/auth/ProfileCompletionRedirect.tsx` (or equivalent): after auth, if intent=merchant and no `merchant_stores` row → redirect to `/merchant/onboarding`; else to `/merchant`.

### 4. Merchant onboarding funnel
- New route `/merchant/onboarding` → new page that collects required fields (business name, owner name, phone, district/market, category, business type) + optional (description, stall, hours, WhatsApp). On submit: insert `merchant_stores` with `status='pending'`, `onboarding_status='submitted'`, `created_by=auth.uid()`, `submitted_at=now()`.

### 5. Merchant dashboard pending state
- Extend `MerchantHub` to render a "Boutique en vérification" banner when `onboarding_status != 'approved'`, with copy from spec. Catalog + product creation remain enabled but new products are forced to `visibility='private'`, `status='draft'` until approval.

### 6. Admin approval module
- Extend `MerchantsAdmin`: add Pending / Needs info / Approved / Rejected tabs (real data), row click opens a sheet with Approve / Reject / Request info / Suspend actions wired through a new `admin_merchant_decision` RPC (security definer, admin-only, audit logged via existing `log_admin_action`). Approve → status='active', onboarding_status='approved', approved_at/by set. Reject → status='rejected', stores `rejection_reason`.

### 7. Customer marketplace safety
- Update `src/lib/marche/stores.ts` and listing queries to filter on approved-store + public-visibility (defense in depth; RLS already enforces).

### 8. QA & build
- Run typecheck/build, run Playwright `03-merchant.spec.ts`. Manual QA notes: client signup unchanged, driver signup unchanged, merchant signup → onboarding → pending dashboard → draft product invisible to anon → admin approves → product publishable.

## Explicitly deferred to V1/V2 (documented, not built)

- Barcode scanner UI (manual field only in V0).
- AI background removal (UI placeholder "bientôt", no fake processing).
- Onboarding specialist field app + campaign management UI (tables + RLS only in V0).
- Sponsored placement ranking, merchant analytics, bulk upload, supplier integrations.
- Separating `merchant_products` from `marketplace_listings` — V0 extends listings with inventory + visibility; doc records the tradeoff and migration path.
- Mode-switch (merchant browsing as client) — existing app already allows this; no changes needed.

## Risks / non-goals

- Tightening the existing "Anyone read active stores" policy could hide stores that were created before this migration. Mitigation: backfill all existing `merchant_stores` to `onboarding_status='approved'` and `status='active'` in the same migration.
- Existing marketplace listings will be backfilled to `visibility='public'` to preserve current customer Marché behaviour.
- No changes to wallet, rides, drivers, OM, legal consent, phone normalization, or email confirmation.

## Lock candidate

`marche-merchant-onboarding-v0-stable` once all hard exit criteria pass.

Approve to proceed with the migration + code changes in a single follow-up pass.
