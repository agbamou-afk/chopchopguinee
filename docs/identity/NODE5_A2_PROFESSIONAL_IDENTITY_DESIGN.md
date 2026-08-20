# NODE 5 · A2 — CANONICAL PROFESSIONAL IDENTITY DESIGN (design only)

Status: DESIGN ONLY. No migrations, no RPCs, no RLS, no grants, no client code, no backfill.
Baseline: A1 complete. Nodes 0–4 frozen (`node4-marche-r14-adversarial-certification-locked`).

Live re-verification performed for this pass (read-only):
- `driver_profiles`: 4 approved, 2 suspended (6 rows, PK `user_id`).
- `driver_applications`: 4 approved, 1 pending.
- `merchant_stores`: 5 approved, 1 submitted.
- `wallets` by `party_type`: client 58, driver 5, merchant 4, master 1.
- Derived driver-like set = 6, merchant-like set = 6, **intersection = 0**.
- Driver capability model already canonical: `driver_profiles.capabilities` + `driver_has_capability`, `driver_set_capabilities`, `admin_set_driver_capability`, `mission_required_capability`.

---

## 1. Canonical storage model

**Recommendation: Option A — a row exists only when a professional lane is claimed.**

| | NO ROW = none | ROW + `professional_type='none'` |
|---|---|---|
| Exclusivity enforcement | `UNIQUE(user_id)` is sufficient and total | needs `UNIQUE(user_id)` **plus** logic to distinguish "none row" from claim; the `none` row must be UPDATEd on claim, which is a read-modify-write and weaker under concurrency than a bare INSERT |
| Rows created | 6 today, ~12 after backfill | 1534 immediately, one per future signup (trigger on profile creation = new coupling to auth path) |
| Failure mode | absence = unambiguous | a missing "none" row for a legacy/edge user creates an ambiguous third state |
| Audit | claim row is itself the audit event | `none` rows are noise |

Option A is smaller, safer, and makes the atomic claim a single `INSERT` whose conflict is arbitrated by the DB. Customer-ness stays intrinsic and needs no row.

Table name: `public.professional_identities`.

## 2. Professional type domain

`professional_type` enum-or-check domain = exactly `{'driver','merchant'}`.

Excluded by law: `customer` (intrinsic), `shopper`/`courier`/`moto`/`course`/`bonbonna`/`taxi_prive`/`repas_delivery`/`marche_delivery` (Driver capabilities), `restaurant`/`store` (Merchant business assets), all admin/finance/ops values (governance axis).

## 3. Lifecycle status

Smallest sufficient set: `onboarding`, `approved`, `suspended`, `rejected`, `released`.

`released` is required only because §15 recommends tombstoning rather than deleting; it is not an active lane.

Semantics (answers to the posed questions):
- **Rejected still holds the lane.** Rejection is a lane-scoped review outcome, not a lane exit. Prevents review-shopping (reject → hop to merchant).
- **Suspended retains the professional class permanently** for the duration of the sanction and beyond; suspension never enables lane switching (§17).
- **Onboarding CAN be released** — this is the only self-service exit, and only when no irreversible dependency exists (§15).
- **Approval is effectively irreversible for self-service switching.** An approved lane may only be exited by governance action after dependency review.
- **Suspension does not affect exclusivity** (expected NO — confirmed).
- **Rejection does not automatically release exclusivity** — a controlled release may be offered when dependency checks pass.

## 4. Database exclusivity law

`professional_identities.user_id UNIQUE` (make it the PRIMARY KEY).

Because a user's professional identity is represented by *at most one row*, and each row carries exactly one `professional_type`, two professional classes are physically unrepresentable. There is no "second row" to write. This is stronger than a trigger or a partial index because it cannot be bypassed by any writer, including SECURITY DEFINER code paths and admin tooling.

**Concurrency.** `claim_driver(X)` and `claim_merchant(X)` racing: the unique index serialises them at the storage layer. One INSERT commits; the other blocks on the index until the first transaction resolves, then fails with unique violation → mapped to `PROFESSIONAL_IDENTITY_CONFLICT`.

Because downstream onboarding artifacts (driver_profiles row, store draft) are created **in the same transaction**, `INSERT ... ON CONFLICT DO NOTHING` alone is not enough — the losing transaction must abort *before* creating artifacts. Design:

1. `INSERT INTO professional_identities(...) ON CONFLICT (user_id) DO NOTHING RETURNING *`
2. If no row returned → `SELECT ... FOR UPDATE` the existing row (now committed and lockable).
   - same type → idempotent success, return existing identity, **create no duplicate artifacts** (upsert-by-existence on the artifact).
   - different type → `RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_CONFLICT'` → whole transaction rolls back, zero partial state.
3. Only after step 2 resolves to success do onboarding artifacts get created, in the same transaction.

No advisory lock needed: the unique index plus `FOR UPDATE` on the losing branch covers both the race and the read-back.

## 5. Claim boundary

**Law: the lane is claimed before any professional onboarding artifact exists.**

- Driver: `Customer → claim(driver) → create/update driver_profiles + driver_applications`.
- Merchant: `Customer → claim(merchant) → create merchant_stores / food_restaurants / merchants draft`.

Mechanism: **both**, with server-owned composition. An internal `_professional_identity_claim(_user uuid, _type professional_type)` SECURITY DEFINER helper is the single canonical mutator; the existing public onboarding RPCs (`driver_apply`, merchant store/restaurant creation RPCs) call it as their first statement. A thin public `professional_identity_claim(type)` RPC exists for pre-flight/explicit claim, but no client flow is permitted to claim in one request and create the artifact in a later request.

## 6. Claim primitive contract

`professional_identity_claim(_type text) returns jsonb`
- authenticated only; subject is always `auth.uid()`; no `_user` parameter on the public surface.
- validates `_type ∈ {driver,merchant}` else `PROFESSIONAL_TYPE_INVALID`.
- atomic; idempotent for the same lane; conflicting for the opposite lane.
- grants no approval, no capability, no wallet, no money.

Return shape:
```json
{ "ok": true, "professional_type": "driver", "lifecycle_status": "onboarding",
  "claimed_at": "...", "idempotent": false }
```
Reason codes on failure: `AUTH_REQUIRED`, `PROFESSIONAL_TYPE_INVALID`, `PROFESSIONAL_IDENTITY_CONFLICT`, `PROFESSIONAL_IDENTITY_RELEASED_LOCKED` (reserved, if policy later blocks re-claim after release).

Matrix: none+driver→driver/onboarding · none+merchant→merchant/onboarding · driver+driver→idempotent · merchant+merchant→idempotent · driver+merchant→CONFLICT · merchant+driver→CONFLICT.

## 7. Driver compatibility

`driver_profiles` is **not** replaced. Split of concerns:
- `professional_identities` = "this account owns the Driver lane" (exclusivity + lane lifecycle).
- `driver_profiles` = operational truth: vehicle, capabilities, presence, documents, operational status.

**Approval truth stays in `driver_profiles.status`** for the Driver operational lifecycle. Frozen Nodes 0–3 and all mission/finance SECURITY DEFINER paths already read it; moving approval truth would be a HIGH-risk rewrite of certified code for no product gain.

To avoid two competing "approved" truths, `professional_identities.lifecycle_status` for Driver is defined as a **projection, not an independent authority**: it is maintained (by the same server functions that mutate `driver_profiles.status`) to mirror `onboarding|approved|suspended|rejected`, and **no authority check may read it** for operational permission. Authority reads keep going to `driver_profiles.status` / `driver_has_capability`. Lane exclusivity reads `professional_identities.professional_type` only.

## 8. Merchant compatibility

- `professional_identities` answers "is this user professionally Merchant?" (account level, exclusivity).
- `merchant_stores` / `food_restaurants` / `merchants` answer "what business assets does this Merchant own, and are they approved/orderable?" — ownership and per-store approval are unchanged.

**Account-level Merchant "approved" is NOT needed.** A1 and R1.5 established per-store approval as the orderability gate (`v_marche_listing_truth` requires an approved store). Duplicating it at account level would create a second approval truth and risk contradicting frozen Marché law.

Therefore Merchant lane lifecycle uses lane semantics only:
- `onboarding` — lane claimed, no approved asset yet.
- `approved` — read as "lane active": at least one approved asset has existed. Maintained as a projection, never consulted for orderability.
- `suspended` — account-level merchant sanction (ops), orthogonal to per-store controls, which remain the R12 mechanism.
- `rejected` — lane-level refusal (e.g. identity/KYC refusal), distinct from a single store rejection.

