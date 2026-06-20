# Mission Launch RED Closure — Stable

Locked: 2026-06-20

Closes the three RED launch blockers raised in `product-critical-path-audit-stable`:
SMTP for auth emails, honest Orange Money top-up copy, and pilot driver readiness.
No wallet ledger, pricing, RLS, or feature-branch changes were made.

## Launch blocker board

| RED                          | Status              | Code action                                                                                  | Ops action needed                                                                 |
| ---------------------------- | ------------------- | -------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Production SMTP for auth     | CODE READY / NEEDS OPS | Auth uses Lovable-managed auth email pipeline; checklist documented in `docs/launch/smtp-readiness.md` | Verify sender domain DNS, run live signup + password reset, confirm in Cloud → Emails |
| Honest top-up copy           | VERIFIED            | Removed "Recharge instantanée" / "crédité automatiquement" from `WalletView` + `TopUpOrangeMoney`. Now reads: operator verification, credit after verification, keep proof of payment | None — verified in client UI                                                      |
| ≥10 approved pilot drivers   | CODE READY / NEEDS OPS | Pilot driver readiness checklist documented in `docs/launch/driver-pilot-readiness.md` (uses existing `DriversAdmin`, no fake records) | Onboard, approve, and live-test ≥10 drivers in pilot polygon                      |

## Honest top-up copy — what changed

- `src/components/wallet/TopUpOrangeMoney.tsx` step 5/6: payment proof + operator verification language; no "crédité automatiquement".
- `src/components/views/WalletView.tsx`: `LiveStrip` chip now says "Recharge vérifiée par opérateur"; sheet description says operator verifies before credit.
- Wallet ledger and crediting RPC are unchanged. Customer still submits OM code; admin reconciliation remains the source of truth.

## SMTP readiness

- Auth emails route through Lovable-managed `auth-email-hook`; no SMTP credentials live in `src/`.
- Production launch requires: verified sender domain DNS, live signup test, live password-reset test, deliverability check (inbox vs spam) on Gmail / Yahoo / Orange / iCloud.
- Detailed checklist: `docs/launch/smtp-readiness.md`.
- Status remains a launch RED until ops signs off on the checklist.

## Pilot driver readiness

- No fake driver records created. No driver auto-approval. No forced online state.
- Operator checklist: `docs/launch/driver-pilot-readiness.md` tracks approved count, pilot-zone assignment, online toggle test, signal freshness, payout/support contact.
- Status remains a launch RED until ops confirms ≥10 approved drivers with ≥5 live-tested online in the pilot polygon.

## Security / privacy

- No SMTP, Orange Money, or service-role secrets in frontend.
- No RLS weakening.
- No driver signal exposure beyond existing scoped RPCs.
- No wallet auto-credit.
- No pricing mutation.

## Files touched

- `.lovable/memory/index.md` (stale wording fixes)
- `.lovable/memory/milestones/mission-launch-red-closure-stable.md` (this file)
- `src/components/wallet/TopUpOrangeMoney.tsx`
- `src/components/views/WalletView.tsx`
- `docs/launch/smtp-readiness.md`
- `docs/launch/driver-pilot-readiness.md`