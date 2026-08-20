---
name: Node 4 Marché R10 — Discovery + Ranking Intelligence (STABLE)
description: Certified/frozen R10 ranking law, shopper intelligence isolation, QA runner restoration, and exact post-final-edit evidence
type: feature
---

# Node 4 — Marché R10: Discovery + Ranking Intelligence — CERTIFIED / FROZEN

Supersedes and voids the earlier in-progress note `node4-marche-r10-discovery-ranking.md`
(and `node4-marche-r10-discovery-ranking-certified.md`), which encoded WRONG doctrine:
listing-age / freshness half-life in scoring and an 82-assertion R10 count. Neither is law.

## Corrected R10 ranking law (frozen)

- Price freshness comes ONLY from the latest canonical R8 merchant-ask observation, under the
  frozen R8 freshness law. Listing age is NOT a ranking signal; no freshness half-life exists.
- Price competitiveness is computed only within the same commodity variant, same base unit and
  same zone, from canonical comparable non-superseded sources, excluding the listing itself,
  and requires at least 5 qualified price observations (`min_price_observations >= 5`).
- True cold start: below `min_qualified_components`, `score` and `score_bps` are NULL and
  `cold_start` is true. Missing evidence is never treated as bad evidence.
- Merchant reliability counts delivered vs merchant-rejected only, within a bounded lookback.
  Buyer cancellations are excluded entirely.
- Responsiveness and preparation come from canonical R5 fulfillment observations with bounded
  lookback, minimum sample count and freshness against a qualified benchmark.
- Distance is optional and geodesic; `road_distance = false`.
- `availability_accuracy` is NOT_COLLECTED; orderability remains a hard gate.
- Promotion / paid boost effect is exactly 0.
- Ranking reasons are server-authored, maximum 2; the client renders them verbatim and computes
  no thresholds, labels or claims of its own.
- Manual sorts are exact and unmodified by ranking.
- Shopper intelligence is read-only (`affects_assignment = false`), eligible-shoppers-only via a
  hard gate, generic cancellations are ambiguous/unscored, and reputation is R9 `shopper` subject
  only with `delivery_driver_signal_effect = 0` and `reputation_subject_scope = 'shopper'` on every
  return branch. No change to R7 assignment.

## Exact DB certification evidence (final product state)

Marché: R10 127/127 · R9 113/113 · R8 122/122 · R7 107/107 · R6.5 249/249 · R6 157/157 ·
R5 167/167 · R4 79/79 · R3.5 200/200 (historical 198 stale: suite gained 2 assertions) ·
R3 136/136 · R2 82/82 · R1.5 38/38 · R1 56/56 (historical 55 stale: suite gained 1 assertion).

Node0 34/34 · Node1 base 24/24, sweeper 15/15, matrix 39/39, full 78/78 · Node2 97/97.

Repas: r1_r4 148/148 · pickup 64/64 · r5 71/71 · r5_runtime 91/91 · r6_custody 171/171 ·
r7_tracking_receipt 203/203 · R8 channel 60/60, core 89/89, discovery 142/142, extra 53/53,
discovery_truth 202/202 · r9 recovery 68/68 · r10 operations 134/134 · r11 hardening 116/116.

Slice13: run1..7 = 18 / 32 / 54 / 98 / 115 / 87 / 103 = 507/507.

Suites overlap; no grand aggregate total is claimed.

## Non-drift snapshot

reputation events 0 · reputation dimensions 0 · R8 observations 0 ·
wallet aggregate 10,703,711 · held 104,758 · ledger postings 120 · ledger sum 0 ·
feature flag fingerprint `bbf3a7943697b978f555d32a7ec5feda` · QA temp tables 0.

## Toolchain evidence (after final code edit, no edits after)

- Vitest: 18 files / 138 tests passed. Files: repas-r9-recovery, bookingRequestId,
  repas-r11-conakry, slice8-cancellation-truth, repasCourierRefresh,
  node4-marche-r10-ranking-client (6), repasReceiptSemantics, repas-r8-discovery-truth,
  node4-marche-r35-measurement, node4-marche-r3-order-truth, auth, repasCustody,
  node4-marche-r9-reputation-client, node4-marche-r8-price-client,
  node4-marche-r65-procurement-client, slice7-ui-truth, example, node2-taxi-labels.
- `bunx tsgo --noEmit -p tsconfig.app.json`: clean (exit 0).
- Production build: PASS (built in 22.00s). PWA v1.3.0 generateSW —
  `dist/sw.js`, `dist/workbox-5cb67add.js`, `dist/manifest.webmanifest`.
  Precache entries: **134** (12035.37 KiB).

## QA runner restoration

`supabase/functions/qa-node-harness/index.ts` restored byte-for-byte to R9-certified commit
`66a9df1ee61fd2ac1646e469184253859aba431c` (allowlist ends at `_qa_node4_marche_r7`);
git diff versus that commit is empty. Runtime redeployed from the restored source only.
Runtime evidence: `_qa_node4_marche_r8/_r9/_r10` → HTTP 400 `Harness not allowlisted`.
No credential rotated or exposed. No product deployment, no feature activation.

VERDICT: **R10 CERTIFIED / FROZEN**
