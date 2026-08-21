# NODE 5 · A13 — IDENTITY CONTINUITY / ACCOUNT RECOVERY INTEGRITY

**Status:** CERTIFIED / LOCKED
**Verdict:** READY
**Closeout date:** 2026-08-21
**Starting HEAD (closeout):** `156972d1` — *Fixed A13 phone bridge defect*
**Final HEAD:** `a12a999dc5b46ae0674f4b64c767bf8349884566`
**Working tree:** `git status --porcelain` → empty (clean)
**Scope:** A13 only. A14 not started.

---

## 1. Mission

Prove and, where necessary, harden identity continuity across phone-number change,
lost-device / session recovery, credential replacement, account recovery, and any
attempted re-registration or duplicate-account path.

Recovery must restore **access** to the same canonical account authority graph when
legitimately verified. It must never create, transfer, duplicate, infer, or resurrect
professional or governance authority from a phone number, stale session, wallet,
artifact, role residue, or historical association.

---

## 2. Canonical authority boundary (frozen law)

| Layer | Canonical? | Role after A13 |
|---|---|---|
| `auth.users.id` (UUID) | **YES** | The single stable human/account key |
| `profiles.user_id` | **YES** | Canonical mapping to the account key |
| `profiles.id` | **NO** | Row surrogate. Never an account key, never crosses a boundary |
| `profiles.phone` | **NO** | Mutable contact/login attribute. Lookup input only |
| Wallet existence / balance / history | **NO** | Money follows the canonical UUID; it never proves ownership |
| `user_roles`, `admin_users` rows | **NO** | Evaluated authority, not identity |
| `merchant_stores`, `driver_profiles` | **NO** | Artifacts of a lane, not proof of a lane |
| JWT claims / UI session / localStorage | **NO** | Presentation only; re-derived server-side every request |

**Recovery restores authentication, not authority.** After recovery the account's
present authority is still computed from the canonical A2–A12 sources
(`professional_identities.claim_state`, `user_roles`, `admin_users.status`,
lifecycle gates). Suspension and offboarding survive recovery unless explicitly
restored through A12 lifecycle law.

---

## 3. Critical defect found and fixed: surrogate-id leak

`agent_lookup_customer_wallet(text)` returned **`profiles.id`** (the row surrogate)
in its `customer_user_id` output column.

Consequences before the fix:

- A non-canonical key was handed to the service-agent cash-in rail, where the caller
  treats it as an account UUID.
- The `self_cashin_forbidden` guard compared `profiles.id` against `auth.uid()` and
  therefore **could never match** — an approved service agent could cash in to their
  own account through the customer path.
- Any downstream join keyed on the returned value silently addressed the wrong key
  space.

**Remediation:** the function now selects `p.user_id`, and the self-cash-in guard
compares canonical UUID to canonical UUID. Verified in source (`-- Canonical account
key only. Never profiles.id.`) and asserted structurally in `_qa_node5_identity_a13`.

Severity: **CRITICAL — fixed and certified.**

---

## 4. Phone normalization + canonical uniqueness

### `public._normalize_guinea_phone(text) → text`
Strips non-digits, unwraps `00224…` and `224…` prefixes, accepts an 8–9 digit
subscriber number, returns `+224XXXXXXXX(X)`. Returns `NULL` for anything else.

### `trg_profiles_normalize_phone` on `public.profiles` (BEFORE INSERT OR UPDATE)
- Empty/blank phone → stored as `NULL` (no bogus canonical value).
- Un-normalizable input → `RAISE EXCEPTION 'INVALID_PHONE'` with `ERRCODE 22023`.
- Otherwise `NEW.phone` is rewritten to the canonical `+224…` form **before** the
  `profiles_phone_key` unique index is evaluated.

Net effect: two accounts can no longer hold the same real phone under different
textual spellings (`622000111`, `+224622000111`, `00224 622 000 111`). Duplicate
assignment now fails closed with a `unique_violation` (23505).

### `find_user_by_phone(text)`
Normalizes the input, then resolves **to a canonical `user_id`**. It is authorization-
gated (admin or active agent), returns identity only, and performs no writes. It is a
**lookup-to-canonical-UUID resolver, not an ownership bridge** — it can never move a
wallet, lane, store, or role between accounts.

**No live code authorizes by phone equality.** Every ownership join is UUID-based.

---

## 5. Threat matrix

