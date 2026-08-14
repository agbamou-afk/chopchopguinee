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

---

## R7 FINAL TRUTH MICRO-CLOSEOUT (receipt semantics) — HEAD 0ee2b516

Verdict: **GO** — three receipt/tracking semantic defects closed, no economics touched.

### A. Ready label no longer claims custody
`src/lib/repas/tracking.ts`: delivery `ready` = **"Prête au restaurant"** (was
"Prête — remise au coursier", which claimed courier possession before the R6
restaurant→courier handoff). Courier possession / en route is now communicated only by
`out_for_delivery` ("Remise au coursier — en route vers vous"), i.e. after real R6 custody.

### B. Custody boundary labels keyed on the real R6 events
`REPAS_CUSTODY_BOUNDARY_LABEL` now maps the actual `repas_custody_events.boundary` values —
`restaurant_to_courier` → Remise au coursier, `courier_to_customer` → Remise au client,
`merchant_to_customer_pickup` → Retrait par le client — with the legacy credential-style keys
retained only as aliases so historical rows never render raw snake_case.

### C. Canonical receipt payment truth
`public.repas_order_receipt(uuid)` (still STABLE / SECURITY DEFINER / `search_path=public`,
anon revoked) now derives, read-only, from the same committed tender runtime tracking uses:
- `payment_rail` (`chop_pay` | `cash` | null), `engine_state`, `payment_state`, `payment_settled`
- chop_pay: completed→`paid`, cancelled/merchant_rejected→`released`, disputed→`disputed`,
  dispute_resolved→`dispute_resolved`, otherwise→`authorized`
- cash: completed→`collected`, cancelled/merchant_rejected→`cancelled`, otherwise→`due`
- legacy `food_orders.payment_status` kept as `legacy_payment_status` (raw, never canonical)
  and **never mutated**; no settlement economics changed.
Client: `RepasReceiptSheet` shows `Statut du paiement` from canonical state and labels the total
dynamically — `Total payé` (settled Chop Pay) / `Total réglé` (settled cash) / `Total de la
commande` for authorized, due, released and cancelled. Frozen item/pricing math untouched.

### D. QA
- R7 harness extended with `public._qa_node3_repas_r7_semantics()` (wired into
  `_qa_node3_repas_r7_ext`, rollback-only, revoked from anon/authenticated):
  **R7 175/175** (was 155) — completed Chop Pay = canonical `paid` even with legacy `unpaid`,
  placed/authorized never paid, in-flight never paid, cancelled = `released` not paid,
  legacy column unmutated, receipt reads create no journal and move no wallet,
  real R6 boundaries preserved, no fabricated cash runtime.
- Vitest `src/test/repasReceiptSemantics.test.ts` (8 tests): ready/custody-boundary labels and
  total/payment-label semantics.

### E. Full frozen board (all green, after last edit)
R7 **175/175** · R6 171/171 · R5 static 71/71 · R5 runtime 91/91 · R4.5 64/64 · R1–R4 148/148 ·
Course 34/34 · Bonbonna full/base/matrix/sweeper 78/24/39/15 · Taxi 97/97 ·
Slice 13 **507/507** (18+32+54+98+115+87+103) via the established privileged
`public._qa_s13_results` path, no grant weakening ·
Vitest **46/46** (9 files) · `tsgo --noEmit -p tsconfig.app.json` exit 0 ·
`bun run build` PASS, PWA generateSW precache **134 entries** · `git status --short` clean.

### F. Posture
ledger posting sum 0 · imbalanced journals 0 · master wallet **-100435 / held 0** ·
feature flags unchanged · approved live `livraison` couriers **0** · zero R7 fixture residue.
