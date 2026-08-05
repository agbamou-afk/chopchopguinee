# Chop Pay — customer payment product

**Chop Pay** is the public name of the CHOPCHOP money surface. Internal
database objects keep their historical names (`wallets`,
`wallet_transactions`, `topup_requests`) for compatibility.

## Launch payment model
| Rail | Status |
| --- | --- |
| Cash | **Primary** for rides, Bonbonna and cash-on-delivery orders |
| Chop Pay internal ledger | **Primary** for in-app balances, transfers, refunds |
| Orange Money **top-up / cash-in** | **Retained** — manual operator confirmation |
| Orange Money **direct checkout** | **Archived** — behind `om_direct_checkout_enabled` (off) |

Orange Money is no longer offered as a payment method at checkout for any
service. It is kept only as a way to fund a Chop Pay balance or a driver
operating balance, confirmed by a Finance Admin against real evidence.

## Flags
- `chop_pay_enabled` — public Chop Pay surface (off until QA green).
- `wallet_public_enabled` — legacy alias, still honoured (OR'ed).
- `om_topup_enabled` — Orange Money cash-in rail (on).
- `om_direct_checkout_enabled` — archived direct checkout (off).
- `driver_balance_gate_enabled` — driver operating-balance eligibility gate (off).
- `chop_pay_checkout_enabled` — Chop Pay as a checkout rail (off).
- `chop_pay_p2p_enabled` — person-to-person transfers (off).
- `driver_cashout_enabled` — payout infrastructure (off).
- `merchant_om_settlement_enabled` — outbound merchant OM settlement (off).
- `driver_starter_credit_enabled` — 25 000 GNF restricted starting credit (off).
- `cash_order_funding_enabled` — Repas/Marché cash-order courier funding (off).

Turning `chop_pay_enabled` off hides the public surface. It never mutates
balances, ledger history or reconciliation data.

Canonical money rules (commission, collateral, fees, cancellation, starting
credit): `docs/finance/CHOPCHOP_FINANCE_POLICY_FREEZE.md`.
