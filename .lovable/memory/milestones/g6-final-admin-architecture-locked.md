---
name: G6 Final Admin Architecture — LOCKED
description: Adversarial certification of the admin governance stack — governed receiving accounts, readiness-gated approvals, no direct writes to governed tables
type: milestone
---
Locked 2026-09-10. Doc: `docs/admin/G6_FINAL_ADMIN_ARCHITECTURE_LOCK.md`.

- `payment_receiving_accounts` is versioned and immutable from any browser session: `version`/`effective_from`/`retired_at`/`superseded_by`, a session-write-rejecting trigger, and governed RPCs. `finance.receiving_account.manage` = allow (reason required); `finance.receiving_account.route` = approval_required (four-eyes). Operations holds neither.
- `admin_review_approval()` now requires canonical God **and** `admin_staff_readiness(caller) = 'ready'` — a temporary-password account can no longer approve a two-person action.
- Approvals are decided only through `admin_review_approval`; raw `approval_requests` and `admin_users` writes are revoked for `anon` and `authenticated`.
- No surface, not even the dev harness, writes a wallet balance directly.
- Boards: G6 128/128, G5 36/36, G4 40/40, G3 24/24, G2 28/28, Node 3/4/5 + Slice 13 + Node 0/2 all 0 failures, Vitest 418/418, typecheck/build clean, PWA 137 entries. Linter 651 (classified, none silenced).
- Never weaken: readiness gate on approval, receiving-account versioning, capability registry, four-eyes binding, Node 5 identity law, finance/ledger law.
