---
name: Node 4 — Marché R10 Discovery + Ranking Intelligence (CERTIFIED / FROZEN)
description: Server-authoritative Marché ranking on value + reliability evidence, honest cold start, no paid boost; certified 2026-08-21
type: feature
---

# Node 4 — Marché R10: Discovery + Ranking Intelligence — CERTIFIED / FROZEN (2026-08-21)

## Governing law
- Ranking optimises VALUE + RELIABILITY only. Missing evidence is never bad evidence:
  an unavailable component returns `score: null` + a reason and is excluded from the weighted mean.
- **True cold start**: below `min_qualified_components` the listing scores `NULL`
  (`cold_start_reason = INSUFFICIENT_EVIDENCE`) — never a fabricated low score.
- No paid boost, no sponsorship, ever. `promotion_effect` is statically 0 and asserted
  on both the evidence engine and the discovery RPC.
- Server-authoritative: `marche_ranking_policies` (versioned, effective-dated, weights sum to 10000),
  `_marche_rank_evidence` (STABLE, SECURITY DEFINER, `search_path` pinned). Clients only read.
- Ranking never resurrects a non-orderable listing: availability is a hard R1/R3 gate.
- Manual sorts (`recent`, `price_asc`, `price_desc`) are exact overrides; only `recommended` ranks.

## Signals
Price (R8 peer cohort isolated by variant + canonical unit + zone, own observation excluded,
min 5 observations) · Price freshness (R8 observations only — listing age is NOT a ranking law) ·
Reputation (R9, merchant_store only) · Reliability (R5 merchant decisions only; buyer cancellations
never counted) · Responsiveness and Preparation (R3.5 observed durations) · Distance (haversine,
fully optional, honestly not road distance). `availability_accuracy` is declared `NOT_COLLECTED`.

## Reasons are server-authored
`_marche_rank_evidence` emits `why_ranked` (≤2 entries, `{code,label}`:
`GOOD_VALUE`, `WELL_RATED`, `FAST_PREPARATION`, `NEARBY`, `PRICE_RECENTLY_UPDATED`), suppressed
entirely on cold start. `src/lib/marche/ranking.ts#rankReasons` only passes them through — it applies
no threshold, no score reading and no invented label. Regression-locked by
`src/test/node4-marche-r10-ranking-client.test.ts`.

## Discovery arity (ambiguity closed)
One canonical 8-argument `marche_listings_discover` (search, category, store, sort, limit, offset,
lat, lng — coordinates non-defaulted) plus one unambiguous 6-argument compatibility delegate.
Both SECURITY DEFINER with pinned `search_path` (locked by N4.B5 / N4.B5a).

## Admin + shopper surfaces
`marche_ranking_policy_admin_list`, `marche_ranking_policy_publish` (versioned, closes the previous
policy), `marche_ranking_audit_listing` (ops/god only), `marche_ranking_policy_public` (weights and
cold-start doctrine are publicly disclosed, never secret), `marche_shopper_performance`
(hard `marche_shopper` eligibility gate, read-only, derived, `affects_assignment: false`,
self or admin only, unattributed cancellations reported honestly, R9 isolated).

## QA infrastructure fixes carried by this pass
- Role-probe helpers (`_qa_r6_err`, `_qa_node4_probe`, `_qa_s13_om_rolecall`, `_qa_s13_rls_probe`)
  restore the exact prior effective role instead of `RESET ROLE`.
- `N4.B5` expects 17 R1 primitives (two discovery arities) and `N4.B5a` proves both are hardened.
- `N4R35.C31` is scoped to milestone WRITERS (`provolatile = 'v'`); `C31b`/`C31c` prove the STABLE
  ranking helper only READS R5/R3.5 telemetry and creates no duplicate stream. R3.5 = 200.

## Final certification board (2026-08-21)
- `tsgo --noEmit -p tsconfig.app.json` → clean
- Vitest → **18 files / 138 tests, 0 failures**
- Production build → success; PWA `generateSW`, **134 precache entries (12,035 KiB)**
- `_qa_node4_marche_r10()` → **127 / 127**
- Marché R1–R10 → **1,633 assertions, 0 failures**
  (R1 56 · R1.5 38 · R2 82 · R3 136 · R3.5 200 · R4 79 · R5 167 · R6 157 · R6.5 249 · R7 107 ·
   R8 122 · R9 113 · R10 127)
