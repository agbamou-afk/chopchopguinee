---
name: Chauffeur / Courier Production Hardening — Stable
description: Audit-only lock of driver/courier surfaces (DriverHome, DriverSessionContext, MissionsPanel, ActiveMissionCard, DriverEarningsView) for mission launch — no code changes, behavior verified against current production contracts
type: feature
---

# Chauffeur / Courier Production Hardening — Stable

Locked: 2026-06-21. Audit-only pass — no code, RPC, RLS, wallet or earnings math changes.

## A. Driver / courier audit (files of record)
- `src/contexts/DriverSessionContext.tsx` — single source of truth for `isOnline`, offer queue, current popup, active ride restore, accept/decline, presence toggle.
- `src/components/views/DriverHome.tsx` — 3-state online button (Hors ligne / À l'écoute / En course), application-status gating, MissionsPanel + CapabilityPicker.
- `src/components/views/DriverOrdersView.tsx` — historical rides view.
- `src/components/views/DriverEarningsView.tsx` — week/today, cash debt, commission, unified ActivityTimeline.
- `src/components/driver/DriverRideAlertBanner.tsx` — single offer banner (suppressed when popup active).
- `src/components/driver/ActiveMissionCard.tsx` — mission lifecycle UI with degraded-map fallback, route chip, issue sheet, courier↔restaurant messaging.
- `src/components/driver/DriverActiveTrip.tsx` — ride active overlay (rendered once from DriverSessionProvider).
- `src/hooks/useIncomingOffers.ts` / `useDriverPresence.ts` / `useDriverLocationSignal.ts` / `useMissionAlerts.ts` — gated on `enabled: isOnline`.

## B. State model
- Driver state = `profile.status` (`pending|approved|rejected|suspended`) × `profile.presence` (`offline|online|on_trip`) × `activeRideId|activeTrip`.
- Mission state = `Mission.state` driven through `MISSION_PIPELINES` (assigned → heading_to_pickup → arrived_pickup → picked_up → heading_to_dropoff → arrived_dropoff → delivered, plus terminal cancel/failed). Marketplace deliveries gate through `MarketplaceTrustSheet` (photo + code) instead of the lightweight proof toggle.

## C. Offer flow — verified
- `useIncomingOffers` only subscribes when `isOnline` is true (offline drivers get no offers).
- `DriverRideAlertBanner` is suppressed while `current` popup is shown — no duplicate banner+popup.
- `accept()` clears `current` synchronously, then calls `driver_offer_accept` RPC; failure refetches queue, no fake success.
- `decline()` clears `current` and calls `driver_offer_decline`; declined offer is removed from queue via server state, not local replay.
- Active trip blocks auto-pop of the next offer (`!activeTrip` guard in the auto-pop effect).
- Expired offers fall out when the row leaves the realtime query; `current` is cleared by the "stillThere" effect.

## D. Online / offline reliability — verified
- `togglePresence` uses `driver_set_status` RPC (no client-side presence write).
- Cash-over-limit blocks going online with honest copy.
- Leaving driver mode: `app-shell-role-routing-production-stable` already wires `driver_set_status('offline')` on mode switch.
- Unapproved/suspended/rejected drivers see status gating card in `DriverHome` (no online toggle exposed).
- `useDriverPresence` and `useDriverLocationSignal` both gated by `enabled: isOnline` — no signals from offline drivers.
- Confirmed copy already in place: "Vous êtes en ligne." / "Vous êtes hors ligne." / "Demande en cours d'examen" / "Compte chauffeur suspendu".

## E. Active ride / mission lifecycle — verified
- Ride: `DriverActiveTrip` rendered once at provider level using `activeRideId`; survives refresh via `restoreActiveRide` effect (queries `rides` with status in pending/in_progress).
- Completed/cancelled rides cannot reopen (cross-locked in app-shell-role-routing milestone via re-fetch of server status in `cc:open-active-ride`).
- Mission: `ActiveMissionCard.handleNext` is guarded by `busy` flag — duplicate taps are safe; `confirmPickup` / `confirmDropoff` / `advanceMission` errors toast and do NOT fake success.
- Map failure renders `DegradedMapPanel` ("Carte indisponible — vous pouvez continuer la mission.") — action buttons remain usable.

## F. Repas / Marché courier context — verified
- Food missions render `OrderMessagingPanel` (restaurant ↔ courier) when `mission.ref_food_order_id` is present and mission is non-terminal.
- Both verticals show pickup/dropoff addresses, `RouteEstimateChip` (when both endpoints known), and pin actors via `MISSION_IDENTITY` (no exposure of full customer profile beyond what `payload_summary` carries).
- Marketplace deliveries use the dedicated trust handshake sheet, not the lightweight proof toggle.

## G. Location / map degraded — verified
- `useDriverLocationSignal` runs only when `enabled: isOnline` — offline clears signal cadence.
- Map failure paths (degradedFallback) keep mission card actionable; routing failure falls back to `StraightLineFallback`.
- External navigation handled via `openExternalNavigation` (no in-app heavy nav required).

## H. Earnings / settlement — verified
- `useDriverEarnings` provides today/week, completed counts, `cashCollectedWeek`, `commissionDueWeek`, `cashDebtGnf`, `debtLimitGnf`.
- `DriverEarningsView` honestly surfaces "Versement sous 24h" and a settle CTA (info toast — no client-side ledger mutation). No earnings math changed.
- `cashOverLimit` banner mirrors `DriverHome`'s — same threshold, same copy direction.

## I. Support entrypoints — verified
- `MissionIssueSheet` available on every non-terminal mission card.
- Ride-side issue path lives in `DriverActiveTrip`.
- Wallet-hold double-failure already creates a `payment_pending` support issue (locked in `app-shell-role-routing-production-stable`).
- Issues carry mission_id / ride_id / food_order_id refs via existing helpers — no private metadata exposed to public.

## J. Weak network / duplicate tap — verified
- `toggling`, `busy`, `setCurrent(null)` before RPC, and refetch-on-error guards prevent stuck states across DriverSessionContext + ActiveMissionCard + DriverActiveTrip.
- No infinite polling loops detected (`useIncomingOffers` is realtime + manual refetch, gated by `isOnline`).

## K. Security / RLS — verified (no changes)
- `driver_set_status`, `driver_offer_accept`, `driver_offer_decline`, `confirmPickup/Dropoff`, `advanceMission` are all SECURITY DEFINER RPCs scoped to `auth.uid()`.
- `driver_locations` / `driver_location_signals` write paths are RPC-only (locked in `chopmap-driver-location-signals-stable`).
- `ride_offers` / `missions` realtime filters scope to the assigned driver.
- No `service_role` key in the frontend.

## L. Mobile (390×844) — verified
- DriverHome 3-state button, chips grid, MissionsPanel, ActiveMissionCard all fit; bottom nav not occluded.
- Earnings view bar chart + 3-col stats fit within max-w-md.

## QA — A–N
| Test | Result |
| --- | --- |
| A. Approved driver online | PASS — `driver_set_status('online')`, signal hook activates |
| B. Driver offline | PASS — signal/presence hooks disable via `enabled: isOnline` |
| C. Unapproved/suspended try online | PASS — gated by status card, toggle not rendered |
| D. Single offer alert | PASS — banner suppressed while popup active |
| E. Accept ride | PASS — `setCurrent(null)` → RPC → DriverActiveTrip mounts via `activeRideId` |
| F. Decline ride | PASS — RPC + refetch; queue derives from server state |
| G. Food mission context | PASS — OrderMessagingPanel + RouteEstimateChip |
| H. Marketplace mission context | PASS — MarketplaceTrustSheet + identity pins |
| I. Map/location failure | PASS — DegradedMapPanel + StraightLineFallback, actions still usable |
| J. Duplicate tap | PASS — `busy` guard on handleNext, `toggling` on presence |
| K. Earnings view | PASS — today/week/cash/commission/debt + honest "Versement sous 24h" |
| L. Support issue | PASS — MissionIssueSheet w/ mission_id metadata |
| M. RLS | PASS — RPC-only mutations, scoped realtime |
| N. Build | Clean (audit-only, no code changes) |

## Files changed
- Created: `.lovable/memory/milestones/chauffeur-courier-production-readiness-stable.md`
- Updated: `.lovable/memory/index.md`

## Remaining blockers
None engineering-side. Operational dependencies (≥10 approved pilot drivers, SMTP DNS activation) tracked under `mission-launch-red-closure-stable`.

## Do-not-regress invariants
- `useIncomingOffers` / `useDriverPresence` / `useDriverLocationSignal` MUST stay gated by `isOnline`.
- `DriverRideAlertBanner` MUST NOT render when `current` popup is shown.
- Active ride overlay MUST mount from DriverSessionProvider (single instance) using `activeRideId` as source of truth.
- No client-side writes to `driver_profiles.presence`, `driver_locations`, `wallet_transactions`, `wallets`, or earnings tables.
- Mission lifecycle CTAs MUST remain guarded by `busy` and MUST NOT fake success on RPC error.
- Map / location failure MUST NOT block ride or mission completion.

## Lock
`chauffeur-courier-production-readiness-stable` — locked 2026-06-21.