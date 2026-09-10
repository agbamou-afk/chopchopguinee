# G5 — Finance Admin Command Center

Status: **CERTIFIED** (see closeout board below). Scope: G5 only. G1 constitution,
G2 backend capability law, G3 staff lifecycle and G4 operations command center are
unchanged; G6 is not started.

## 1. Principle

Finance holds **money authority only**. It reads operational facts, it never
mutates an operational case. Governance (staff, flags, settings, promotions)
stays outside Finance entirely. Every monetary movement remains bound to the
G2 capability registry, and every approval-bound capability still requires a
second God Admin.

Constitutional mapping actually stored in `admin_capability_grants`:

| Capability | Finance | Operations |
| --- | --- | --- |
| `finance.wallet.read` | allow | read |
| `finance.treasury.read` | allow | — |
| `finance.topup.manage` | allow | — |
| `finance.reconciliation.approve` | allow | — |
| `finance.payouts.manage` | allow | — |
| `finance.audit.view_financial` | allow | read |
| `finance.dormant.review` | allow | read |
| `finance.wallet.credit` / `.adjust` | approval_required | — |
| `finance.payout.confirm` | approval_required | — |
| `finance.refund.approve` | approval_required | — |
| `finance.dispute.resolve` | approval_required | — |
| `finance.treasury.move` | approval_required | — |
| `finance.policy.change`, `finance.flags.payment` | approval_required | — |
| `ops.*` (orders, drivers, users, support, risk, maps, liveops, reports) | read | allow |
| `governance.*` (staff, flags, settings) | — | — |

Operations keeps `finance.wallet.read` in **read** mode: it may see financial
facts through the G4 operational read model, and `admin_capability()` (allow
only) still denies it every finance console.

## 2. What G5 added

### `public.finance_command_overview()` — canonical read model
Read-only, `STABLE SECURITY DEFINER`, gated by
`admin_capability('finance.wallet.read')` (allow only → God + Finance).
Returns `generated_at`, `role`, a bounded `snapshot`, an `attention` list and the
`exceptions` list produced by `finance_treasury_exceptions()`.

- Snapshot queues: topups pending/review, open provider events, driver cashouts,
  merchant settlement requests, open merchant payables, open payout orders,
  pending refunds, payment intents in review, frozen wallets.
- Each attention row carries its **server capability mode**
  (`allow` / `approval_required` / `read` / `null`), so the console never presents
  an action the caller cannot lawfully execute.
- No PII: no phone, MSISDN, email or name is projected. References are truncated ids.
- Sandbox rows are excluded from provider events, intents and refunds.
- Exceptions are named and quantified; nothing is netted, plugged or auto-compensated.
  Master wallet `DEF-FIN-001` remains frozen and reported, not normalized.

### `public.admin_reject_om_event(uuid, text)` — governed rejection
Rejecting an unmatched Orange Money provider event used to be a **direct table
update available to any canonical admin**, including Operations. That path is
closed:

- policy `Admins update provider events` dropped; `UPDATE/INSERT/DELETE` revoked
  from `authenticated` on `payment_provider_events`;
- the new RPC enforces `finance.topup.manage`, requires a non-empty reason,
  refuses an already-credited event, and writes the G2 audit entry;
- `src/pages/admin/WalletReconciliation.tsx` now calls the RPC.

### Frontend
- `src/lib/admin/financeCommandCenter.ts` — read model client. One RPC, zero
  writes, honest states: a failed read is `Indisponible`, never `0`.
- `src/pages/admin/FinanceCommandCenter.tsx` — rebuilt on the read model:
  queues, treasury exceptions, attention list with execution-mode badges, and
  explicit escalation copy (`Intervention Opérations requise`).
- `src/lib/admin/permissions.ts` — `FINANCE_FORBIDDEN_MODULES` and
  `FINANCE_READ_ONLY_MODULES` make the Finance denial matrix explicit.

## 3. Certification board

| Gate | Result |
| --- | --- |
| `_qa_g5_finance_command_center()` | **36 / 36**, 0 failure |
| Ephemeral fixture residue | 0 (admin_users, wallets, profiles, auth.users) |
| Capability registry drift | none |
| Ledger posting drift | none |
| Wallet balance drift | none |
| Provider event drift | none |
| Focused UI suite `src/test/g5FinanceCommandCenter.test.ts` | **26 / 26** |
| Full Vitest | 36 files / 378 tests |
| `bunx tsgo --noEmit -p tsconfig.app.json` | clean |
| Supabase linter | 647 (+2 vs G4 baseline 645) — the two new gated SECURITY DEFINER reads |

Denials verified server-side: Operations, customer, suspended Finance,
temp-password Finance and unauthenticated callers are all refused
`finance_command_overview()`; Operations and customers are refused
`admin_reject_om_event`; Finance is refused payout-policy change without
approval, feature-flag changes and staff role grants.

## 4. Known posture / not in scope

- No live Finance Admin exists; certification used ephemeral fixtures only.
- No payment rail was activated and no provider secret was touched.
- `payment_receiving_accounts` remains writable by God/Finance via RLS
  (`can_manage_wallet`) rather than an RPC — finance-only already, flagged for G6.
- G6 (final adversarial governance certification) not started.
