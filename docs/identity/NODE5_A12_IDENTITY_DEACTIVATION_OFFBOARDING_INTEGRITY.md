# NODE 5 · A12 — IDENTITY DEACTIVATION / OFFBOARDING INTEGRITY

Status: **READY / CERTIFIED**
Suite: `_qa_node5_identity_a12` — **122 / 122 · 0 failed**

Board after A12 (no earlier count changed):
- **Canonical: 5,669** = 5,547 (A11) + 122
- **Raw: 5,747** = 5,625 (A11) + 122 (raw keeps the Bonbonna +78 component suites that canonical does not double-count)

## Frozen Node 5 law (regression law for A12 and later)

Recorded in `NODE5_A11_ADMIN_STAFF_IDENTITY_SEPARATION.md`:

> Professional authority comes only from the professional identity lane. Governance
> authority comes only from the governance/staff systems. Money, UI mode, JWT
> metadata, historical artifacts, and membership in the other axis confer neither.
> A human may lawfully possess both axes, but each remains independently granted,
> revoked, audited, and restored.

## Preflight inventory — actual state model

| Surface | Canonical source | Active semantics | Notes |
|---|---|---|---|
| Professional lane | `professional_identities` | `claim_state ∈ {active, released}`; partial unique index on active | `released` is **terminal** (`_professional_identity_guard`); restoration appends a new row |
| Lane mutation | `_professional_identity_claim` / `_professional_identity_release` | internal only | revoked from `anon` and `authenticated` |
| Driver operation | `driver_profiles.status/presence` | `approved` + active lane | `_driver_class_active`, `_driver_operational_require` |
| Merchant operation | `merchant_stores` / `food_restaurants` | `status='active'` + active lane | `_merchant_class_active`, `_merchant_store_require` |
| Governance grade | `admin_users(admin_role, status)` | `status='active'` | `is_admin`, `is_any_admin`, `_is_god_admin`, `_is_ops_or_god_admin` |
| Staff roles | `user_roles` | row presence | `has_role`; write-guarded to god admin |
| UI context | `user_preferences.app_mode` | never authority | `account_mode_context` re-derives from the lane |
| Finance gates | `mission_financial_holds`, `driver_profiles.cash_debt_gnf`, `merchant_payables`, `merchant_settlement_requests` | | consulted, never mutated by offboarding |

### Gaps found (2)

1. **No governance-scoped lifecycle entrypoint.** Suspending an admin or removing a
   staff role required raw table DML; `authenticated` holds no `DELETE` on
   `user_roles` / `admin_users` (correct A11 posture), so there was no lawful,
   audited path at all.
2. **No admin professional offboarding path.** `professional_identity_self_release`
   only covers pre-approval safe abandonment. There was no atomic,
   finance-gated way to stand an approved driver or merchant down while
   preserving artifacts, nor an explicit restoration that refuses to
   auto-restore operational approval.

Everything else was already correct and was **proved, not churned**: lane
terminality, class helpers reading canonical tables only, stale `app_mode`
non-authority, forged-claim rejection, A11 grant posture.

## Remediation — six functions, no schema change

| Function | Purpose |
|---|---|
| `admin_governance_set_status(uuid,text,text)` | audited `active` ↔ `suspended`; refuses self-suspension |
| `admin_staff_role_grant(uuid,text,text)` | audited, idempotent; refuses professional roles |
| `admin_staff_role_revoke(uuid,text,text)` | audited; refuses professional roles |
| `professional_offboard_blockers(uuid)` | read-only finance/eligibility surface |
| `admin_professional_offboard(uuid,text)` | fail-closed lane stand-down + artifact suspension |
| `admin_professional_restore(uuid,text,text)` | explicit lane restoration only; never re-grants roles or approval |
| `_governance_role_allowed(text)` | internal governance-role whitelist (revoked from `anon` **and** `authenticated`) |

No table, column, enum, policy, flag, pricing or payout law changed. No live
identity was mutated.

## Authority transition matrix (certified)

| Case | Transition | Proven result |
|---|---|---|
| A | admin active → suspended → restored | all governance predicates drop, then return at the same grade; row preserved; no lane created |
| B | staff role removed → restored | `has_role` false then true; no governance grade created; idempotent re-grant |
| C | driver active → offboarded → restored | lane released, profile suspended-not-deleted, wallet intact; restoration returns the lane but **not** approval |
| D | merchant active → offboarded → restored | lane released, store suspended-not-deleted, wallet intact; restoration does **not** reactivate the store |
| E | admin+driver, governance only | governance gone, driver lane + approval + wallet + workspace all still usable |
| F | admin+merchant, professional only | merchant class gone, governance still exercises a real admin RPC |
| G | staff+professional | staff whitelist refuses professional roles in both directions |
| H | stale mode / forged claim / old role / old artifact / old wallet | all non-authoritative; canonical refusal each time |
| I | finance-bearing professional | fails closed on open hold and on cash debt; settles → offboards with balance and history intact |

## QA matrix — `_qa_node5_identity_a12` (122 assertions)

