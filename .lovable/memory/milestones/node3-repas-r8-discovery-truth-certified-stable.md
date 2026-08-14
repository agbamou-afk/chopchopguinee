# Milestone — node3-repas-r8-discovery-truth-certified-stable

Scope: Node 3 Repas R8 — Discovery Truth / Real Supply certification.
No changes to R5 economics, R6 custody, or R7 tracking/receipt semantics.

## What this certifies
Repas discovery shows only real, server-verified supply, and never advertises a
channel the server would refuse.

- Publication signal: `verification_state` (draft / verified / suspended / rejected).
- Channel split: `orderable_pickup` and `orderable_delivery` are independent server truths.
- Canonical refusal codes: `RESTAURANT_CLOSED`, `NO_AVAILABLE_ITEMS`,
  `DELIVERY_DISTANCE_UNVERIFIABLE`, `not_published`.
- `delivery_destination_check_required` states plainly that the customer address
  is only verified at quote time; discovery never pre-approves a destination.
- Discovery publishes no distance value, no ETA, no rating, no owner identity,
  no merchant contact, no finance or custody internals.
- Quote is the authority for destination eligibility; order creation fails closed
  on unpublished, closed, and out-of-stock supply before any durable state.
- Discovery is economically inert: no order, mission, wallet movement, or journal.

## New QA harness
`public._qa_node3_repas_r8_discovery_truth()` (staff/service only) =
`_qa_node3_repas_r8_core()` + `_qa_node3_repas_r8_extra()` + new `_qa_node3_repas_r8_channel()`.

Result: **202 assertions / 0 failed**.

Two defects were found and corrected while building it:
1. Static check `P0.14` banned the substring "distance" outright, which conflicted with
   the legitimate delivery max-distance policy read. Replaced with the real intent:
   the discovery signature must publish no distance/ETA/rating value.
2. Assertion drift against real column and payload names
   (`food_orders.user_id`, `wallets.owner_user_id`, quote `ineligible_reason`).

## Frozen board (after the last edit)
| Suite | Total | Failed |
|---|---|---|
| Node 0 Course | 34 | 0 |
| Node 1 Bonbonna | 78 | 0 |
| Node 2 Taxi | 97 | 0 |
| Repas R1–R4 | 148 | 0 |
| Repas R4.5 Pickup | 64 | 0 |
| Repas R5 rails | 1 | 0 |
| Repas R5 runtime | 91 | 0 |
| Repas R6 Custody | 171 | 0 |
| Repas R7 Tracking/Receipt | 203 | 0 |
| Repas R8 Discovery Truth | 202 | 0 |

Vitest: 53 passed (10 files). Typecheck: exit 0. Production build: PASS.

## Verdict
GO — Node 3 Repas R8 Discovery Truth / Real Supply certified.
Live supply remains thin (unverified restaurants are correctly invisible); onboarding
real verified restaurants is an operations task, not an engineering blocker.
