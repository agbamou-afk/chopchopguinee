# CHOP CHOP — Web Production Release Candidate (`web-rc-1`)

Status: **RELEASE CANDIDATE — NOT LOCKED**
Baseline: main after `orange-money-sandbox-ecosystem-ready-stable`
RC working SHA: `fa9a186a23ef586b53afb18399fb1fcb0c6c3f4d` (superseded by this phase's commit; see §Freeze)
Release identifier: `web-rc-1`
Date: 2026-07-28

## 0. Freeze principle

From this record onward the web app is the authoritative baseline for Android
packaging. Permitted changes only:

1. release blocker fix
2. security fix
3. payment/provider adapter fix
4. Android packaging compatibility fix
5. deferred post-1.0 feature (must NOT enter Android 1.0)

No broad product features, no redesigns, no new service modules, no
fake-success paths.

## 1. Provider neutrality (binding constraint)

Orange Money is the launch provider only. The intent / refund / reconciliation /
ledger / mission-orchestration layers stay provider-abstracted:

- `src/lib/payments/providers/registry.ts` — adapter registry
- `src/lib/payments/providers/types.ts` — `PaymentProviderAdapter`, normalized events
- `payment_intents`, `payment_refund_requests`, `payment_provider_events`,
  `payment_reconciliation_events` — provider column driven, not OM-specific

No release work in this phase added OM-specific coupling. A second low-fee rail
must be addable as a new adapter + provider row, with zero mission-layer change.

## 2. Role mission inventory

| Role | Auth entry | Gates | Primary dashboard | Critical missions | Payment dependency | Support path | Launch risk |
|---|---|---|---|---|---|---|---|
| Client | `/auth` (email+password) | `RequireProfile` → `/complete-profile`; legal consent modal | `Index` client shell | ride quote→request→assign→pickup→complete; Repas order; Marché offer | OM manual verification (operator) | `/help`, `/help/issues`, ReportIssueButton | OM manual latency; no instant confirmation |
| Driver / courier | `/auth` + `signup_intent=driver` | `driver_applications` approval; `driver_profile` | DriverHome (mode toggle) | online/offline, offer accept, pickup handshake, completion, earnings, cashout | cash accounting, commission/debt, `driver_cashout_requests` | ReportIssueButton on Earnings | manual cashout payout |
| Restaurant (Repas) | `/auth` + merchant intent | merchant ownership + restaurant record | `MerchantHub` (`isRepasOnly`) | order accept/reject, prep→ready→handoff | order settlement state | order messaging thread | settlement display is informational only |
| Merchant / Marché | `/auth` + merchant intent | `merchant_stores` ownership/approval | `MerchantHub` Marché layout | listing, offer accept/reject, paid progression, fulfillment | `marketplace_offers.settlement_state` | order messaging thread | merchant approval backlog |
| Finance Admin | `/admin` | `AdminGuard` + `must_change_password` | `/admin` | top-ups, cashouts, OM reconciliation, refunds | full finance modules | `/admin/support` | manual reconciliation throughput |
| Operations Admin | `/admin` | `AdminGuard` + `must_change_password` | `/admin/ops` | driver approvals, live ops, support | read-limited finance | `/admin/support` | none blocking |
| God Admin | `/admin` | `AdminGuard` + `must_change_password` | `/admin` | everything + `/admin/payments/sandbox` | sandbox simulation RPCs (God only) | `/admin/support` | sandbox must stay OFF in prod |

## 3. Gate table

| Gate | Status | Evidence |
|---|---|---|
| Production build clean | GREEN | `npm run build` ✓ 23.3s, PWA `dist/sw.js` + 127 precache entries |
| TypeScript | GREEN | `tsgo --noEmit` clean |
| Unit tests | GREEN | 12/12 pass (was 11/12 — see DEF-002) |
| Frontend secret sweep | GREEN | only public anon JWT (`role: anon`) + public map token in bundle |
| Sandbox OFF in production | GREEN (was RED) | DEF-001 fixed; `om_sandbox_enabled=false`, `om_environment=false` |
| Feature-flag rollback order | GREEN | documented + verified via flag registry, see rollback runbook |
| Staff forced password change | GREEN (code) / YELLOW (live) | `AdminGuard` + `admin_clear_must_change_password()`; live staff login not executable here |
| Offline / low-data | GREEN (code) | `DegradedMapPanel`, `clientCache`, `fieldDrafts`, guarded PWA registration |
| Orange Money real/manual path | **YELLOW** | no live operator reference available in this environment |
| SMTP live inbox (Gmail/Yahoo/iCloud/Orange) | **YELLOW** | `email_send_log`: 4 sent total, last 2026-06-06; no multi-provider inbox evidence |
| Rollback executed for real | **YELLOW** | flag rollback verified; deployment rollback is paper-only until a real deploy is rolled back |
| P0 open | 0 | DEF-001 closed |
| P1 open | 0 | — |
| P2 accepted | 3 | see defect registry |

## 4. Lock recommendation

**DO NOT LOCK YET.** Three gates are YELLOW and all three require actions that
cannot be performed from this environment (a real Orange Money operator
reference, real mailbox access, and a real production deploy+rollback cycle).
All engineering work reachable from here is complete.

See `docs/qa/web-production-release-matrix.md` §Manual actions for the exact
external steps required to turn each YELLOW GREEN.