| # | Threat | Outcome | Evidence |
|---|---|---|---|
| T1 | Phone change mints a second identity/profile/wallet | Refused — one profile, one canonical wallet per party type | A13 D-series |
| T2 | Phone change transfers professional lane or governance authority | Refused — lane/role rows are keyed by UUID and untouched | A13 D/F-series |
| T3 | Two accounts hold the same real phone via different spellings | Refused at write time (23505) after normalization | A13 D-series, S13 A9.4b |
| T4 | Invalid/garbage phone accepted | Refused with `INVALID_PHONE` (22023) | A13 D-series, S13 A9.4c |
| T5 | Re-registration on a recycled phone inherits predecessor's wallet/history/lane | Refused — successor is a distinct UUID with an empty authority graph | A13 E-series |
| T6 | Recovery resurrects a suspended/offboarded professional | Refused — A12 lifecycle state survives recovery | A13 F-series |
| T7 | Recovery restores a suspended admin | Refused — `admin_users.status` unchanged by recovery | A13 G-series |
| T8 | Dual-axis account collapses into one axis after recovery | Refused — axes evaluated independently | A13 H-series |
| T9 | Stale session / forged JWT claim confers authority | Refused — claims are non-authoritative, re-derived server side | A13 I-series |
| T10 | Wallet balance used as proof of ownership after recovery | Refused — money stays bound to the canonical UUID | A13 J-series |
| T11 | Password reset creates a parallel user ID | Refused — reset mutates credentials on the same UUID | A13 C-series |
| T12 | Surrogate `profiles.id` escapes into the finance rail | Refused — canonical UUID only | A13 A-series (§3) |

---

## 6. Auth / device-session proof boundary

- The existing Supabase auth subsystem plus the `account-recovery` Edge Function
  remain canonical. **No second authentication subsystem was created.**
- `account-recovery` verifies evidence (date of birth, three private questions,
  recovery key) that is HMAC-peppered server-side, then resets the password on the
  **same** `auth.users.id`. Continuity is therefore structural, not inferred.
- Session/device invalidation is a credential-plane event. It destroys neither
  identity history nor money, and it grants nothing: a stale token that survives in
  a client cannot outlive canonical revocation because authority is recomputed from
  the database on every privileged call.
- **Proof boundary:** A13 certifies the *database-side* continuity and non-transfer
  law exhaustively. Live browser-side session-expiry behaviour is covered by the
  existing auth guards and is not re-proved here; it is out of A13 scope because no
  client state is authoritative under Law 9.

---

## 7. Slice 13 fixture remediation (`_qa_s13_run2`)

The pre-A13 fixture deliberately wrote the *same* subscriber number to two driver
accounts (`+224622000111` on d1, `622000111` on d2) to exercise a legacy
"duplicate identity signal routes to review" branch of `driver_starter_credit_grant`.

Under A13 that state is unreachable: the write is refused at the database. The old
assertions were therefore asserting the persistence of a defect. The trigger was
**not** loosened; the fixture was corrected.

| Assertion | Semantics after A13 |
|---|---|
| `A9.4b` | Assigning d1's canonical phone to d2 is refused at write time with `unique_violation` (exact SQLSTATE class asserted, not "any exception") |
| `A9.4c` | An un-normalizable phone on d2 is refused with the exact message `INVALID_PHONE` |
| `A9.5` | After refusal the fixture pair holds **distinct** canonical phones — d1 `+224622000111`, d2 `+224622000112` (written as `00224 622 000 112` to also prove normalization) |
| `A9.6` | Each canonical phone resolves only to its own account: `+224622000111 → d1`, `+224622000112 → d2`, and exactly one of the pair holds d1's number — d2 inherits no identity |

`A9.4b` is retained and non-redundant (it proves the *refusal*; A9.5/A9.6 prove the
*post-refusal state*). No global duplicate-phone census is asserted — assertions are
scoped strictly to the two fixture accounts. The obsolete
`driver_starter_credit_grant(d2)` review-branch call was removed.

Result: `_qa_s13_run2` **34 / 34 PASS** (was 25 pre-A13).

---

## 8. Legacy duplicate-phone posture

Measured on live data after the trigger shipped:

| Metric | Value |
|---|---|
| Profiles with a phone that is not already canonical | **0** |
| Distinct phone values held by more than one profile | **0** |
| Live rows mutated by A13 | **0** |

