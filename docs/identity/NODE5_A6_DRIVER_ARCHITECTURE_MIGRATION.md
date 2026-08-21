# NODE 5 · A6 — DRIVER ARCHITECTURE MIGRATION

Status: **CERTIFIED**
Suite: `_qa_node5_identity_a6()` — **110 / 110 PASS**
Full canonical board: **5,078 assertions · 0 failures**

## Canonical question

> IS THIS ACCOUNT PROFESSIONALLY A DRIVER?

Canonical answer, and the only one any Driver surface may consult:

> An **ACTIVE** row in `public.professional_identities` with `professional_type = 'driver'`.

Roles (`user_roles`), `driver_profiles.status`, capabilities, wallets and mission
assignment are **not** answers to that question. They answer different questions.

## The four independent layers

| Layer | Question | Source of truth | Refusal |
|---|---|---|---|
| CLASS | Is this account a Driver at all? | `professional_identities` (active) | `PROFESSIONAL_IDENTITY_REQUIRED` / `PROFESSIONAL_IDENTITY_CONFLICT` |
| OPERATIONAL STATUS | Is this Driver allowed to work right now? | `driver_profiles.status` | `DRIVER_NOT_OPERATIONAL` |
| CAPABILITY (A5) | Is this Driver allowed to do *this kind* of work? | `driver_profiles.capabilities` | `DRIVER_CAPABILITY_MISSING` |
| OBJECT | Is this Driver the assigned party for *this* row? | the row itself | frozen per-service message |

Layers are never collapsed. The class gate reads no status and no capabilities
(certified: `N5A6.A17`, `N5A6.A18`).

## Canonical primitives

| Function | Layers enforced |
|---|---|
| `_driver_class_active(uuid) → boolean` | CLASS (predicate, for queries) |
| `_driver_class_require(uuid, ctx)` | CLASS |
| `_driver_operational_require(uuid, ctx, capability)` | CLASS → STATUS → CAPABILITY |

All three are `SECURITY DEFINER`, `STABLE`, `search_path=public`, and revoked
from `anon` and `authenticated`. They are internal to server-authoritative RPCs.

## Migrated authority surfaces (24)

**Class gate — in-flight work (a suspended Driver may finish an assigned job,
a non-Driver may not touch it at all):**
`driver_set_status`, `driver_offer_accept`, `driver_offer_decline`,
`driver_update_location_signal`, `ride_accept`, `ride_start`, `ride_complete`,
`ride_set_phase`, `mission_set_state`, `mission_confirm_pickup`,
`mission_confirm_dropoff`, `mission_confirm_pickup_with_proof`,
`mission_confirm_dropoff_with_proof`, `mission_report_issue`,
`repas_custody_confirm_handoff`, `repas_custody_confirm_delivery`,
`package_verify_pickup`, `package_verify_delivery`,
`marche_courier_transition`, `_marche_pm_shopper_lock`.

**Operational gate — acquiring new work:**
`mission_claim`, `marche_shopper_claim`.

**Administrative / dispatch:**
- `driver_admin_decide` — approval and reactivation now refuse a target that
  does not hold the ACTIVE DRIVER class (`PROFESSIONAL_IDENTITY_CONFLICT`).
  Admin authority can no longer manufacture a Driver out of a non-Driver.
- `ride_dispatch` — candidate selection filters on `_driver_class_active`, so a
  released or wrong-class account is invisible to dispatch even if its legacy
  `driver_profiles` row is still `approved` and `online`.

Gates are inserted **after** existing object/ownership validation, so every
frozen service refusal message keeps its original priority.

## Ordering guarantee

Every gate is placed after the object lookup and before any state mutation, so
a refusal is always total: no presence change, no offer consumption, no
mission transition, no wallet or ledger effect (`N5A6.G2`, `N5A6.I2`, `K1`, `K2`).

## Onboarding creation path

`driver_apply` is the only production path that creates `driver_profiles`, and
it claims the Driver lane before writing the artifact — satisfying the A3
`_professional_lane_require` and A5 `_driver_capability_guard` trigger ordering
unchanged. A6 adds no new creation path.

## Worst-case certification fixture

The suite's decisive fixture is an account that is *operationally perfect and
professionally illegitimate*: a released ex-driver whose `driver_profiles` row
is still `approved`, still capability-bearing, and still online. Every Driver
authority surface refuses it (`N5A6.C5–C7`, `D5`, `E5`, `F5`, `G1–G3`, `H1`, `I1`, `J1`).

## Non-goals honoured

No changes to pricing, fares, commissions, wallets, ledger, mission lifecycle,
Repas/Marché product law, merchant lane behaviour, or the A5 capability
vocabulary. Merchant lane verified untouched (`N5A6.K5`, `K6`).

## Verdict

**NODE 5 · A6 — CERTIFIED.** Ready for A7.
