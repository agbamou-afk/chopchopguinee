# Driver operating balance, commission and collateral

## Purpose
The driver **operating balance** (party_type `driver`) funds CHOPCHOP
commission and mission collateral. It is not personal earnings; earnings
remain separately visible and withdrawable under existing cashout policy.

## Policy source of truth — `public.finance_policies`
Per mission type (`ride`, `bonbonna`, `repas`, `marche`, `envoyer`):
commission bps, fixed commission, minimum driver balance, collateral mode
(`none|fixed|percentage`), collateral pct/min/max, whether collateral is
required before offer visibility, effective date, enabled state.

Rows are **append-only in practice**: `admin_set_finance_policy` inserts a
new effective-dated row rather than editing history. God Admin only,
audited into `audit_logs` with before/after.

### Launch defaults
| Mission | Commission | Collateral |
| --- | --- | --- |
| ride | 10% | none |
| bonbonna | 10% | none |
| repas | 10% | 100% of order value, cap 500 000 GNF |
| marche | 10% | 100% of merchandise value, cap 1 000 000 GNF |
| envoyer | 10% | 50% of declared value, cap 500 000 GNF |
| all | — | minimum available balance 5 000 GNF |

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
