# Node 4 — Marché R1: Listing & Publication Truth — CERTIFIED STABLE

Date: 2026-08-16 UTC
HEAD at certification: a48d8b30

## Root cause (anonymous read defect)
Signed-out reads of `marketplace_listings` / `listing_images` failed with
`permission denied for function has_role`. The canonical public listing path joins
`merchant_stores`; its single anon-reachable SELECT policy (`Public read approved stores`)
invoked `has_role(...)`, which `anon` may not execute.

## Narrow fix (DB policy scoping only, no app-code edits)
- Dropped `merchant_stores` policy `Public read approved stores`.
- Added `Anon read approved stores` — `TO anon`, SELECT,
  `status = 'active' AND onboarding_status = 'approved'` (no role-function call).
- Added `Auth read stores` — `TO authenticated`, SELECT, identical prior semantics
  (approved OR owner OR admin OR onboarding_specialist, still via `has_role`).
- No write policy, ownership rule, merchant approval truth, publication truth,
  media privacy rule or canonical listing filter was changed.
- `merchant_stores` is not broader than before for any role.

## has_role
`has_role` was NOT granted to `anon`. Verified: `has_function_privilege('anon', 'public.has_role(uuid,app_role)', 'EXECUTE') = false`.
Grants remain postgres / authenticated / service_role. Frozen Repas R8 invariant P15.5 intact.

## R1 harness
`_qa_node4_marche_r1()` → total 55, passed 55, failed 0. All three anonymous visitor
probes PASS with no permission-denied.

## Frozen board (actual returned counts, all failed = 0)
- Node0 Course 34
- Node1 Bonbonna 78
- Node2 Taxi Privé 97
- Repas R1–R4 148
- R4.5 Pickup 64
- R5 static 71 / R5 runtime 91
- R6 Custody 171
- R7 Tracking 203
- R8 Discovery 142
- R9 Recovery 68
- R10 Operations 134
- R11 Conakry 116
- Slice 13 runs 1–7: 18 + 32 + 54 + 98 + 115 + 87 + 103 = 507

## Client gates
- Vitest: 12 files / 71 tests PASS
- `tsgo --noEmit -p tsconfig.app.json`: exit 0
- Production build: OK; PWA generateSW: 134 precache entries, `dist/sw.js` generated

## Data / posture
- Demo supply quarantine unchanged: 47 demo-seller listings excluded from canonical
  discovery (6 of 53 listings discoverable), 0 rows deleted.
- `marketplace_listings` has no direct table grants for `anon`/`authenticated`;
  all client access flows through the canonical SECURITY DEFINER RPCs.
- Feature flags / activation posture unchanged (11 enabled, untouched).
- No finance, wallet, ledger, mission, courier or offer-economics change.
- Node 0–3 and Slice 13 contracts untouched.
- No QA fixture residue in business tables (Z-series residue checks PASS);
  harness output rows live only in the QA-only `_qa_s13_results` table.

## Residual limitations / non-goals (deferred beyond R1)
- Cart/checkout and Slice 13 runtime adoption for Marché.
- Offer economics, courier/mission wiring for marketplace delivery.
- Demo supply is quarantined, not purged.
- No feature activation, rollout or deployment performed.

STATUS: Node 4 — Marché R1 LOCKED.
