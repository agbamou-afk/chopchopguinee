---
name: Node 4 Marché R7 — Shopper-Driver Fulfillment (implemented)
description: Server-authoritative shopper-driver procurement lifecycle (claim -> market -> shopping -> verified purchase -> delivery -> settlement) reusing R6.5 authorization and Slice13 finance
type: feature
---
- States: unassigned, assigned, at_market, shopping, purchase_verified, delivering, completed, cancelled. No client-authoritative transition.
- Identity: existing DRIVER identity + `marche_shopper` capability (`_marche_shopper_eligible`); no new role/professional enum.
- Authority RPCs: `marche_shopper_claim/arrive_market/start_shopping/resolve_line/attach_evidence/submit_purchase/start_delivery/complete_delivery`, customer-only `marche_customer_decide_proposal`, sanitized read `marche_procurement_mission_get`.
- Law: any qty change or substitution requires an approved proposal (versioned, supersede + stale rejection); acquisition needs a real unit price; verification needs all lines resolved + >=1 receipt; spend above ceiling returns PROCUREMENT_AUTHORIZATION_REQUIRED and only the customer can raise it via R6.5 `marche_procurement_increase`.
- Money: no parallel rail — capture/release go through `_marche_procurement_settle_core` on the Slice13 hold primitives, at delivery completion only.
- Price intelligence: verified purchases write `marche_procurement_price_observations` with source_kind `shopper_receipt` (as-requested lines only).
- Evidence: private bucket `marche-procurement-evidence`, path scoped to the basket id.
- Client: `src/lib/marche/shopper.ts`, `src/components/driver/ShopperBasketsPanel.tsx`, `src/components/marche/ProcurementMissionTracker.tsx`.
- Certification: `_qa_node4_marche_r7()` 107/107, 0 failures, full fixture rollback (master wallet, flags, missions, all R7 tables residue-free); tsgo clean; vitest 111/111. Full cross-service frozen board NOT re-run in that pass.
