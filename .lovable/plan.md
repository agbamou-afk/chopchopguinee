# Home Map — Diagnosis and Surgical Remediation Plan

Audit only; nothing was changed.

## Root causes (verified)

**1. Anonymous discovery query dies on the first request, so ALL pins disappear.**
`useVendorDiscovery` queries `food_restaurants` first, then `merchant_stores`, inside a single `try`. Live anon REST check returns:

```text
food_restaurants  -> 42501 "permission denied for function has_role"
merchant_stores   -> 200, 4 rows
```

The restaurant policy `Published restaurants are publicly readable` is granted to role `public` and its `USING` clause calls `has_role(auth.uid(), 'admin')`. `EXECUTE` on `has_role` was granted to `anon` in an older migration but is no longer in effect (revoked during the Marché R14 privilege tightening). The thrown error aborts the whole `try` block **before** the store loop runs, so signed-out visitors get zero pins even though stores are readable. This is the main "businesses vanished" cause, and it is unrelated to the Mapbox token change.

**2. There is no orderable geography to pin, for Repas.**
Read-only census:

| Source | Total | With coords | Active | Pinnable today |
|---|---|---|---|---|
| `food_restaurants` | 1 | 0 | 1 | **0** |
| `merchant_stores` | 6 | 5 | 5 | 4 |
| `map_places` | 1 | 1 | — | — |

Of the 4 pinnable stores, 2 (`Cona`, `American Classics Guinee`) carry coordinates at 40.99 / -73.65 — New York, not Conakry — so only 2 stores (`Chicha Store Chez Parisien`, `Kam's chop`) can ever appear near a Conakry viewport. No data loss occurred; no coordinates will be invented or duplicated by this plan.

**3. The home map is wired as a ride surface, not a directory.**
`UserHome.tsx` renders the map section only when `exposure.isExposed("moto")`, wraps the entire map in a `<button onClick={() => onActionClick("moto")}>`, labels it "Chauffeurs près de vous", and passes `interactive={false}` to `ChopMap`. `NearbyDriversMap` mounts `NearbyAvailableDrivers` first and `VendorDiscoveryLayer` second. Consequence: business pins are unreachable — every tap becomes ride intent, and the map cannot pan, zoom, or expand. This is existing wiring, not a regression from the Mapbox change.

**4. The Mapbox/public-routing change is clean.** `maps-config`, `maps-search`, `maps-route` now serve anonymous callers with public style/token and per-IP limits. No shared route helper injects ride semantics into the home map, and no DB mutation authority was broadened.

## Canonical sources and targets to reuse (no new subsystems)

- Repas geography: `food_restaurants` (`latitude`, `longitude`, `status='active'`, `verification_state='verified'`). Detail surface: `RepasRestaurantDetail`, opened as a sheet from `FoodView` — there is no standalone restaurant route.
- Marché geography: `merchant_stores` (`status='active'`, `onboarding_status='approved'`). Public target route already exists: `/marche/boutique/:slug` (`PublicStorefront`).
- Preferred verified coordinates: `resolveTrustedMerchantLocation` / `map_places` layer (used at order time today, not for discovery).
- Discovery hook: `useVendorDiscovery`; layer: `VendorDiscoveryLayer`; map shell: `ChopMap`.

## Remediation plan

**Step 1 — Restore anonymous discovery (root cause 1).**
Split `useVendorDiscovery` so each vertical has its own `try/catch`: a restaurant failure must never suppress store pins, and vice versa. Separately, fix the RLS asymmetry by rewriting the `food_restaurants` public SELECT policy the same way `merchant_stores` was split in Marché R1: an `anon` policy limited to `status='active' AND verification_state='verified'` (no `has_role` call), and an `authenticated` policy keeping owner/admin visibility. Do **not** grant `has_role` to `anon` — that would violate the Repas R8 P15.5 invariant.

**Step 2 — Make the home map a directory map by default.**
In `UserHome.tsx`: ungate the map section from the `moto` flag; expose it when `service_repas_enabled` OR `service_marche_enabled` is on. Replace the ride-CTA wrapper button with a non-ride "Commerces près de vous" header plus an explicit expand affordance. Ride overlay (`NearbyAvailableDrivers`) becomes opt-in via an explicit prop, rendered only in ride mode.

**Step 3 — Introduce a minimal map context, reusing existing components.**
Add a `mode: 'directory' | 'ride'` prop to `NearbyDriversMap` (rename to a neutral name if cheap). `directory` renders `VendorDiscoveryLayer` and no ride markers, and treats map taps as pin selection only. `ride` keeps today's behaviour. No new map subsystem, no second Mapbox wrapper.

**Step 4 — Expandable map + pin click-through.**
Add a fullscreen sheet that mounts the same `ChopMap` with `interactive`, `VendorDiscoveryLayer`, and pin popups. Pin tap targets: store -> `/marche/boutique/:slug`; restaurant -> Repas view with the restaurant pre-selected (reuse `FoodView`'s existing selection state; no parallel page). Anonymous users may browse and open both; commitment gates stay untouched.

**Step 5 — Exposure filtering.**
Pass `{ restaurants: repasExposed, stores: marcheExposed }` into `VendorDiscoveryLayer`. Ride flags must not hide business pins.

**Step 6 — Data hygiene (report, do not silently patch).**
Surface the two out-of-country store coordinates to admin (Map Places / Merchants admin) for correction by their owners. No coordinate is invented or copied.

## Tests to add after remediation

Anon store pins present when the restaurant query fails; anon restaurant read returns 200 post-policy split; directory mode renders no driver markers and no ride toggle; explicit ride mode still renders drivers; pin tap resolves to `/marche/boutique/:slug` and to Repas detail; exposure flags filter the correct vertical; ride flags do not suppress pins.

## Must remain untouched

Node 5 identity/auth architecture; Marché R1–R14 laws and `v_marche_listing_truth`; `has_role` grants; all order/commit RPCs and finance rails; `maps-config` / `maps-route` / `maps-search` behaviour; `src/integrations/supabase/*` generated files.
