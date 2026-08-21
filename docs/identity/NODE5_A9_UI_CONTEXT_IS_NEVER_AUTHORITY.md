# Node 5 · A9 — UI Context Is Never Authority

Status: **CERTIFIED**
Suite: `_qa_node5_identity_a9` — **121 / 121 PASS**
Canonical board at close: **5,344 assertions · 0 failed** (raw 5,422)

## Law

UI mode / client context can never create, expand, restore or substitute server
authority. Mode is presentation only (A8). Every professional surface derives its
answer from the server-held professional identity (A2/A3), the operational
primitives (A6/A7) and RLS — never from a client-supplied mode, claim or preference.

## Adversarial coverage

Twelve attack groups: static mode non-authority, customer→professional forgery,
driver→merchant and merchant→driver forgery, released lane, role+mode, wallet+mode,
artifact+mode, suspension/capability/approval isolation, cross-tenant object
isolation, preference-RPC abuse (injection, NULL, case variants, signed-out),
forged JWT claims (`app_mode`, `professional_type`, `user_role`, `is_admin`,
`capabilities`, `driver_status`, `store_status`, `store_id`), finance
non-interference and full baseline restoration.

Every forged call was refused fail-closed against real surfaces
(`driver_set_status`, `driver_offer_accept`, `mission_claim`,
`driver_set_capabilities`, `marche_listing_create`, `marche_merchant_transition`,
`marche_courier_transition`, `marche_shopper_claim`, `merchant_submit_location`,
`merchant_settlement_request_create`). No identity, role, capability, approval,
store, listing, mission, wallet, ledger, payable or payout was created or changed.

## P1 grant defect discovered and closed

Six identity tables still carried the default `arwdDxtm` grant to **anon and
authenticated** — including **TRUNCATE, which bypasses RLS entirely**:

- `user_preferences`
- `user_roles`
- `driver_profiles`
- `profiles`
- `user_pins`
- `user_legal_consents`

A client-key holder could have wiped account roles, preferences, PINs or consents
despite correct policies. Same class as the Marché R14 leak.

### Final effective client privilege posture

| Table                 | anon | authenticated                                   |
| --------------------- | ---- | ----------------------------------------------- |
| `profiles`            | none | SELECT, INSERT, UPDATE                           |
| `user_roles`          | none | SELECT, INSERT, UPDATE                           |
| `user_preferences`    | none | SELECT, INSERT, UPDATE                           |
| `user_pins`           | none | SELECT, INSERT, UPDATE                           |
| `user_legal_consents` | none | SELECT, INSERT, UPDATE                           |
| `driver_profiles`     | none | SELECT, INSERT, UPDATE                           |

No DELETE, no TRUNCATE, no TRIGGER, no REFERENCES for either client role, on any of
the six. Grants are not equalised for symmetry — each table keeps exactly the verbs
its current RLS and client architecture require.

## Table grant vs RLS authorization

A grant says *which verbs the role may attempt*. RLS says *which rows the verb may
touch*. The two are not interchangeable:

- TRUNCATE is a grant-level verb with **no RLS evaluation at all** — that is why the
  leak was P1 even though every policy was correct.
- INSERT/UPDATE on `user_roles` are held by `authenticated` **only** so the
  governance policy `Super admins manage roles`
  (`has_admin_role(auth.uid(),'super_admin')` in both USING and WITH CHECK) has a verb
  to authorize. An ordinary signed-in user fails that predicate and can write nothing.

## Why `N5A9.A17` was stale

The original assertion demanded that `user_roles` be *globally* read-only for signed-in
users (`NOT has_table_privilege('authenticated', ..., 'INSERT'/'UPDATE')`). That tests a
table grant, not authority, and contradicts the shipped governance architecture: super
admins are ordinary `authenticated` sessions. The invariant is
**role mutation is governance-scoped, not globally absent.**

`A17` was replaced by `_qa_n5a9_role_governance()`, seven semantic assertions:

| Id       | Proof                                                                        |
| -------- | ---------------------------------------------------------------------------- |
| `A17a`   | every non-SELECT policy on `user_roles` is super-admin scoped in USING+WITH CHECK |
| `A17b`   | no policy exposes `anon`; `anon` holds no INSERT/UPDATE/DELETE                 |
| `A17c`   | `authenticated` holds no DELETE and no TRUNCATE                                |
| `A17d`   | RLS is enabled, so the INSERT/UPDATE grant is policy-bound                     |
| `A17e`   | an ordinary signed-in fixture user fails the governance predicate              |
| `A17f`   | a real super-admin fixture satisfies it — the legitimate path still works      |
| `A17g`   | the probe leaves zero role/admin/user residue                                  |

Runtime `SET ROLE` probing is not possible inside a `SECURITY DEFINER` harness
(`42501: cannot set parameter "role"`), so denial is proven by evaluating the policy
predicate itself against real fixture identities plus the grant and RLS-enabled facts.

## Assertion arithmetic

- old A9: **115** (1 stale failure)
- new A9: **121** — `A17` (1) removed, `A17a`–`A17g` (7) added → **+6**
- no assertion was deleted or merged to preserve arithmetic

Canonical board = 5,223 (pre-A9) + 121 = **5,344 · 0 failed**.
Raw runner total = **5,422**; the +78 delta is `_qa_node1_bonbonna_full` re-executing
its three components (24 + 15 + 39). Canonical excludes the components, never the wrapper.
