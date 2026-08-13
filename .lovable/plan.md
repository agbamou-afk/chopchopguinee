# Node 0 Closeout — Course (Moto) P1 Remediation Plan

Baseline: `2c769fa`. Plan only; nothing edited. Scope is Course/Moto request path. No Bonbonna, no flag activation, no finance-primitive refactor.

## What the audit found in live code

Verified this turn:

- `ride_create(p_mode, lat/lng…, p_fare_gnf, p_hold_tx_id, p_driver_id)` inserts `p_fare_gnf` and `p_hold_tx_id` verbatim. No fare recomputation, no hold validation, no ownership check on the hold, no idempotency key, no finance snapshot written. (**CRS-G1**)
- `src/pages/Index.tsx:852-872` computes `Math.ceil(trip.fare * 1.1)`, calls `wallet_hold` itself, then calls `ride_create`, then compensates with `wallet_release` on failure — a client-orchestrated two-step money path. (**CRS-G2**)
- `src/components/ride/RideBooking.tsx:143-148, 321, 595` reads `fare_settings` client-side and computes `base + perKm * (distanceKm ?? 5)`; that number is what is sent as the fare. Line 571 hardcodes `paymentMethod="wallet"`. (**CRS-G3**)
- Server-authoritative pricing **already exists and is unused**: `ride_get_quote` / `ride_compute_quote_gnf` derive fare from `fare_settings` + Haversine over the coordinates. This is the anchor for the fix — no new pricing engine needed.
- `ride_complete` and `ride_cancel` already branch on `public._ride_payment_mode(ride)`, which reads `metadata->>'payment_mode'` ∈ {`cash`,`chop_pay`} and falls back to `chop_pay` when `hold_tx_id IS NOT NULL`, else `cash`. Both branches are implemented: chop_pay → `wallet_capture` + commission transfer; cash → cancellation-debt engine on cancel. **Nothing writes `metadata.payment_mode` today**, so mode is inferred purely from hold presence.
- Both read `metadata->'finance_snapshot'` and fall back to `finance_policy_snapshot(...)` at completion/cancel time. Because `ride_create` never freezes a snapshot, Course economics are currently evaluated **at settlement time**, not at request time.
- Flags today: `chop_pay_checkout_enabled=false`, `chop_pay_enabled=false`, `om_ride_checkout_enabled=false`, `cancellation_policy_enabled=false`, `moto=true`, `toktok=true`, `wallet=true`. Ride wallet holds currently run regardless of the Chop Pay flags.

## Conflicts to surface before coding (decisions needed)

1. **Chop Pay flags are OFF, yet ride holds run today.** Either the ride path is legitimately outside staged gating, or it is an unnoticed gate leak. The closeout must pick one and say it in the UI: if we gate ride Chop Pay behind `chop_pay_checkout_enabled`, the current wallet-hold ride flow stops working until that flag is turned on (not permitted here) and Course becomes cash-only. Recommendation: **do not add a new gate in this closeout**; treat the existing ride hold as the already-live Chop Pay ride rail, and record the ambiguity as a follow-up so we do not silently change activation posture. Needs your confirmation.
2. **Cash rides today have no explicit fee/settlement leg on completion** (`ride_complete` else-branch); `cancellation_policy_enabled` is OFF so cash cancellation debt is likely inert. Offering "Espèces" is truthful (the runtime supports it) but the customer must not be told a cancellation fee applies while that flag is off.
3. `ride_complete` allows a `_finance_privileged` caller to override the fare; that stays.

## Design

### A. One atomic server-owned commitment RPC

New `public.ride_request_create(p_mode, p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng, p_payment_mode text, p_client_request_id uuid, p_pickup_label text, p_dest_label text)` — SECURITY DEFINER, `SET search_path=public`, EXECUTE to `authenticated` + `service_role` only.

