# Map not displaying — diagnosis and fix

## What is actually happening

The map is not broken — it is being skipped for signed-out visitors.

Verified in this session:
- The map component (`ChopMap`) asks `useMapConfig()` for the style + publishable token.
- `useMapConfig()` first checks for a logged-in session and **throws `unauthenticated` before making any request** when there is none.
- The `maps-config` backend function itself also returns `401` without a bearer token.
- The captured network log for the current preview session contains **no call to `maps-config` at all**, confirming the early bail.
- The map token (`MAPBOX_PUBLIC_TOKEN`) is present in backend secrets, so credentials are fine.

You are currently signed out (on `/auth`), so every map surface — home nearby-drivers map, Envoyer picker, ride maps — renders the fallback card instead of tiles.

## Proposed fix

Let signed-out visitors load the public map configuration, while keeping the token server-side-issued and quota-protected.

1. **Backend (`maps-config`)**: accept anonymous callers. Keep requiring the project's publishable API key (default for the functions gateway), and return only the already-public payload: style URL, default center/zoom, flags, provider, and the publishable Mapbox token. No change to what data is exposed — the same payload is already handed to any logged-in user.
2. **Frontend (`useMapConfig`)**: remove the "no session → throw" short-circuit and just call the function; keep the existing cache, the auth-state retry, and the error → fallback path.
3. **Rate limiting**: keep/confirm the existing per-caller throttling in the function so anonymous traffic cannot burn Mapbox quota; cache headers stay at 5 minutes.

## Non-goals

- No change to driver-location, routing, or any privacy-sensitive map layer (those stay authenticated).
- No change to Node 5 identity/auth, feature flags, or exposure logic.
- No new secrets, no provider swap, no map redesign.

## Verification

- Signed-out home renders real tiles; signed-in surfaces unchanged.
- `maps-config` returns 200 without a bearer token and still returns 200 with one.
- No server-only key (`GOOGLE_MAPS_SERVER_KEY`) appears in any client payload.
- Full test suite, typecheck, and production build stay green.

## Alternative

If you prefer the map to stay behind login, the fix is instead a UI one: replace the blank fallback with an explicit "Connectez-vous pour voir la carte" state so it is clear the map is gated rather than broken. Tell me which direction you want.
