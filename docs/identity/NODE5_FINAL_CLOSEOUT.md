# NODE 5 — FINAL CLOSEOUT / CONSTITUTIONAL CHARTER

Closeout pass type: **Step A docs-only refresh**. No product code, DB schema, migration,
policy, function, flag, pricing, payout law, harness credential or live user row was changed
in this edit. Only `docs/identity/NODE5_FINAL_CLOSEOUT.md` is mutated.

## 0. Chronology (do not conflate)

| Marker | SHA | Meaning |
| --- | --- | --- |
| A13 certification code HEAD | `a12a999dc5b46ae0674f4b64c767bf8349884566` | pre-documentation/internal closeout |
| A13 closeout report commit | `80b5e406f0f73081e4bf18621e7bdc8ab5a0852d` | Lovable closeout edit |
| A13 bookkeeping correction | `20aabd91dc322e0735816fa1522e07b2da875b95` | docs-only; also A14 starting HEAD |
| A14 certification code HEAD | `fe72ef0df7137c36bc805e06eb51b481cf693cc8` | A14 implementation + docs |
| **Node 5 final-closeout starting HEAD (code certification)** | `fe72ef0df7137c36bc805e06eb51b481cf693cc8` | `git status --porcelain` clean |
| First closeout report commit | `9e6f4260…` | docs-only; **superseded** by the correction below |
| Docs-only correction commit | `20aabd91dc322e0735816fa1522e07b2da875b95` | superseded correction; verdict HOLD |
| **Final remediation code HEAD** | recorded in §8 | remediation pass: `auth_uid_active()`, `pgrst_pre_request`, `account_access_terminations`, `admin_account_closure_reconcile()` |
| **This Step A docs-only refresh** | recorded in §8 | current document; verdict still HOLD |

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
- Full board — **6,052 assertions / 0 failures**.
- `tsgo --noEmit` — exit 0.
- Production build + PWA — built OK.
- Temporary QA `RUN` harness token slot and one-time reconciliation runner — **removed**.

## 3. Local gates / security linter (measured this pass)

| Gate | Result |
| --- | --- |
| `tsgo --noEmit` | exit 0 |
| Vitest | 19 files / 155 tests, all pass |
| Production build + PWA | built OK |
| DB / security linter | **662 findings** |

**Linter baseline.** The accepted A14 baseline is **658 findings**. The current remediation
surface added **+4 findings**, yielding **662**. This +4 delta is **not yet accepted as a new
baseline**. Step D will audit the delta and decide acceptance or reduction before any LOCK.

The ESLint 666/113 figure is a separate, purely informational frontend measurement and is not
the same metric as the DB/security linter.

## 4. Live census / non-drift (read-only, post-remediation)

| Metric | Measured | Baseline |
| --- | --- | --- |
| profiles | 1,534 | 1,534 |
| active professional lanes | 12 (driver 6 / merchant 6) | 12 (6/6) |
| active governance accounts | 1 | 1 |
| lawful overlap (governance ∧ lane) | 0 | 0 |
| merchant stores | 6 | 6 |
| driver_profiles | 6 | 6 |
| wallets | 71 (client 61 / driver 5 / merchant 4 / master 1) | identical |
| ledger postings / sum | 120 / 0 | 120 / 0 |
| duplicate canonical wallets | 0 | 0 |
| duplicate active lanes | 0 | 0 |
| duplicate phones / non-canonical phones | 0 / 0 | 0 / 0 |
| Node 5 QA fixture residue | 0 | 0 |
| enabled feature flags | 11 | — |
| active professional lanes on closed accounts | **0** | — |
| capability roles on closed accounts | **0** | — |
| approved/non-offline driver rows on closed accounts | **0** | — |
| pending ride offers on closed accounts | **0** | — |
| recovery material on closed accounts | **0** | — |
| active governance rows on closed accounts | **0** | — |

**No identity-axis drift.** The live database currently shows 3 CLIENT wallets holding
104,758 GNF total. None belong to a closed account. Pending `mission_financial_holds`
attributable to the 6 deleted users remain **0**.

## 5. Closed-account audit (read-only, no PII, post-remediation)

6 profiles carry `account_status='deleted'`. After the final remediation pass:

| Ref (UUID prefix) | Lane | Driver status | Presence | user_roles | Wallet balance | Held | auth user | Banned |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `19fe6432` | none | — | `offline` | 0 | 0 | 0 | exists | **unproven** |
| `fb8fcfb5` | none | — | `offline` | 0 | **29,448 GNF** | 0 | exists | **unproven** |
| `4c32b26c` | none | — | `offline` | 0 | 0 | 0 | exists | **unproven** |
| `8e8023b5` | none | — | `offline` | 0 | 0 | 0 | exists | **unproven** |
| `691afc07` | none | — | — | 0 | 0 | 0 | exists | **unproven** |
| `d980534f` | none | — | — | 0 | 0 | 0 | exists | **unproven** |

All active professional lanes, capability roles, approved driver statuses, and pending ride
offers for these 6 accounts have been released through the remediation RPCs. Four professional
identities were released with timestamps; history and provenance remain intact. The ledger
posting count (120) and sum (0) are unchanged.

**Auth layer.** The 6 `auth.users` rows still exist and carry credentials. The `account-access-
termination-worker` is the designated mechanism to ban the accounts and revoke sessions. That
step has **not yet been executed or proven** in this closeout; the "Banned" column above is
therefore marked **unproven**.

**Queue hygiene.** `account_access_terminations` currently has **14 pending rows**: 6 rows for
the real closed accounts, plus **8 profile-less rows** left by QA fixture teardown. These 8 rows
have no corresponding `profiles` record and therefore cannot hold any active authority or
access. They are a queue-cleanliness artifact, not a third architectural blocker, unless analysis
in Step B proves they create active access. The worker must handle them as already inaccessible
and resolve them without treating missing profiles as an error.

## 6. Verdict (task H)

**HOLD — NODE 5 IS NOT LOCKED.**

Two blockers remain after the final remediation pass:

1. **Auth termination unproven.** The 6 closed accounts have not yet been proven banned and
   their sessions/refresh tokens revoked. `pgrst_pre_request` and `auth_uid_active()` close the
   already-issued access-token window for RLS/RPC surfaces, but the canonical Supabase auth layer
   termination step is not yet executed or evidenced.
2. **29,448 GNF balance on `fb8fcfb5` with no proven lawful disposition.** This one closed
   account still holds a wallet balance. No existing finance primitive has been proven as a lawful
   path for this specific involuntary balance. The balance remains correctly blocked from full
   closure.

Explicitly NOT blockers: no active professional lanes, roles, approved drivers, pending ride
offers, recovery material, governance rows, holds, cashouts, freezes, cancellation debts, or
in-flight orders exist for the 6 closed users. The 8 profile-less queue rows are hygiene, not
active authority, unless Step B proves otherwise.

## 7. Next sequential steps (B → E)

Follow the accepted plan. Do not start A15.

- **Step B — Prove auth termination.** Invoke the `account-access-termination-worker` against the
  6 real closed accounts using a sanctioned service-role or god_admin/operations_admin session.
  Capture evidence: ban status, zero sessions/refresh tokens per UUID, and queue resolution. If
  invocation is impossible, Blocker 1 stays open.
- **Step C — Finance-law audit (audit-only).** Examine the 29,448 GNF against existing primitives
  (`wallet_internal_transfer`, `wallet_admin_credit`, refund paths). Identify a lawful disposition
  only if it satisfies ledger balance, provenance, and involuntary-authority requirements. If no
  existing path is lawful, Blocker 2 stays open.
- **Step D — Final micro-certification.** Rerun the full board (6,052 assertions) and audit the
  DB/security linter 662 vs 658 delta. Accept the +4 as a new baseline only if it represents
  unavoidable remediation-surface exposure and no reductions are possible.
- **Step E — Verdict.** **LOCK** only if B and C are proven closed and D is green. Otherwise
  **HOLD** with residual blockers documented.

## 8. Docs-only correction record (Step A)

This revision refreshes the closeout document to reflect the post-remediation state:
- Added final remediation certification (§2) and updated suite counts (100/100, 6,052/0).
- Updated live census (§4) with zero active authority on closed accounts.
- Updated closed-account table (§5) to show released lanes, unproven auth termination, and the
  14-row queue hygiene note.
- Updated verdict (§6) to two residual blockers, removing stale pre-remediation items.
- Added next steps B→E (§7).
- Kept linter at 662 with the explicit note that the +4 delta is **not yet accepted**.

No product code, DB schema, migration, function, policy, harness, harness credential, or live
user row was changed in this Step A refresh.

Commit SHA of this Step A refresh: recorded on commit; `git status --porcelain` expected clean
except for this document.

**A15 not started. Node 5 remains open at HOLD.**
