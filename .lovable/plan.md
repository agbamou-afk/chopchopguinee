# Node 4 — Marché R2 (audit + smallest next certification pass)

## Part A — Audit findings (repo + live DB, verified this turn)

### 1. Offer / negotiation lifecycle
- Table `public.marketplace_offers` (25 cols): `status` is a **plain text** column, default `'pending'`, **no CHECK constraint, no enum** — any string is storable at DB level.
- Write RPCs (all SECURITY DEFINER): `create_marketplace_offer(listing,amount,message,payment_method)`, `merchant_respond_marketplace_offer(offer,action,counter,message)`, `withdraw_marketplace_offer(offer)`, `marche_offer_set_tender(offer,method)`.
- **Defect D1 — counter has no buyer consent.** `merchant_respond_marketplace_offer` accepts actions on `status IN ('pending','countered')`. After the merchant counters, the merchant can call `accept` again on its own `countered` row and the offer becomes `accepted` at the merchant's `counter_amount_gnf`. The buyer has no `accept counter` path anywhere (RPC or UI: `ListingDetail.tsx` only shows the counter amount plus withdraw/re-offer).
- **Defect D2 — price agreed is not frozen.** Downstream money reads `COALESCE(counter_amount_gnf, offer_amount_gnf)` at payment time (`marche_create_offer_payment_intent`, `marche_complete_offer`). There is no immutable `agreed_amount_gnf` snapshot at acceptance.
- **Defect D3 — offer creation bypasses R1.5 doctrine.** `create_marketplace_offer` validates raw columns (`status`, `visibility`, `allow_offers`, `pricing_mode`, `quantity_in_stock`) and only checks the store when `store_id IS NOT NULL`. It never calls `marche_listing_truth()` / `v_marche_listing_truth`, so it cannot return `MERCHANT_STORE_REQUIRED`, `DEMO_SUPPLY` or `SELLER_NOT_ELIGIBLE`, and it accepts stores in `status='paused'`.
- **Defect D4 — expiry is decorative.** `expires_at` is set to `now() + 7 days` and never enforced: no job, no guard, and the `'expired'` status is never written by any function.
- **Defect D5 — direct table CRUD is open.** `has_table_privilege('authenticated','marketplace_offers','UPDATE') = true`, and `anon` has SELECT. RLS policies are read-only (buyer/merchant/admin SELECT), so an UPDATE currently fails only for lack of a policy — the grant posture contradicts the R1 doctrine applied to `marketplace_listings` (direct CRUD revoked, RPC-only). Only `payment_status` is trigger-protected (`prevent_unsafe_marketplace_offer_payment_status_update`); `status`, `counter_amount_gnf`, `fulfillment_status`, `settlement_state` are not.
- Client: `src/lib/marche/offers.ts` reads `marketplace_offers` with `select("*")` directly (buyer, merchant, admin lists). UI: `OfferSheet.tsx`, `ListingDetail.tsx`, `MerchantOffersSection.tsx`, `MarcheAdmin.tsx`.
- Live data: `marketplace_offers` is **empty (0 rows)** — no migration/backfill risk.

### 2. Order / cart / checkout objects
- There is **no canonical Marché order object**. `marketplace_offers` is the de-facto commitment row (it carries `fulfillment_status`, `settlement_state`, `completed_at`). No cart, no `market_orders` table (only referenced as a future `refMarketOrderId` comment in `src/lib/marche/delivery.ts`).

### 3. Money references
- `marche_create_offer_payment_intent` → `payment_intents` (`source_module='marketplace'`) via legacy `choppay_*`; `marche_complete_offer` → `choppay_capture_payment_intent` + merchant settlement; admin `admin_marche_capture_and_settle_offer`, `admin_preview_marche_payment_intents/settlement`; OM sandbox `om_sandbox_create_marche_intent`, `om_sandbox_request_marche_refund`.
- Slice 13 runtime tables `chop_pay_order_runtime` / `cash_order_runtime` contain **0 rows** and have **no Marché source rows**; `marche_offer_set_tender` only writes `metadata.payment_method`. So Marché money is a **parallel legacy path**, not Slice 13. Flag `om_marche_checkout_enabled` is `false`.

