---
name: Service Node Standard v1 — Stable
description: Node 0 Course golden-reference audit + CHOPCHOP Service Node Standard v1 (8 lenses, evidence grades, exit gates, scorecard, node order)
type: feature
---

# Milestone: service-node-standard-v1-stable

Locked 2026-08-12. Documentation/audit only — no runtime, finance, RLS, flag or
migration change (head `26fe9a7e8658a14124526a39dbb48254fed45030`).

## Artefacts
- `docs/product/service-nodes/course-golden-reference-audit.md`
- `docs/product/service-nodes/chopchop-service-node-standard-v1.md`

## Course verdict
**REFERENCE WITH GAPS.** Course is the benchmark node: full two-actor lifecycle,
server-authoritative transitions, customer-held pickup secret, idempotent
accept/complete, snapshot-driven economics, cancellation debt engine, audit
provenance. Open P1 gaps: CRS-G1 client-supplied fare in `ride_create`,
CRS-G2 client-computed `fare*1.1` hold, CRS-G3 no customer payment-mode selector.
YELLOWs: no authenticated 390x844 visual pass, no live two-device Conakry run,
no native push.

## Standard v1
8 mandatory lenses (Discovery, Runtime, Supply, Finance, Recovery, Ops,
Environment, Engagement); evidence grades LIVE-PROVEN / REGRESSION-PROVEN /
CODE-VERIFIED / VISUAL-YELLOW / FIELD-YELLOW / GAP; verdicts REFERENCE /
LAUNCH-READY / READY WITH YELLOWS / HOLD / NOT SUFFICIENTLY BUILT; 14 hard exit
gates (4, 5, 11, 14 non-negotiable); universal state vocabulary vs
service-specific extensions; reusable scorecard filled for Course only.

## Frozen node order
Node 0 Course (done) -> Node 1 Bonbonna -> Node 2 Repas -> Node 3 Marché ->
Node 4 Envoyer -> Node 5 Cross-Service UX/Engagement -> Node 6 Release Blocker
Closure -> Node 7 Android RC. Node 1 not started.
