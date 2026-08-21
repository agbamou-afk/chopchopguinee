# NODE 5 — FINAL CLOSEOUT / CONSTITUTIONAL CHARTER

Closeout pass type: **Step E final verdict + documentation**. No product code, DB schema, migration,
policy, function, flag, pricing, payout law, harness credential or live user row was changed
in this edit. Only `docs/identity/NODE5_FINAL_CLOSEOUT.md` is mutated.

## 0. Chronology (do not conflate)

| Marker | SHA / Date | Meaning |
| --- | --- | --- |
| A13 certification code HEAD | `a12a999dc5b46ae0674f4b64c767bf8349884566` | pre-documentation/internal closeout |
| A13 closeout report commit | `80b5e406f0f73081e4bf18621e7bdc8ab5a0852d` | Lovable closeout edit |
| A13 bookkeeping correction | `20aabd91dc322e0735816fa1522e07b2da875b95` | docs-only; also A14 starting HEAD |
| A14 certification code HEAD | `fe72ef0df7137c36bc805e06eb51b481cf693cc8` | A14 implementation + docs |
| Node 5 final-closeout starting HEAD | `fe72ef0df7137c36bc805e06eb51b481cf693cc8` | code certified; `git status --porcelain` clean |
| Step A docs-only refresh | `5ee357d32df5421e9d1fb34012f568e5964177aa` | superseded pre-remediation closeout update |
| Step D certification HEAD | `9a16d119…` | 58 suites, 6,052/0 PASS; no new blocker beyond known finance-law gap |
| **Step E final verdict edit** | after `9a16d119…` | current document; verdict **HOLD** |

This document is a docs-only artifact created **after** `fe72ef0d`. Its own commit SHA is by
definition later than the code-certification HEAD and must never be quoted as the certification HEAD.

## 1. Node 5 constitutional charter (frozen)

1. **Customer identity is intrinsic and universal.** Professional class is canonical only
   through an ACTIVE `professional_identities` lane. UI mode, JWT claims, `user_roles`,
   wallets, artifacts and history are non-authoritative and confer nothing.
2. **Governance/staff authority is an orthogonal axis.** Lawful overlap is permitted; each
   axis is independently granted, revoked and restored. Neither axis implies the other.
3. **Offboarding revokes present authority, never historical identity or provenance.**
   Restoration is always explicit. Finance/operations may block an unsafe transition but
   never define authority.
4. **Contact/auth recovery restores access to the same canonical UUID only.** Phone and
   email are mutable contact/auth attributes, never ownership keys. A successor UUID
   inherits nothing by contact equality.
5. **Account closure ends access and present authority while preserving financial,
   professional, governance, operational and audit provenance.** PII may be released under
   policy; retained history stays bound to the closed UUID. Re-registration is a new
   identity, not resurrection.

Sub-pass sources: A2/A3 (lane design + claim), A5 (fixture compatibility), A6/A7 (driver &
merchant migration), A8 (unified mode switcher), A9 (UI context is never authority),
A10 (conflict remediation), A11 (admin/staff axis separation), A12 (offboarding integrity),
A13 (continuity/recovery integrity), A14 (closure/deletion/anonymization integrity).

## 2. Final remediation certification (measured post-remediation)

The final remediation pass introduced:
- `public.auth_uid_active()` — RLS helper that gates access to `account_status != 'deleted'`.
- `public.pgrst_pre_request()` — global PostgREST pre-request hook bound to `authenticator`,
  raising `ACCOUNT_CLOSED` for any deleted profile before RPC/REST requests reach the DB.
- `account_access_terminations` queue + `account-access-termination-worker` edge function
  for service-role/admin auth termination (ban + session/refresh revocation).
- `admin_account_closure_reconcile()` governance-idempotent RPC to stand down authority for
  legacy already-deleted accounts.
- Census predicates `_professional_conflict_scan()`, A2/A4/A5/A10 updated to exclude closed
  accounts in live-conflict interpretation.

Measured results:
- `_qa_node5_identity_final_remediation` — **100 / 100 PASS**.
- Full board — **6,052 raw assertions / 5,974 canonical assertions / 0 failures**.
- `tsgo --noEmit` — exit 0.
- Production build + PWA — built OK; generateSW produced 136 precache entries.
- Temporary QA `RUN` harness token slot and one-time reconciliation runner — **removed**.

## 3. Local gates / security linter (Step D audit complete)

| Gate | Result |
| --- | --- |
| `tsgo --noEmit` | exit 0 |
| Vitest | 19 files / 155 tests, all pass |
| Production build + PWA | built OK; 136 precache entries |
| DB / security linter | **662 findings** |