### 4. Fulfillment / courier
- Fulfillment is listing metadata only (`delivery_available`, `fulfillment_options`, `availability`). `marketplace_create_delivery_mission(offer,...)` can create a `marketplace_delivery` mission from an offer, but no dropoff address, pickup truth or fulfillment mode is stored on the offer itself. `fulfillment_status` defaults `'pending'` with no state machine.

### 5. Post-commitment lifecycle
- No stock reservation or decrement on acceptance (`marche_listing_adjust_stock` is a merchant-manual RPC only). No cancellation path after `accepted`. No replay/idempotency key on offers beyond the "one open offer per buyer" guard. `marche_complete_offer` is idempotent only on the paid+settled terminal state.

### 6. Receipts / support / admin
- Admin `src/pages/admin/MarcheAdmin.tsx` lists listings + offers; payments admin previews Marché intents. No Marché dispute/support object; `support_issues` has no Marché offer linkage.

### 7. RLS / grants posture
- `marketplace_offers`: RLS on, 3 SELECT policies (buyer / merchant / `is_any_admin`), no write policies, but table grants remain broad (see D5).
- `marketplace_listings` public SELECT policy still contains the pre-R1.5 clause `(store_id IS NULL) OR (approved store)`. R1.5 neutralises storeless supply through truth + guard + quarantine, so this is doctrine drift in the policy text rather than a live exposure — but it is a latent contradiction.

### 8. Tests
- Harnesses `_qa_node4_marche_r1()` (55) and `_qa_node4_marche_r15()` (38) cover listing/publication truth only. **No offer-lifecycle harness exists.** No vitest file covers Marché offers.

## Part B — Proposed R2

**Name:** `node4-marche-r2-offer-agreement-commitment-truth`

**Objective:** make the Marché negotiation a constitutionally sound, server-authoritative, mutually-consented agreement object — *before* any money, checkout or fee work. This is the narrowest prerequisite: every money path already reads an amount that no buyer ever consented to (D1/D2), so certifying checkout first would certify a broken commitment.

### Constitutional laws
1. **L1 Mutual consent.** A price becomes binding only when the party who did *not* propose it accepts it. A merchant may never accept its own counter.
2. **L2 Frozen agreement.** On acceptance the system writes an immutable `agreed_amount_gnf` + `agreed_by` + `agreed_at`; all downstream reads use it.
3. **L3 Supply doctrine inherited.** Offer creation must pass canonical `marche_listing_truth()` and return its machine-readable refusal reason (`MERCHANT_STORE_REQUIRED`, `DEMO_SUPPLY`, `STORE_NOT_APPROVED`, `LISTING_PAUSED`, `OUT_OF_STOCK`, `NO_PHOTO`).
4. **L4 Server-only writes.** No client may write `marketplace_offers` directly; all transitions go through SECURITY DEFINER RPCs, mirroring the R1 listing contract.
5. **L5 Explicit state machine.** Only declared transitions are legal; terminal states are terminal; expiry is real and derived.
6. **L6 Money untouched.** Amount semantics change only by pointing existing money RPCs at `agreed_amount_gnf`; no rail, ledger, fee or Slice 13 change.

