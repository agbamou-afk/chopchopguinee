---
name: Node 4 Marché R9 — Verified Reputation (stable)
description: Server-authoritative, immutable reputation for stores, delivery drivers and shoppers, derived only from completed Marché transactions
type: feature
---
- Model: `marche_reputation_events` (immutable, append-only) + `marche_reputation_dimensions`. Tables are REVOKE ALL / RLS-on with zero policies; all access via `SECURITY DEFINER` RPCs pinned to `search_path=public`.
- Transaction kinds: `merchant_order` (canonical completion = `fulfillment_state='delivered'`), `procurement` (canonical completion = mission `state='completed'`). Nothing earlier is rateable.
- Subject kinds: `merchant_store`, `delivery_driver`, `shopper`. Subject identity is resolved server-side by `_marche_reputation_resolve` from frozen transaction truth; a client-supplied subject id is refused with `CLIENT_SUBJECT_NOT_ALLOWED`, a client-supplied aggregate with `CLIENT_AGGREGATE_NOT_ALLOWED`.
- Authority: only the transaction's buyer may rate, once per (transaction, subject), never themselves. Replay returns `ALREADY_RATED`. Updates/deletes raise `REPUTATION_IMMUTABLE`.
- Public surface: `marche_reputation_summary` (anon-readable) exposes count, average and dimension averages only — no rater, transaction, mission or comment. `marche_reputation_submit` / `marche_reputation_eligibility` are authenticated-only.
- Isolation: the same person rated as delivery driver and as shopper keeps two separate cohorts. Legacy `ride_ratings` and `driver_profiles.rating` are never written by R9; no wallet/ledger/price effect.
- Client: `src/lib/marche/reputation.ts`, `RatingSheet.tsx`, `ReputationBadge.tsx`, buyer `MarcheMyOrdersView` (Marché header → Mes commandes), procurement rating in `ProcurementMissionTracker`, store aggregate in `StoreHeader`.
- Certification: `_qa_node4_marche_r9()` 95/95, self-rolling-back, zero residue. tsgo clean, vitest 132/132 (17 files) including `node4-marche-r9-reputation-client.test.tsx`. Frozen suites re-run green: node0 34, node1 78, node2 97, repas r1_r4 148 / r5 71 / r8 142 / r11 116, Marché R3.5 198, R5 167, s13 run1 18.
- Runner note: `_qa_node4_marche_r9` is definer + service_role-only and runs through `qa-node-harness` (allowlisted). Several older invoker harnesses (Marché R1/R1.5/R2/R3/R4/R6.5, s13 run4/run7, and the R7/R8 anon sub-probes) cannot execute through that edge path — they need the privileged SQL runner. Not an R9 regression.
- No deploy, no feature-flag change.