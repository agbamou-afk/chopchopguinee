# Node 4 — Marché R10: Discovery + Ranking Intelligence (in progress)

## Law
- Ranking optimises VALUE + RELIABILITY. Missing evidence is never treated as bad evidence:
  an unavailable component returns `score: null` + a reason and is excluded from the weighted mean.
- No paid boost, no sponsorship, ever (statically asserted on the evidence engine and discovery RPC).
- Server-authoritative: `marche_ranking_policies` (versioned, effective-dated), `_marche_rank_evidence`
  (STABLE, SECURITY DEFINER, search_path pinned), clients only read.
- Manual sorts (`recent`, `price_asc`, `price_desc`) remain exact overrides; `recommended` is ranked.
- Ranking never resurrects a non-orderable listing (R1/R1.5 truth stays sovereign).

## Signals
Price (R8 peer cohort, own observation excluded) · Reputation (R9 merchant_store only) ·
Reliability (R5 delivered vs merchant-rejected; buyer cancellations never counted) ·
Distance (haversine, honest "not road distance") · Freshness (exponential half-life).
`availability_accuracy` is declared NOT_COLLECTED, never synthesised.

## Admin + shopper surfaces
`marche_ranking_policy_admin_list`, `marche_ranking_policy_publish` (versioned, closes previous),
`marche_ranking_audit_listing` (ops/god only) · `marche_shopper_performance` (read-only, derived,
`affects_assignment: false`, self or admin only).

## Client
`src/lib/marche/ranking.ts`, `src/components/marche/RankReasonChips.tsx`,
`ListingCard` reason chips, `MarketView` "Recommandé" sort + optional coordinates.

## Evidence (this pass)
- `_qa_node4_marche_r10()` — 82/82 PASS (non-vacuous fixtures, full rollback, zero residue).
- `_qa_node4_marche_r5` 167/0 · `_qa_node4_marche_r9` 113/0 · `_qa_node4_marche_r8` 99 total / 1 fail.
- Typecheck clean.

## Open before R10 can be declared CERTIFIED / FROZEN
1. `_qa_node4_marche_r1` calls the pre-R10 6-argument `marche_listings_discover`; the harness must be
   updated to the canonical 8-argument signature (a back-compat overload was tried and reverted because
   it made the call ambiguous).
2. `_qa_node4_marche_r8` aborts with `permission denied for function _qa_s13_ok` (harness-side grant).
3. Full cross-node certification board + production build evidence not yet re-run this pass.
