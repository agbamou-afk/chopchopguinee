# CHOPCHOP Store Disclosure Checklist

Use this checklist when preparing App Store Connect and Google Play
listings. Keep in sync with `src/pages/Privacy.tsx` and the Permission
Center.

## Data Collected

| Category | Used for | Linked to user | Tracking |
|---|---|---|---|
| Name, email, phone | Account, support | Yes | No |
| Precise location | Ride/delivery dispatch | Yes (during active use) | No |
| Coarse location | Service availability per district | No (aggregated) | No |
| Payment info | Wallet, top-ups, transfers | Yes | No |
| Order/ride history | Service delivery, support | Yes | No |
| Device identifiers | Push notifications, fraud prevention | Yes | No |
| Diagnostics | Crash reporting | No | No |

## Permissions Requested

- **Location (While Using)** — dispatch, pickup, ETA. Never background.
- **Notifications** — order/ride updates, wallet, support replies.
- **Camera** — KYC documents (drivers/merchants), profile photo.
- **Photo library** — profile photo, merchant catalog images.
- **Contacts** — *not requested at launch.*
- **Microphone** — *not requested at launch.*

## App Tracking Transparency (iOS)

CHOPCHOP does **not** request ATT. We do not access IDFA and do not
track users across other companies' apps or websites.

## Ads

No third-party ads at launch. First-party promotional content only,
toggleable in Permission Center.

## Account Deletion

In-app account deletion path: Profil → Légal & confidentialité →
Permissions & données → Supprimer mon compte. Must be operational
before store submission.

## Contact

- Support: support@chopchopguinee.com
- Privacy: privacy@chopchopguinee.com
- Legal entity: CHOP GUINEE LTD