### In-scope changes
- DB: add `agreed_amount_gnf`, `agreed_by_user_id`, `agreed_at`, `last_actor_role`, `expired_at` to `marketplace_offers`; add a status CHECK constraint.
- DB: new `marche_offer_transition_guard()` trigger enforcing the legal transition matrix + immutability of agreed fields.
- DB: rewrite `create_marketplace_offer` to call `marche_listing_truth()` (L3) and keep tender persistence unchanged.
- DB: rewrite `merchant_respond_marketplace_offer` — merchant may accept only a `pending` buyer amount, may counter, may reject; accepting a `countered` row it authored raises `COUNTER_AWAITS_BUYER`.
- DB: new `buyer_respond_marketplace_offer(p_offer_id, p_action)` with `accept | reject | counter` (buyer counter re-opens as `pending`, capped by re-offer rules).
- DB: `marche_offer_expire_due()` maintenance RPC (admin/service only) that moves due open offers to `expired`; read paths treat past-due open offers as expired.
- DB: sanitized read RPCs `marche_offers_for_buyer()`, `marche_offers_for_merchant()`, `marche_offer_get(id)`; REVOKE INSERT/UPDATE/DELETE on `marketplace_offers` from `anon`/`authenticated`, and revoke `anon` SELECT.
- DB: point `marche_create_offer_payment_intent` and `marche_complete_offer` at `agreed_amount_gnf` (falling back to the existing COALESCE only for legacy rows — table is empty, so effectively none).
- Client (presentation + lib only): `src/lib/marche/offers.ts` switches to the sanitized RPCs and gains `buyerRespondOffer`; `ListingDetail.tsx` gains "Accepter la contre-offre" / "Refuser" / "Contre-proposer" for the buyer; `MerchantOffersSection.tsx` hides accept on merchant-authored counters and shows "En attente de l'acheteur"; `MarcheAdmin.tsx` reads through the admin RPC; French error translations extended.
- QA: new `_qa_node4_marche_r2()` harness.

### Hard non-goals
No cart/checkout, no 1% or any fee, no Slice 13 adoption or migration of Marché money, no payment-rail change, no ledger/wallet/settlement change, no mission/courier change, no stock reservation, no dispute/support object, no feature-flag activation, no deploy, and no reopening of R1/R1.5 primitives (truth view, publication guard, listing mutation RPCs, discovery, media privacy, quarantine, anon `has_role` posture).

### Runtime QA matrix (`_qa_node4_marche_r2()`, ~45 assertions)
- Creation: refusals `MERCHANT_STORE_REQUIRED`, `DEMO_SUPPLY`, `STORE_NOT_APPROVED`, `LISTING_PAUSED`, `OUT_OF_STOCK`; happy path on approved store; self-offer blocked; banned/frozen blocked; duplicate open offer blocked; invalid/negative amount; invalid tender.
- Consent: merchant accepts pending → `accepted` with `agreed_amount_gnf = offer_amount_gnf`; merchant counters → `countered`; merchant re-accept → `COUNTER_AWAITS_BUYER`; buyer accepts counter → `accepted` with `agreed_amount_gnf = counter_amount_gnf`, `agreed_by = buyer`; buyer rejects counter; buyer counters back → `pending`; third party forbidden on both sides.
- Terminality: no transition out of `accepted|rejected|withdrawn|expired`; withdraw only while open; agreed fields immutable on later updates.
- Expiry: due open offer expires via `marche_offer_expire_due()`; accepted offers never expire; expired offer cannot be accepted/paid.
- Authority: direct INSERT/UPDATE/DELETE by `authenticated` denied; `anon` SELECT denied; buyer cannot read another buyer's offer; merchant cannot read another merchant's; admin reads all; sanitized RPCs expose no `minimum_price_gnf`.
- Money linkage (assertions only, no new money): payment intent amount equals `agreed_amount_gnf`; intent refused on non-accepted/expired offers.

### Frozen regression board to rerun
`_qa_node0_course`, `_qa_node1_bonbonna`, `_qa_node2_taxi`, Repas R1–R4 / R4.5 / R5 static+runtime / R6 / R7 / R8 (P15.5) / R9 / R10 / R11, Slice 13 runs 1–7, `_qa_node4_marche_r1()` 55/55, `_qa_node4_marche_r15()` 38/38, plus anon Marché discovery probes, `has_role` anon-execute = false, quarantine count unchanged, feature flags unchanged. Client gates: `tsgo --noEmit -p tsconfig.app.json`, vitest, production+PWA build.

### Safety
Safe to execute immediately without reopening R1/R1.5: every change is additive to the offer layer, `marketplace_offers` is empty (0 rows) so no backfill or data migration risk, and no R1/R1.5 primitive is modified. The only touch to certified surfaces is tightening grants on `marketplace_offers` in the same direction R1 already took for `marketplace_listings`.