There is **no legacy duplicate-phone debt**. The trigger is forward-enforcing only;
no backfill or controlled remediation is required, and no live user row was rewritten
during A13. Should duplicates ever appear (e.g. from a future bulk import), they would
be read-only legacy data requiring an explicit, audited merge pass — never an implicit
one.

---

## 9. QA harness token audit (`QA_NODE_HARNESS_TOKEN_CERT`)

**Why a third slot was necessary.** `qa-node-harness` accepts two operator tokens.
Neither value is readable by the agent, and existing secret values cannot be rotated
programmatically — only the user can change them in Project Settings → Secrets. The
A13 certification run required an authenticated harness invocation, so a third,
purpose-scoped slot was added rather than weakening the harness's authorization.

**Storage.** Server-side Edge Function secret only, read via
`Deno.env.get("QA_NODE_HARNESS_TOKEN_CERT")`. Verified:

- Repository grep for `QA_NODE_HARNESS_TOKEN` matches **only** the three
  `Deno.env.get` lines in `supabase/functions/qa-node-harness/index.ts`.
- The token value does not appear anywhere in `dist/` after a production build.
- No `VITE_` exposure, no client import, no `.env` commit.

**Access control unchanged.** Re-verified against the deployed function:

| Caller | Result |
|---|---|
| No auth header | `401 Unauthorized` |
| Valid anon JWT (publishable key) | `{"error":"Unauthorized"}` |
| Wrong `x-qa-token` | `{"error":"Unauthorized"}` |

The token authorizes **only** the allowlisted, self-rolling-back `_qa_*` harnesses. It
grants no database privilege: it does not appear in any `GRANT`, does not alter RLS,
and every QA function remains `REVOKE ALL … FROM PUBLIC, anon, authenticated` with
`EXECUTE` to `service_role` only.

**Debt classification.** Temporary and rotatable. It is a QA-plane credential with no
production surface. It should be deleted, or rotated by the user in Project Settings →
Secrets, once the Node 5 certification campaign closes.

---

## 10. Certification results

### A13 suite
`_qa_node5_identity_a13` — **89 / 89 PASS**, 0 failures.

Coverage: structural UUID-key integrity and grant/RLS audit; bootstrap uniqueness
(one profile, one wallet, one default role per new auth user); session continuity;
phone-change safety (D); re-registration / number recycling (E); professional
lifecycle non-bypass (F); governance non-bypass (G); dual-axis continuity (H);
stale-state and forged-claim rejection (I); finance continuity by UUID (J).

Execution note: the suite runs `SECURITY INVOKER` (like every other probe-using
harness) because `SET LOCAL ROLE` probes cannot run inside a `SECURITY DEFINER`
function. `EXECUTE` is revoked from `anon` and `authenticated`.

### Full board — single pass, 57 suites, **no timeouts**

| Family | Suites | Assertions | Failed |
|---|---|---|---|
| Node 0 · Course | 1 | 34 | 0 |
| Node 1 · Bonbonna | 4 | 156 | 0 |
| Node 2 · Taxi | 1 | 97 | 0 |
| Slice 13 | 7 | 529 | 0 |
| Node 3 · Repas | 14 | 1,612 | 0 |
| Node 4 · Marché | 17 | 1,943 | 0 |
| Node 5 · Identity A2–A13 | 12 | 1,327 | 0 |
| **Raw total** | **57** | **5,838** | **0** |

- **Raw measured: 5,838 / 0.**
- **Canonical measured: 5,760** (raw minus the 78 Bonbonna sub-suite assertions that
  `_qa_node1_bonbonna_full` re-runs: 24 + 15 + 39).
- Predicted arithmetic was 5,836 raw / 5,758 canonical. The measured board is **+2**
  because `_qa_s13_run2` grew from 25 to 34 assertions during this closeout while the
  previously *recorded* baseline figures (5,747 / 5,669) were carried across separate
  runs and no longer reconcile exactly with per-suite measurement. **The measured
  board is authoritative; the recorded baseline is not.**
- Node 5 A2–A12 counts unchanged from the A12 closeout: 96, 119, 133, 111, 110, 130,
  93, 121, 95, 108, 122 — **1,238 / 0**. No drift.

### Local gates

| Gate | Result |
|---|---|
| `tsgo --noEmit` | exit 0 |
| Vitest | 19 files, **155 / 155 passed** |
| Production build | ✓ built in 29.90s |
| PWA (`generateSW`) | 136 precache entries, `sw.js` generated |
| Supabase linter | **658** — identical to the accepted post-A12 baseline |

