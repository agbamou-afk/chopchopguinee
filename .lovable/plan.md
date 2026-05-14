## Why no popups appear

The demo driver is stuck in `presence='on_trip'` because of a stale `in_progress` ride from an earlier session (`d7bf8111…`). Two consequences:

1. **No new offers are dispatched.** The auto-dispatcher (`public.ride_dispatch`) only looks for drivers with `dp.presence='online'`. With the demo driver pinned to `on_trip`, every ride the demo client books inserts a `rides` row with no matching `ride_offers` row — so the bottom sheet and the global banner have nothing to show.
2. **The active trip never reappears in the UI.** `DriverSessionContext.activeTrip` is local React state. After a refresh it resets to `null`, so the in-app navigation screen for the still-running ride doesn’t mount, and the driver has no way to complete or cancel it from the UI.

The fix is to (a) recover from this state automatically, (b) make the demo seed self-healing, and (c) give the demo panel an explicit reset switch.

## Changes

### 1. Database migration — self-healing demo + reset helper

- Update `public.demo_seed_ride_offer()` so it first:
  - Cancels any non-terminal `rides` rows assigned to the demo driver (`status` set to `cancelled`, reason `demo_reset`).
  - Expires any pending `ride_offers` for the demo driver.
  - Forces `driver_profiles.presence='online'` and a corresponding `driver_locations` row near the demo pickup zone (so the dispatcher can find them).
  - Then inserts the new pending offer (existing behaviour).
- Add `public.demo_reset_driver()` (SECURITY DEFINER, callable by demo accounts or admins) that performs only the cleanup above without seeding an offer.

### 2. `src/contexts/DriverSessionContext.tsx` — restore active ride on boot

- On profile load, if `profile.presence === 'on_trip'` and no local `activeTrip`, query `rides` for the latest non-terminal ride where `driver_id = user.id` and seed:
  - `activeRideId = ride.id`
  - `activeTrip` from the ride’s pickup/destination zones + fare (mirroring `offerToRequest`).
- This makes `DriverActiveTrip` mount again so the driver can complete/cancel the stuck trip instead of being stranded.
- Keep the auto-pop guard (`!activeTrip`) intact so popups don’t fight the recovered trip.

### 3. `src/components/devtools/DemoTestPanel.tsx` — visible reset action

- Add a button **“Réinitialiser le chauffeur démo”** above the existing test-offer button. Wires to the new `demo_reset_driver` RPC and toasts the result.
- Tweak the existing test-offer toast to mention that any stuck trip is auto-cleared, since the seed RPC now resets first.

## Out of scope

- Dispatcher logic itself (already correct: only `online` drivers should receive offers).
- Realtime/polling plumbing (already in place from the previous turn).
- Client-side booking flow.

## Acceptance

- Logging into the demo driver with a stuck `in_progress` ride immediately shows the in-app navigation screen for that ride (no more silent dead state).
- Tapping **Réinitialiser le chauffeur démo** clears the stuck ride and flips presence back to `online`.
- Tapping **Envoyer une demande test au chauffeur démo** always produces a popup in the Courses tab and a banner on Tableau/Profil, even if the driver was previously stuck.
- Demo client → demo driver booking flow produces a popup again because the demo driver can be picked by `ride_dispatch`.
