# Slice 6 — Envoyer declared value & claims engine — QA results

Method: self-rolling-back harness (`_qa_s6_run1` / `_qa_s6_run2`), production-shaped
(non-sandbox) fixtures, real schema, every fixture rolled back. Only the report row
persists. Master wallet naturally restored each run.

## Part 1 — creation gate, economics, ceiling governance — 29/29 PASS(DB)
A1–A8 declared 500 000 -> collateral 375 000, claims exposure 125 000, platform fee
1 000 (1 % of the delivery fee, never of declared value), commission 0, cash due
101 000, attestation frozen/timestamped/attributable, mission dispatched, **no hold
before a courier accepts**.
B1–B6 500 001 denied atomically (`DECLARED_VALUE_ABOVE_CEILING`); no shipment, no
runtime, no hold, no journal residue; 500 000 allowed (ceiling inclusive).
C1–C2 missing private photos denied (`SHIPMENT_PHOTOS_REQUIRED`), nothing persisted.
D1–D4 false/missing attestation denied, no implicit tender, declared value must be
positive.
K1–K5 God-Admin effective-dated ceiling change is applied and audited; the already
authorised shipment keeps its frozen economics and snapshot ceiling; a new shipment
above the new ceiling is refused.

## Part 2 — cash lifecycle + ledger invariants — 26/26 PASS(DB)
E1–E6 under-funded courier cannot take custody (no hold, no assignment); capable
courier holds exactly 375 000 collateral (unrestricted) + 1 000 fee reserve; balance
untouched, held 376 000.
F1–F4 wrong pickup code refused and moves no money; correct code establishes custody;
both holds stay held through custody.
G1–G7 delivery captures the platform fee exactly once (master +1 000), courier ends at
4 999 000 with nothing held, collateral released in full and never captured, **no
digital delivery-fee earning on a cash shipment**, runtime completed with cash due
101 000.
H1–H3 replayed delivery is inert, creates no second capture and no extra hold; a
settled mission cannot be re-claimed.
N1–N3 every Envoyer journal balanced with >= 2 postings, no hold over-captures or
over-releases, every journal traceable to its shipment.

## Part 3 — Chop Pay tender lifecycle — PASS(DB)
Full-order customer hold, 1 % fee on the delivery fee only, digital courier earning,
balanced journals.

## Part 4 — Claims lifecycle — PASS(DB)
Custody boundary, settlement freeze on claim, God-Admin upheld split (collateral first,
then platform exposure), exonerated release, reconciliation_required with no money moved.
DEF-FIN-S6-001 (customer hold wrongly matched by the driver release routine) closed.

## Part 5 — Privilege matrix & posture — PASS(DB)
Internals `service_role`-only, participant wrappers `authenticated`-only
(DEF-FIN-S6-002 closed), runtime/evidence tables read-only to clients, private
`package-evidence` bucket with participant + ops read policies.

**Total: 121/121 assertions PASS.**

## Product surfaces (Slice 6, behind `envoyer_declared_value_enabled` / `envoyer_claims_enabled`)
- Customer creation: declared value with policy-read ceiling, honour attestation,
  mandatory private photo evidence, explicit cash / Chop Pay tender choice.
- Customer tracking: claim state and "Ouvrir une réclamation" (custody required).
- Courier hand-off: frozen declared value, blocked collateral, tender, cash to collect,
  custody warning.
- Admin: God-Admin claims queue in Support (`/admin/support`).

## Not yet executed (OPEN)
- Authenticated visual QA of the Slice 6 surfaces (preview signed out).

## YELLOW (carried forward, not closed)
Slice 2/3/4/5 authenticated visual QA; DEF-FIN-001 master wallet -100 435 GNF;
PWA large-chunk warning; Slice 6 authenticated visual QA (preview signed out).
