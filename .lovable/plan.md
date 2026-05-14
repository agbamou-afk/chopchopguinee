## Goal

Make demo client and demo driver participate in the **same real ride** end-to-end, removing the parallel fake-driver simulation.

## Trigger conditions (demo detection)

- Signed-in email = `demo.client@chopchop.gn` (linked-mode client), OR
- URL contains `?demo=linked`
- Server-side: linking RPC also verifies the demo driver exists.

---

## 1. Database migration (new functions only — no schema changes)

**`get_demo_driver()`** — `SECURITY DEFINER`, returns `uuid` of the demo driver `auth.users` row whose email is `demo.driver@chopchop.gn`. Returns `NULL` if missing.

**`demo_link_ride(p_ride_id uuid)`** — `SECURITY DEFINER`:

1. Caller must be authenticated. Resolve caller email from `auth.users`.
2. Allow only when caller email = `demo.client@chopchop.gn` **or** the caller owns the ride and the ride row's `metadata->>'demo_linked' = 'true'` (set by client param).
3. Resolve `v_driver := get_demo_driver()`. If null, no-op return.
4. Expire any other `pending` ride_offers for that driver (keep queue clean).
5. Insert one `ride_offers` row: `ride_id = p_ride_id`, `driver_id = v_driver`, status `pending`, `expires_at = now() + 90s`, `pickup_zone='Demo pickup'`, `destination_zone='Demo destination'`, `estimated_fare_gnf` and `estimated_earning_gnf` derived from the ride (85% to driver).
6. Tag `rides.metadata` with `{linked_demo: true, linked_at: now}`.
7. Return the new offer id.

The existing `driver_offer_accept` RPC already sets `rides.driver_id` and moves `rides.status='in_progress'` — no changes needed there.

## 2. Client-side wiring (`src/pages/Index.tsx`)

After `ride_create` succeeds in the booking handler:
- Compute `isLinkedDemo` = (current user's email is demo client) OR `?demo=linked` in URL.
- If true: `await supabase.rpc('demo_link_ride', { p_ride_id: ride.id })`. Best-effort, log on failure.

Force the `RealtimeTripScreen` path for linked-demo clients (so the screen renders **real** ride state — no `Mamadou Camara`):
- Update the `activeTrip && …` condition to also enter v2 when `isLinkedDemo`.

## 3. Stop fake driver render in `LiveTracking.tsx`

For the legacy LiveTracking screen (used by non-demo bookings):
- When `rideId` is provided, subscribe once to that `rides` row. While `driver.driver_id` is null, render a "searching" state (use `DriverSearchOverlay` `phase="searching"`) instead of jumping to the random `DRIVERS[]` card.
- When DB returns a real `driver_id`, fetch that driver's profile and render the real card.
- Keep the random fallback only when no `rideId` is provided (defensive — should not happen in current flows).

## 4. Driver auto-offer guard (`DriverSessionContext.tsx`)

The existing `demoAutoOffer` effect already early-returns when `queue.length > 0`, so a real linked offer suppresses synthetic auto-offers. Add one more guard: skip auto-offer creation if the latest pending offer's ride row has `metadata->>'linked_demo' = 'true'` (so we never race a synthetic over a real linked one). Implemented as a quick check before the RPC fires.

## 5. Auth UX clean-up

- **Logout button**: add explicit `aria-label="Se déconnecter"` and a stable `data-testid="logout-button"` on the ProfileView logout `Button`, and ensure no nav FAB lives at the same coordinates that confuses natural-language clicks.
- **Demo account switch**: in the auth page's "Demo Client" / "Demo Chauffeur" handlers, before signing in, call `supabase.auth.signOut({ scope: 'local' })`, then `sessionStorage.removeItem('cc_driver_mode')` and `localStorage.removeItem('cc_realtime_trip')` so the next account starts clean.
- **Misleading "Connexion instable" toast**: in the booking screen, only render the unstable-network toast when the fare estimate **fails** to resolve before the user taps Réserver; suppress it once a fare is shown.

## 6. Acceptance verification

After the migration applies, in a single browser:
1. Demo client books → linked offer auto-created for demo driver.
2. Switch to demo driver (clean auth) → offer popup shows the **client's actual ride**.
3. Driver accepts → `rides.driver_id = demo driver`, status `in_progress`.
4. Client's RealtimeTripScreen reflects the real driver instantly (no Mamadou).
5. Pickup QR / "Je suis arrivé" / completion flow runs on the same `ride_id`.
6. After completion both sides see receipts.

## Files to touch

- **New migration** — `get_demo_driver`, `demo_link_ride`.
- `src/pages/Index.tsx` — call link RPC + force v2 trip screen for linked demo.
- `src/components/tracking/LiveTracking.tsx` — drive driver card from DB, drop random fake.
- `src/contexts/DriverSessionContext.tsx` — defensive linked-offer guard for auto-offer.
- `src/components/views/ProfileView.tsx` — accessible logout label.
- `src/pages/Auth.tsx` (or wherever the Demo Client / Demo Chauffeur buttons live) — clean session before demo sign-in.
- `src/components/ride/RideBooking.tsx` — gate the network-unstable toast.

## Out of scope

- No changes to ride lifecycle RPCs (`driver_offer_accept`, `ride_complete`, etc).
- No changes to the realtime channel setup (already in place).
- No new tables or RLS policies.

---

Approve to proceed and I'll ship the migration first, then wire the client code in a follow-up edit.
