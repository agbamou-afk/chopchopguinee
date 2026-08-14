# node3-repas-r8-discovery-truth-stable

VERDICT: GO — R8 final certification closeout complete.
HEAD: 2ae03c465d28555c679281265345d945f51d8d56 (git status clean)

## Closeout corrections
- Publication bypass closed: `repas_quote_preview` and `repas_order_create` both call
  `_repas_assert_orderable_publication` and fail closed with `RESTAURANT_NOT_PUBLISHED`
  unless `status='active' AND verification_state='verified'`, before any durable
  order/mission/money state. Not RLS-dependent.
- `repas_admin_set_publication(...,'publish')` refuses zero-menu supply (`PUBLISH_REQUIRES_MENU`).
  A restaurant whose real menu is temporarily unavailable may still publish (shown non-orderable).
- QA fixtures modernized to `verified` through the trusted fixture context; production guard untouched.
- `RepasRestaurantDetail`: canonical fetch resolution (`loading|found|unavailable`); after resolution a
  NULL/error result is treated as unavailable and disables add/cart/checkout. No stale-snapshot fallback.
  Unsplash fallback replaced by a neutral CHOPCHOP placeholder (gradient + icon).
- `RestaurantCard`: prep estimate labelled `Préparation ~N min` (never a delivery ETA).
- `FoodView`: marketplace-empty = `Aucun restaurant disponible pour le moment`; search-empty = `Aucun résultat`.
- Admin ops truth: `repas_admin_restaurant_overview()` (staff-only) + expanded `/admin/repas` table —
  owner, merchant-store link/status, publication + canonical status, open state, available/total menu,
  delivery/pickup/Chop Pay capability, coordinates completeness, derived discoverable/orderable truth.
  No fabricated ratings/orders/revenue/traffic.

## Board (after last edit)
- R8 dedicated QA: 142/142 PASS (was 89) — adds draft quote/commit refusal before money,
  zero-menu publish refusal, anon/stranger mutation proofs, hidden draft/suspended reads,
  and a non-vacuous historical R7 receipt-freeze proof across menu mutation + suspension.
- R7 203/203 · R6 171/171 · R5 static 71/71 + runtime 91/91 · R4.5 64/64 · R1–R4 148/148
- Course 34/34 · Bonbonna full/base/matrix/sweeper 78/24/39/15 · Taxi 97/97
- Slice 13 parts 1–7: 18+32+54+98+115+87+103 = 507/507 PASS
  (parts 4–7 executed on the privileged path and recorded in `_qa_s13_results`; no grant weakening)
- Vitest 53 passed (10 files, incl. new `repas-r8-discovery-truth.test.ts`)
- `tsgo --noEmit -p tsconfig.app.json` clean · production build PASS · PWA generateSW, 134 precache entries

## Posture
- Ledger posting sum 0 · imbalanced journals 0 · master wallet -100435 / held 0 (unchanged)
- Feature flags unchanged · R8 fixture residue 0
- Live supply: 0 discoverable restaurants, 0 with available menu. `Le bon coin` untouched
  (active, verification_state none, zero menu) and therefore yields zero customer supply.

## Honest limitations
- Anonymous INSERT rejection is proven live through the public API (HTTP 42501, zero rows) and in-harness
  via policy-predicate proofs; `SET ROLE` is not possible inside SECURITY DEFINER harnesses.
- No realtime system was added; suspension truth surfaces on refetch/reopen.
