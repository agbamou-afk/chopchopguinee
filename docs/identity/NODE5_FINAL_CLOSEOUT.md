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
| ESLint (frontend, informational) | 666 errors / 113 warnings (779 problems) |

**Linter category correction.** The accepted `658` baseline carried through A12–A14 is the
**database/security linter** finding count (the known signed-in-executable `SECURITY DEFINER`
finding class). It is **not** an `eslint` error count, and the two are **incomparable** — no
`+8` delta exists or should ever be quoted. Because this closeout changed no DB object,
function, policy or migration, the last certified DB-security-linter measurement stands at
**A14 = 658**; it was **not re-run** in this session.

The ESLint figure above is a separate, purely informational frontend measurement. None of it
is attributable to A14: `src/components/account/SelfDeleteAccountSheet.tsx`,
`src/integrations/supabase/types.ts` and `supabase/functions/qa-node-harness/index.ts` all lint
clean (0 problems). Highest-error files are pre-existing:
`src/lib/marche/products.ts` 22, `src/lib/merchant/operations.ts` 22,
`src/components/admin/DriverGroupsV3Panels.tsx` 20, `src/lib/packages/api.ts` 19,
`src/components/driver/DriverActiveTrip.tsx` 18.

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

**No identity-axis drift.**

**Held funds — concurrent operational state, not drift and not a Node 5 artifact.** The live
database currently shows **3 CLIENT wallets holding 104,758 GNF total**. None belong to a
closed account. This is ordinary operational finance activity occurring *after* A14; it must
not be presented as identical to an A14 snapshot, as Node 5 fixture residue, or as a
closed-account blocker. Pending `mission_financial_holds` attributable to the 6 deleted users
remain **0**.


## 5. Closed-account audit (task G) — read-only, no PII

6 profiles carry `account_status='deleted'`.

| Ref (UUID prefix) | Lane | Driver status | Presence | user_roles | Wallet balance | Held | auth user | Banned |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `19fe6432` | driver ACTIVE | approved | `on_trip` (stale) | 2 | 0 | 0 | exists | no |
| `fb8fcfb5` | driver ACTIVE | approved | `online` (stale) | 2 | **29,448 GNF** | 0 | exists | no |
| `4c32b26c` | driver ACTIVE | suspended | offline | 2 | 0 | 0 | exists | no |
| `8e8023b5` | driver ACTIVE | suspended | offline | 1 | 0 | 0 | exists | no |
| `691afc07` | none | — | — | 1 | 0 | 0 | exists | no |
| `d980534f` | none | — | — | 1 | 0 | 0 | exists | no |

**Stale presence is not an active trip.** Independent authoritative queries confirm all six
closed profiles have **0 active rides, 0 active missions, 0 active Repas orders, 0 active
Marché orders**. `_account_closure_blockers(user,'admin')` returns `eligible=true, blockers=[]`
for `19fe6432`, `4c32b26c` and `8e8023b5`; for `fb8fcfb5` the only blocker is
`WALLET_BALANCE_NONZERO`. `19fe6432`'s `presence='on_trip'` is therefore **stale
driver-profile state**, not an in-flight trip, and must never be presented as an
`ACTIVE_RIDE` / `ACTIVE_MISSION` blocker.

**Professional offboard is unblocked for all four lanes.** `professional_offboard_blockers()`
returns eligible with no blockers for all four deleted accounts holding an active DRIVER lane —
**including `fb8fcfb5`**. The wallet balance blocks *full A14 closure*, not A12 offboarding.

Aggregate across the 6: active merchant lanes 0 · active governance/admin rows 0 · stores 0 ·
active rides / missions / Repas orders / Marché orders 0 · open driver financial holds 0 ·
active account freezes 0 · unsettled cancellation debts 0 · pending top-ups 0 ·
in-flight cashouts 0 · driver cash-ledger rows 0 · recovery rows 0 ·
**pending ride offers 1 — owned by `fb8fcfb5`** (stale, unsafe operational residue attached to
the closed active driver; to be expired/cancelled through the existing ride-offer lifecycle) ·
total residual wallet balance 29,448 GNF, held 0.

