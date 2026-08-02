# Web Production Release QA Matrix (`web-rc-1`)

Legend: **PASS** verified this phase · **PASS(code)** verified by code/state
inspection, no live actor available · **BLOCKED** requires external actor ·
**FAIL** → defect ID.

## Client (A–K)

| # | Test | Result | Notes |
|---|---|---|---|
| A | signup / signin / profile completion | PASS(code) | `AuthProvider` + `RequireProfile`; unit-covered (12/12). Metadata repair path prevents repeat `/complete-profile`. |
| B | password reset & recovery | BLOCKED | needs real mailbox — see SMTP gate |
| C | ride quote→request→assign→pickup→complete | PASS(code) | `ride_compute_quote_gnf` authoritative server-side; `ride_dispatch` gated |
| D | no-driver / cancel before assignment | PASS(code) | no fee path when `driver_id is null` |
| E | cancel after assignment, fee/refund | PASS | `ride_cancel` captures 10% to master wallet |
| F | Repas browse→cart→checkout→accept→complete | PASS(code) | order thread + settlement state present |
| G | Repas rejection / cancel / refund | PASS(code) | `payment_refund_requests` lifecycle |
| H | Marché browse→offer→accept→pay→fulfil | PASS(code) | `marketplace_offers.settlement_state` |
| I | Marché rejection / cancel / refund | PASS(code) | same refund model |
| J | notifications + support visibility | PASS | `/help/issues` |
| K | OM Wallet payment/refund history | PASS | `OmPaymentsList` shows own intents + refund status, no balance |

## Driver / courier (L–U)

| # | Test | Result | Notes |
|---|---|---|---|
| L | approval gate / profile state | PASS(code) | `driver_applications` + `driver_profile` |
| M | online/offline toggle | PASS(code) | offers gated on `isOnline` |
| N | incoming offer | PASS(code) | `useIncomingOffers` |
| O | accept / decline | PASS(code) | |
| P | arrived → QR/code handshake | PASS(code) | `scanner` flag true |
| Q | in-progress → completion | PASS(code) | terminal statuses never reopen (`isActiveClientRideStatus`) |
| R | earnings update | PASS(code) | honest "Versement sous 24h" copy |
| S | cash accounting / commission / debt | PASS(code) | debt limit enforced |
| T | cashout request + admin review | PASS(code) | `driver_cashout_requests` → `/admin/wallet/driver-cashouts` |
| U | offline interruption during mission | PASS(code) | server state wins on reconnect; `DegradedMapPanel` |

## Restaurant (V–AA) · Merchant/Marché (AB–AH)

All **PASS(code)**: ownership gate (`isRepasOnly` vs Marché layout), order
visibility, accept/reject, prep→ready→handoff, settlement display, refund state
consistency, offer accept/reject, paid progression, fulfilment, payable display.
No live merchant actor was available to execute a real end-to-end order.

## Admin (AI–AQ)

| # | Test | Result | Notes |
|---|---|---|---|
| AI | God Admin access + password-change enforcement | PASS(code) | `AdminGuard` → `/admin/change-password` when `must_change_password` |
| AJ | Finance Admin limits | PASS | `can('finance_admin', ...)` unit-tested |
| AK | Operations Admin limits | PASS | `operations_admin` cannot edit wallet (unit-tested) |
| AL | driver approval/rejection | PASS(code) | |
| AM | cashout review | PASS(code) | |
| AN | OM reconciliation / manual ops | PASS(code) | `/admin/wallet/reconciliation`, `om-import-csv` |
| AO | sandbox OFF & isolated in production | **PASS (after DEF-001 fix)** | both flags now `false`; simulation RPCs are `is_god_admin` only |
| AP | support / recovery handling | PASS | `/admin/support` |
| AQ | Ops Command Center readiness | PASS | `/admin/ops`, 60s polling |

## Orange Money real/manual verification — **GATE YELLOW**

Verified by code/state: sandbox fixtures (`OM-SBX-*`) are rejected outside
sandbox mode; `confirm_payment_intent` / `fail_payment_intent` /
`choppay_capture_payment_intent` explicitly reject sandbox rows; idempotent
replay produces exactly one source object; failed finalization creates a
support/recovery record.

**Not executable here** (no live operator reference, no real MSISDN):
1. successful real payment confirmation
2. rejected/invalid reference
3. duplicate reference replay
4. amount mismatch
5. phone/reference mismatch
6. cancellation before fulfilment
7. cancellation after driver assignment (fee policy)
8. refund request creation
9. refund operational resolution
10. reconciliation record + audit trail
11. support escalation on unresolved mismatch

→ Finance Admin must execute all 11 against a real low-value production
transaction and attach the `payment_intents.id` + `payment_reconciliation_events`
row IDs here before lock.

## SMTP live inbox — **GATE YELLOW**

Observed state: `email_send_log` contains 4 `sent` and 4 `pending` rows, last
activity 2026-06-06. That is **not** delivery evidence. Domain
`notify.chopchopguinee.com` is configured; configuration is not delivery.

Required manual checklist (one row per cell, attach screenshots):

