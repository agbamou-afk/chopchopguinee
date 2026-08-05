---
name: Chop Pay Ledger Revival — In Progress
description: Chop Pay branding, finance-policy engine and driver commission/collateral holds; OM direct checkout archived, OM top-up retained
type: feature
---

# chop-pay-ledger-revival — NOT LOCKED

## Landed
- **Slice 0 policy freeze** — canonical rules in
  `docs/finance/CHOPCHOP_FINANCE_POLICY_FREEZE.md` (this document wins over all
  earlier finance docs). Envoyer collateral **75%**, declared-value cap
  500 000 GNF (collateral cap 375 000). Repas/Marché: Chop Pay orders 50%
  collateral, CASH orders 100%-of-subtotal courier funding from **unrestricted
  funds only**. Default 1% non-ride transaction fee. Cancellation 5% before /
  10% after dispatch.
- **Slice 1 ledger primitives** — `driver_starter_credit_policies` (25 000 GNF),
  `driver_promo_credits`, funding-source columns on `mission_financial_holds`,
  `driver_promo_balance`, `driver_funding_allocate` (promo-first for
  commission/fees, unrestricted-only for cash funding),
  `driver_starter_credit_grant`, `admin_reverse_starter_credit`,
  `admin_set_starter_credit_policy`, `admin_promotional_credit_treasury`.
  Cash-out excludes restricted funds. QA evidence:
  `docs/qa/chop-pay-slice1-results.md` (20/20 PASS, rolled back).
- `finance_policies` (per mission type: commission, min driver balance, collateral mode/pct/min/max, effective date) + launch defaults (10% commission; Repas/Marché 100% collateral, Envoyer 50%, caps applied).
- `mission_financial_holds` with `UNIQUE (source_module, source_id, kind)` idempotency and `policy_snapshot` per hold.
- RPCs: `finance_policy_current`, `finance_mission_requirement`, `driver_balance_summary`, `driver_financial_eligibility`, `driver_mission_hold_place`, `driver_mission_hold_release`, `driver_mission_commission_capture`, `driver_mission_hold_freeze`, `driver_collateral_resolve`, `admin_set_finance_policy`.
- Flags: `chop_pay_enabled` (off), `om_topup_enabled` (on), `om_direct_checkout_enabled` (off), `driver_balance_gate_enabled` (off).
- Public naming unified to **Chop Pay**; `wallet_public_enabled` kept as an alias.
- Driver operating-balance card (available / collateral / commission reserve / top-up).
- God Admin finance-policy editor at `/admin/finance-policy` (read-only for other roles).

## Rules
- Orange Money DIRECT checkout is archived, not deleted. OM remains the manual cash-in rail only.
- Commission is computed from the hold's policy snapshot — rate changes are never retroactive.
- Collateral is never captured silently: freeze then audited `driver_collateral_resolve`.
- Never mutate `wallets.balance_gnf` or `wallet_transactions` from the client.

## Remaining before lock
Runtime wiring of holds into ride/mission acceptance and completion, Chop Pay ecosystem checkout, Finance top-up ops surface for driver balances, full end-to-end QA.
Also: grant-on-approval wiring (DEF-019), admin starting-credit/treasury UI
(DEF-020), cash-order funding caller (DEF-021). All new flags remain OFF.
