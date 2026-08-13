# Milestone: node0-course-closeout-stable

Date: 2026-08-13 (UTC)
Scope: Node 0 — Course (Moto) P1 remediation only. Node 1 (Bonbonna) not started,
not audited, not scored.

## What is locked
- `public.ride_request_create(...)`: the single authoritative Course request RPC.
  No client fare parameter, no client hold parameter. Server quote + frozen
  finance snapshot + reservation + ride insert in one atomic transaction.
- Reservation buffer: single shared server helper
  `public.ride_reservation_amount_gnf(bigint)` = 11000 bps (today's 1.10
  behaviour preserved). Used by BOTH `ride_get_quote` (preview) and
  `ride_request_create` (commitment), so preview and charge cannot drift.
  No new finance-policy semantics (D3).
- Idempotency: `rides_client_request_id_uidx` on
  `(client_id, metadata->>'client_request_id')`.
- Legacy `public.ride_create(...)`: recomputes the fare, ignores `p_fare_gnf`,
  rejects unrelated holds, and is no longer executable by `authenticated` (D2).
- Explicit customer payment choice (Chop Pay / Espèces) persisted as
  `metadata.payment_mode`. Pre-commit preview shows the server fare and, for
  Chop Pay, the server `chop_pay_hold_gnf`. `ride_get_quote` is preview-only,
  fail-closed on a NULL caller, and denied to `anon`.
- Client retry idempotency: `src/lib/rides/bookingRequestId.ts` persists one
  valid v4 uuid per booking commitment attempt, reused across retries and reset
  only on success, sheet close, or a material intent change.
- Regression: `public._qa_node0_course()` — 34/34 PASS, self-rolling-back.

## Findings closed
CRS-G1 (client-supplied fare), CRS-G2 (client-computed hold), CRS-G3 (no payment
selector) are CLOSED.

Formal verdict: **HOLD — Gate 14 only.** Functionally READY WITH YELLOWS
(Slice 13 507/507 batch `node0-final-gate-20260813002450`, Node 0 QA 34/34, no
P0/P1 open), but the Standard v1 two-actor/two-device gate could not be executed
in this environment (`LOVABLE_BROWSER_AUTH_STATUS=signed_out`), so `REFERENCE` /
`LAUNCH-READY` is NOT claimed.

## Posture
No feature-flag or activation change (D1). Master wallet `-100435 GNF`, held 0,
unchanged. No RLS, ledger or money-primitive change. Slice 0–13 architecture
untouched.

Evidence: `docs/product/service-nodes/node0-course-closeout.md`.
