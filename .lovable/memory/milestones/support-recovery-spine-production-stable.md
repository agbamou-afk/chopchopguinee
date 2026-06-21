---
name: Support + Recovery Spine — Stable
description: Milestone 2026-06-21 — user-facing Mes signalements page (/help/issues), report entrypoints added on wallet and driver earnings, support_issues schema/RLS unchanged
type: feature
---
Locked 2026-06-21.

- `src/pages/MyIssues.tsx` at `/help/issues` lists own issues via `listMyIssues` (RLS-scoped).
- `Help.tsx` links into Mes signalements.
- `WalletView` adds payment ReportIssueButton (surface=wallet).
- `DriverEarningsView` adds payment ReportIssueButton (surface=driver_earnings) next to cashout.
- No RLS change, no enum change, no wallet mutation from support UI.
- Admin triage already handled by `SupportAdmin.tsx` with role/severity/type/status filters.