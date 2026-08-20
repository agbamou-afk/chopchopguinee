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
