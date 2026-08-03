# Envoyer v1 — Parcel & document delivery (RC amendment, Slice 3)

Status: **implemented behind `envoyer_enabled` (currently OFF)**.
`web-production-release-candidate-stable` remains **UNLOCKED**.

## What Envoyer is

A first-class parcel/document delivery service reusing the existing
`package_delivery` mission type, mission lifecycle, driver capabilities,
payment-intent contract and map/location components. No new payment
architecture, no new wallet model, no pricing engine of its own — the quote is
derived server-side from the existing moto tariff in `fare_settings`.

## Customer flow

1. **Services → Envoyer** (tile 3) opens `EnvoyerComposer` (5 steps).
2. *Itinéraire* — pickup + destination via `LocationField` (maps-search,
   "Ma position", reverse geocoding).
3. *Destinataire* — recipient name + Guinea-normalised phone, optional
   sender phone.
4. *Colis* — category (document, small, medium, large), description,
   handling notes, prohibited-items notice.
5. *Prix* — server-authoritative quote (`package_delivery_quote`, 15-minute
   expiry). The client never computes a price.
6. *Confirmation* — `package_delivery_create_checkout` creates the package row
   and a provider-neutral `payment_intent` (`source_module = 'package'`,
   purpose `package_payment`). Orange Money manual verification copy applies.

Tracking lives in **Activité** (`PackageDeliveries`), including the
sender-only pickup and delivery codes.

## Courier flow

- Available package missions appear only for drivers holding the
  `package_delivery` capability (enforced by mission RLS).
- `PackageHandoffPanel` on `ActiveMissionCard` collects the 6-digit pickup code
  and the 6-digit delivery code.
- The courier operational payload comes from `package_delivery_courier_view`,
  which **never** returns verification codes.

## Cancellation

`package_delivery_cancel` is sender-only and idempotent:
- before courier assignment → full refund request, no fee;
- after assignment, before pickup → 10 % fee, remainder refunded;
- after pickup verification → no self-service refund; a `package_dispute`
  support issue is opened instead.

## Honest limits at this state

- Feature flag OFF; no customer sees Envoyer yet.
- No real-money Envoyer payment has been executed.
- Production payment finalisation is not yet wired (see DEF-015).
- Driver `package_delivery` capability is currently driver self-selected;
  there is no admin capability editor.
