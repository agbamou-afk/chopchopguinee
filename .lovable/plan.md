# Map not rendering (signed-out AND signed-in)

## What is confirmed

- `ChopMap` shows a fallback in three different situations, and all three look identical to the user when a caller passes `degradedFallback` (Envoyer does):
  1. config error (`useMapConfig` failed),
  2. tile runtime error (bad/expired Mapbox token, network),
  3. low-data mode (`useLowDataMode`) — the map is intentionally never rendered, even when everything works.
- `useMapConfig` refuses to even call the backend when there is no session, so signed-out visitors always get the fallback.
- Once the config fetch fails, the failure is effectively sticky for the page: retry only happens on an auth state change, and a page reload is the only user-facing recovery.
- `MAPBOX_PUBLIC_TOKEN` exists in backend secrets. Its validity is NOT verified — the current fallback hides whether Mapbox rejects it.
- The signed-in root cause is not yet proven. It is one of: invalid/restricted Mapbox token, `maps-config` returning an error for the signed-in session, or low-data mode auto-triggering.

## Step 1 — Prove the cause before changing behaviour

- Call `maps-config` with a real signed-in session and inspect the exact status/body and whether `mapboxToken` comes back non-empty.
- If a token is returned, validate it directly against Mapbox's style endpoint to see if Mapbox itself rejects it (401/403).
- Load the app signed in with the browser harness and read the console/network to see which of the three fallback paths fires.

Outcome of Step 1 decides Step 3.

## Step 2 — Make the failure modes distinguishable (regardless of cause)

- Give `ChopMap` an explicit `reason` (`'config' | 'tiles' | 'low-data' | 'unauthenticated'`) and pass it to `degradedFallback`.
- Log the real reason to console/analytics instead of collapsing everything into one silent card.
- Add an in-place "Réessayer" that re-fetches config instead of forcing a full page reload, and clear the module-level failure so the retry can succeed.
- Stop low-data mode from silently blanking interactive pickers (Envoyer, ride pickup): in low-data show the map but with a lighter style / reduced effects, or show a fallback that clearly says "mode éco" with a one-tap "Afficher la carte".

## Step 3 — Fix the actual cause

Depending on Step 1:
- Invalid or URL-restricted token → replace/repair `MAPBOX_PUBLIC_TOKEN` (and confirm the preview and published domains are allowed on the token).
- Backend error → fix `maps-config`.
- Signed-out gating → let `maps-config` serve the public style + publishable token to anonymous callers (rate-limited), and drop the client-side `unauthenticated` short-circuit. Privacy layers (driver signals, nearby drivers) stay authenticated.

## Step 4 — Certify

- Vitest suite green, `tsgo` clean, production build clean.
- Manual check: map renders on home and in the Envoyer itinerary step, both signed out and signed in.

## Non-goals

- No Node 5 identity/auth changes, no routing/pricing changes, no new map provider.
