# NODE 5 — FINAL CLOSEOUT / CONSTITUTIONAL CHARTER

Closeout pass type: **certification & reconciliation only**. No product code, DB schema,
migration, policy, function, flag, pricing, payout law, harness credential or live user
row was changed in this pass.

## 0. Chronology (do not conflate)

| Marker | SHA | Meaning |
| --- | --- | --- |
| A13 certification code HEAD | `a12a999dc5b46ae0674f4b64c767bf8349884566` | pre-documentation internal closeout |
| A13 closeout report commit | `80b5e406f0f73081e4bf18621e7bdc8ab5a0852d` | Lovable closeout edit |
| A13 bookkeeping correction | `20aabd91dc322e0735816fa1522e07b2da875b95` | docs-only; also A14 starting HEAD |
| A14 certification code HEAD | `fe72ef0df7137c36bc805e06eb51b481cf693cc8` | A14 implementation + docs |
| **Node 5 final-closeout starting HEAD (this pass)** | `fe72ef0df7137c36bc805e06eb51b481cf693cc8` | `git status --porcelain` clean |

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

## 2. Suite re-run (task C/D) — NOT EXECUTED THIS PASS, stated honestly

`_qa_node5_identity_a2 … a14` and the 57-suite board could **not** be re-run in this session:
the harness accepts only the service-role key or an `admin` user JWT, `QA_NODE_HARNESS_TOKEN*`
values are write-only server secrets, direct `EXECUTE` on `_qa_*` is denied to the query role,
and minting an admin session for a specific user is unavailable in this context. No fourth
token was created and the harness was not broadened to work around this.

Last measured values therefore stand as of code HEAD `fe72ef0d`, which is unchanged since A14:

- A2 96 · A3 119 · A4 133 · A5 111 · A6 110 · A7 130 · A8 93 · A9 121 · A10 95 · A11 108 ·
  A12 122 · A13 89 · A14 114 → **Node 5 total 1,441 / 0 failed**.
- Full board: 57 suites, **5,952 raw / 0 failed**; canonical **5,874 / 0 failed**
  (raw−canonical = 78 Bonbonna duplicate-component convention).

No assertion failure is masked; this is a credential-availability gap in the closeout session,
not a certification result.

## 3. Local gates (task E) — measured this pass

| Gate | Result |
| --- | --- |
| `tsgo --noEmit` | exit 0 |
| Vitest | 19 files / 155 tests, all pass |
| Production build + PWA | built OK, generateSW, **136 precache entries** |
| ESLint | **666 errors / 113 warnings (779 problems)** |

**Linter delta: +8 errors vs the accepted 658 baseline.** The delta is *not* attributable to
any file A14 touched — `src/components/account/SelfDeleteAccountSheet.tsx`,
`src/integrations/supabase/types.ts` and `supabase/functions/qa-node-harness/index.ts` all lint
clean (0 problems). Highest-error files are pre-existing:
`src/lib/marche/products.ts` 22, `src/lib/merchant/operations.ts` 22,
`src/components/admin/DriverGroupsV3Panels.tsx` 20, `src/lib/packages/api.ts` 19,
`src/components/driver/DriverActiveTrip.tsx` 18. The +8 is recorded as an open bookkeeping
delta (most likely a baseline counting-convention difference), not a Node 5 regression.

## 4. Live census / non-drift (task F) — read-only

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
| wallets with held funds / total held | 3 / 104,758 GNF | operational, none on closed accounts |

**No drift.**

## 5. Closed-account audit (task G) — read-only, no PII

6 profiles carry `account_status='deleted'`.

| Ref (UUID prefix) | Lane | Driver status | Presence | user_roles | Wallet balance | Held | auth user | Banned |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `19fe6432` | driver ACTIVE | approved | **on_trip** | 2 | 0 | 0 | exists | no |
| `fb8fcfb5` | driver ACTIVE | approved | **online** | 2 | **29,448 GNF** | 0 | exists | no |
| `4c32b26c` | driver ACTIVE | suspended | offline | 2 | 0 | 0 | exists | no |
| `8e8023b5` | driver ACTIVE | suspended | offline | 1 | 0 | 0 | exists | no |
| `691afc07` | none | — | — | 1 | 0 | 0 | exists | no |
| `d980534f` | none | — | — | 1 | 0 | 0 | exists | no |

