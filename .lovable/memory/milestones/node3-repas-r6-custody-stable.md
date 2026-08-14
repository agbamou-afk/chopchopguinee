---
name: Node 3 Repas R6 Custody — Stable
description: Locked 2026-08-14. Repas verified custody (salted verifier + Vault secret, holder-only code access, real private delivery proof) certified green with all predecessor Repas fixtures modernized to the R6 contract.
type: feature
---

# Node 3 Repas R6 — Verified Custody (LOCKED 2026-08-14)

Commit: `5cf0f7bda24903ad0d5fd1c97b785cedf29fbcd8`

## Frozen contract
- No plaintext handover code at rest anywhere: salted verifier + Vault secret; `code_plain` no longer exists.
- Codes are readable only through `repas_custody_code_view(order_id, kind)` by their designated holder.
- Livraison custody requires a real private `mission-proofs` object owned by the assigned courier, matching mission and phase.
- Canonical delivery order: courier `mission_claim` (collateral committed) → merchant `accept` → `prepare` → `ready`.
- Merchant legacy `handoff` is closed (`HANDOFF_OWNED_BY_COURIER_CUSTODY`); restaurant→courier custody goes through `repas_custody_confirm_handoff`.
- Courier→customer completion goes through `repas_custody_confirm_delivery`.
- Retrait completion goes through `repas_custody_confirm_pickup_collection` with the customer-held pickup code; missionless, no courier economics.
- Expiry, dispute, terminal invalidation and client privilege hardening as certified. Custody RPC internals closed to `anon`/`authenticated`.

## Certification board (all green after the last QA migration)
| Gate | Result |
| --- | --- |
| R6 dedicated custody | 171/171 |
| R5 static | 71/71 |
| R5 runtime | 91/91 |
| R4.5 Retrait/pickup | 64/64 |
| R1–R4 | 148/148 |
| Node 0 Course | 34/34 |
| Node 1 Bonbonna full / base / matrix / sweeper | 78/78, 24/24, 39/39, 15/15 |
| Node 2 Taxi Privé | 97/97 |
| Finance Slice 13 parts 1–7 | 507/507 |
| Vitest | 34/34 (7 files) |
| tsgo --noEmit | clean |
| Production build + PWA | pass, 30.10s, 134 precache entries |

R1–R4 and Retrait read 148 and 64 rather than the older 147 and 63: the R6 migration added exactly one guard assertion to each (merchant handoff closed; direct Slice 5 pickup completion closed). No assertion was deleted or weakened.

## Posture
Ledger posting sum 0; imbalanced journals 0; zero Repas/R6 QA residue (restaurants, custody rows/events, QA users, QA proof objects, QA result rows all 0); feature flags byte-identical with every finance rail OFF (`chop_pay_*`, `cash_order_funding_enabled`, `om_*`, `driver_cashout_enabled`, `merchant_om_settlement_enabled`, `taxi`); master wallet baseline -100435 GNF / held 0; clean git status.

## Supply reality
Approved live `livraison` couriers: **0**. R6 is engineering-complete and certified; live Repas delivery still has no real courier supply.
