# node3-repas-r5-pricing-certified-stable

Status: CERTIFIED (engineering) — activation still OFF
HEAD at certification: 27f817ee51ca7ab6eea8809908ce7f529383aa0c (plus this closeout commit)
Date: 2026-08-14

## Scope
Repas R5 pricing control-plane certification closeout. No feature activation,
no wallet normalization, no Course/Bonbonna/Taxi or Slice 4/5/8 semantic change.

## Corrections landed in this pass
1. Quote menu truth — `repas_quote_preview` rejects unavailable dishes with the
   canonical `ITEM_UNAVAILABLE`, refuses non-active restaurants with
   `RESTAURANT_NOT_ORDERABLE`, and reports `restaurant_open` / `orderable`.
2. Distance preview truth — when a `delivery_max_distance_km` policy exists and
   authoritative distance cannot be computed (restaurant or destination
   coordinates missing), quote returns `delivery_eligible=false`,
   `distance_verified=false` and a truthful reason; commitment fails closed with
   `DELIVERY_DISTANCE_UNVERIFIABLE`.
3. Promotion shape — promotions are restricted to `delivery` scope by table
   constraint and by `admin_set_repas_promotion`. No silent no-op pickup promos.
4. Legacy — `repas_delivery_earning_gnf()` is a deprecated policy-driven shim;
   15 000 GNF is no longer encoded as product law in QA or production.
5. Client truth — checkout is blocked whenever the server quote is missing or
   `delivery_eligible=false`; base price, promo discount, platform fee, total and
   measured distance are rendered from the quote only.

## Production defect found and fixed by the runtime harness
`_chop_pay_courier_adjust_internal` posted the ledger entry with the actor uuid
in the `p_mission_type` slot, so the courier subsidy / delivery-margin settlement
raised `function _ledger_post(...) does not exist` whenever the customer delivery
price differed from the courier payout. Only reachable once R5 allowed that
divergence (promotions / margin). Now posted with named arguments.

## Certification board (all after the last edit)
| Suite | Result |
|---|---|
| Repas R5 static | 71/71 PASS |
| Repas R5 runtime (non-vacuous, real fixtures/orders) | 91/91 PASS |
| Repas R4.5 pickup | 63/63 PASS |
| Repas R1–R4 | 147/147 PASS |
| Course (Node 0) | 34/34 PASS |
| Bonbonna full / base / matrix / sweeper | 78 / 24 / 39 / 15 PASS |
| Taxi (Node 2) | 97/97 PASS |
| Slice 13 parts 1–7 | 18+32+54+98+115+87+103 = 507/507 PASS |
| Vitest | 28/28 PASS |
| tsgo --noEmit | clean |
| Production build + PWA generateSW | PASS (134 precache entries) |

The runtime harness proves with real committed orders: policy-driven quote and
order, an effective-dated policy change repricing only NEW orders, over-limit and
unverifiable distance refused with zero order/mission/value, unavailable dish
refused at both quote and commitment, policy-driven delivery and pickup fees,
mission-less pickup with zero courier economics, a promotion lowering only the
customer price while the courier is paid in full (customer 170 000 = merchant
150 000 + courier 18 000 + platform 2 000), inert replay, frozen economics after
a later policy change, fail-closed invalid/unauthorised admin pricing, cash
refusal for both pickup and subsidised delivery, zero-sum journals, no
over-consumed holds and zero fixture residue.

## Final posture (unchanged by this pass)
- Flags: all chop_pay_*, cash_order_funding_enabled, om_repas_checkout_enabled,
  envoyer_*, taxi = OFF. `repas` = ON (browse only).
- Master wallet: balance -100 435 GNF, held 0 — deliberately NOT normalized.
- Ledger: postings sum 0, imbalanced journals 0.
- Approved live `livraison` couriers: 0 (supply blocker, unchanged).
- Effective Repas policy: delivery flat fee 15 000, courier payout 15 000,
  transaction fee 100 bps, max distance 10 km, pickup fee bps NULL (falls back to
  transaction fee), collateral 50% of merchandise, min driver balance 5 000.
- Active promotions: 0.
- Fixture residue: 0 restaurants, 0 policies, 0 promotions.
- Live data note: 1 active restaurant has no coordinates, so delivery is now
  honestly refused for it until it is mapped.

## Honest limitation
Distance is server-authoritative **straight-line geodesic (Haversine)**, not road
route distance. No trusted server routing API is wired; the quote reports
`distance_method = geodesic_straight_line`. Zone enforcement is therefore
conservative relative to real driving distance.

## Not done on purpose
Promotion max-redemptions/budget caps, pickup-price promotions, road-route
distance, and any activation.
