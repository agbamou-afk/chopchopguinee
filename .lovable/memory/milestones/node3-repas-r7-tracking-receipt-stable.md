# Milestone — node3-repas-r7-tracking-receipt-stable

Verdict: **GO (engineering closed)** — Repas tracking + itemized receipt truth certified.
HEAD at certification: 48b302f1ede35b61b56ff0c3304e68e34a4261ab (plus this milestone + QA allowlist edit).

## Scope landed
- Server read models (SECURITY DEFINER, `search_path=public`, anon EXECUTE revoked):
  `repas_order_tracking(uuid)`, `repas_order_receipt(uuid)`, `mission_earnings(uuid[])`.
- Privacy hardening: table-wide SELECT on `public.missions` / `public.food_orders` revoked from
  `authenticated`/`anon` and replaced with explicit column-level grants. Courier payout,
  estimated earning, pricing snapshot / policy / promotion ids are no longer client-readable;
  entitled parties read them only through the authorized RPCs.
- Client: `src/lib/missions/columns.ts`, `src/lib/repas/tracking.ts`, safe projections across
  missions/repas/merchant libs, `RepasOrderTrackingPanel.tsx`, `RepasReceiptSheet.tsx`,
  merchant actions driven by server `allowed_actions`.

## Certification board (all green)
- Node 3 R7 tracking/receipt: 89/89
- Node 3 R6 custody: 171/171 · R5 runtime: 91/91 · R5 static: 71/71 · R4.5 pickup: 64/64 · R1–R4: 148/148
- Node 0 Course: 34/34 · Node 1 Bonbonna: 78/78 · Node 2 Taxi: 97/97
- Slice 13 finance regression: 507/507 (18+32+54+98+115+87+103)
- Vitest: 34/34 (7 files) · Typecheck: exit 0 · Build: PASS, PWA precache 134 entries

## Frozen constraints respected
No feature-flag changes, no pricing/economics changes, no custody behavior changes,
no parallel settlement engine. Evidence rows stored in `public._qa_s13_results` (parts 900–917).
