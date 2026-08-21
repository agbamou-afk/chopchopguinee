# NODE 5 · A11 — ADMIN / STAFF IDENTITY SEPARATION

Status: CERTIFIED
Suite: `_qa_node5_identity_a11` — **108 / 108 · 0 failed**
Full board after A11: **5,625 assertions · 0 failed**

## Law

Two independent authority axes, never inferred from each other:

- **Governance / staff axis** — `admin_users` (grade + status) and `user_roles`
  (staff roles: `field_captain`, `onboarding_specialist`, …). Read only through
  `is_admin`, `is_any_admin`, `has_admin_role`, `_is_god_admin`,
  `_is_ops_or_god_admin`, `_finance_privileged`, `_repas_caller_is_staff`.
- **Professional axis** — `professional_identities` (Driver XOR Merchant), read
  through `professional_active_type`, `_driver_class_active`,
  `_merchant_class_active`, `account_available_modes`.

Rules enforced:

1. Governance authority never creates, implies, or unlocks a professional lane,
   a professional workspace mode, a driver profile, a store, a professional
   wallet, or a driver capability.
2. Professional identity never creates or implies governance authority; admin
   RPCs refuse professional callers with `forbidden`.
3. Lawful overlap (a real admin who is also a real approved driver/merchant) is
   allowed; each axis is satisfied only by its own canonical source.
4. Transitions are isolated: revoking governance leaves the lane and its
   approval intact; releasing a lane leaves governance intact.
5. Forged JWT claims (`is_admin`, `admin_role`, `professional_type`) grant
   nothing on either axis.

## Changes shipped in A11

- **Governance table hardening** (parity with A9 identity hardening):
  `anon` holds no privilege on `admin_users`, `user_roles`, `approval_requests`,
  `agent_profiles`, `field_pilots`, `field_assignments`, `audit_logs`.
  `authenticated` lost `DELETE`, `TRUNCATE`, `TRIGGER`, `REFERENCES` on those
  tables; `audit_logs` is read-only for clients (writes are service-role only).
- **`_qa_node5_identity_a11()`** — 108 assertions across:
  A. structure and privilege separation (17)
  B. governance ⇒ no professional (16)
  C. staff classes: ops, finance, agent, field captain, onboarding (16)
  D. professional ⇒ no governance, incl. forged-claim probes (15)
  E. lawful overlap and revocation isolation (14)
  F. cross-axis transition isolation (8)
  G. finance non-interference (5)
  H. full non-drift / zero-residue snapshot (17)

No product behaviour changed: A2–A10 predicates, policies, and RPC contracts are
untouched. The suite is self-cleaning and asserts byte-identical live governance
rows before and after execution.

## Census at certification

- 1 live governance account (super_admin), no professional lane overlap.
- 12 live professional accounts, zero A10 conflicts, zero remediations required.
