---
name: Node 4 — Marché R6.5 Procurement Basket + Authorization (Stable)
description: ChopChop procurement basket, server-sovereign estimate, explicit customer spending ceiling with Slice13 hold reuse, fail-closed on insufficient price data. Certified 248/248, board 3144 assertions / 0 failures. LOCKED.
type: feature
---

# Node 4 — Marché R6.5: Procurement Basket + Authorization — LOCKED

## Scope
Customer builds a basket from the R6 ChopChop staples catalog, receives a SERVER estimate,
and authorizes a MAXIMUM spend (ceiling) backed by a wallet hold. No shopper operations,
no substitutions, no market evidence UI, no price-intelligence aggregation (all R7).

## Product law
- **No invented price.** If any line lacks trustworthy observations, the server returns
  `estimate_status='insufficient_data'` and `marche_procurement_authorize` fails closed with
  `PROCUREMENT_ESTIMATE_INSUFFICIENT_DATA`. No fallback price, no customer-declared ceiling,
  no basket floor.
- **Estimate ≠ purchase price.** Ceiling must be `>= estimated_subtotal_gnf` and `<= max_ceiling_gnf`
  (app_settings `marche_procurement`, default 20 000 000 GNF).
- Settlement debits only actual spend up to the ceiling; unused authorization is released.
- Client is never authoritative for economics, authorization state or settlement.

## Finance posture (Slice13 reuse, not a parallel rail)
- Holds placed by the canonical `chop_pay_customer_hold_place` primitive.
- Capture/release go through the extracted generic `_customer_hold_capture_internal` /
  `_customer_hold_release_internal`; `_marche_procurement_capture_internal` /
  `_release_internal` are THIN adapters with no bespoke wallet math.
- No second wallets/holds/journal/refund/payment-intent system. Ledger sum remains 0.

## Server surface
`marche_procurement_quote|authorize|increase|cancel|get|list` (SECURITY DEFINER,
`search_path=public`), `marche_procurement_settle_internal` and
`marche_procurement_observation_record` privileged/service only.
Zero direct `anon`/`authenticated` grants on procurement tables; zero anon-executable
procurement RPCs; `has_role` still not executable by `anon` (Repas R8 P15.5 preserved).

## Client (R6.5 closeout)
- `src/lib/marche/procurement.ts` — thin typed RPC wrapper, line sanitizer (rejects merchant/price
  fields), durable `createProcurementRequestIdStore` idempotency keys, honest French copy helpers.
- `src/components/marche/ProcurementBasketSheet.tsx` — basket → server quote → insufficient-data
  state (authorization disabled) → estimate vs authorized-maximum distinction → ceiling presets
  (estimate / +10% / +20%, server-validated) → authorize. No shopper/settlement controls.
- `src/components/marche/StaplesView.tsx` — allowable-quantity steppers (min/max/step from server),
  add-to-basket, continue shopping, sticky basket bar.
- `src/test/node4-marche-r65-procurement-client.test.tsx` — 12 UI/law tests.

## Certification
- `_qa_node4_marche_r65()` → **248/248 PASS**, 0 failures, zero fixture residue after rollback.
- Full frozen board (29 parent suites: Node0 Course, Node1 Bonbonna full, Node2 Taxi, Repas
  pickup/R1–R4/R5/R5 runtime/R6/R7/R8 discovery-truth incl. P15.5/R9/R10/R11, Slice13 run1–7,
  Marché R1/R1.5/R2/R3/R3.5/R4/R5/R6/R6.5) → **3144 assertions, 0 failures, 0 errored**.
- Vitest 111/111, tsgo clean, production build + PWA (134 precache entries) OK.
- QA residue: diagnostic table `public._qa_r65_trace` (empty, unreferenced) dropped.

Status: LOCKED. No deploy, no flag activation.