Inside one transaction:
1. `auth.uid()` required (fail closed).
2. Validate `p_payment_mode ∈ ('cash','chop_pay')`; validate coordinates present and within a Guinea bounding box.
3. **Idempotency**: `SELECT ... FROM rides WHERE client_id=uid AND metadata->>'client_request_id' = p_client_request_id::text FOR UPDATE` → if found, return it unchanged (`status:'already_created'`). Backed by a partial unique index on `(client_id, (metadata->>'client_request_id'))`. Also reject if the client already has a `pending`/`in_progress` ride (returns `ACTIVE_RIDE_EXISTS`).
4. **Fare**: `v_fare := public.ride_compute_quote_gnf(p_mode, …)`. Client fare is never accepted — the parameter does not exist.
5. **Distance**: server-derived Haversine inside `ride_compute_quote_gnf`. Client route distance is *not* trusted and is not an input. (Road-distance uplift is out of scope; note in the audit that Haversine understates real road distance — pricing accuracy is a separate future item, not a P1.)
6. **Snapshot**: `finance_policy_snapshot(_ride_mission_type(mode), now(), p_payment_mode, v_fare, 0,0,0,false)` stored at `metadata.finance_snapshot`, plus `metadata.payment_mode`, `metadata.fare_source='server:ride_compute_quote_gnf'`, `metadata.client_request_id`, labels. Freezes economics at request time for both `ride_complete` and `ride_cancel` (both already prefer the snapshot).
7. **Hold (chop_pay only)**: hold amount derived server-side as `ceil(v_fare * hold_multiplier)`, multiplier read from the snapshot/`finance_policies` if present, else a constant defined in the migration (matching today's 1.10). Calls the existing `wallet_hold` under the caller's claims — no new money primitive. Insufficient balance → raise `INSUFFICIENT_FUNDS` and the whole transaction rolls back, so **no orphan hold and no client-side compensation is possible**.
8. **Cash**: no hold; `hold_tx_id` stays NULL; `metadata.payment_mode='cash'` makes `_ride_payment_mode` explicit rather than inferred.
9. Insert the ride, return the row + `{fare_gnf, hold_amount_gnf, payment_mode}`.

`ride_create` is **kept** for compatibility but hardened: recompute the fare server-side and ignore `p_fare_gnf` (or raise if it differs beyond rounding), and reject a `p_hold_tx_id` that is not a `held` transaction owned by the caller. Alternative: revoke `authenticated` EXECUTE on `ride_create` once no client calls it. Recommendation: harden **and** revoke `authenticated`, leaving `service_role` — decision point.

### B. CRS-G3 payment selection

`RideBooking` gains a two-option selector: **Chop Pay** (wallet-held) and **Espèces** (cash to driver). Both are genuinely supported by `_ride_payment_mode`, `ride_complete`, `ride_cancel`. Rules:
- Selection is UI intent only; the rail is whatever the server accepts. No new rail invented, no flag bypassed.
- If a mode is unavailable (e.g. Chop Pay when available balance < required hold), it renders **disabled with an explicit reason** — never a fake success.
- Copy is truthful: cash shows "Vous payez le chauffeur en espèces"; Chop Pay shows the exact server-quoted hold amount returned by the quote call.
- Orange Money is **not** offered here (`om_ride_checkout_enabled=false`).

### C. Client changes (surgical)

- `src/components/ride/RideBooking.tsx`: replace the local `base + perKm*km` estimate with a debounced `supabase.rpc('ride_get_quote', …)` call; render the server fare, show a skeleton while quoting, and disable "Réserver" until a quote exists. Add the payment selector; pass `paymentMode` up through `onBook`. Keep `fare_settings` read only as a non-binding pre-destination placeholder, clearly labelled "estimation".
- `src/pages/Index.tsx`: delete the `Math.ceil(trip.fare*1.1)` + `wallet_hold` + `wallet_release` compensation block; call `ride_request_create` once with a `crypto.randomUUID()` request id retained across retries. Toast the hold amount **returned by the server**. Keep the existing support-issue escalation only for genuine unknown failures.
- `src/components/booking/EtaPricePreview.tsx`: `paymentMethod` becomes `"chop_pay" | "cash"` with accurate labels.
- No client table writes, no client-side persisted financial arithmetic anywhere in the path.

### D. Migration shape (single migration)

1. `CREATE OR REPLACE FUNCTION public.ride_request_create(...)`
2. `REVOKE ALL ON FUNCTION public.ride_request_create(...) FROM PUBLIC, anon;` `GRANT EXECUTE TO authenticated, service_role;`
3. `CREATE OR REPLACE FUNCTION public.ride_create(...)` hardened (+ optional `REVOKE EXECUTE ... FROM authenticated`)
4. Partial unique index on `rides (client_id, (metadata->>'client_request_id')) WHERE metadata ? 'client_request_id'`
5. Extend `_qa_s13_run*` (or a new `_qa_node0_course()`) with the assertions below.

No new tables, no RLS changes, no grant widening, no flag writes, no historical data touched.

## Regression plan

New assertions, run as one batch:
1. Tampered fare: `ride_request_create` has no fare parameter; a direct `ride_create` call with an inflated `p_fare_gnf` persists the server-recomputed fare (or raises).
2. Tampered hold: `ride_create` with a foreign / non-`held` `p_hold_tx_id` raises; `ride_request_create` hold equals `ceil(server_fare * multiplier)` exactly.
3. Replay: same `client_request_id` twice → one `rides` row, one `wallet_transactions` hold, second call returns `already_created`.
4. Failure atomicity: chop_pay request with insufficient balance → 0 rides, 0 holds.
5. Cash mode → `hold_tx_id IS NULL`, `metadata.payment_mode='cash'`, `_ride_payment_mode='cash'`; completion and cancellation take the cash branch.
6. Chop Pay mode → `_ride_payment_mode='chop_pay'`; `ride_complete` captures against the frozen snapshot's commission bps, not a recomputed live policy.
7. Snapshot freeze: mutate `finance_policies` after request → `ride_complete` / `ride_cancel` still use the request-time snapshot.
8. Anon fail-closed on `ride_request_create`.
9. Full untouched sequential Slice 13 sweep Part 1→7 must still return **507/507 PASS**, master wallet unchanged at `-100 435 GNF`, ledger sum 0, flag posture unchanged.
Plus `tsgo` typecheck, vitest, and build.

## Visual QA (390×844)

Screenshot via Playwright: payment selector (both states + disabled-with-reason), quote loading vs ready, confirmation sheet showing server fare + server hold, active-trip screen, and the completed-ride receipt — verifying every displayed number matches the DB row (`fare_gnf`, hold `amount_gnf`, commission) with no client-side recomputation.

## Documentation

`docs/product/service-nodes/course-golden-reference-audit.md` and `.lovable/memory/milestones/service-node-standard-v1-stable.md` are updated **only after** code + regression pass: CRS-G1/G2/G3 flipped to CLOSED with evidence, Course regraded to REFERENCE / LAUNCH-READY, remaining non-P1 notes (Haversine vs road distance; the Chop Pay flag-posture ambiguity in Conflict 1) recorded as open YELLOW. Bonbonna stays NOT STARTED / NOT SCORED.

## Decisions I need from you

- **D1** — Conflict 1: leave ride Chop Pay ungated (recommended) or gate it behind `chop_pay_checkout_enabled` and accept Course becoming cash-only until you activate it?
- **D2** — After migrating the client, revoke `authenticated` EXECUTE on `ride_create` (recommended) or leave it hardened-but-callable?
- **D3** — Hold multiplier: keep the current 1.10, or source it from `finance_policies` if a field exists there?
