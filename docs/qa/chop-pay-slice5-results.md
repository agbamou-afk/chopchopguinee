# Chop Pay Slice 5 — Repas / Marché Chop Pay engine, QA results

Policy authority: `docs/product/chop-pay-canonical-operating-policy.md`.
Engine mechanics: `docs/architecture/chop-pay-ledger-and-settlement.md`.

## Status: GREEN — 152 / 152 assertions PASS

| Harness part | Scope | Result |
| --- | --- | --- |
| `_qa_s5_run` | Authorization, exit gate, merchant capture, settlement | 45 / 45 PASS |
| `_qa_s5_run2` | Cancellations, merchant rejection, disputes, custody | 42 / 42 PASS |
| `_qa_s5_run3` | Marché end-to-end, frozen economics, authorization matrix, privileges | 47 / 47 PASS |
| `_qa_s5_run4` | Ledger invariants, collateral freeze, residue checks | 18 / 18 PASS |

Every harness part runs inside a transaction that ends in a forced
`QA_S5_ROLLBACK`, so no test row, wallet movement, policy row or feature-flag
change survives. `Z0` asserts the master wallet returns to `-100 435 GNF`.

## Exit gate

150 000 GNF merchandise + 25 000 GNF delivery + 1 500 GNF platform fee:

- Customer hold at authorization: **176 500 GNF** (full order total, once)
- Driver collateral at claim: **75 000 GNF** (50% of merchandise only)
- Merchant capture on accept: **150 000 GNF**
- Driver earning on delivery: **25 000 GNF** (digital, no cash leg)
- Platform revenue: **1 500 GNF**, captured exactly once under replay

## DEF-FIN-S5-001 — closed

Driver collateral was re-derived from the *live* finance policy at claim time
instead of the Snapshot v2 economics frozen at authorization.

Fix:
1. `_chop_pay_customer_hold_internal` persists `collateral_gnf` at authorization.
2. New service-role primitive `_driver_exact_hold_place_internal` reserves that
   exact amount without consulting the live policy.
3. `_chop_pay_accept_internal` calls it with the persisted amount.
4. `_chop_pay_runtime_immutable` freezes `collateral_gnf` once set.

Regression cover: `N1`, `N1b`, `N2`, `N2b`, `N2c`, `N3`, `N3b` prove a later
policy (90% collateral, 5% fee, 40/50% cancellation) does not change an
already-authorized order, and `N4`/`N4b`/`N4c` prove an underfunded courier
cannot claim and leaves no partial hold or assignment behind.

## Privilege matrix

- `P1` all raw `_chop_pay_*` helpers: service_role only
- `P2` admin wrappers: not executable by anon
- `P3` participant RPCs: executable by authenticated
- `P4` Slice 1–4 money primitives: still closed to anon and authenticated
- `P5` QA harness: not reachable by app roles
- `P6` `_driver_exact_hold_place_internal`: service_role only

## Product surfaces wired

| Surface | File | Role |
| --- | --- | --- |
| Repas merchant order detail | `src/components/merchant/repas/RepasOrdersSection.tsx` | merchant |
| Marché merchant accepted offers | `src/components/merchant/MerchantCommandesView.tsx` | merchant |
| Customer deliveries (Repas + Marché) | `src/components/missions/CustomerMarketplaceDeliveries.tsx` | customer |
| Driver active mission | `src/components/driver/ActiveMissionCard.tsx` | driver |
| Finance dispute queue | `src/components/admin/ChopPayDisputeQueue.tsx` | finance / god admin |

Shared bindings: `src/lib/chopPay/chopPayOrders.ts`.
Shared panel: `src/components/chopPay/ChopPayOrderPanel.tsx`.

Courier collateral placement and settlement are deliberately *not* buttons: the
mission lifecycle (`mission_claim`, `mission_confirm_pickup`,
`mission_confirm_dropoff`) runs the engine in the same transaction.

## Build evidence

- `tsgo --noEmit -p tsconfig.app.json` — clean, no errors
- `vitest run` — 12 / 12 pass
- `bun run build` — built in 24.83s, PWA precache 130 entries / 11 879 KiB

## Flag posture (unchanged)

`Z3` asserts that of the canonical finance flags only `om_topup_enabled` is ON.
`chop_pay_enabled`, `chop_pay_checkout_enabled`, `chop_pay_p2p_enabled`,
`driver_balance_gate_enabled`, `driver_starter_credit_enabled`,
`cash_order_funding_enabled`, `driver_cashout_enabled`,
`merchant_om_settlement_enabled` and `om_direct_checkout_enabled` remain OFF.
The new surfaces render nothing until a Chop Pay runtime row exists, so they are
inert in production while the checkout flag is off.

## YELLOW register carried forward

- Master wallet sits at **-100 435 GNF** from earlier slices; treasury
  reconciliation is still owed before public launch.
- Visual QA remains signed-out only in this environment.
- PWA bundle warning (chunks > 500 kB) unchanged and accepted for web RC.