**Auth layer.** All 6 `auth.users` rows still exist; all 6 carry password credentials, 5 are
email-confirmed, none are banned, active sessions 0. The React `AuthContext` signs a deleted
profile out, but **no RLS policy references `account_status`** and customer-axis policies (own
wallet, profile, mission, ride) use raw `auth.uid()` equality. A closed account that obtains a
JWT can therefore still satisfy customer-axis RLS outside the UI — so "closure ends access" is
**not structurally enforced server-side**, for legacy *or* future closures.

This legacy row state predates A14. A14 deliberately mutated no live user; it fixed the *code
path* so future closures stand authority down. The legacy rows were never re-run through the
new core.

## 6. Verdict (task H)

**HOLD — NODE 5 IS NOT LOCKED.** Precise blockers:

1. 4 closed profiles retain an **active canonical DRIVER lane** (charter laws 1 and 5).
2. 2 of those remain `driver_profiles.status='approved'`, with stale `on_trip` / `online`
   presence — dispatch-eligible posture on a closed account.
3. 1 pending ride offer outstanding against `fb8fcfb5`.
4. **29,448 GNF** wallet balance on `fb8fcfb5` — blocks full closure, does **not** block
   professional offboard.
5. 9 `user_roles` rows survive across the 6 closed accounts.
6. All 6 closed `auth.users` remain credentialed and un-banned while server-side customer RLS
   does not gate `account_status` → closure access termination is incomplete.

Explicitly NOT blockers: no active rides, missions, Repas orders or Marché orders exist for the
6 closed users; no active governance rows; no recovery rows; no closed-user holds, cashouts or
freezes.

A legacy violation of a newly frozen law is still a live violation. It is not accepted debt.

## 7. Minimal surgical remediation plan (task I) — NOT executed here

Per-UUID, ordered, fail-closed, through already-certified A12/A14 primitives. Do **not** write a
parallel subsystem and do **not** hand-edit rows.

1. **Expire/cancel the pending ride offer** on `fb8fcfb5` via the existing ride-offer lifecycle,
   so no closed driver can be matched during remediation.
2. **`admin_professional_offboard` (A12) on all four active-lane accounts** — `19fe6432`,
   `fb8fcfb5`, `4c32b26c`, `8e8023b5` — promptly. Offboard blockers are already empty for all
   four. This releases canonical professional authority, stands `driver_profiles` down to
   non-approved and forces `presence='offline'`, while preserving wallet and history.
   **Authority stand-down must not wait on wallet settlement.**
3. **Reconcile the 29,448 GNF** on `fb8fcfb5` through a **verified existing canonical finance
   path**, preserving a balanced ledger and full provenance. No ad-hoc zeroing, deletion or
   transfer, and **no new money disposition is prescribed here** — no "sweep to master/unclaimed"
   account or RPC has been proven to exist for this case. Until reconciled, `WALLET_BALANCE_NONZERO`
   correctly blocks full closure for that one account only.
4. **Closure-core re-run is a design seam, not an executable step today.** The current
   `_account_closure_core` rejects profiles already at `account_status='deleted'` with
   `ACCOUNT_ALREADY_CLOSED`, so `admin_anonymize_user → _account_closure_core` ×6 **cannot** be
   run as previously written. The next surgical pass must choose one of:
   (a) minimally make the existing canonical closure path governance-idempotent /
   reconciliation-capable for legacy already-deleted accounts, or
   (b) a one-time governed reconciliation migration reproducing **only** the A14 authority and
   recovery-material cleanup. Either way it must remove the **9 surviving `user_roles`** and
   preserve audit/provenance. No parallel subsystem.
5. **Auth-layer access termination is a required law, not a wording choice.** Charter law 5
   already states closure ends access; today it is enforced only in the React client. The next
   pass must add a small explicit, audited server-side termination law — canonical Supabase auth
   disable/ban plus session and refresh-token revocation, or an equivalent proven server-side
   gate. The specific mechanism must be audited before it is prescribed.
6. **Re-verify** with `_qa_node5_identity_a14` plus the read-only census in §5. The
   closed-account table must show 0 active lanes, 0 surviving roles, non-approved driver rows,
   offline presence, no credentialed access, and a reconciled balance before Node 5 can move
   from HOLD to LOCKED.



**A15 not started. Node 5 remains open at HOLD.**
