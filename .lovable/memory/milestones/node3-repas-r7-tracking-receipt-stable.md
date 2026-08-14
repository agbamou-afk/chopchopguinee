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

---

## R7 FINAL MICRO-CLOSEOUT (courier canonical truth + non-vacuous QA)
HEAD at certification: `24abc3c5d985645b9d8facd951d4bde0f8314db0`

### A. Courier reconnect / canonical truth
- `src/lib/repas/courierRefresh.ts` — single canonical refresh: `repas_order_tracking(orderId)`
  FIRST (server read model = truth), then the safe mission row via `MISSION_SAFE_COLS`, then
  entitled earning via `mission_earnings`. Returns `null` rather than inventing state.
- `ActiveMissionCard` no longer propagates the stale pre-confirmation mission after custody:
  `RepasCustodySheet.onConfirmed` now triggers the canonical refresh.
- Refresh also fires on realtime `food_orders`/`missions` updates (signal only), `window.online`,
  and document visibility returning to visible; guarded by a re-entrancy ref, listeners cleaned up.
- `custodyPhaseStillValid` closes the custody sheet when canonical state moved past the boundary
  (second-device completion cannot leave a sheet logically open).

### B/C. QA expansion
- `public._qa_node3_repas_r7_ext()` (invoked inside the R7 harness subtransaction, rolled back):
  courier role-shape + unrelated courier/customer refusal, full real R6 delivery lifecycle
  (claim → accept → prepare → ready → real handoff proof+code → out_for_delivery → real delivery
  proof+code → completed) with tracking matched to order/mission/custody truth at each boundary,
  frozen customer receipt truth (payout & private policy keys hidden, courier receipt has payout),
  strict read idempotency (credentials/events/journals/wallets/order/mission rows unchanged after
  3× reads per role), cancelled-order terminal-without-success, and promotion truth on a
  rollback-only promotion (base fee / discount / name / customer fee / platform fee / total all
  matched to the frozen row). Residue proof extended: custody credentials, custody events,
  proof objects, QA users, QA promotions, QA missions.
- `src/test/repasCourierRefresh.test.ts` — behavioural: canonical tracking before mission read,
  no private earning columns selected, earnings hydrated via RPC only, non-Repas missions skipped.

### D. Final certification board (all green)
- Node 3 R7 tracking/receipt (expanded): **155/155**
- R6 custody 171/171 · R5 runtime 91/91 · R5 static 71/71 · R4.5 pickup 64/64 · R1–R4 148/148
- Node 0 Course 34/34 · Node 1 Bonbonna 78/78 · Node 2 Taxi 97/97
- Slice 13 finance regression **507/507** (18+32+54+98+115+87+103); parts 4–7 via the privileged
  path into `public._qa_s13_results`, no grant weakening
- Vitest 38/38 (8 files) · `tsgo --noEmit -p tsconfig.app.json` exit 0
- `bun run build` PASS — PWA precache **134 entries** · `git status --short` clean

### Invariants
ledger posting sum 0 · imbalanced journals 0 · master wallet -100435 / held 0 · feature flags
unchanged · zero R7 fixture/proof/custody/promotion/user residue.

### Honest supply note
Approved live `livraison` couriers: **0**. Engineering is closed; live Repas delivery still
depends on courier supply.

**Verdict: GO — R7 micro-closeout complete.**
