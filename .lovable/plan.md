# Moto Booking — "Aucun itinéraire trouvé" Audit (read-only)

## Verdict

The route did NOT fail. Routing returned a valid itinerary for the reported destination. The blank ETA/price and the "Aucun itinéraire trouvé. Vérifiez la destination." card come from a **fare-quote authorization failure that the UI misclassifies as a routing failure**.

Two independent defects, one cosmetic-but-serious config defect:

1. **Primary (client UX + auth gating)** — `ride_get_quote` is not executable by signed-out visitors, and `RideBooking` collapses every quote error into the same `unavailable` state as a route error, whose copy blames the destination.
2. **Secondary (provider config)** — the Google Routes API key is returning `PERMISSION_DENIED` on 100% of calls; every route in production is silently served by the public OSRM demo router.
3. **Not a bug** — the "New Broad Street, Purdys Grove" label is correct: the reproduction happened from a real GPS fix in Purdys, New York, not from a coordinate-order error.

## Evidence (all read-only, gathered this turn)

- `maps_request_log`, the exact reproduction attempts:
  - `01:56:09` route origin `40.99920, -73.65909` → dest `40.99843, -73.67429`, `status = ok`, `provider = osrm`, `user_id = NULL`
  - `02:32:35` route origin `40.99920, -73.65901` → dest `40.99890, -73.66676`, `status = ok`, `provider = osrm`, `user_id = NULL`
  - Both preceded by a successful `reverse` (nominatim) — the label resolved fine.
- Control probe, known-routable Conakry pair (`9.5370,-13.6785` → `9.6412,-13.5784`): HTTP 200, `distanceM 18149`, `durationS 934`, full polyline + steps, `provider: "osrm"`. Routing works for both arbitrary NY points and Conakry points.
- Anonymous RPC probe (both a NY pair and a Conakry pair):
  `POST /rest/v1/rpc/ride_get_quote` → `42501 permission denied for function ride_get_quote`.
- `fare_settings` has rows for `moto` (500 / 1000), `toktok`, `auto` — no missing-tariff cause.
- `ride_get_quote` itself also raises `NOT_AUTHENTICATED` when `auth.uid()` is NULL, so even with EXECUTE granted a signed-out quote is refused by design.
- Every `route` row logs `fallback_reason: PERMISSION_DENIED` (Google Routes), and `search` rows log `google_places_403`.

## Failure chain

```text
map tap -> reverse geocode (OK, nominatim) -> destCoords set
   |-> RoutingService.route -> maps-route -> Google PERMISSION_DENIED -> OSRM fallback -> 200 OK route
   |-> supabase.rpc('ride_get_quote') -> 42501 permission denied (anon)
             -> quoteError = "Tarif indisponible"
             -> previewState = "unavailable"      (quoteError checked BEFORE routeError)
             -> EtaPricePreview renders "Aucun itinéraire trouvé. Vérifiez la destination."
```

`RideBooking.tsx:384-391` ranks `quoteError` first and maps it onto the same `unavailable` state the route uses; `EtaPricePreview.tsx` has only one message for `unavailable`, and it names the destination as the suspect.

## Classification

| Question | Answer |
| --- | --- |
| Client, edge, provider, data, or UX? | UX/error-classification (primary) + auth gating (primary) + provider config (secondary) |
| Edge function at fault? | No — `maps-route` returned 200 with a valid route both times |
| Coordinate order wrong anywhere? | No — `{lat,lng}` client → `latLng` Google → `lng,lat` OSRM → `[1]=lat` decode all verified correct |
| Off-road / unroutable point? | No — OSRM snapped and routed the arbitrary NY clicks fine |
| Service-area constraint? | None enforced in routing or `ride_compute_quote_gnf` (pure haversine, no zone gate) |
| Did the public map/search/route change cause it? | Indirectly: making the map public exposed ride booking to signed-out users, where the quote RPC was always going to fail. `verify_jwt`, rate limits, and `userId` handling in `maps-route` are correct (anon → per-IP bucket, no 401) |
| All arbitrary destinations or only some? | **All** destinations, for **every signed-out session**, regardless of location. Signed-in sessions are unaffected |

## Affected files / functions

- `src/components/ride/RideBooking.tsx` — quote effect (179-213), `previewState` (384-391), route effect (338-375)
- `src/components/booking/EtaPricePreview.tsx` — single `unavailable` message
- `public.ride_get_quote` (EXECUTE grant + `NOT_AUTHENTICATED` guard)
- `supabase/functions/maps-route/index.ts` — Google `PERMISSION_DENIED` never surfaced to operators beyond the log row
- Google Cloud key `GOOGLE_MAPS_SERVER_KEY` — Routes API and Places API not enabled/authorized

## Surgical remediation plan (not executed)

**Step 1 — Stop lying about the cause (client only).**
Split `previewState` into distinct outcomes: `route-unavailable`, `fare-unavailable`, `auth-required`, `network`. Give `EtaPricePreview` one message per outcome:
- fare failure → "Tarif indisponible pour le moment." (no "vérifiez la destination")
- auth failure → "Connectez-vous pour voir le prix." with a sign-in action
- route failure → keep the current destination-focused copy
Keep the retry button wired to the failing domain only.

**Step 2 — Decide the signed-out ride policy explicitly.**
Either (a) gate the ride booking entry point behind sign-in when `moto`/`toktok` is opened by an anonymous visitor, or (b) allow an anonymous *estimate* by adding a sanitized, rate-limited quote path. Option (a) is the smaller and safer change and matches the existing "no anonymous commitment" law; option (b) requires a new SECURITY DEFINER preview RPC — it must not reuse `ride_get_quote`, and must not create any ride state. Owner decision required before implementation.

**Step 3 — Fix the routing provider config.**
Enable/authorize the Routes API (and Places API) for `GOOGLE_MAPS_SERVER_KEY`, or formally accept OSRM as the production router. Today every trip estimate is computed by a public demo server with no SLA, no traffic model, and no real `TWO_WHEELER` profile — that is a live production risk independent of this bug.

**Step 4 — Make provider degradation visible.**
Return the fallback reason in the `maps-route` payload (non-PII, e.g. `degraded: 'google_permission_denied'`) so the client can log it and ops can alert, instead of it only living in `maps_request_log`.

**Step 5 — Regression proof.**
Add tests asserting: a quote failure never renders route-failure copy; a route failure never renders fare copy; anonymous ride entry follows the Step 2 decision. Then run the full Vitest board, typecheck, build, and a linter census with zero delta.

## Non-goals

No Node 5 identity/auth architecture changes, no RLS loosening, no fare formula changes, no new provider integration, no changes to the Home directory map work just certified.