`marche_*` merchant RPCs keep authorizing from store ownership. Node 5 adds an exclusivity precondition at claim/creation time, not a new authorization source.

## 9. Multiple stores

Explicit: **one Merchant professional identity per user; zero, one, or many stores/restaurants.** No uniqueness is added to `merchant_stores.owner_user_id`. Node 5 must not narrow existing business rules.

## 10. Capability architecture

Identity ≠ capability.
- Driver capabilities remain in the certified model: `driver_profiles.capabilities` + `driver_has_capability` / `driver_set_capabilities` / `admin_set_driver_capability` / `mission_required_capability`. Keep as-is.
- Merchant business surfaces remain expressed by owned assets (a `food_restaurants` row = Repas surface; a `merchant_stores` row = Marché retail surface).

**No generic universal capability table.** A1 shows no evidence of need. Node 5 only gates capability *granting* by professional identity: a capability may not be granted to a user whose lane is not Driver.

## 11. Shopper classification

Marché shopper is a **Driver capability** (`marche_shopper` in `driver_profiles.capabilities`), exactly as R7 already implements it, enforced per mission via `mission_required_capability`. It is not a professional identity and not a separate lane. No change required — this is a confirmation, not a migration.

## 12. `user_roles` compatibility

No enum surgery, no row deletion in Node 5.

