# Web Production Release Candidate — Freeze Document (`web-rc-1`)

## Release metadata

| Field | Value |
|---|---|
| RC identifier | `web-rc-1` |
| Baseline milestone | `orange-money-sandbox-ecosystem-ready-stable` |
| Baseline commit (declared) | `3826dab294f27adaac8ed9ca03988090e5bfe215` |
| RC commit at audit time | `c45b19be31cee08b53bfb90ebf041c771759db0b` |
| Build timestamp | 2026-07-28T17:22Z |
| Environment | production (Lovable Cloud, `chopchopguinee.com` / `www.chopchopguinee.com`) |
| Migrations included | 170 files under `supabase/migrations` |
| Edge Functions included | 23 under `supabase/functions` |
| Rollback reference | previous published build; see `web-production-rollback.md` |
| Status | **RELEASE CANDIDATE — NOT LOCKED** |

## Allowed changes during RC

1. P0 / P1 defect fixes.
2. Security and privacy fixes.
3. Payment provider-adapter fixes (inside `src/lib/payments/providers/`).
4. Android packaging compatibility fixes.
5. Documentation, runbooks, QA evidence.
6. Honest copy corrections that remove a false claim.

## Prohibited during RC

- New business modules or verticals.
- New payment architecture or wallet model.
- Broad navigation or role-flow redesign.
- UX redesign not required to close a P0/P1.
- Major database state-machine changes.
- Deepening Orange Money coupling outside adapters/copy.

## Provider-neutrality rule

Orange Money is the **active launch rail only**. The intent, refund,
reconciliation, ledger and mission-orchestration layers must continue to depend
on the payment-intent contract, not on OM internals. A future low-fee rail is a
new adapter in `src/lib/payments/providers/registry.ts` plus its own tested
release phase — never a silent insertion into the frozen Android baseline.

## Severity definitions

**P0 — release blocker.** Security/privacy breach; unauthorized cross-role or
cross-tenant access; money/ledger corruption; duplicate charge, ride, order,
settlement or earning; auth fully blocked for a launch role; app unusable at
390×844; data-destructive behaviour; rollback impossible.

**P1 — must fix before lock.** Primary mission cannot complete; incorrect
payment/cancellation/refund state; broken recovery path; forced-password
enforcement bypass; material offline/reconnect failure; major mobile overflow or
blocked controls; admin cannot perform a required launch operation; production
email recovery unavailable.

**P2 — acceptable if documented and accepted.** Secondary UX friction,
non-critical copy inconsistency, cosmetic defects, edge-case operational
inconvenience with a safe workaround.

Defects are never downgraded to pass a gate.

## Hard exit gates

| Gate | Requirement |
|---|---|
| Orange Money orchestration | GREEN with real production evidence |
| SMTP | GREEN with observed mailbox delivery |
| P0 open | 0 |
| P1 open | 0 |
| P2 | documented + explicitly accepted |
| Rollback | materially tested |
| Production build | clean |
| Frontend secrets | none |
| Sandbox flags | OFF |
| Fake success states | none |

## Test-evidence requirements

- **Code-verified** results are labelled `PASS(code)` and are *not* sufficient
  for the Orange Money or SMTP gates.
- Real payment evidence must cite `payment_intents.id` and the
  `payment_reconciliation_events` row.
- Mailbox evidence must cite provider, timestamp, inbox-vs-spam placement, and
  a screenshot reference.
- Rollback evidence must cite the flag rows changed (`updated_at`) and/or the
  published build reverted to.
- Nothing may be marked GREEN from code review alone where a runnable path
  exists but was not run.

## RC amendment — Slice 2: Client shell + Services navigation (approved pre-lock)

Approved by the product owner before lock, so the release freeze does not apply.

- Bottom navigation is now exactly four destinations: Accueil, Services, Activité, Compte.
- The permanent center scanner FAB was removed; Scanner is a Services tile plus a
  compact shortcut in the Services header.
- The flag-gated ChopWallet tab was removed from the nav; the Orange-Money-first
  payment surface is reached from the Services directory.
- New client `Services` destination (`src/components/views/ServicesView.tsx`) with the
  full 10-service directory, wired to the existing actions and routes only.
- Home shows a compact subset with `Voir tous les services`.
- Envoyer has its final tile but an explicitly honest interim state pending Slice 3.

See `docs/product/client-services-navigation.md` for the full action map.
No pricing/wallet/backend changes. Sandbox flags remain OFF; public wallet remains OFF.
RC remains **UNLOCKED** pending Slice 3 and real-money/SMTP verification.

## RC amendment — Slice 3: Envoyer v1 (approved pre-lock)

- Real parcel/document module on the existing `package_delivery` mission type,
  provider-neutral payment intents and existing map components. No new payment
  architecture, wallet model or pricing engine.
- Ships behind `envoyer_enabled`, **OFF** in production.
- Docs: `docs/product/envoyer-v1.md`,
  `docs/architecture/envoyer-mission-and-payment.md`,
  `docs/qa/envoyer-v1-test-matrix.md`.
- Open: DEF-015 (P1, production finaliser not wired — contained by the OFF flag),
  DEF-016 (P2, no admin capability editor).
- Build packaging correction: Workbox `maximumFileSizeToCacheInBytes` raised to
  4 MiB because the main chunk (2,100.58 kB) exceeded the 2 MiB default. This was
  a packaging/precache limit, not an Envoyer runtime defect.
- Flags verified: `om_sandbox_enabled` false, `om_environment` false,
  `wallet_public_enabled` false, `envoyer_enabled` false.

RC remains **UNLOCKED**.
