---
name: Node 5 · A3 Professional Lane Claim — Certified
description: Professional lane exclusivity (customer holds at most one active driver OR merchant class) enforced unbypassably through every onboarding path; certified 118/118, board 4,723/0
type: feature
---

# Node 5 · A3 — Professional Lane Claim (LOCKED)

Certified: `_qa_node5_identity_a3()` **118/118 PASS**. Full frozen board (46 suites, Node 0
through Node 5 A3): **4,723 assertions · 0 failed**. Vitest 155/155, typecheck clean.

## Frozen law

- Every account is a customer. At most **one active professional class**: none / driver / merchant.
- Refusal code: `PROFESSIONAL_IDENTITY_CONFLICT`.
- Lane claim happens in the same statement as the onboarding artifact write (rollback together).
- Lane active ≠ approved. Driver/store approval remains domain-sovereign.
- Suspended or rejected domain state does NOT free the lane.
- Release creates history; re-entry creates a NEW identity row. Released rows are immutable.
- Admin cannot bypass exclusivity, in any direction, on create or on ownership transfer.

## Enforcement points (do not weaken)

- `professional_identities` partial unique index `(user_id) WHERE claim_state='active'`.
- `_professional_lane_require` / `_professional_identity_claim` / `_professional_identity_release`
  — SECURITY DEFINER, `search_path=public`, **no anon or authenticated EXECUTE**.
- BEFORE INSERT OR UPDATE trigger `professional_lane_guard` on: `driver_profiles`,
  `driver_applications`, `merchant_stores`, `food_restaurants`, `merchants`.

## Notes discovered during certification

- `merchant_stores` has a unique constraint on `owner_user_id`: one store per merchant owner.
- Assigning the protected roles (`admin`, `god_admin`, `operations_admin`, `finance_admin`)
  requires a god_admin session; server-side (no JWT) provisioning is allowed.

## Client

`useProfessionalLane` + `ProfessionalLaneBlocked` gate `DriverApply` and `MerchantOnboarding`
with honest French copy. Client gating is convenience only — the server is the authority.

Docs: `docs/identity/NODE5_A3_PROFESSIONAL_LANE_CLAIM.md`

## Post-A4 QA compatibility note (2026-08-21)

A3's governing law is unchanged. A4 superseded two *implementation details* A3 had
asserted, so exactly two A3 assertions were refreshed (QA only, no product change):

- Driver claim provenance moved from the artifact-trigger path to an explicit
  `driver_apply` composition (`_professional_lane_require(uid,'driver','driver_apply')`
  runs before the artifact write, so re-entry after release reclaims correctly).
  `N5A3.B6` now proves provenance + `claimed_at <= driver_profiles.created_at`.
- Merchant store ownership uniqueness moved from full uniqueness
  (`merchant_stores_owner_user_id_key`) to partial uniqueness
  (`merchant_stores_owner_active_uidx`, `WHERE status <> 'archived'`), preserving
  abandoned store history. `N5A3.D5` now asserts the partial predicate semantically,
  and new `N5A3.D5c` proves archived history never blocks lawful re-entry.

A3 total: 118 → 119 (one added assertion, none removed). Board through A4: 4,779 / 0.
