# Envoyer — mission & payment architecture

## Tables

| Table | Purpose |
|---|---|
| `package_delivery_quotes` | Server-authoritative quote, 15-minute expiry, owner-read only |
| `package_deliveries` | Package record: sender, recipient, category, mission/payment links, status, cancellation fields |
| `package_delivery_secrets` | 6-digit pickup/delivery codes; **sender-read only** RLS, no courier or public read |

All three carry explicit GRANTs; `service_role` retains full access for
functions.

## RPCs

| RPC | Role |
|---|---|
| `package_delivery_quote` | Prices from the existing moto tariff (`fare_settings`); never client-computed |
| `package_delivery_create_checkout` | Creates package + provider-neutral `payment_intent` (`source_module='package'`, `payment_purpose='package_payment'`), idempotency-keyed |
| `package_delivery_finalize_from_intent` | On authorised payment: creates the `package_delivery` mission and the verification codes |
| `package_verify_pickup` / `package_verify_delivery` | Code comparison, mission state transition, earnings credit **guarded by `IF NOT is_sandbox`** |
| `package_delivery_cancel` | Sender-only, idempotent; fee/refund/support-dispute branches |
| `package_delivery_courier_view` | SECURITY DEFINER operational payload for the assigned courier; excludes codes |

## Payment path

Envoyer never touches the wallet model. It creates a payment intent on the
existing provider-neutral contract; Orange Money is the active rail. Refunds go
through `payment_refund_requests` (now accepting `source_module='package'`).

### Known integration gap (DEF-015)

`om_sandbox_finalize_authorized_intent` calls
`package_delivery_finalize_from_intent`; the production/manual admin path
`confirm_payment_intent` does **not**. Until that call is added, a real-money
Envoyer payment would confirm the intent without creating the mission. This is
why `envoyer_enabled` stays OFF.

## Capability & privacy

- Mission visibility: RLS policy *Eligible couriers read available missions*
  requires `driver_has_capability(auth.uid(), mission_required_capability(type))`,
  so a driver without `package_delivery` cannot see or accept package missions.
- Courier view exposes recipient name and phone (operationally required for
  hand-off) and never the verification codes — matching the ride/food policy
  where the assigned courier sees the contact of the party they must meet.
- Sandbox package rows carry `is_sandbox = true` and are excluded from
  earnings credit and production totals.
