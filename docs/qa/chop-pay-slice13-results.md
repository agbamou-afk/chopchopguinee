# Slice 13 — Final Full Financial Regression (results)

Harness: service_role-only `_qa_s13_run1..run4()`, results stored in `_qa_s13_results`.
Every part builds its own fixtures inside one transaction and rolls the whole block back.

| Part | Scope | Result |
| --- | --- | --- |
| 1 | Stage isolation / flag gating | PASS 17/17 |
| 2 | Ride / Bonbonna (Stage 1) | PASS 32/32 |
| 3 | Repas / Marché cash + Chop Pay orders (Stages 2–4) | PASS 54/54 |
| 4 | Envoyer declared value, custody, claims, sandbox isolation | **PASS 98/98** |

## Part 4 — closeout coverage

- C1 exact declared-value ceiling boundary (accepted at the ceiling, refused one GNF above).
- C2 evidence photo privacy: storage RLS probed as owner, assigned courier, unrelated user, ops.
- C3 courier cancellation before custody: exact collateral release plus replay idempotency,
  through the real `package_courier_cancel` RPC.
- C4 full claims compensation cap.
- C5 sandbox ↔ production financial isolation (J series), including cross-environment intents:
  the sandbox finaliser refuses a production intent (`not_a_sandbox_intent`) and the production
  confirmation path refuses a sandbox intent
  (`sandbox_intent_use_om_payment_submit_sandbox_reference`) while the caller really holds
  `super_admin`.
- I series three-way claim cap:
  `max_compensation = LEAST(accepted_declared_value, documented_actual_value, active_claim_limit)`
  with a non-vacuous binding fixture for each of the three constraints, plus refusal to pay any
  money before a God-Admin-investigated documented value is persisted
  (`CLAIM_DOCUMENTED_VALUE_REQUIRED`).

## Post-run live posture (re-proved after every run)

- Master wallet `b6858980-…` = **-100435 GNF / held 0**.
- Global ledger posting sum = **0**, imbalanced journals = **0**.
- Feature flags byte-identical; all Envoyer / Chop Pay stage rails remain OFF, `om_topup_enabled`
  is the only finance rail ON. The sandbox rail is enabled only inside the rolled-back fixture.
- No fixture residue: 0 QA packages, 0 QA intents, 0 sandbox intents, buffer table dropped.
- `_qa_s13*` helpers: anon/authenticated EXECUTE denied, service_role only.
- `package_courier_cancel`: authenticated + service_role only, assigned-courier check,
  custody lock, idempotent replay.
