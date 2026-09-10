---
name: G5 Finance Admin Command Center — Certified
description: Canonical finance read model, governed provider-event rejection, Finance/Operations/Governance separation certified 36/36
type: milestone
---
Locked 2026-09-10. Doc: `docs/admin/G5_FINANCE_COMMAND_CENTER.md`.

- `public.finance_command_overview()` is the only finance console read model: read-only, gated by `admin_capability('finance.wallet.read')` (allow → God + Finance), no PII, sandbox excluded, each attention row carries its server capability mode.
- Direct browser mutation of `payment_provider_events` removed (policy dropped, grants revoked). Rejection goes through `admin_reject_om_event(uuid,text)` — `finance.topup.manage`, reason required, credited events refused, audited.
- Operations keeps `finance.wallet.read` in READ mode (facts only) and is denied every finance console. Finance holds `ops.*` in READ mode and no `governance.*` grant.
- Money movement stays approval-bound: wallet credit/adjust, payout confirm, refund approve, dispute resolve, treasury move, policy change.
- QA: `_qa_g5_finance_command_center()` 36/36, zero residue, no ledger/wallet/registry/event drift. Focused UI 26/26. Full Vitest 378. tsgo clean. Linter 647 (+2 intended).
- G6 not started. `payment_receiving_accounts` still RLS-writable by God/Finance — flagged for G6.
