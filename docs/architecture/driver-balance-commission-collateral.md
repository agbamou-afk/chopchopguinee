# Driver wallet, commission and collateral

## Purpose
There is **one driver ledger wallet** (party_type `driver`). Orange Money
top-ups and mission earnings credit it; CHOPCHOP commission, mission
collateral and cashout requests place **holds** on it. Held funds are not
withdrawable until released or captured. A driver may withdraw the
available balance; if that drops below mission requirements, future offers
pause until a new top-up or earning restores eligibility.

## Policy source of truth — `public.finance_policies`
Per mission type (`ride`, `bonbonna`, `repas`, `marche`, `envoyer`):
commission bps, fixed commission, minimum driver balance, collateral mode
(`none|fixed|percentage`), collateral pct/min/max, whether collateral is
required before offer visibility, effective date, enabled state.

Rows are **append-only in practice**: `admin_set_finance_policy` inserts a
new effective-dated row rather than editing history. God Admin only,
audited into `audit_logs` with before/after.

### Launch defaults (frozen — Slice 0/1, 2026-08-05)
Canonical source (authoritative, wins over this file):
`docs/product/chop-pay-canonical-operating-policy.md`.
| Mission | Driver commission | Collateral |
| --- | --- | --- |
| ride | 10% of fare | none |
| bonbonna | 10% of fare | none |
| repas (Chop Pay) | 0% | 50% of the food/merchandise **subtotal**, cap 500 000 GNF |
| marche (Chop Pay) | 0% | 50% of the merchandise **subtotal**, cap 1 000 000 GNF |
| repas/marche (CASH) | 0% | no collateral — courier funds **100% of the subtotal** from unrestricted funds (`cash_funding` hold) |
| envoyer | 0% | **75%** of the accepted declared value, declared value capped at 500 000 GNF (collateral cap 375 000 GNF) |
| all | — | minimum available balance 5 000 GNF |

Default non-ride transaction fee: **1%**, bases: merchandise subtotal
(Repas/Marché) and **delivery/service fee** (Envoyer — the seeded
`declared_value` basis is stale and pending correction; see canonical §13). Cancellation: **5%** before
dispatch, **10%** after dispatch; Repas customer cancellation locked once the
kitchen marks preparation.

### Restricted starting credit
A newly approved driver receives a one-time **25 000 GNF restricted** credit in
the same driver wallet. It funds commission, platform fees and collateral only.
It is excluded from withdrawable balance and can never fund cash-order
merchandise principal. Every hold records `unrestricted_gnf` / `promo_gnf`;
release restores each bucket, capture consumes the recorded split. See the
canonical operating policy for the full rules.

The collateral basis for repas/marche is the server-authoritative
item subtotal **only**: delivery fee, driver earning, tip, tax, platform
fee and service fee are excluded. Merchant/platform commissions are a
separate settlement policy and are never charged to the driver as
"driver commission".

Worked example (repas): subtotal 150 000 GNF, delivery fee 25 000 GNF →
collateral hold 75 000 GNF, driver commission 0. On trusted completion the
75 000 collateral is **released** and the 25 000 earning is **credited**
as two distinct ledger entries; available balance rises by 100 000 GNF but
net earning is 25 000 GNF. Released collateral is never labelled earnings.

Prior provisional defaults (repas/marche 100% collateral, 10% commission on
every mission type) were superseded by new effective-dated rows on
2026-08-05; historical rows were not rewritten and no mission holds had
been placed (runtime gate still OFF).

## Lifecycle
1. `finance_mission_requirement(type, value)` computes commission +
   collateral + minimum balance, server-side.
2. `driver_financial_eligibility(...)` gates offer visibility/acceptance.
3. On acceptance, `driver_mission_hold_place(...)` places at most one
   commission hold and one collateral hold, atomically, after re-checking
   available balance. A **policy snapshot** is stored on each hold.
4. On completion, `driver_mission_commission_capture(source, id, final_value)`
   recomputes commission from the *snapshot* and the authoritative final
   fare, captures at most the reserved amount and releases the excess.
5. Collateral is released on trusted completion or pre-custody cancellation.
6. Disputes call `driver_mission_hold_freeze` — funds stay frozen, never
   silently confiscated. Only `driver_collateral_resolve` (God/Finance
   Admin, documented reason, capped at the original hold) can capture.

Rate changes are never retroactive: an accepted mission keeps its snapshot.
