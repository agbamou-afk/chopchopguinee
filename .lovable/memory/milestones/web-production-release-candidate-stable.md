---
name: Web Production Release Candidate
description: Release-freeze baseline web-rc-1 for Android 1.0 packaging — audit, QA matrix, defect registry, deploy/rollback runbooks; NOT locked (OM + SMTP + deploy-rollback gates YELLOW)
type: feature
---

# Web Production Release Candidate — `web-rc-1`

Status: **RELEASE CANDIDATE — LOCK WITHHELD**
Date: 2026-07-28
Baseline: main after `orange-money-sandbox-ecosystem-ready-stable`

## Freeze rule (binding)

The web app is now the authoritative baseline for Android 1.0. Only these change
classes are permitted: release blocker fix, security fix, payment/provider
adapter fix, Android packaging compatibility fix. Everything else is
deferred post-1.0. No broad features, no redesigns, no new service modules.

## Provider neutrality (binding)

Orange Money is the launch provider only. Ledger, intent, refund, reconciliation
and mission-orchestration layers remain provider-abstracted via
`src/lib/payments/providers/registry.ts`. A second low-fee rail must be addable
as a new adapter with zero mission-layer change. Do not deepen OM coupling.

## Delivered

- Release-candidate record, deploy runbook, rollback runbook (`docs/releases/`)
- Full role QA matrix + defect registry (`docs/qa/`)
- DEF-001 **P0 fixed**: sandbox flags (`om_sandbox_enabled`, `om_environment`)
  were left `true` in production after Slice D QA — now `false`
- DEF-002 P2 fixed: AuthProvider test mock lacked `rpc`, masking role loading
- DEF-003 P2 fixed: production console emitted driver offer payload
- Frontend secret sweep clean (only public anon key + public map token)
- Build / typecheck / 12 unit tests green

## Gates

GREEN: build, typecheck, tests, secret sweep, sandbox-off, flag rollback,
offline/low-data, staff password enforcement (code), P0=0, P1=0.
YELLOW: Orange Money real/manual evidence, SMTP live inbox evidence,
deployment rollback executed for real.

## Accepted P2

DEF-004 bundle size, DEF-005 451 warn-level Supabase linter findings,
DEF-006 self-serve read gaps on `driver_applications` / `driver_referrals` /
`topup_requests` (to be closed post-1.0 with sanitized RPCs, never raw SELECT).

## Do not lock until

The three YELLOW gates have real external evidence attached in
`docs/qa/web-production-release-matrix.md` §Manual actions.
