# CHOPCHOP Ads Pipeline (Inactive)

Status: **DESIGN ONLY — NOT ACTIVE**. No ads are served and no third-party
ad SDKs are integrated. This document defines the future first-party,
privacy-respecting advertising surface for CHOPCHOP.

## Principles

1. **First-party only.** Ads are sold and served by CHOPCHOP GUINEE LTD —
   no Google Ads, Meta Audience Network, AppLovin, IronSource, or any
   third-party ad SDK.
2. **No cross-app tracking.** We do not request Apple App Tracking
   Transparency and do not access the iOS IDFA or Android Advertising ID.
3. **No personal targeting at launch.** Initial ads target by *placement*
   and *zone* only (e.g. "Repas — Kaloum"), not by individual user profile.
4. **Clearly labeled.** Every sponsored surface is marked *Sponsorisé* in
   French.
5. **User control.** Users can disable promotional content via the
   Permission Center (`allow_marketing_notifications`,
   `allow_personalized_offers`).

## Future Surfaces (Not Built)

- Home screen promoted merchant cards (Repas, Marché)
- Search results sponsored listings (Marché)
- Wallet promo banners (CHOPCHOP-operated campaigns only)

## Required Before Going Live

- Dedicated `ad_placements`, `ad_campaigns`, `ad_impressions` tables with
  zone-level aggregation only
- Frequency capping per device (local, not server-tracked individually)
- Public advertising policy
- Store disclosures updated (see `STORE_DISCLOSURE_CHECKLIST.md`)
- Legal review under Guinean consumer protection law

## Out of Scope (Forever)

- Selling user data to third parties
- Behavioral retargeting across other apps
- Location-history-based ad targeting