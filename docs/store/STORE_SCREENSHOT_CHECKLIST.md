# CHOPCHOP — Store Screenshot Checklist

Capture from a clean **production** build (`isSandboxMode() === false`,
no `?sandbox=`/`?debug=`/`?field=` flags). Use realistic but
non-personal data.

## Required device frames

- iPhone 6.7" (1290×2796) — App Store mandatory
- iPhone 6.5" (1242×2688) — App Store fallback
- iPad 12.9" (2048×2732) — only if iPad listing
- Android phone (1080×1920 minimum, up to 1242×2688)
- Android 7" + 10" tablet — only if tablet listing
- Play feature graphic — 1024×500

## Required screens (in capture order)

1. **Onboarding — slide 1 "Bienvenue sur CHOPCHOP"**
2. **Client home (`/`)** — primary action grid, ChopWallet card
3. **Ride booking** — vehicle picker + ETA preview, fake but
   realistic Conakry address
4. **Chop Repas** — restaurant list with at least one real-looking
   restaurant
5. **Chop Marché** — category grid + one product card
6. **ChopWallet** — balance card (round number), recent activity
7. **Live tracking / trip in progress** — driver pin on map
8. **Support / Help** — issue type picker or chat list
9. **Driver dashboard** (if listing mentions driver mode) — earnings
   card + online toggle
10. **Profile** — clean profile hero, no orange Bug button

## QA checklist for every screenshot

- [ ] No orange Bug / debug button visible (DriverOfferDebugPanel)
- [ ] No sandbox / field-testing / demo panel visible
- [ ] No `?sandbox=1` / `?debug=1` / `?field=1` in the URL bar
- [ ] No real customer or driver phone number
- [ ] No real email address
- [ ] No real payment provider transaction ID
- [ ] No broken layout, no skeleton flash, no clipped text
- [ ] No "TODO" / placeholder copy
- [ ] No console errors visible in DevTools while recording
- [ ] French-only copy (no English fallback leaking through)
- [ ] Light theme unless dark theme is the brand-default screen

## Forbidden content

- Live wallet balances of real users
- Real driver license plates or photos
- Real merchant tax IDs
- Real support tickets containing PII
- Any image generated from sandbox seed data with debug overlays on

## File naming

`chopchop-<platform>-<device>-<order>-<screen>.png`

e.g. `chopchop-ios-6.7-01-onboarding.png`,
`chopchop-android-phone-04-repas.png`.