# NODE 5 · A10 — EXISTING CONFLICT REMEDIATION

Status: **CERTIFIED · LIVE_REMEDIATIONS = 0**
Suite: `_qa_node5_identity_a10` → **95 / 95 · 0 failed**
Canonical board: **5,439 / 0** (5,344 pre-A10 + 95). Raw with Bonbonna component
wrappers: 5,517 (do not double-count the +78).

A10 re-audited every existing professional record under the finalized Node 5
laws (A2–A9), classified every contradiction category, and established a
deterministic, governance-only conflict detector. **No live user's professional
state was changed.**

---

## 1. Canonical derived sets (re-derived post A2–A9, not from A1)

| Set | Definition |
| --- | --- |
| ACTIVE DRIVER IDENTITY | `professional_identities` where `professional_type='driver' AND claim_state='active'` |
| ACTIVE MERCHANT IDENTITY | same with `professional_type='merchant'` |
| CURRENT DRIVER ARTIFACT | `driver_profiles.status ∈ (pending, approved, suspended)` or `driver_applications.decision ∈ (pending, approved)` |
| HISTORICAL DRIVER | `driver_profiles.status ∈ (withdrawn, rejected)`, `driver_applications.decision = withdrawn` |
| CURRENT MERCHANT ASSET | `merchant_stores.status ∉ (archived, rejected)`, `food_restaurants.status ∉ (archived, rejected)`, `merchants.status='active'` with a canonical owner |
| HISTORICAL MERCHANT | archived / rejected assets |
| DRIVER FINANCE EVIDENCE | driver wallets, pending `driver_cashout_requests` |
| MERCHANT FINANCE EVIDENCE | merchant wallets, pending `merchant_settlement_requests`, open `merchant_payables` |

Financial evidence never defines current professional class. Only an ACTIVE
`professional_identities` row does.

---

## 2. Conflict taxonomy

| Code | Severity | Meaning |
| --- | --- | --- |
| `C1_DUAL_ACTIVE_IDENTITY` | CRITICAL | more than one active lane (structurally blocked by the partial unique index) |
| `C2_ACTIVE_DRIVER_WITH_CURRENT_MERCHANT_ASSET` | CRITICAL | driver class + live merchant asset |
| `C3_ACTIVE_MERCHANT_WITH_CURRENT_DRIVER_ARTIFACT` | CRITICAL | merchant class + live driver artifact |
| `C4_CURRENT_DRIVER_ARTIFACT_WITHOUT_ACTIVE_DRIVER_IDENTITY` | CRITICAL | driver authority with no lane |
| `C5_CURRENT_MERCHANT_ASSET_WITHOUT_ACTIVE_MERCHANT_IDENTITY` | CRITICAL | merchant authority with no lane |
| `C6_RELEASED_DRIVER_STILL_OPERATIONAL` | HIGH | A4 release left an operational driver artifact |
| `C7_RELEASED_MERCHANT_STILL_OPERATIONAL` | HIGH | A4 release left an operational merchant asset |
| `C8_PROFESSIONAL_FINANCE_CLASS_MISMATCH` | HIGH | **pending** obligation payable under a class the account does not hold |
| `C9_LEGACY_ROLE_MISMATCH` | MEDIUM | `user_roles.driver/merchant` residue with no matching lane (no server authority) |
| `C10_ORPHAN_PROFESSIONAL_ARTIFACT` | MEDIUM | artifact with no canonical account |
| `I1_LEGACY_MERCHANT_ENTITY_NO_OWNER` | INFO | pre-Node-5 `merchants` directory row, owner NULL, confers no authority |
| `I2_LAWFUL_HISTORICAL_CROSS_CLASS` | INFO | lawful release-then-opposite-claim sequence |

Explicit non-conflicts (never flagged): customer+driver, customer+merchant,
admin+driver, admin+merchant, released-driver→active-merchant (and the mirror),
historical wallets of the opposite class, one merchant owning both Repas and
Marché assets, one driver holding several capabilities.

---

## 3. Audit surface

