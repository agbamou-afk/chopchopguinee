# NODE 5 · A11 — ADMIN / STAFF IDENTITY SEPARATION

Status: CERTIFIED (remediated closeout, 2026-08-21)
Suite: `_qa_node5_identity_a11` — **108 / 108 · 0 failed**

Board after A11:
- **Canonical: 5,547** = 5,439 (A10 canonical) + 108
- **Raw: 5,625** = 5,517 (A10 raw) + 108
  Raw includes the Bonbonna +78 component suites that canonical does not double-count.

## Law

Two independent authority axes, neither inferred from the other:

- **Governance / staff axis** — `admin_users` (grade + status) and `user_roles`
  (staff roles: `field_captain`, `onboarding_specialist`, …), read only through
  `is_admin`, `is_any_admin`, `has_admin_role`, `_is_god_admin`,
  `_is_ops_or_god_admin`, `_finance_privileged`, `_repas_caller_is_staff`.
- **Professional axis** — `professional_identities` (Driver XOR Merchant), read
  through `professional_active_type`, `_driver_class_active`,
  `_merchant_class_active`, `account_available_modes`.

Enforced rules:

1. Governance authority never creates or implies a professional lane, workspace
   mode, driver profile, store, professional wallet, or driver capability.
2. Professional identity never implies governance; admin RPCs answer `forbidden`.
3. Lawful overlap (real admin who is also a real approved driver/merchant) is
   allowed; each axis is satisfied only by its own canonical source.
4. Transitions are isolated: revoking governance preserves the lane and its
   approval; releasing a lane preserves governance.
5. Forged JWT claims (`is_admin`, `admin_role`, `professional_type`) grant nothing.

## Preflight finding and LIVE_REMEDIATIONS

**Account-level identity conflicts requiring remediation: 0.** The 12 live
professional accounts and the single live governance account contain no
cross-domain contradiction under A2–A10 law.

**LIVE_REMEDIATIONS = 1 ACL/security remediation (not an identity remediation).**
The preflight found that governance-bearing tables never received the A9 identity
hardening and still carried inherited broad grants — including `TRUNCATE` — for
`anon` and/or `authenticated`. Fixed in A11:

- `anon` now holds no privilege on `admin_users`, `user_roles`,
  `approval_requests`, `agent_profiles`, `field_pilots`, `field_assignments`,
  `audit_logs`.
- `authenticated` lost `DELETE`, `TRUNCATE`, `TRIGGER`, `REFERENCES` on those
  tables.
- `audit_logs` is now read-only for clients (writes remain service-role only).

## Final QA matrix — `_qa_node5_identity_a11` (108 assertions)

| Block | Count | Proves |
|---|---|---|
| A. Structure, storage separation, grants, RLS, policy hygiene | 17 | canonical sources are disjoint; governance tables locked down |
| B. Governance ⇒ no professional | 16 | admin cannot take a lane, a mode, a driver action, merchant supply, or another owner's store; B10 asserts the exact `not store owner` refusal |
| C. Staff classes (ops, finance, agent, field captain, onboarding) | 16 | each staff class is client-only on the professional axis and holds only its own governance predicate |
| D. Professional ⇒ no governance | 15 | driver/merchant refused governance RPCs; forged admin claims refused; D15 first asserts a real driver wallet exists, then that it grants no governance |
| E. Lawful overlap + revocation isolation | 14 | overlap works on both axes; revoking one axis leaves the other intact |
| F. Cross-axis transition isolation | 8 | grants/revokes on either axis never move the other; F8 checkpoints live non-fixture governance rows |
| G. Finance non-interference | 5 | ledger rows, ledger sum, wallet transactions unchanged; G5 compares `finance_policies` count **and** an md5 content fingerprint against the pre-suite baseline |
| H. Non-drift / zero residue | 17 | 15 table baselines restored; H4 compares the final governance snapshot to the **immutable pre-suite** snapshot (`b_gov_initial`); zero governance and professional residue |

Remediations applied to the proof itself in this pass: G5 was tautological,
H4 compared a final snapshot against itself, D15 claimed wallet evidence it never
checked, and B10 accepted any exception as success. All four now assert real
before/after or exact-refusal evidence.

## Gates (run after the last edit)

| Gate | Result |
|---|---|
| A. `_qa_node5_identity_a11` | 108 / 108 · 0 failed |
| B. Node 5 regressions | A2 96, A3 119, A4 133, A5 111, A6 110, A7 130, A8 93, A9 121, A10 95 — all 0 failed (unchanged) |
| C. Full Node 0–4 + Node 5 board | raw 5,625 · 0 failed; canonical 5,547 · 0 failed. `_qa_node4_marche_r10` hit the known harness-level statement timeout inside the sequential board run and was rerun solo: 127 / 127 · 0 failed. (`_qa_node4_marche_r65` hit the same timeout on the prior run and also passed solo: 249 / 249.) |
| D. TypeScript | `bunx tsgo --noEmit -p tsconfig.app.json` — exit 0 |
| E. Vitest | 19 files / 155 tests passed |
| F. Build + PWA | `bun run build` OK in 26.26s; PWA generateSW, **136 precache entries** (12,057 KiB); pre-existing chunk-size warnings only |
| G. Linter | 652 findings, identical composition to the A10 baseline — no new findings |

## Non-drift after last edit

| Metric | A10 baseline | A11 final |
|---|---|---|
| profiles | 1,534 | 1,534 |
| active professional identities | 12 | 12 (driver 6 / merchant 6) |
| governance accounts (`admin_users`) | 1 | 1 |
| lawful admin×professional overlap | 0 | 0 |
| merchant stores | 6 | 6 |
| driver profiles | 6 | 6 |
| wallets | 71 | 71 (client 61 / driver 5 / merchant 4) |
| ledger postings / sum | — / 0 | 120 / 0 |
| pending finance holds | — | 0 |
| feature flags enabled | — | 11 |
| A11 fixture residue | — | 0 |

## Head / files

- Clean HEAD immediately before A11 was `733aa4ec` per repository inspection.
  Neither the user-supplied baseline `22e1a532` nor the earlier agent claim
  `3f797ed7` appears in the recent history of this working tree; the repository
  is the authority here and the discrepancy is recorded rather than resolved in
  favour of either quoted hash.
- A11 implementation commit: `8b2c83ad` (harness registry edit + applied migrations).
- Files changed in A11: `supabase/functions/qa-node-harness/index.ts` (registers
  `_qa_node5_identity_a11`, redeployed) and
  `docs/identity/NODE5_A11_ADMIN_STAFF_IDENTITY_SEPARATION.md`.
- Migrations applied: governance-table grant hardening + `_qa_node5_identity_a11`
  creation, then three corrective replacements of that certification function
  (fixture column fix, presence assertion fix, and this pass's G5/H4/D15/B10
  proof remediation).

## Unresolved risks

- Product behaviour was not exercised end-to-end by A11; the gates above cover
  database law, types, unit tests and a production build, not UI regression.
  Claims of unchanged behaviour extend only that far.
- Two Marché harnesses (`r10`, `r65`) are near the harness statement-timeout
  ceiling and intermittently need a solo rerun. This is a runner-capacity issue,
  not a law failure, but it makes the sequential board run non-deterministic.
- The 652-item linter baseline (SECURITY DEFINER executability, RLS-enabled-no-
  policy) remains accepted project posture and was not reduced in A11.
