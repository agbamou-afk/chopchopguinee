---
name: Node 4 Marché R11 — Merchant Operations + Settlement (certified)
description: Server-authoritative merchant operations cockpit, order-level finance audit, and settlement surface on canonical finance rails; certified on the 4,088-assertion complete frozen board
type: feature
---

# Node 4 — Marché R11: Merchant Operations + Settlement — CERTIFIED / LOCKED / FROZEN

## Certification authority

Certified by decisive independent complete-board run at HEAD:

```
a2034195a4c40c004949df4a7b4c9cefe8ed6c88
```

Working tree clean before and after certification. No product code, QA functions, assertions, migrations, schema, RLS, grants, auth, feature flags, timeout configuration, runner, or allowlists were modified during the certification or during this closeout.

## Complete frozen QA board

| Suite | Assertions | Failed | Notes |
| --- | --- | --- | --- |
| Node 0 | 34 | 0 | course |
| Node 1 full | 78 | 0 | component 24, sweeper 15, matrix 39 |
| Node 2 | 97 | 0 | taxi |
| Slice 13 | 507 | 0 | 18 / 32 / 54 / 98 / 115 / 87 / 103 |
| Repas | 1,612 | 0 | R1–R4 148, pickup 64, R5 71, R5 runtime 91, R6 custody 171, R7 tracking/receipt 203, R8 channel 60 / core 89 / discovery 142 / extra 53 / discovery truth 202, R9 recovery 68, R10 operations 134, R11 Conakry hardening 116 |
| Marché | 1,760 | 0 | R1 55, R1.5 38, R2 82, R3 136, R3.5 200, R4 79, R5 167, R6 157, R6.5 249, R7 107, R8 122, R9 113, R10 127, R11 128 |

**Machine-derived complete-board result:** 4,088 executed / 0 failed / 0 timeouts / 0 runner errors / 0 retries.

Note: canonical Marché R3.5 count is 200 (historical milestone reference to 198 is stale and recorded only as historical context). R1 count is 55 (historical 56 references are stale).

## Client / build gates

- `bunx tsgo --noEmit -p tsconfig.app.json`: exit 0, 0 errors.
- Vitest: 18 files, 138 tests, 138 passed, 0 failed.
- Production build: PASS, built in 23.72s.
- PWA: v1.3.0, generateSW, 134 precache entries, 12035.17 KiB, `dist/sw.js`, `dist/workbox-5cb67add.js`.

## Non-drift certification (pre → post)

- `profiles`: 1,534 → 1,534
- `auth.users`: 52 → 52
- `wallets`: 68 → 68
- `wallet_transactions`: 76 → 76
- `ledger_journals`: 60 → 60
- `ledger_postings`: 120 → 120
- ledger posting sum: 0 → 0
- `payment_intents`: 0 → 0
- `merchant_payables`: 0 → 0
- `merchant_settlement_requests`: 0 → 0
- `payout_orders`: 0 → 0
- `payout_settlement_allocations`: 0 → 0
- `payout_provider_evidence`: 0 → 0
- `marketplace_listings`: 53 → 53
- `merchant_stores`: 6 → 6
- `marketplace_offers`: 0 → 0
- `marche_orders`: 0 → 0
- `marche_fulfillment_transitions`: 0 → 0
- `marche_procurement_missions`: 0 → 0
- `missions`: 0 → 0
- R8 price observations: 0 → 0
- R9 reputation events: 0 → 0
- R9 reputation dimensions: 0 → 0
- QA listing residue: 0 → 0
- QA store residue: 0 → 0
- Feature flags: 41 total / 11 enabled → unchanged
- Feature flag fingerprint: `64b2a25e24b39114b21bbf21ae7920c1` → identical
- New QA orphan profiles: 0
- New QA auth identities: 0
- HEAD: unchanged during certification
- Git status: clean before and after

## Historic QA orphan baseline (deferred technical debt, not an R11 blocker)

The following pre-existing QA orphan residue was intentionally NOT remediated during R11 certification and is preserved as evidence:

- 1,450 orphan profiles matching `…@qa.invalid`
- 30 orphan profiles matching `demo.qa-*`
- 1,482 total orphan profiles reported by the baseline query

This is legacy QA technical debt, not a product defect, and is out of scope for the R11 freeze.

## QA-infra remediations that preceded final certification (provenance only)

These are certification-provenance changes, not product behavior changes:

1. **R8 authoritative-harness completeness** — Added the four existing frozen R8 QA functions to the `qa-node-harness` allowlist so the full R8 family became executable through the existing service-role path.
2. **QA identity cleanup correctness** — `_qa_users_purge(uuid[])` was corrected to safely match `profiles.id` OR `profiles.user_id`, while retaining the orphan-auth guard. R3.5 and R5 were converted from direct auth deletion to the canonical QA purge path. Leak attribution: 31 rows from shared identifier-key defect, 10 rows from R3.5/R5 direct cleanup bypass, 41 rows total. Focused proof showed all fourteen Marché suites individually self-cleaning.
3. **QA-only execution timeout** — Proven limiter: PostgREST/authenticator session `statement_timeout = 8s`. Database default remains 120s; `anon` remains 3s; `authenticated` remains 8s; `authenticator` remains 8s + `lock_timeout` 8s; `service_role` has no role override. All 81 `public._qa_*` functions now carry bounded function-local `statement_timeout = 60s`. Non-QA functions with this override: 0. No global/product timeout was relaxed. Final certification proved the posture with no timeout.

## R11 product scope (frozen)

- Server-authoritative merchant operations read model (`marche_merchant_order_ops`, `marche_merchant_orders_cockpit`).
- Order-level finance audit (`marche_finance_order_audit`) with exact identity bridge between `marche_orders` and payables.
- Settlement request surface on canonical wallet rails, with fail-closed validation and honest receipt availability.
- Client presentation in `MerchantCommandesView.tsx` and related merchant operations surfaces; no client-authoritative mutation.
- No new payment rail, no fee change, no flag activation, no deployment.

## Final verdict

**NODE 4 · MARCHÉ R11 — CERTIFIED / LOCKED / FROZEN**