- Nodes 0–3 → Node 0 34 · Node 1 156 · Node 2 97 · Node 3 1,208
- Slice 13 canonical finance runs 1–7 → **507 assertions, 0 failures**
- Whole board = **36 suites, 3,635 assertions, 0 failures**
- Non-drift after the full board: wallets balance 10,703,711 · held 104,758 · ledger postings 120 ·
  ledger sum 0 — unchanged
- Residue: price observations 0 · `QA %` listings 0 · no temporary QA capture tables
- No deployment, no activation, no feature-flag change

## Known harness note (not a defect)
Suites containing role probes must be run on the privileged SQL path (session user `postgres`).
Run through the `service_role` edge path, a probe cannot restore the prior role and later
assertions fail with `permission denied for function _qa_s13_ok`. This is a property of the
runner, not of R10 law.

**Status: R10 CERTIFIED / FROZEN. Edits frozen.**

## Micro-corrections 8–12 re-verification (2026-08-20)

Re-audited live HEAD against the five requested micro-corrections; all are already
implemented by the closeout pass and were re-proven, not re-asserted:

- (8) `_marche_rank_evidence` price cohort filters `variant_id + canonical_base_unit +
  zone_commune IS NOT DISTINCT FROM own_zone`, bounds by `price_lookback_hours`, requires
  `min_price_observations`, and refuses on `marche_price_confidence = insufficient` or
  `marche_price_freshness IN ('none','stale')` → `INSUFFICIENT_PRICE_EVIDENCE`.
  QA: D3 (zone contamination), D3b/D3c (stale/backdated), D4, D7, D9.
- (9) `marche_shopper_performance` reports
  `missions_cancelled_unattributed = {value, scored:false,
  reason:'NO_CANONICAL_CANCELLATION_ATTRIBUTION'}`; no failure-rate penalty is derived.
  QA: O5.
- (10) Hard gate `_marche_shopper_eligible(target)` → `SHOPPER_NOT_ELIGIBLE` before any
  representation. QA: O1, O2.
- (11) R9 shopper cohort only (`subject_kind='shopper'`), low-N (<3) → `available:false /
  INSUFFICIENT_REPUTATION_SAMPLE`, no rater/comment/transaction identifiers.
  QA: O7 (surfaced), O8 (delivery-driver isolation), O9 (no buyer/basket identity).
- (12) Defective first-pass assertions are gone: D7 now expects refusal, E1–E5 measure
  observed-price freshness (not listing age), I3 expects unknown-distance neutrality,
  J1–J6/L3/L4 encode true cold start, L4 asserts ordering not cancellation penalty.

Board re-run after last edit (privileged path):
- `_qa_node4_marche_r10` 127/127, 0 failed.
- Marché R1–R10 + Nodes 0–3 + Slice 13: 0 failures across all standard harnesses.
- Array-shaped harnesses re-counted explicitly: bonbonna_matrix 39/0, sweeper 15/0,
  repas_r8_channel 60/0, repas_r8_extra 53/0, marche_r5 167/0, marche_r9 113/0,
  marche_r9_backlink 18/0.
- Known legacy (pre-R10, not part of the certified board): `_qa_node3_repas_r7_ext`,
  `_qa_node3_repas_r7_readtruth`, `_qa_node3_repas_r7_semantics` raise
  `RESTAURANT_NOT_PUBLISHED` because their fixtures predate Repas R8
  `verification_state='verified'` publication law. Not a Marché regression; untouched.

R10 remains CERTIFIED / FROZEN.

## R10 QA fixture correction (2026-08-20)
- Fixed harness fixtures: all `client_request_id` values in `_qa_node4_marche_r10()` are now UUID-shaped (`gen_random_uuid()::text`); `request_fingerprint` labels unchanged.
- Re-ran from scratch on a privileged path: **R10 = 127 total / 0 failed** (no `HARNESS_R10_UNEXPECTED_ABORT`).
- Marché board re-run: R1 56, R1.5 38, R2 82, R3 136, R3.5 200, R4 79, R5 167, R6 157, R6.5 249, R7 107, R8 122, R9 113, R9-backlink 18, R10 127 — **1651 assertions, 0 failures**.
- Temporary QA result rows removed; no production schema or data changed.
