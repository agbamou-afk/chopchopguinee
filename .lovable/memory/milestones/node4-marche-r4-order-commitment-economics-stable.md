---
name: Node 4 Marché R4 — Order Commitment + Economics (CERTIFIED STABLE / LOCKED)
description: Marché R4 freezes merchant economics on the canonical R3 order using shared finance_policies (100 bps, effective-dated); floor rounding, delivery separate, zero money movement at commitment
type: feature
---

# Node 4 — Marché R4: Order Commitment + Economics — CERTIFIED STABLE / LOCKED (2026-08-16)

Commit: `eec73034819e62a5580a2484da91404608f86789`. No deploy, no activation, no feature-flag change.

## Product law
- Marché is approved-merchant commerce. R4 extends the canonical R3 `marche_orders` / `marche_order_items`
  commitment spine. No second order model, no parallel money architecture.
- At commitment the server freezes: buyer, merchant/store, listing identities, quantities, merchandise price
  snapshots, merchandise subtotal, R3.5 basket profile linkage, destination snapshot, fulfillment mode
  (`unspecified` unless an authoritative dispatch decision exists), buyer-scoped idempotency identity, and the
  exact effective finance-policy snapshot.

## Slice 13 / finance reuse (no new money tables)
- `finance_policies` (+ `merchant_platform_fee_bps`), `finance_policy_at`, `finance_policy_predecessor`,
  `finance_policy_snapshot` (v2), `admin_set_finance_policy` (god-admin only), `audit_logs`.
- Untouched: wallets, wallet_transactions, ledger_journals/postings, payment_intents, merchant_payables,
  settlement requests. No `marche_finance_policies`.

## Fee policy
- Marché merchant platform fee = **100 bps (1%)**, seeded and effective-dated, admin-editable through the
  existing god-admin finance surface (`src/lib/admin/financePolicy.ts`, `ServicePolicyEditor.tsx`).
- Policy history is append-only/effective-dated; historical orders keep their frozen policy id/rate/effective_from.

## Rounding law
`merchant_fee_gnf = floor(merchandise_subtotal_gnf * bps / 10000)`, clamped to `[0, merchandise_subtotal_gnf]`.
`merchant_payable_gnf = merchandise_subtotal_gnf - merchant_fee_gnf` (never negative).
Examples: 175 000 → fee 1 750 / payable 173 250; 123 456 → fee 1 234 / payable 122 222.

## Delivery separation
Customer delivery economics are a separate axis: `delivery_charge_gnf` NULL and
`delivery_pricing_state = 'unresolved'` until a canonical Marché delivery policy exists. Never netted against
merchant payable, never folded into the merchant fee.

## Money movement
None at commitment. Zero drift on wallets, wallet_transactions, ledger journals/postings, payment_intents,
missions, merchant_payables, settlements.

## Visibility / security
- All economics server-derived; clients cannot author or mutate price, fee, payable, rate, policy or delivery.
- `marche_order_guard` raises `ECONOMICS_IMMUTABLE` on committed economics.
- Buyer payload omits merchant fee / payable / economics_snapshot; merchant and admin read them.
- `marche_orders`, `marche_order_items`, `finance_policies`, fulfillment tables: no anon/authenticated grants.
- `marche_merchant_fee_gnf` service_role-only; SECURITY DEFINER functions pin `search_path=public`;
  `has_role` remains unavailable to anon (R8 P15.5 intact).

## Versioned compatibility assertions
R3 (A25, B1g, B9f, B15, B15b, B15c) and R3.5 (C30, D22, N3) previously asserted "no finance in R3"; they now
assert coherent R4 economics and immutability. Suite totals unchanged (136, 198). Do not revert to NULL-money.

## Freshly rerun frozen board (2026-08-16, after final edit) — 0 failures
Course 34 · Bonbonna 78 · Taxi 97 · Repas R1–R4 148 · Pickup 64 · R5 static 71 · R5 runtime 91 · R6 171 ·
R7 203 · R8 discovery-truth 202 · R8 core 89 · R8 channel 60 · R8 discovery/extra 142 + 53 · R9 68 · R10 134 ·
R11 116 · Slice13 run1–7 = 18+32+54+98+115+87+103 = 507 · Marché R1 55 · R1.5 38 · R2 82 · R3 136 · R3.5 198 ·
R4 79. Aggregate 3017 assertions, 0 failures.
Vitest 99/99 · `tsgo --noEmit -p tsconfig.app.json` clean · production build + PWA (134 precache entries).

## Posture verified post-board
Active Marché fee exactly 100 bps, 0 future/QA residue policies · 0 committed Marché orders and 0 fixture
residue · quantity_reserved sum 0 (baseline) · listings 53 total / 48 storeless-quarantined / 5 orderable ·
0 non-ORDER_COMMITTED fulfillment events · feature flags unchanged (11 enabled).
