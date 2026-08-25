# Map not rendering (signed-out AND signed-in)

## What is confirmed

- The new Mapbox public token you provided is valid: a direct call to the Mapbox style endpoint with it returns HTTP 200.
- `ChopMap` shows a fallback in three different situations, and all three look identical to the user when a caller passes `degradedFallback` (the Envoyer itinerary does):
  1. config error (`useMapConfig` failed),
  2. tile runtime error (bad/expired token, network),
  3. low-data mode (`useLowDataMode`) — the map is intentionally never rendered, even when everything works.
- `useMapConfig` refuses to call the backend at all when there is no session, so signed-out visitors always get the fallback.
- Once the config fetch fails, the failure is sticky for the page: it only retries on an auth state change, so a full reload is the only recovery.
- `MAPBOX_PUBLIC_TOKEN` exists in backend secrets, but the value in there is not necessarily the valid token above — the signed-in failure is consistent with a stale/invalid stored token, and that is the first thing to correct.

## Step 1 — Replace the stored token and re-test

- Store the provided public token as `MAPBOX_PUBLIC_TOKEN` (it is a publishable `pk.` token, safe for the browser) and redeploy `maps-config` so it serves the new value.
- Re-open the app signed in and confirm tiles render on home and in the Envoyer itinerary step.

If tiles now render signed in, the remaining work is Steps 2 and 3.

## Step 2 — Make failure modes distinguishable and recoverable

- Give `ChopMap` an explicit reason (`'config' | 'tiles' | 'low-data' | 'unauthenticated'`) and pass it to `degradedFallback`, so a stale token never again looks the same as "mode éco".
- Log the real reason to console/analytics instead of collapsing everything into one silent card.
- Add an in-place "Réessayer" that clears the cached failure and re-fetches config, instead of forcing a page reload.
- Stop low-data mode from silently blanking interactive pickers (Envoyer, ride pickup): show the map with reduced effects, or a fallback that clearly says "mode éco" with a one-tap "Afficher la carte".

## Step 3 — Signed-out visitors

- Let `maps-config` serve the public style + publishable token to anonymous callers (rate-limited), and drop the client-side `unauthenticated` short-circuit.
- Privacy layers (driver signals, nearby drivers) stay authenticated and unchanged.

## Step 4 — Certify

- Vitest suite green, `tsgo` clean, production build clean.
- Manual check: map renders on home and in the Envoyer itinerary step, both signed out and signed in.

## Non-goals

- No Node 5 identity/auth changes, no routing/pricing changes, no new map provider.