**Linter baseline.** The accepted A14 baseline is **658 findings**. The current remediation
surface added **+4 findings**, yielding **662**. Step D audited the exact attribution:

1. `public.auth_uid_active()` — signed-in SECURITY DEFINER executable.
2. `public.admin_account_closure_reconcile(uuid, text)` — signed-in SECURITY DEFINER executable.
3. `public.pgrst_pre_request()` — anonymous SECURITY DEFINER executable.
4. `public.pgrst_pre_request()` — signed-in SECURITY DEFINER executable.

All four are in the previously accepted SECURITY DEFINER-executable warning class and are
required by the remediation design. No new exposure class was introduced. Therefore,
**662 is recorded as the post-remediation measured/accepted security-linter baseline for this
frozen remediation state**. This acceptance does not change the Node 5 verdict, which remains
**HOLD** on the separate finance-law blocker described below.

The ESLint 666/113 figure is a separate, purely informational frontend measurement and is not
the same metric as the DB/security linter.

## 4. Live census / non-drift (read-only, post-remediation)

| Metric | Measured | Notes |
| --- | --- | --- |
| profiles | 1,534 | — |
| closed profiles | 6 | — |
| active professional lanes | **8** (driver **2** / merchant **6**) | 4 legacy closed driver lanes were lawfully released; expected remediation reduction, not drift |
| active governance accounts | 1 | — |
| lawful overlap (governance ∧ lane) | 0 | — |
| merchant stores | 6 | — |
| driver_profiles | 6 | — |
| wallets | 71 (incl. master 1) | — |
| ledger postings / sum | 120 / 0 | — |
| duplicate canonical wallets | 0 | — |
| duplicate active lanes | 0 | — |
| duplicate phones / non-canonical phones | 0 / 0 | — |
| enabled feature flags | 11 | — |
| active professional lanes on closed accounts | 0 | — |
| capability roles on closed accounts | 0 | — |
| approved/non-offline driver rows on closed accounts | 0 | — |
| pending ride offers on closed accounts | 0 | — |
| recovery material on closed accounts | 0 | — |
| active governance rows on closed accounts | 0 | — |
| banned closed accounts with 0 sessions / 0 refresh tokens | 6 / 6 / 6 | Step B proven |

**No identity-axis drift.** The live database currently shows 3 CLIENT wallets holding
104,758 GNF total. None belong to a closed account. Pending `mission_financial_holds`
attributable to the 6 deleted users remain **0**.

## 5. Closed-account audit (read-only, no PII, post-remediation)

6 profiles carry `account_status='deleted'`. After the final remediation pass and Step B auth
termination:

| Ref (UUID prefix) | Lane | Driver status | Presence | user_roles | Wallet balance | Held | auth user | Sessions | Refresh tokens | Banned |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `19fe6432` | none | — | `offline` | 0 | 0 | 0 | exists | 0 | 0 | until 2126-07-28 |
| `fb8fcfb5` | none | — | `offline` | 0 | **29,448 GNF** | 0 | exists | 0 | 0 | until 2126-07-28 |
| `4c32b26c` | none | — | `offline` | 0 | 0 | 0 | exists | 0 | 0 | until 2126-07-28 |
| `8e8023b5` | none | — | `offline` | 0 | 0 | 0 | exists | 0 | 0 | until 2126-07-28 |
| `691afc07` | none | — | — | 0 | 0 | 0 | exists | 0 | 0 | until 2126-07-28 |
| `d980534f` | none | — | — | 0 | 0 | 0 | exists | 0 | 0 | until 2126-07-28 |

All active professional lanes, capability roles, approved driver statuses, and pending ride
offers for these 6 accounts have been released through the remediation RPCs. Four professional
identities were released with timestamps; history and provenance remain intact. The ledger
posting count (120) and sum (0) are unchanged.

**Auth layer (Blocker 1 — CLOSED).** The `account-access-termination-worker` was invoked via
the sanctioned service-role path for the 6 real closed accounts. Each `auth.users` row is now
banned until `2126-07-28`, with **0 active sessions** and **0 live refresh tokens**. The
`account_access_terminations` queue rows for these 6 users are `status = 'terminated'`,
`attempts = 1`, `last_error = null`. `pgrst_pre_request` remains bound and `auth_uid_active()`
remains present. No live, non-deleted account is banned.