| value | posture |
|---|---|
| `client` | keep as baseline customer compatibility signal |
| `driver` | keep, **mirrored** from Driver lane during migration; new professional authority checks must NOT read it |
| `merchant` | remains unused/**deprecated**; must never become canonical; a guard should prevent granting it |
| `admin/god_admin/operations_admin/finance_admin` | governance axis, untouched |
| `agent`/`field_*`/`onboarding_specialist` | separate operational/governance axis, untouched |

Mirroring: yes, keep writing `user_roles.driver` on driver approval while frozen code still reads it. A6 removes readers one surface at a time, then a final pass stops writing it. Never delete rows before all readers are gone.

## 13. Admin axis separation

Three independent dimensions: customer baseline · optional professional identity · governance authority (`admin_users`, `is_any_admin`, `_is_god_admin`).

Future guard semantics:
- Admin authority never implies Driver or Merchant capability.
- Admin RPCs may *review/approve/suspend* a lane; they may **not** create a lane for a user who has the opposite lane, and may not bypass `UNIQUE(user_id)` — which they physically cannot, by §4.
- Any admin-initiated lane change must be an explicit, audited operation (release-then-claim, with §15 dependency checks), never an implicit side effect.

## 14. Wallet / finance compatibility

Slice 13 untouched. `wallets` keeps `UNIQUE(owner_user_id, party_type)`.

- Professional **claim creates no wallet**. Identity alone must not create money.
- Driver wallet creation stays where it is today: at the point the Driver operational lifecycle reaches approval.
- Merchant wallet/payable rails stay driven by existing merchant/store/payment law (R11 settlement).
- New precondition only: a `driver` party wallet may only be created for a user whose lane is Driver; a `merchant` party wallet only for a Merchant lane. Because a user can hold at most one professional lane, the existing unique constraint can never be used to hold both a driver and a merchant professional wallet going forward. Existing rows (5 driver + 4 merchant wallets, disjoint users) are already compliant.

## 15. Safe abandonment model (design only)

`professional_identity_release()` — server-computed, subject = `auth.uid()` (admin variant separate and audited).

**Recommendation: preserve the row, set `lifecycle_status='released'`, `released_at`, and null-out nothing.** Deleting destroys the audit trail of a lane that once existed and makes "identity hopping" invisible. A released row still occupies `user_id`, so re-claim into the *other* lane must be an explicit, policy-gated UPDATE of `professional_type` (governance-visible), not a silent new INSERT.

Blocking dependencies:

| Lane | Blocker | Checked by |
|---|---|---|
| Driver | `driver_profiles.status` approved/suspended | STATUS |
| Driver | approved credentials/documents | STATUS |
| Driver | granted operational capabilities | EXISTENCE (non-empty) |
| Driver | rides / missions / package deliveries / procurement missions | EXISTENCE |
| Driver | driver earnings, cash ledger, cashout requests, collateral | EXISTENCE |
| Driver | ops sanctions / bans / group commissions | EXISTENCE |
| Merchant | store/restaurant with approved status | STATUS |
| Merchant | `marche_orders`, fulfillment transitions | EXISTENCE |
| Merchant | `merchant_payables`, settlement requests, payout allocations | EXISTENCE |
| Merchant | price observations sourced from this merchant's asks | EXISTENCE |
| Merchant | reputation events, `marche_ops_cases`/controls | EXISTENCE |

Rule of thumb: *lifecycle* objects are checked by STATUS (an unapproved draft is not a blocker); *historical/economic* objects are checked by EXISTENCE (any row is permanent history).

Return shape:
```json
{ "release_allowed": false,
  "blocking_reasons": ["DRIVER_APPROVED","DRIVER_HAS_MISSION_HISTORY","DRIVER_HAS_EARNINGS"] }
```

## 16. Rejection semantics

**Recommendation: B — rejected retains the lane** until an explicit, dependency-checked release.

Justification: auto-release turns a rejection into a free lane switch. A user refused as a Driver for identity/KYC reasons could immediately become a Merchant, defeating the review control. Retaining the lane keeps the refusal attached to the account; a controlled release remains available when no irreversible dependency exists, which preserves legitimate second chances without enabling review-shopping.

## 17. Suspension semantics

Hard design requirement: **suspension never permits lane switching.** A suspended Driver remains `professional_type='driver'`; a suspended Merchant remains `professional_type='merchant'`. `professional_identity_release()` must hard-fail on `lifecycle_status='suspended'` with `PROFESSIONAL_IDENTITY_SUSPENDED`, ahead of all other dependency checks. No self-service path may mutate `professional_type` while suspended.

## 18. Legacy bootstrap / backfill design

Driver seed = `driver_profiles.user_id` ∪ `driver_applications.user_id` (all statuses, including pending/rejected/suspended). Rationale: A3's law is that a meaningful onboarding claim already reserves the lane; a pending applicant has claimed. Seeded `lifecycle_status` maps: approved→`approved`, suspended→`suspended`, rejected→`rejected`, otherwise→`onboarding`.

Merchant seed = distinct users from `merchant_stores.owner_user_id` ∪ `food_restaurants.owner_user_id` ∪ `merchants.owner_user_id`, non-null. Seeded status: any approved asset→`approved`, else→`onboarding`.

Evidence rule: ownership of *any* meaningful merchant onboarding/ownership artifact claims the Merchant lane. Rows in `merchants` with a NULL `owner_user_id` seed nothing.

**Migration guard (mandatory):** compute both sets; if the intersection is non-empty, `RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_BACKFILL_CONFLICT'` with the offending user ids and abort the whole migration. Never auto-pick a side. Current live intersection = 0, re-verified this pass.

## 19. Data invariants

- `user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE` (PK gives the UNIQUE).
- `professional_type` constrained to `{driver,merchant}`.
- `lifecycle_status` constrained to `{onboarding,approved,suspended,rejected,released}`.
- `claimed_at NOT NULL DEFAULT now()`.
- `approved_at`, `suspended_at`, `rejected_at`, `released_at` nullable timestamps.
- Light consistency only: `approved_at IS NOT NULL` when status is `approved`; same shape for `suspended`/`rejected`/`released`. **Do not** add cross-status transition constraints before A3/A4 finalise semantics.
- `created_at` / `updated_at` with the standard update trigger, per project convention.

## 20. RLS / grants posture

- RLS ENABLED.
- `GRANT SELECT ON public.professional_identities TO authenticated` + policy `user_id = auth.uid()`; admin read via existing governance helper.
- **No** INSERT/UPDATE/DELETE grants to `authenticated` or `anon`. No `TRUNCATE/TRIGGER/REFERENCES` (matching the R14 posture).
- `GRANT ALL ... TO service_role`.
- No `anon` access at all — professional identity is private truth.
- All mutation via SECURITY DEFINER RPCs with `SET search_path = public`.

`driver_has_capability(uuid,text)` currently EXECUTE to PUBLIC: **recommend narrowing to `authenticated`** in the eventual architecture; it is a per-user capability probe over another user's operational state and has no anon use case. Not changed in A2.

## 21. Client identity/mode contract

Server-returned shape (single read RPC, e.g. `my_professional_identity()`):
```json
{ "professional_type": "none|driver|merchant",
  "professional_status": "onboarding|approved|suspended|rejected|released|null",
  "available_modes": ["client", "..."] }
```
- none → `["client"]`; driver → `["client","driver"]`; merchant → `["client","merchant"]`. Never `["client","driver","merchant"]`.
- `preferred_mode` is presentation only and lives client-side (`cc_app_mode_override`).
- **Stale localStorage rule:** on hydrate, if `preferred_mode ∉ available_modes`, the client discards it, falls back to `client`, and rewrites storage. Server truth always wins; no UI path may synthesise a mode the server did not return.

## 22. Phone-first / second-account policy

Current auth: email+password with phone stored on `profiles` (normalized `+224XXXXXXXXX`). Auth-level uniqueness is on **email**; phone uniqueness is enforced by product convention on `profiles`.

Consequences, stated plainly:
- A Driver who wants a separate Merchant account must create a **second auth identity with a different email**.
- Phone uniqueness must **not** be weakened. Therefore the second account also requires a **different phone number** — which is the operationally distinct credential in a phone-first Guinean market, and it is the real constraint for the user.
- The current login flow supports separate accounts fine (independent sessions), so the policy is operationally feasible, but the two accounts are unlinked: separate wallets, separate history, separate notifications.
- Multi-account linking is explicitly **out of scope for Node 5**.

## 23. Atomic claim concurrency design

```
FUNCTION _professional_identity_claim(_user uuid, _type professional_type)
BEGIN                                   -- caller's transaction
  IF _user IS NULL THEN RAISE 'AUTH_REQUIRED'; END IF;

  INSERT INTO professional_identities(user_id, professional_type, lifecycle_status, claimed_at)
  VALUES (_user, _type, 'onboarding', now())
  ON CONFLICT (user_id) DO NOTHING
  RETURNING * INTO v_row;               -- winner path

  IF v_row IS NULL THEN                 -- loser / pre-existing path
    SELECT * INTO v_row
      FROM professional_identities
      WHERE user_id = _user
      FOR UPDATE;                       -- blocks until the winner commits

    IF v_row.professional_type <> _type THEN
      RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_CONFLICT';   -- rolls back everything
    END IF;
    IF v_row.lifecycle_status = 'suspended' THEN
      RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_SUSPENDED';
    END IF;
    v_idempotent := true;
  END IF;
  RETURN v_row;
END
```
Calling RPC ordering (single transaction):
1. resolve `auth.uid()`
2. `_professional_identity_claim(...)`  ← nothing else may precede it
3. create/upsert onboarding artifact (guarded by existence so retries don't duplicate)
4. commit

Primitive choice: `INSERT ... ON CONFLICT DO NOTHING` + `SELECT ... FOR UPDATE` on the loser branch. Smallest sufficient mechanism — the unique index is the arbiter; `FOR UPDATE` only serialises the read-back and same-lane retry. Advisory locks are unnecessary and would add a second, weaker source of exclusion. A3 proves this with true multi-connection concurrency.

## 24. Authority migration map (A6 / A7)

**A6 — Driver surfaces**

| Surface | Risk |
|---|---|
| `driver_apply()` / driver application RPCs (add claim as first statement) | MEDIUM |
| driver approval path (`driver_profiles.status`, `user_roles.driver` mirror, driver wallet creation) | HIGH (finance) |
| `driver_set_capabilities` / `admin_set_driver_capability` (gate on lane) | MEDIUM |
| `mission_claim`, `mission_required_capability`, offer/dispatch paths | HIGH (frozen lifecycle, SECURITY DEFINER) |
| `marche_shopper_*` (R7) | HIGH (frozen) |
| driver cash ledger / cashout / collateral | HIGH (finance) |
| `DriverSessionContext`, `useDriverProfile`, driver route guards | LOW |

**A7 — Merchant surfaces**

| Surface | Risk |
|---|---|
| store/restaurant creation RPCs & `StoreOnboardingSheet` / `RestaurantOnboardingSheet` (add claim first) | MEDIUM |
| `MerchantApply` / `MerchantOnboarding` pages, `MerchantActivationPanel` | LOW |
| `merchant_stores` / `food_restaurants` RLS (ownership stays canonical) | MEDIUM |
| `marche_merchant_*` ops/cockpit RPCs (R11/R12) | HIGH (frozen) |
| `merchant_payables`, settlement requests, payout allocations | HIGH (finance) |
| `v_marche_listing_truth` / publication guard (must stay store-approval driven) | HIGH (frozen R1.5) |
| `MerchantModeToggle`, `useMerchantIdentity`, `useAppMode` | LOW |

**Staging, not one pass:** (1) create table + backfill + claim primitive; (2) wire claim into onboarding entry points only; (3) migrate LOW client guards to the new read RPC; (4) migrate MEDIUM server surfaces; (5) only then touch HIGH finance/frozen surfaces, each with its own certification; (6) stop writing `user_roles.driver`.

## 25. Recommended model — final proposal

```sql
-- SHAPE ONLY. NOT A MIGRATION.
professional_type   : 'driver' | 'merchant'
lifecycle_status    : 'onboarding' | 'approved' | 'suspended' | 'rejected' | 'released'

public.professional_identities (
  user_id            uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  professional_type  professional_type   NOT NULL,
  lifecycle_status   lifecycle_status    NOT NULL DEFAULT 'onboarding',
  claimed_at         timestamptz NOT NULL DEFAULT now(),
  approved_at        timestamptz,
  suspended_at       timestamptz,
  rejected_at        timestamptz,
  rejection_reason   text,
  released_at        timestamptz,
  claim_source       text,          -- 'driver_apply' | 'store_create' | 'restaurant_create' | 'backfill'
  created_by         uuid,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
)
```
- Exclusivity: PK on `user_id`.
- Claim: `professional_identity_claim(type)` → `_professional_identity_claim` internal, first statement of every onboarding RPC.
- Release: `professional_identity_release()` → tombstone to `released`, blocked by suspension and by the §15 dependency matrix.
- Driver: `driver_profiles` keeps operational + approval truth; lane status is a projection.
- Merchant: ownership of stores/restaurants keeps business + approval truth; lane status is account-level only.
- Capabilities: unchanged Driver capability model; merchant surfaces = owned assets.
- Admin: independent axis; may review lanes, may never bypass exclusivity.
- Finance: unchanged Slice 13; claim creates no wallet; wallet party_type must match the lane.
- RLS: read-own only, all mutation via SECURITY DEFINER RPCs, no anon.

```text
                     AUTH USER
                         |
                      CUSTOMER            (intrinsic, always)
                         |
        +---- PROFESSIONAL IDENTITY (0..1) ----+
        |                                      |
      DRIVER                               MERCHANT
        |                                      |
  capabilities                         business assets
  (driver_profiles.capabilities)       (merchant_stores / food_restaurants
   moto, course, bonbonna,              / merchants; 0..N; per-store approval)
   taxi prive, repas/marche
   delivery, marche shopper)

  ADMIN / GOVERNANCE  ......... independent axis (admin_users, user_roles admin values)
  WALLETS / LEDGER    ......... independent certified financial truth (Slice 13)
```

## 26. Risk register

| # | Risk | Mitigation direction |
|---|---|---|
| 1 | Dual authority during migration (lane vs legacy checks) | staged A6/A7; lane is exclusivity-only until a surface is explicitly migrated |
| 2 | Duplicated approval truth (lane vs `driver_profiles.status`) | lane status is a projection; no authority check reads it (§7) |
| 3 | Stale `user_roles.driver` | keep mirroring during migration; remove readers before removing writers before removing rows |
| 4 | Accidental resurrection of `merchant` role authority | never grant it; add a guard that refuses inserting `user_roles.merchant`; document as deprecated |
| 5 | Professional row without onboarding artifact | claim + artifact in one transaction; orphan detector in A3 QA |
| 6 | Onboarding artifact without professional row | claim is the first statement of every onboarding RPC; backfill covers legacy |
| 7 | Release after economic history | §15 EXISTENCE checks on all economic tables; fail-closed default |
| 8 | Admin bypass of exclusivity | PK makes it physically impossible; admin lane change must be explicit + audited |
| 9 | Duplicate professional wallets | keep `UNIQUE(owner_user_id, party_type)`; gate professional wallet creation on matching lane |
| 10 | Stale UI mode | `preferred_mode ∉ available_modes` → discard and fall back to client (§21) |
| 11 | Cross-account notification routing (two accounts, one human) | out of scope; document that accounts are unlinked; no shared phone |
| 12 | Second-account phone constraint | do not weaken phone uniqueness; state the product consequence explicitly (§22) |
| 13 | Backfill overlap appearing between design and migration | migration aborts on non-empty intersection; never auto-resolve |
```
```