Aggregate across the 6: active merchant lanes 0 · active governance/admin rows 0 · stores 0 ·
open rides as driver 0 · open missions as customer 0 · open driver financial holds 0 ·
active account freezes 0 · unsettled cancellation debts 0 · pending top-ups 0 ·
in-flight cashouts 0 · driver cash-ledger rows 0 · **pending ride offers 1** ·
total residual wallet balance 29,448 GNF, held 0. All 6 `auth.users` rows still exist and are
un-banned (closure was PII anonymization only, not access termination at the auth layer).

This state predates A14. A14 deliberately mutated no live user; it fixed the *code path* so
future closures stand authority down. The legacy rows were never re-run through the new core.

## 6. Verdict (task H)

**HOLD — NODE 5 IS NOT LOCKED.**

Charter law 5 (and law 1, via the lane being the sole canonical authority) is violated by
current live state, not merely by a historical code path:

- 4 closed accounts retain an **active driver professional lane** → canonical professional
  authority survives closure.
- 2 of those are `driver_profiles.status='approved'`, one `presence='online'`, one
  `presence='on_trip'` → dispatch-eligible operational posture on a closed account, and one
  pending ride offer is outstanding against a closed driver.
- 1 closed account holds a **29,448 GNF** driver wallet balance with no settlement path,
  since closure removed the contact/PII needed to pay out.
- 9 `user_roles` rows survive across the 6 closed accounts.

A legacy violation of a newly frozen law is still a live violation. It is not accepted debt.

## 7. Minimal surgical remediation plan (task I) — NOT executed here

Per-UUID, ordered, fail-closed. All of it must run through the already-certified A12/A14
primitives; do **not** write new subsystems, and do **not** hand-edit rows.

Order of operations (blockers first, authority second, verification third):

1. **`19fe6432` — presence `on_trip`.** Resolve or force-terminate the in-flight trip through
   the normal ride/mission lifecycle first. Nothing else may be touched until the trip is
   terminal; A14 blockers (`ACTIVE_RIDE` / `ACTIVE_MISSION`) will correctly refuse otherwise.
2. **Pending ride offer (1).** Expire/cancel via the ride-offer lifecycle so no closed driver
   can be matched during remediation.
3. **`fb8fcfb5` — 29,448 GNF residual driver balance.** Finance decision required before any
   authority change: settle to the driver via an out-of-band verified payout, or sweep to the
   master/unclaimed account with a `ledger_postings` journal preserving provenance. Balance
   must reach 0 with a balanced journal; A14's `WALLET_BALANCE_NONZERO` blocker is the gate.
   Presence must also be forced `offline`.
4. **All 4 active-lane accounts** (`19fe6432`, `fb8fcfb5`, `4c32b26c`, `8e8023b5`): run
   `admin_professional_offboard` (A12) → lane released, `driver_profiles` stood down,
   presence `offline`, status non-approved.
5. **All 6 accounts:** re-run the closure core (`admin_anonymize_user` → `_account_closure_core`)
   so `user_roles` are revoked (9 rows), recovery material erased and an `account.closure`
   audit entry written. Expected end state per account: 0 active lanes, 0 roles beyond none,
   0 balance, `driver_profiles` not approved, presence offline.
6. **Auth-layer posture:** decide policy explicitly — ban (`banned_until`) or leave the
   `auth.users` row intact-but-credential-less. Whichever is chosen must be stated in the
   charter; today the rows are un-banned, which does not satisfy "closure ends access".
7. **Re-verify** with `_qa_node5_identity_a14` plus the read-only census in §5; the closed-account
   table must show all zeros before Node 5 can move from HOLD to LOCKED.

Known blockers: the in-flight trip (step 1) and the finance decision on 29,448 GNF (step 3)
are prerequisites — the A14 blocker engine will refuse steps 4–5 until both are cleared.

**A15 not started. Node 5 remains open at HOLD.**