**Finance layer (Blocker 2 — OPEN).** The `fb8fcfb5…` driver wallet retains exactly **29,448 GNF**
(held 0). The balance is the sum of two completed ride-earning backfill credits posted on
2026-06-11: 4,299 GNF + 25,149 GNF. Current canonical policy classifies driver operating
balance as a customer liability. Driver cashout/payout and reconciliation rails are OFF;
payout origination is self-service; no escheat/dormant/unclaimed balance doctrine exists. The
Step C audit concluded **NO_LAWFUL_EXISTING_PATH**: no existing finance primitive can clear this
balance without violating current finance law or impersonating a banned user. No money was moved.

**Queue hygiene.** `account_access_terminations` currently has **18 total rows**: 6 terminated
rows for the real closed accounts, plus 12 inert profile-less/no-auth-user QA artifacts (8 marked
`failed` + 4 new pending from certification fixture enqueue behavior). These 12 rows have no
corresponding `profiles` or `auth.users` record and therefore hold no authority or access. They
are **QA hygiene debt**, not a security blocker, and must be corrected in future QA maintenance
without reopening Node 5 law. They are intentionally **not deleted** in this closeout.

## 6. Verdict (Step E)

**HOLD — NODE 5 SECURITY/AUTHORITY CLEAN; ONE FINANCE-LAW BLOCKER REMAINS.**

Blocker status after Steps A–D:

1. **Auth termination — CLOSED.** Step B proved the 6 closed accounts are banned in Supabase
   auth until 2126-07-28 with zero sessions and zero live refresh tokens. The queue reflects
   `terminated` for all 6 real users.
2. **29,448 GNF balance on `fb8fcfb5…` — OPEN.** No existing finance primitive provides a
   lawful path for this involuntary positive balance under current canonical policy. The balance
   is a real customer liability that cannot be written off, swept, or paid out without a new
   finance-law doctrine.

Explicitly NOT blockers: no active professional lanes, roles, approved drivers, pending ride
offers, recovery material, governance rows, holds, cashouts, freezes, cancellation debts, or
in-flight orders exist for the 6 closed users. The 12 inert queue rows are QA hygiene, not active
authority.

## 7. Condition to unlock Node 5

Node 5 can be **LOCKED** only after the following, executed in the finance domain:

- Adopt a deliberate finance policy/law for positive balances on closed accounts (or another
  lawful resolution path) that is approved by project governance.
- Implement that policy with balanced ledger entries, full provenance, and appropriate QA
  coverage.
- Rerun only the necessary Node 5 closeout verification to confirm the finance blocker is closed
  and no new identity-axis drift was introduced.

This document does not propose or invent that policy. Until it is implemented and proven, the
Node 5 verdict remains **HOLD**.

## 8. Next steps beyond Node 5

- **A15 not started.** Node 5 is the current final identity milestone.
- QA hygiene cleanup of the 12 inert `account_access_terminations` rows should be performed as
  routine maintenance, without reopening Node 5 law.

## 9. Docs-only correction record (Step E)

This final revision updates the closeout document to reflect the post-Step B/C/D state:
- Marked Blocker 1 (auth termination) **CLOSED** with exact proof boundary.
- Recorded Step C finance provenance and the `NO_LAWFUL_EXISTING_PATH` conclusion without
  proposing or implementing an unapproved finance law.
- Recorded Step D certification board (58 suites, 6,052 raw / 5,974 canonical / 0 failures),
  `tsgo` clean, Vitest 155/155, build + PWA 136 precache entries.
- Recorded the DB/security linter at 662 with exact +4 attribution and accepted it as the
  post-remediation baseline for the frozen remediation state.
- Updated the live census to **8 active lanes (driver 2 / merchant 6)** and explained the
  4-lane reduction as intended legacy closed-account reconciliation.
- Updated the closed-account table to show banned-until-2126-07-28, 0 sessions, 0 refresh tokens.
- Recorded queue hygiene separately: 18 total rows (6 terminated + 12 inert QA artifacts).
- Set final verdict to **HOLD — NODE 5 SECURITY/AUTHORITY CLEAN; ONE FINANCE-LAW BLOCKER REMAINS**.
- Documented the exact unlock condition in §7.
- Confirmed A15 not started.

No product code, DB schema, migration, function, policy, edge function, harness, harness
credential, or live user row was changed in this Step E edit.

## 10. Repo state at Step E

- Working HEAD at start of this edit: `9a16d119…` ("Update plan"), clean tree.
- Files changed since Step A (`5ee357d3…`) before this edit: only Lovable plan metadata/docs
  chronology; no product/DB/DB files changed.
- After this edit, the only modified file is `docs/identity/NODE5_FINAL_CLOSEOUT.md`.
- `git status` is expected to be clean after the platform commits this docs-only change.
- **A15 not started.**
