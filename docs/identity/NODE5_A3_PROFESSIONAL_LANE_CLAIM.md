# Node 5 · A3 — Professional Lane Claim (Unbypassable Exclusivity)

Status: **IMPLEMENTED / CERTIFIED**
Certification: `_qa_node5_identity_a3()` → **118 / 118 PASS**
Full frozen board: **4,723 assertions · 0 failed** (46 suites, Node 0 → Node 5 A3)

## Governing law

Every CHOPCHOP account is a customer account. A customer holds **at most one active
professional class**: none, driver, or merchant. Never both — through any path.

## How exclusivity is enforced

| Layer | Mechanism |
| --- | --- |
| Storage | `professional_identities`, partial unique index on `(user_id) WHERE claim_state='active'` |
| Claim | `_professional_lane_require(user_id, type, source)` (SECURITY DEFINER, `search_path=public`, server-only) |
| Guard | `_professional_artifact_guard()` BEFORE INSERT OR UPDATE row trigger |
| Guarded artifacts | `driver_profiles`, `driver_applications`, `merchant_stores`, `food_restaurants`, `merchants` |
| Refusal | `PROFESSIONAL_IDENTITY_CONFLICT` (machine readable) |

The claim happens **inside the same statement** that writes the artifact. If the artifact
write fails, the claim rolls back with it. If the lane conflicts, the artifact never exists.

## Certified properties

- Driver signup (`driver_apply`) claims the driver lane atomically; re-apply is idempotent
  (one identity row, one profile, application history preserved).
- Merchant ownership (store, restaurant, merchant entity) claims the merchant lane atomically.
  One professional class may hold several assets; it never creates a second identity row.
- A driver cannot create a store/restaurant/merchant; a merchant cannot apply as driver.
  Every refusal leaves **zero** residue: no artifact, no role, no wallet, no notification.
- Direct table writes under the `authenticated` role are denied; a signed-in user cannot
  rewrite its own professional class.
- **Admin does not bypass exclusivity.** An admin may still approve legitimate same-lane
  drivers and stores — approval is domain truth, identity is a separate truth.
- Ownership transfer to an opposite-lane user is refused; transfer to a lane-free customer
  atomically claims the merchant lane for the new owner.
- Released lanes are historical: re-entry creates a **new** row, the released row is never
  resurrected or mutated.
- Suspended / rejected domain state does **not** free the lane.
- No finance, role, mission or capability side effect is produced by a claim.

## Concurrency proof

Two simultaneous connections, same fresh user, opposite lanes
(`POST /driver_profiles` and `POST /merchant_stores` in parallel):

```
A: 201  (driver lane won)
B: 400  {"code":"P0001","message":"PROFESSIONAL_IDENTITY_CONFLICT"}
professional_identities → [{"professional_type":"driver","claim_state":"active"}]
```

Exactly one lane, exactly one artifact — the partial unique index plus in-statement claim
makes the race deterministic.

## Client surface

- `src/lib/identity/professionalIdentity.ts` — server-derived lane read (`professional_identity_current`).
- `src/hooks/useProfessionalLane.ts` — lane state + `blockedFor(...)` + French refusal copy.
- `src/components/identity/ProfessionalLaneBlocked.tsx` — honest refusal screen.
- Wired into `DriverApply` and `MerchantOnboarding`: the opposite lane never sees a form it
  cannot submit, and a server refusal is translated to plain French.

The client gate is convenience only. The server refuses regardless of the UI.

## Non-drift

The suite provisions and purges its own fixtures and asserts that profiles, auth users,
roles, wallets, ledger journals/postings and balance sum, driver/merchant artifacts,
identity census, approved-store population, Marché and Repas orders, price observations and
feature flags are all byte-identical before and after the run.