| Email | Gmail | Yahoo | iCloud | Orange |
|---|---|---|---|---|
| signup confirmation (if enabled) | | | | |
| password reset | | | | |
| staff temporary password / invitation | | | | |
| forced password-change notice | | | | |
| support/operational notification | | | | |

For each cell record: sender name, From address, Reply-To, subject, delivered
y/n, inbox vs spam, link opens correct origin, mobile rendering at 390×844,
expired-link behaviour. Update Ops readiness only from observed results.

## Auth recovery & staff password enforcement

| Check | Result |
|---|---|
| forgot-password request | BLOCKED (mailbox) |
| valid reset link | BLOCKED (mailbox) |
| expired/invalid reset link | PASS(code) — Supabase GoTrue default error surface |
| password update + session behaviour | PASS(code) |
| staff account creation | PASS(code) — `admin-create-staff-user` (God only) |
| temporary password login | PASS(code) |
| `must_change_password=true` route isolation | PASS(code) — `AdminGuard` redirects before any admin route renders |
| admin routes unreachable before change | PASS(code) |
| successful password replacement | PASS(code) |
| flag cleared only after success | PASS(code) — `admin_clear_must_change_password()` |
| temp password reuse rejected | PASS(code) — complexity + change-required check |
| audit log written | PASS(code) |
| role preserved after change | PASS(code) |

No bypass path found → no P0.

## Low-data / offline (390×844)

| Scenario | Result |
|---|---|
| first load slow network | PASS — low-data mode reduces nonessential map load |
| returning load from SW cache | PASS — 127 precache entries |
| offline on home/dashboard | PASS — honest offline surface |
| offline during map/search | PASS — `DegradedMapPanel` |
| offline while composing a mission | PASS — no submit allowed |
| connection loss after submit | PASS — server state authoritative on reconnect |
| connection loss during active driver mission | PASS |
| retry after restore | PASS |
| duplicate-submit prevention | PASS — idempotency keys on intents |
| stale state refresh | PASS |
| low-data assets/maps | PASS — `useLowDataMode` |
| toast/notification behaviour | PASS |
| keyboard overlap / modal recovery | PASS(code) |
| PWA update handling | PASS — `autoUpdate`, guarded registration, `?sw=off` kill switch |

No fake-success submission path found offline.

## Frontend secret & security sweep

Swept `dist/` (post-build) and `src/`:

| Pattern | Result |
|---|---|
| `service_role` key | none — single match is French UI copy in `RepasPayments.tsx` |
| JWTs in bundle | one, decoded `{"role":"anon"}` — approved public key |
| provider API secrets / SMTP passwords / private keys | none |
| hardcoded admin or temp staff passwords | none in bundle |
| `.env` in build output | none |
| debug/demo bypass | `DemoTestPanel` is `import.meta.env.DEV`-gated and tree-shaken out of the production bundle; `?demo=1` has no effect in prod |
| console logs with PII/payment refs | 1 found (driver offer payload) → DEF-003 fixed |
| source maps exposing secrets | none emitted |

## Build / deployment verification

| Check | Result |
|---|---|
| clean build | PASS — `npm run build`, 23.3s |
| typecheck | PASS — `tsgo --noEmit` clean |
| unit tests | PASS — 12/12 |
| production bundle | PASS — `dist/` with hashed chunks |
| lazy-load / chunk smoke | PASS — admin/map routes code-split |
| PWA manifest + SW | PASS — `manifest.webmanifest`, `dist/sw.js`, workbox runtime |
| migration consistency | PASS — 169 migrations, no drift |
| Edge Function status | PASS(code) — 23 functions present at RC SHA |
| RLS / function permission spot-check | PASS with warnings — 451 warn-level linter findings, 0 error-level (DEF-005) |
| bundle size | WARN — DEF-004 accepted |

## Manual actions required to reach GREEN

1. **Orange Money (Finance Admin):** execute the 11 real/manual cases above on a
   low-value production transaction; attach intent + reconciliation IDs.
2. **SMTP (Ops):** complete the 5×4 inbox matrix with screenshots from Gmail,
   Yahoo, iCloud and an Orange-hosted mailbox.
   The welcome mail is the intended vehicle: it is dispatched server-side by
   the `profiles` insert trigger, exactly once per account
   (`welcome_email_dispatches`), and is the only mail a new account receives
   while auto-confirm stays ON. Rail evidence (render → queue → provider
   accepted → `sent`) is already recorded in
   `docs/qa/smtp-inbox-test-results.md`; only real inbox placement is missing.
3. **Rollback (God Admin):** perform one real publish → rollback → re-publish
   cycle and record the outcome in the rollback runbook §Rollback test status.

---

## Superseded references

The deploy/rollback runbooks and the earlier defect list were consolidated into
the canonical RC set:

- `docs/releases/web-production-rc.md` — freeze rules, severity, gates
- `docs/releases/web-production-release.md` — release instructions
- `docs/releases/web-production-rollback.md` — rollback instructions
- `docs/releases/web-production-checklist.md` — tick-list
- `docs/qa/web-rc-defect-register.md` — canonical defect register
- `docs/qa/smtp-inbox-test-results.md` — SMTP evidence sheet
- `docs/security/web-rc-frontend-secret-audit.md` — secret audit
