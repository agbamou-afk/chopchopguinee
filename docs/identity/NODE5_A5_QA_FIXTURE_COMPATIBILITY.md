# Node 5 · A5 — QA Fixture Compatibility Note

Status: **QA-ONLY REMEDIATION — COMPLETE**
Canonical board after this pass: **4,890 / 4,890 · 0 failed**

## Why this note exists

Node 5 A5 introduced the canonical requirement that a Driver capability-bearing
`driver_profiles` artifact may only exist when the account already holds an
**ACTIVE DRIVER professional lane** (`_driver_capability_guard` →
`_driver_capability_lane_gate`, refusal `PROFESSIONAL_IDENTITY_REQUIRED`).

Historical QA Driver fixture constructors composed identity in the pre-Node-5
order: they inserted `driver_profiles` directly and relied on the A3 artifact
guard to claim the lane inside the same statement. Because Postgres fires
BEFORE-row triggers in alphabetical name order, `driver_capability_guard` runs
before `professional_lane_guard`, so the default capability `{rides_moto}` was
evaluated before the lane existed and those fixtures aborted.

Production is unaffected: `driver_apply` claims the lane before composing the
artifact, and all live Driver accounts already hold ACTIVE DRIVER lanes
(6 / 6, zero capability-without-lane rows).

## What was changed

QA fixture **setup only**. Every affected constructor now composes identity in
canonical order:

```
QA user → PERFORM public._professional_lane_require(uid, 'driver', 'qa_fixture')
        → INSERT INTO public.driver_profiles(...)
        → test → cleanup (auth.users delete cascades the identity row)
```

No product guard, capability semantics, identity semantics, RPC behaviour,
finance rule, RLS policy, grant or feature flag was modified. No product
assertion was removed, softened or re-counted.

- Affected suites: **18** (Slice13 ×7, Repas ×4, Marché ×7)
- Unique fixture constructors repaired: **14**
- Driver fixture composition sites repaired: **29**
- Claim provenance recorded truthfully as `qa_fixture`
- QA residue after the pass: `professional_identities WHERE claim_source='qa_fixture'` = **0**

### Suite → constructor map

| Constructor (repaired) | Suites served |
| --- | --- |
| `_qa_s13_driver` | s13 run3, run5, run6, run7, Marché r5/r7/r8/r9/r10/r11/r14 |
| `_qa_s13_run1` | Slice13 run1 |
| `_qa_s13_run2` | Slice13 run2 |
| `_qa_s13_run3_fxcore` | Slice13 run3 |
| `_qa_s13_run4` | Slice13 run4 |
| `_qa_node0_course` | Node 0 Course |
| `_qa_node1_bonbonna`, `_qa_node1_bonbonna_matrix` | Node 1 Bonbonna full |
| `_qa_node2_taxi_full` | Node 2 Taxi |
| `_qa_node3_repas_r1_r4_fxcore` | Repas r1–r4 |
| `_qa_node3_repas_r5_runtime_core` | Repas r5 runtime |
| `_qa_node3_repas_r6_custody_fxcore` | Repas r6 custody |
| `_qa_node3_repas_r7_ext`, `_qa_node3_repas_r7_semantics` | Repas r7 tracking/receipt |

## Observation carried forward (not fixed in this pass)

The A3 documentation property "a direct `driver_profiles` insert claims the lane
inside the same statement" now holds only for capability-free inserts, because
the capability guard is alphabetically ordered ahead of the lane guard. This is
a trigger-ordering interaction, not a hole: no capability-bearing Driver artifact
can exist without an ACTIVE DRIVER lane through any path. Reordering (or folding
the capability check behind the lane claim) belongs to A6 — Driver Architecture
Migration, where Driver authority is systematically derived from professional
identity.