| Block | Count | Proves |
|---|---|---|
| A Structure / grants / source-of-truth | 12 | entrypoints exist, are SECURITY DEFINER, unreachable signed-out; no parallel status system; A11 grant posture intact; offboard contains no destructive DML; restore contains no role/approval grant |
| B Admin-only offboarding | 10 | exact before/after transition; all four governance predicates drop; row preserved; suspended admin cannot act; self-suspension refused |
| C Staff revocation | 11 | exact row delta against a captured fixture baseline; axis violations refused in both directions with the exact error; idempotent restore |
| D Driver lifecycle | 12 | operational before, refused after; profile/approval timestamp/wallet preserved; restoration withholds operational authority; reactivation duplicates no wallet |
| E Merchant lifecycle | 12 | store suspended not deleted, onboarding approval preserved; supply origination refused; store count unchanged |
| F Overlap — governance isolation | 10 | driver lane, profile, wallet, workspace and live capability all survive governance revocation |
| G Overlap — professional isolation | 10 | governance survives professional offboarding and executes a real admin RPC; release terminal + append-only provenance |
| H Stale / forged authority | 11 | stale `app_mode` row on disk yet effective mode collapses to client; forged professional and forged governance claims both refused; retained role/artifact/wallet each first proven present, then proven powerless |
| I Finance-safe offboarding | 10 | blocker surface names the exact obligation; two distinct fail-closed paths; blocked attempt mutates nothing; settled offboard preserves balance 5000 and a single wallet |
| J Audit / provenance | 6 | four audited actions with before/after payloads; release reason retained; history appended |
| K Residue / non-drift | 18 | 14 table baselines restored, governance snapshot byte-identical to the immutable pre-suite snapshot, flags unchanged, zero governance/professional/finance residue |

Quality rules honoured: every refusal asserts an exact canonical error string or a
narrowly enumerated set; every "X grants nothing" assertion first proves X exists;
pre/post comparisons use immutable baselines captured before any fixture.

## Live census (read-only)

12 active professional lanes (6 driver / 6 merchant), 1 governance account,
0 lawful admin×professional overlaps, 0 released-but-artifact-active accounts,
0 pending finance holds.

## Security / stale-authority proof boundary

A real JWT refresh cannot be simulated in SQL. The suite instead injects a forged
`request.jwt.claims` payload carrying `professional_type`, `app_mode`,
`is_admin`, `admin_role` and `role: service_role`, and proves the sensitive
helpers refuse it. H10/H11 additionally prove by source inspection that
`_driver_class_active`, `_merchant_class_active`, `professional_active_type` and
`account_available_modes` never read `request.jwt` and resolve only against
`professional_identities`. This is the exact boundary: **claim content is proven
non-authoritative; token issuance/refresh itself is out of scope.**

## Gates (run after the last edit)

| Gate | Result |
|---|---|
| A `_qa_node5_identity_a12` | **122 / 122 · 0 failed** |
| B Node 5 A2–A11 | 96, 119, 133, 111, 110, 130, 93, 121, 95, 108 — all 0 failed, all unchanged |
| C Full Node 0–4 board | 0 failed. `_qa_node4_marche_r4` hit the known harness statement timeout in the sequential run and passed solo: 79 / 79 · 0 failed (harness runtime, not an assertion failure) |
| D TypeScript | `bunx tsgo --noEmit -p tsconfig.app.json` — exit 0 |
| E Vitest | 19 files / 155 tests passed |
| F Build + PWA | `bun run build` OK in 25.50s; generateSW, **136 precache entries** (12,057 KiB); pre-existing chunk-size warnings only |
| G Linter | **658** (A11 baseline 652 **+6**). The +6 are exactly the six new SECURITY DEFINER entrypoints under the already-accepted `0029 authenticated_security_definer_function_executable` class; no new finding class and no `anon`-executable finding. Accepted baseline moves 652 → 658 |

## Non-drift after last edit (vs A11 baseline)

| Metric | A11 | A12 |
|---|---|---|
| profiles | 1,534 | 1,534 |
| active professional identities | 12 (6/6) | 12 (6 driver / 6 merchant) |
| governance accounts | 1 | 1 |
| lawful overlaps | 0 | 0 |
| merchant stores | 6 | 6 |
| driver profiles | 6 | 6 |
| wallets | 71 (61/5/4) | 71 (61 client / 5 driver / 4 merchant) |
| ledger postings / sum | 120 / 0 | 120 / 0 |
| pending finance holds | 0 | 0 |
| feature flags enabled | 11 | 11 |
| A12 fixture residue | — | 0 |

## Files / migrations

- Migrations: A12 lifecycle RPCs + grants; `_qa_node5_identity_a12` creation; one
  corrective replacement of that certification function (six assertions were
  measuring baseline fixture roles/wallets rather than the claimed property —
  law unchanged, proof tightened).
- `supabase/functions/qa-node-harness/index.ts` — registers
  `_qa_node5_identity_a12`; redeployed.
- `docs/identity/NODE5_A11_ADMIN_STAFF_IDENTITY_SEPARATION.md` — frozen-law section.
- `docs/identity/NODE5_A12_IDENTITY_DEACTIVATION_OFFBOARDING_INTEGRITY.md` — this file.

## Unresolved risks

- Restoration of a released lane appends a **new** identity row (release is
  terminal by A3 law). Consumers that assume one row per user must read the
  active row, never `LIMIT 1` by user.
- Merchant offboarding suspends stores and restaurants but leaves already-committed
  Marché/Repas orders to complete under existing fulfillment law; A12 deliberately
  invents no cancellation policy for in-flight orders.
- The +6 linter delta is accepted posture, not a reduction.
- `_qa_node4_marche_r4`, `r10` and `r65` remain near the harness statement-timeout
  ceiling; sequential board runs stay non-deterministic in runtime, not in law.
- A12 covers database law; no UI regression pass was performed.

**VERDICT: NODE 5 · A12 — READY.** Stopping here; A13 not started.
