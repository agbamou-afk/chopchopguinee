# Pilot Driver Readiness — Mission Launch

**Status:** RED — CODE READY / NEEDS OPS.
Target: ≥10 approved drivers in the pilot polygon, ≥5 live-tested online before launch.

No fake drivers. No auto-approval. No forced online state. Every row must be a real
driver account that can log in and toggle online from a real device.

## Per-driver tracker

Use this table during onboarding. Each driver must reach **GREEN** before being counted
toward the pilot readiness target.

| # | Driver name | Phone (WhatsApp) | Vehicle type | Pilot zone | Onboarding complete | Approved by admin | Online toggle tested | Recent driver_location_signal | Payout/settlement understood | Support contact path |
| - | ----------- | ---------------- | ------------ | ---------- | ------------------- | ----------------- | -------------------- | ----------------------------- | ---------------------------- | -------------------- |
| 1 |             |                  |              |            | ☐                   | ☐                 | ☐                    | ☐                             | ☐                            | ☐                    |
| 2 |             |                  |              |            | ☐                   | ☐                 | ☐                    | ☐                             | ☐                            | ☐                    |
| 3 |             |                  |              |            | ☐                   | ☐                 | ☐                    | ☐                             | ☐                            | ☐                    |
| 4 |             |                  |              |            | ☐                   | ☐                 | ☐                    | ☐                             | ☐                            | ☐                    |
| 5 |             |                  |              |            | ☐                   | ☐                 | ☐                    | ☐                             | ☐                            | ☐                    |
| 6 |             |                  |              |            | ☐                   | ☐                 | ☐                    | ☐                             | ☐                            | ☐                    |
| 7 |             |                  |              |            | ☐                   | ☐                 | ☐                    | ☐                             | ☐                            | ☐                    |
| 8 |             |                  |              |            | ☐                   | ☐                 | ☐                    | ☐                             | ☐                            | ☐                    |
| 9 |             |                  |              |            | ☐                   | ☐                 | ☐                    | ☐                             | ☐                            | ☐                    |
| 10|             |                  |              |            | ☐                   | ☐                 | ☐                    | ☐                             | ☐                            | ☐                    |

## Where to verify in the admin app

- **Approved count + per-driver state:** Admin → Drivers (`DriversAdmin`). Existing
  approval flow is the only path to approve a driver — no shortcut, no auto-approve.
- **Online-ready / recent signal:** filter the same view for drivers with a recent
  `driver_location_signal`. Offline drivers must not be shown as available.
- **Pilot polygon assignment:** use the existing service-zone tooling in Admin → Maps.
- **Support contact path:** every pilot driver must have a working phone/WhatsApp the
  ops team can reach in <2 minutes during launch hours.

## Hard rules

- No fake driver records.
- No bulk-approve scripts.
- No client-side override of `is_online` or `is_available`.
- Offline drivers must not appear in client-side availability surfaces.
- A driver only counts toward the pilot target after a successful real login +
  real online toggle from their real device.

## Launch readiness gate

Launch is GREEN on this RED only when:

1. ≥10 rows in the tracker are fully GREEN
2. ≥5 of those have completed a live online test in the last 7 days
3. All 10 are reachable by phone/WhatsApp/operator contact at launch time