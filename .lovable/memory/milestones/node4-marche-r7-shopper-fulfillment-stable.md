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
- Full cross-service frozen board re-run (2026-08-17): Node0 34, Node1 78, Node2 97, Slice13 runs1-7 (18/32/54/98/115/87/103), Repas r1_r4 148, pickup 64, r5 71, r5_runtime 91, r6_custody 171, r7_tracking 203, r8_discovery 142, r9 68, r10 134, r11 116, Marché r1 55, r1.5 38, r2 82, r3 136, r3.5 198, r4 79, r5 167, r6 157, r6.5 248, r7 107 — 0 failures.
- Two defects found and fixed during that board: (1) R7 storage policies on `marche-procurement-evidence` referenced `marche_procurement_missions` directly, which broke unrelated authenticated storage reads (package evidence) with "permission denied"; now routed through SECURITY DEFINER `_marche_procurement_evidence_can_read/_can_write`. (2) R6.5 assertion A9 widened to allow R7 delivery lifecycle `*_at` timestamps (money-column intent preserved).
