---
name: Node 4 Marché R14 — Adversarial Certification (LOCKED)
description: R14 remediation of the three HOLD findings and final certified/locked state of Node 4 Marché
type: feature
---

# NODE 4 · MARCHÉ — CERTIFIED / LOCKED / FROZEN (R14)

Remediation of the three R14 HOLD findings, applied on top of the certified R13 head.

## Finding 1 — excess table privilege (posture)
`TRUNCATE`, `TRIGGER` and `REFERENCES` revoked from `anon`, `authenticated` and `PUBLIC` on all
Marché-bearing tables. `anon` is now read-only across the whole Marché surface.
`authenticated` keeps only the direct Data API writes the client really performs:
- `merchant_stores` — INSERT/UPDATE (no DELETE)
- `listing_images` — INSERT/DELETE (no UPDATE)
- `listing_interests` — INSERT/UPDATE (no DELETE)
- `listing_reports` — INSERT only (append-only for users)
- `saved_listings` — INSERT/DELETE
- `listing_saves`, `listing_metrics`, `marketplace_offers`, `marketplace_listings`,
  `market_onboarding_*` — SELECT only
Everything else must pass a `SECURITY DEFINER` RPC. (`MAINTAIN` remains — it is a
vacuum/analyze privilege, not a data privilege.)

## Finding 2 — merchant price history gap (product defect, root cause fixed)
Root cause: `marche_listing_create` derives `asking_price_gnf` from `price_gnf`, but
`marche_listing_update` allowed the two to diverge. Since the effective merchant ask is
`COALESCE(asking_price_gnf, price_gnf)`, a merchant editing `price_gnf` alone never changed the
effective ask, so `marche_price_ingest_merchant_ask` always answered `ALREADY_OBSERVED`.
Fix: `marche_listing_update` now mirrors `asking_price_gnf := price_gnf` when the payload sets
`price_gnf` without an explicit `asking_price_gnf`. A real 11 000 → 13 000 → 11 000 sequence now
yields three ordered observations; re-saving the same price still yields none.

## Finding 3 — cockpit guard fail-open
`marche_merchant_orders_cockpit` guarded with `IF caller IS NULL AND NOT v_priv` (NULL-valued
predicate). Now `IF caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'` — explicit fail-closed.

## Certification
- `_qa_node4_marche_r14`: **109 / 109 PASS** (was 106/109)
- Full frozen board (44 harnesses): **4 509 assertions / 0 failed**
- Vitest 155/155, production build green

Verdict: **NODE 4 · MARCHÉ — CERTIFIED / LOCKED / FROZEN**. Do not reopen R1–R14 law without a new node.
