# G6 — Final Adversarial Certification / Admin Architecture Lock

Status: **LOCKED**
Scope: audit → attack → remediate real defects → focused retest → full regression board → lock.
No product feature, business economics, payment rail, customer feature or real staff account was created or activated.

---

## 1. Census (live, read-only)

| Fact | Value |
| --- | --- |
| Public `admin_*` RPCs | 112 |
| `admin_*` executable by `anon` | 0 |
| Active God Admin | 1 (stored as `super_admin`) |
| Active Operations Admins | 2 (real, untouched, fingerprinted before/after) |
| Active Finance Admins | 0 |
| SECURITY DEFINER functions | 810 |

## 2. Real defects found and remediated

| # | Defect | Remediation |
| --- | --- | --- |
| 1 | `payment_receiving_accounts` was directly writable from a browser session by Finance/God (G5 known seam). | Raw grants revoked, write policies removed, `trg` rejects any session write; governed RPCs only. |
| 2 | Receiving-account routing could be edited in place — a money destination could change with no trace. | Added `version`, `effective_from`, `retired_at`, `superseded_by`; routing changes create a new version and retire the old one, under `finance.receiving_account.route` (approval-required, four-eyes). Metadata/activation sit under `finance.receiving_account.manage` (allow) with a mandatory reason. Operations holds neither. |
| 3 | `approval_requests` could be decided by a raw `UPDATE` from the admin console. | Console now calls `admin_review_approval`; raw mutation grants/policies removed. |
| 4 | Excessive `anon` DML/SELECT grants on sensitive payment/admin tables. | Revoked. |
| 5 | `admin_review_approval()` checked the canonical God role but not readiness — a staff account still on its temporary password could approve a two-person action. | Now requires `admin_staff_readiness(caller) = 'ready'`; anon EXECUTE revoked. |
| 6 | Dev harness `DemoTestPanel` wrote a wallet balance directly. | Wallet-reset action and button removed. A balance is a financial fact; it moves only through governed, audited server actions. |

Search-path and internal-trigger privilege hygiene were applied in the same pass.

## 3. Adversarial harness

`public._qa_g6_admin_architecture_lock()` — **128/128 pass, 0 failures**, ephemeral fixtures only, zero residue, zero drift.

Coverage: role canonicalisation and conflicts, readiness, capability registry, raw grants and policies, receiving-account validation/versioning/retirement, four-eyes binding, approval replay and intent mismatch, Operations↔Finance isolation, governance restrictions, audit immutability, Node 5 identity separation, financial invariants, drift and residue fingerprints.

Frontend lock suite `src/test/g6AdminArchitectureLock.test.ts` — **40/40**: no direct writes to governed tables anywhere in `src/`, receiving-account seam usage, governed approval console, retired staff endpoint, frontend role boundaries, guarded admin routes, no service-role key in browser code.

## 4. Harness correction (no product change)

`_qa_node5_identity_a11` check A13 still asserted the former "super-admin scoped mutation policy" on `admin_users`. G6 replaced that with a strictly stronger posture — no session role holds any write privilege and no non-SELECT policy exists — so the check now asserts the stronger invariant. Node 5 A11: 108 checks, 0 failures.

## 5. Final regression board

| Suite | Total | Failures |
| --- | --- | --- |
| G6 admin architecture lock | 128 | 0 |
| G5 finance command center | 36 | 0 |
| G4 operations command center | 40 | 0 |
| G3 staff lifecycle | 24 | 0 |
| G2 admin authority | 28 | 0 |
| Node 5 A2–A14 + final remediation + dormant liability | 1141 | 0 |
| Slice 13 run1–run7 | 509 | 0 |
| Node 4 Marché r1–r15 | 1293 | 0 |
| Node 3 Repas (r1–r4, r6, r10, r11, pickup) | 633 | 0 |
| Node 0 Course / Node 2 Taxi | 131 | 0 |
| Frontend Vitest | 418 (37 files) | 0 |

Typecheck `bunx tsgo --noEmit -p tsconfig.app.json`: clean. Build: clean. PWA precache: 137 entries.

## 6. Linter posture

651 issues — baseline 645 (G4) / 647 (G5), the delta being the intended governed receiving-account and governance-read functions. Breakdown: 31 RLS-enabled-without-policy (service-role-only ledger/queue/evidence tables, deny-by-default intended), 9 mutable search_path, 1 extension in public, 109 anon SECURITY DEFINER, 501 authenticated SECURITY DEFINER. Recorded, classified, not silenced. No RLS was weakened at any point.

## 7. Lock

The admin architecture is locked: G1 constitution, G2 backend capability law, G3 staff lifecycle, G4 operations console, G5 finance console, G6 adversarial certification. Any future change to admin authority must re-run the G2–G6 boards.
