---
name: Node 4 — Marché R8 Market Price Intelligence (CERTIFIED / FROZEN)
description: Server-authored observed-price intelligence from merchant asks + verified procurement, with honest client surface; certified 2026-08-20
type: feature
---

# Node 4 — Marché R8: Market Price Intelligence — CERTIFIED / FROZEN (2026-08-20)

## Scope
Turns canonical Marché history into auditable market-price intelligence from two
provenance-linked sources only: approved merchant **asking** prices
(`merchant_ask`) and **verified procurement** purchases from R7
(`verified_procurement`). No forecasts, no ETA, no money movement, no PII.

## Frozen server semantics
- Raw evidence: `marche_procurement_price_observations` (append-only, superseded
  via `marche_price_supersede_observation`, admin-only). Derived aggregates are
  never stored.
- Normalization: `_marche_price_normalize` + `_marche_price_record`. Callers pass
  the **raw sale-unit quantity**; canonical multiplication happens exactly once.
- Cohort key: `variant_id | canonical_base_unit | zone_commune(unknown)`.
- Freshness vocabulary (`marche_price_freshness`), exactly four values:
  `none` (no observation date) · `fresh` (≤72h) · `aging` (≤168h) · `stale`.
- Confidence vocabulary (`marche_price_confidence`):
  `insufficient` (<5 samples) · `low` (stale) · `medium` (<12 samples or aging) · `high`.
- **Merchant-ask effective-event identity (2026-08-20 closeout).** The *current
  effective ask* of a listing is the latest recorded `merchant_ask` observation
  for that listing. Ingestion is a no-op (`ALREADY_OBSERVED`) when the listing's
  ask equals that latest observed amount, so retries, lost responses, idle
  re-saves and same-price republication stay one logical event. Any other value
  — **including a return to a previously observed numeric price** — is a NEW
  immutable observation with its own `observed_at` (`clock_timestamp()`) and its
  own identity `listing:<uuid>:<monotonic event seq>`. The seq is derived from
  the highest existing seq for that listing and is never reused. The old
  `listing:<uuid>:<price>` identity was defective: `11 000 -> 13 000 -> 11 000`
  silently lost the third event.
- **Trigger discipline.** `trg_marche_price_merchant_ask` (fire-on-everything) is
  replaced by `trg_marche_price_merchant_ask_ins` (AFTER INSERT) and
  `trg_marche_price_merchant_ask_upd` (AFTER UPDATE ... WHEN) guarded on
  `asking_price_gnf`, `price_gnf`, `status`, `visibility`, `store_id`, `kind`,
  `staple_purchase_option_id`. Irrelevant listing edits observe nothing.
- Public read: `marche_price_observed_public(commodity_code, zone)` — sanitized,
  returns `zone` (`all` when unscoped), per-variant cohorts with p25/median/p75,
  sample count, source mix, freshness, confidence, movement.
- Below `min_samples` the server returns `insufficient_data: true` with
  `reason = INSUFFICIENT_OBSERVATIONS` and no median. No price is ever invented.

## Frozen client semantics
- `src/lib/marche/priceIntelligence.ts` mirrors the server vocabulary exactly
  (`none | fresh | aging | stale`). No client-invented freshness state
  (`recent` / `unknown` are forbidden); unknown server values degrade to the
  honest no-date label.
- `ObservedPriceBadge` renders median, p25–p75 band, sample count, confidence,
  zone context and freshness. Zone shows `Zone : <commune>` when specific,
  `Toutes zones` for the `all` sentinel, and nothing for `unknown`.
- Insufficient data renders an explicit honest refusal, never a number.
- Integrated read-only in `StaplesView` (R6 catalog). No ranking or discovery change.

## Double-normalization law (regression-locked)
`marche_shopper_submit_purchase` passes `COALESCE(actual_qty, requested_qty)`
(raw), never a pre-normalized quantity. For a 25 kg sack bought at 300,000 GNF:
`raw_quantity = 1`, `normalized_quantity = 25`, `canonical_base_unit = kg`,
`normalized_unit_price_gnf = 12,000`, exactly **one** observation
(harness N4R8.I1–I5).

## Harness composition
`_qa_node4_marche_r8()` is the entrypoint and returns the merged verdict of
`_qa_node4_marche_r8_core()` (101, sections A–I) and
`_qa_node4_marche_r8_j()` (21, section J = merchant-ask effective-event
identity). Total **122**. No prior assertion was removed or weakened.

## Final certification board (2026-08-20, provenance closeout)
- `tsgo --noEmit -p tsconfig.app.json` → clean
- Vitest → **16 files / 123 tests, 0 failures**
- Production build → success; PWA `generateSW`, **134 precache entries (12,024 KiB)**,
  `dist/sw.js` + `dist/workbox-5cb67add.js` + `dist/manifest.webmanifest` emitted
- `_qa_node4_marche_r8()` → **122 / 122** (core 101 + section J 21)
- Marché R1–R8 → **1,390 assertions, 0 failures**
  (R1 55 · R1.5 38 · R2 82 · R3 136 · R3.5 198 · R4 79 · R5 167 · R6 157 · R6.5 249 · R7 107 · R8 122)
- Node entrypoint board (Nodes 0–4) → **31 suites, 3,033 assertions, 0 failures**
  (Nodes 0–3 = 1,643)
- Slice 13 canonical finance runs 1–7 → **507 assertions, 0 failures**
  (run1 18 · run2 32 · run3 54 · run4 98 · run5 115 · run6 87 · run7 103)
- Whole board = **38 suites, 3,540 assertions, 0 failures**
- Non-drift after the full board: wallets balance 10,703,711 · held 104,758 ·
  ledger postings 120 · ledger sum 0 · feature-flag fingerprint
  `bbf3a7943697b978f555d32a7ec5feda` — unchanged
- R8 fixture residue: observations = **0**, `QA R8%` listings = **0**
- No temporary QA capture tables exist
- No deployment, no activation, no feature-flag change

## Known harness note (not a defect)
`_qa_node3_repas_r5_runtime_core`, `_qa_node3_repas_r7_ext`, `_r7_readtruth`,
`_r7_semantics` are internal sections invoked by their `_fxcore` fixture
wrappers; run standalone they abort with `RESTAURANT_NOT_PUBLISHED`. Their
coverage is counted inside the entrypoints `_qa_node3_repas_r5_runtime` (91/91)
and `_qa_node3_repas_r7_tracking_receipt` (203/203), both green.

## R6.5 A6/A7 narrowing (retained, law preserved)
R8 provenance columns live on the evidence stream, not the procurement
transaction rail. A6/A7 now scope the no-merchant-coupling law to the
transaction rail (requests, items, authorizations, missions, events,
resolutions, proposals, evidence), and **A6b** proves the coupling is
provenance-only by asserting `_marche_procurement_option_estimate` never reads
`marketplace_listings` or `merchant_stores`. R6.5 = 249/249.

**Status: R8 CERTIFIED / FROZEN. Edits frozen.**