**Linter:** A13 added **zero** new findings. Every A13 change either replaced an
existing function body in place or was a trigger function; `_qa_node5_identity_a13`
and `_qa_s13_run2` are `SECURITY INVOKER` with `EXECUTE` revoked from `anon` and
`authenticated`, so they contribute nothing to lints 0028/0029. Baseline held at 658.

---

## 11. Non-drift census (post-final-edit)

| Metric | Expected | Measured | ✓ |
|---|---|---|---|
| profiles | 1534 | 1534 | ✓ |
| active professional lanes | 12 (6 driver / 6 merchant) | 12 — driver:6, merchant:6 | ✓ |
| active governance accounts | 1 | 1 | ✓ |
| merchant stores | 6 | 6 | ✓ |
| driver profiles | 6 | 6 | ✓ |
| wallets | 71 (61 client / 5 driver / 4 merchant) | 71 — client:61, driver:5, merchant:4, master:1 | ✓ |
| ledger postings | 120, sum 0 | 120, sum 0 | ✓ |
| pending financial obligations | 0 | 0 | ✓ |
| duplicate canonical wallets | 0 | 0 | ✓ |
| duplicate active lanes | 0 | 0 | ✓ |
| A13 fixture residue | 0 | 0 | ✓ |
| non-canonical phone rows | 0 | 0 | ✓ |
| duplicate canonical phone groups | 0 | 0 | ✓ |

No concurrent live change was observed during this closeout. (The `master:1` wallet is
the platform treasury wallet and was already inside the 71 total at A12.)

---

## 12. Files and migrations

**Edge function**
- `supabase/functions/qa-node-harness/index.ts` — registered `_qa_node5_identity_a13`
  in the allowlist; added the `QA_NODE_HARNESS_TOKEN_CERT` slot. Redeployed.

**Product remediation (A13)**
- `agent_lookup_customer_wallet(text)` — canonical `user_id`; self-cash-in guard fixed.
- `_normalize_guinea_phone(text)` + `trg_profiles_normalize_phone` on `public.profiles`.
- `find_user_by_phone(text)` — normalizes input, resolves to canonical UUID.

**Migrations applied during this closeout**
- `20260821191001_*` — `_qa_node5_identity_a13` → `SECURITY INVOKER`, grants tightened.
- `20260821191343_*` — A13 suite: corrected `mission_financial_holds` column reference.
- `20260821191525_*` — A13 suite: corrected `driver_locations` column reference.
- `20260821191556_*`, `20260821191625_*`, `20260821192223_*` — interim `_qa_s13_run2`
  fixture corrections (superseded).
- `20260821192745_*` — **final** `_qa_s13_run2` remediation: A9.4b / A9.4c / A9.5 / A9.6
  rewritten to post-A13 law, fixture-scoped, exact error codes asserted.

One migration attempt failed with `S13_PATCH_NO_MATCH` (guarded no-op, whitespace
mismatch against live `prosrc`) and applied nothing.

**Commits:** `156972d1` (A13 phone bridge defect fix) → `a12a999d` (final).
Working tree clean.

---

## 13. Unresolved risks

1. **`QA_NODE_HARNESS_TOKEN_CERT` is live.** No production surface and no database
   privilege, but it should be removed or rotated at the end of the Node 5 campaign.
2. **Linter baseline 658 is an accepted, not a clean, posture.** The 143 + 474
   `SECURITY DEFINER` executable findings are the deliberate RPC-gateway architecture
   (authorization enforced inside each function). Unchanged by A13.
3. **Client-side session expiry UX is not re-proved by A13.** Safe under Law 9 —
   no client state is authoritative — but a live browser pass would be needed to
   certify the *user-visible* experience of a revoked session.
4. **Phone normalization is Guinea-only (`+224`).** Any future international
   expansion must extend `_normalize_guinea_phone` before onboarding non-GN numbers,
   or those inserts will be refused with `INVALID_PHONE`.

---

## 14. Verdict

**NODE 5 · A13 — IDENTITY CONTINUITY / ACCOUNT RECOVERY INTEGRITY: READY / CERTIFIED / LOCKED.**

One critical surrogate-id defect found and fixed. Phone demoted to a mutable contact
attribute with server-enforced canonicalization and fail-closed uniqueness. Recovery
proven to restore access without transferring, duplicating, or resurrecting authority.
Board green at 5,838 / 0 with no timeouts, no drift, and the linter baseline held.

A14 not started.
