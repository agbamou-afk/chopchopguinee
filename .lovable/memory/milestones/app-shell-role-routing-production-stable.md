# App Shell + Role Routing — Production Hardening (locked 2026-06-21)

Status: LOCKED. Authoritative behavior for role-aware routing across
client, driver, merchant (Marché), restaurant (Repas), and admin.

## Hard exits (verified)

1. **Client stays client.** `?mode=client` writes
   `cc_app_mode_override` + `cc_driver_mode_choice="client"` and clears
   any stored merchant intent (`Index.tsx` module init). The merchant
   redirect effect short-circuits on `readModeQuery() === "client"` and
   on `effectiveMode === "client"`.
2. **Driver stays driver.** `cc_driver_mode_choice` is the per-session
   source of truth. Driver-designated accounts auto-enter driver mode
   only when no explicit choice exists. Switching OUT of driver mode
   fires `driver_set_status('offline')` so no offers leak.
3. **Marché merchant → Marché dashboard.** `MerchantHub` renders
   `MARCHE_TABS` whenever a `merchant_stores` row exists without a
   Repas-only shell flag.
4. **Repas merchant → Repas restaurant dashboard.** `isRepasOnly`
   resolves true when `restaurant` exists and either there is no store
   or the store is a Repas shell (`wants_food && !wants_marketplace`).
   Legacy `wants_food` signups get a one-shot backfill into
   `food_restaurants` via `createOrUpdateRestaurant`.
5. **Hybrid merchant can switch cleanly.** Mixed (store + restaurant,
   non-shell) accounts keep `MARCHE_TABS` and render Repas sections
   inline. `MerchantModeToggle` is always visible in the hub header
   banner (`forceVisible`).
6. **Admin → /admin.** `adminRedirectedRef` bounces admins from `/`
   to `/admin` on first landing; `?public=1` opts out.
7. **Active ride restores correctly.** Restore queries `rides` filtered
   by `ACTIVE_CLIENT_RIDE_STATUSES` within a 2h window, with orphan
   pending guard (>30 min unmatched is ignored). Per-session
   `dismissedRidesRef` prevents re-restore after explicit cancel.
8. **Completed/cancelled ride never reopens as active.** The
   `cc:open-active-ride` handler re-fetches server status and refuses
   to mount the live trip screen unless `isActiveClientRideStatus`
   is true — sends the user to Activité instead.
9. **Wallet hold failure → support issue.** If `ride_create` fails AND
   `wallet_release` also fails, `createSupportIssue` files a
   `payment_pending` high-severity ticket with hold + ride context.
   No client-side wallet mutation.
10. **No redirect loop.** Merchant redirect uses
    `merchantRedirectedRef` (one-shot), respects
    `effectiveMode === "client" | "driver"`, and honors the
    `?mode=client` override before any storage / intent lookup.

## Files of record

- `src/pages/Index.tsx` — mode override, merchant/admin/driver-apply
  redirects, ride restore + dismiss, hold-failure support issue.
- `src/components/merchant/MerchantHub.tsx` — Repas-vs-Marché tab
  selection, Repas shell backfill, always-visible mode toggle.
- `src/lib/merchantRouting.ts` — `resolveMerchantPostAuthRoute`,
  `persistMerchantAppMode`, intent storage helpers.
- `src/lib/rides/status.ts` — `ACTIVE_CLIENT_RIDE_STATUSES`,
  `isActiveClientRideStatus`.
- `src/hooks/useAppMode.ts`, `src/hooks/useMerchantIdentity.ts`,
  `src/hooks/useDriverProfile.ts` — async readiness signals consumed
  by `Index`.

## Do-not-regress invariants

- Never write `cc_app_mode_override` or `cc_driver_mode_choice` outside
  the helpers in `Index.tsx` / `ModeToggle`.
- Never bypass `isActiveClientRideStatus` when mounting
  `RealtimeTripScreen`.
- Never mutate wallet balances from the client on hold failure — only
  call `wallet_release` and, on failure, file a support issue.
- Never give a merchant the Marché dashboard when they are Repas-only,
  and never give a Repas-only signup the product catalog tabs.

## QA smoke

1. Client signup → land on `/`, stays on `/` after refresh.
2. Driver signup (pre-approval) → `/driver/apply`.
3. Marché signup → `/merchant/hub` with Marché tabs.
4. Repas signup → `/merchant/hub` with Repas tabs (Menu/Restaurant).
5. Hybrid (existing store + restaurant) → Marché tabs + Repas sections.
6. Admin → `/admin` on first hit; `/?public=1` lets them browse.
7. Active ride → refresh → restored. Cancel → never re-opens.
8. Force `ride_create` failure with hold present → toast + support
   issue created; no balance mutation.
9. Toggle merchant → client → merchant: no redirect loop.