- `public._professional_conflict_scan()` — internal, read-only (no DML verbs),
  `SECURITY DEFINER`, **revoked from `anon` and `authenticated`**.
- `public.professional_identity_conflict_audit()` — governance RPC. Requires a
  session (`AUTH_REQUIRED`) and `_is_ops_or_god_admin` (`ADMIN_REQUIRED`).
  Returns severity summary + per-subject evidence (user id, code, severity,
  active class, artifact/asset states, released types, role signals, finance
  summary, classification, recommended posture). No emails, PINs, passwords or
  ledger rows are exposed.
- `public._professional_actor_class(uuid)` — classifies a subject as
  `staff_admin | qa_test | demo | orphan_unknown | real_user | unowned_entity`.

No one-click "make driver / make merchant / delete conflict" action exists, by
design. The detector reports evidence; it never picks a side.

---

## 4. Live census (read-only, post-cleanup)

```
subjects examined              12
CRITICAL                        0
HIGH                            0
MEDIUM                          0
INFO                            4   (I1_LEGACY_MERCHANT_ENTITY_NO_OWNER)
QA / test residue               0
unknown / unclassified          0
LIVE_REMEDIATIONS               0
```

- Active DRIVER identities: 6 · Active MERCHANT identities: 6 · intersection **∅**
- Released identities: 0 (nothing to re-validate; the release path is proven by fixture)
- Driver artifacts: `driver_profiles` 6 (4 approved, 2 suspended), `driver_applications` 5
  (4 approved, 1 pending) — every one backed by an ACTIVE driver lane
- Merchant assets: 6 stores (5 active, 1 paused), 1 restaurant — every one backed
  by an ACTIVE merchant lane
- Role residue: `user_roles.driver` = 5, all with an active driver lane;
  `user_roles.merchant` = 0 → zero C9
- Wallets: 61 client, 5 driver, 4 merchant, 1 master — no wrong-class pending
  obligation anywhere (`driver_cashout_requests`, `merchant_settlement_requests`,
  `merchant_payables` are all empty)
- Admin overlap: 1 admin account, no professional artifact mismatch

### The four INFO rows
`merchants` holds four legacy directory rows (Le Damier, Pharmacie Niger,
Boutique Kaba, Marché Madina) created 2026-05-15 with `owner_user_id IS NULL`.
NULL ownership confers **no** merchant authority — every merchant gate resolves
authority through `professional_identities` for a concrete owner. They are
historical directory data, not defects. **Do not auto-assign an owner.**

---

## 5. Operator guidance

1. **Never silently choose a professional side.** If a CRITICAL/HIGH conflict
   appears, stop and gather evidence: operational history, money dependencies,
   approval history, released claims, orders/missions, provenance.
2. Newest timestamp, a role row, a wallet, a UI preference, or "fewer rows on
   one side" are **not** decision criteria.
3. Released history is lawful history. Driver → release → Merchant (and the
   mirror) is legal and must never be "cleaned up".
4. Role rows and wallets are compatibility/economic residue, never class.
5. Wallets are never merged or deleted. Slice 13 remains sovereign.
6. Fixture/test residue is the only category eligible for automatic cleanup, and
   only through canonical cleanup functions.

---

## 6. Verification

- `_qa_node5_identity_a10` — 95 / 95 (structure, detector shape, audit security,
  clean-account negatives, lawful cross-class history, positive C4/C6/C5/C7
  detection on reachable worst-case fixtures, cross-class acquisition refusal,
  role/wallet non-authority, admin orthogonality, legacy merchant classification,
  live census, self-cleaning + non-drift).
- Node 5 regression: A2 96 · A3 119 · A4 133 · A5 111 · A6 110 · A7 130 ·
  A8 93 · A9 121 · A10 95.
- Full board: **5,439 canonical / 0 failed** (raw 5,517).
- `bunx tsgo --noEmit` clean · Vitest 19 files / 155 tests pass · production
  build OK (25.5s, PWA 136 precache entries).
- Non-drift: identity, admin, finance and product snapshots identical before and
  after A10.
