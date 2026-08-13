# Milestone: node0-course-closeout-stable

Date: 2026-08-13 (UTC)
Scope: Node 0 — Course (Moto) P1 remediation only. Node 1 (Bonbonna) not started,
not audited, not scored.

## What is locked
- `public.ride_request_create(...)`: the single authoritative Course request RPC.
  No client fare parameter, no client hold parameter. Server quote + frozen
  finance snapshot + reservation + ride insert in one atomic transaction.
- Reservation buffer: named server-side constant `C_RESERVATION_BUFFER_BPS = 11000`
  (today's 1.10 behaviour preserved). No new finance-policy semantics (D3).
- Idempotency: `rides_client_request_id_uidx` on
  `(client_id, metadata->>'client_request_id')`.
- Legacy `public.ride_create(...)`: recomputes the fare, ignores `p_fare_gnf`,
  rejects unrelated holds, and is no longer executable by `authenticated` (D2).
- Explicit customer payment choice (Chop Pay / Espèces) persisted as
  `metadata.payment_mode`.
- Regression: `public._qa_node0_course()` — 34/34 PASS, self-rolling-back.

## Findings closed
CRS-G1 (client-supplied fare), CRS-G2 (client-computed hold), CRS-G3 (no payment
selector). Course (Moto) verdict moves from REFERENCE WITH GAPS to
REFERENCE / LAUNCH-READY for the request → assignment → completion path.

## Posture
No feature-flag or activation change (D1). Master wallet `-100435 GNF`, held 0,
unchanged. No RLS, ledger or money-primitive change. Slice 0–13 architecture
untouched.

Evidence: `docs/product/service-nodes/node0-course-closeout.md`.
