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
| `package_delivery_cancel_preview` | Read-only fee/refund preview shown before the sender confirms |
| `package_delivery_courier_view` | SECURITY DEFINER operational payload for the assigned courier; excludes codes |
| `admin_set_driver_capability` | Ops/god admin only, audited grant/revoke of one driver capability (DEF-016) |
| `_package_notify` | Failure-isolated `notification_log` insert for sender-facing package events |

All of the above are `EXECUTE`-revoked from `anon`/`PUBLIC`;
`_package_notify` and `package_delivery_finalize_from_intent` are
`service_role` only.

### Verification attempt semantics

A wrong code returns `{ ok:false, error:'invalid_code', attempts_left }` instead
of raising. Raising rolled back the `pickup_attempts` / `delivery_attempts`
increment in the same transaction, which made the 6-attempt lockout
unreachable. Authorisation and state errors still raise.

### Dispatch semantics

`state = 'assigned'` with `courier_id IS NULL` is the project-wide "available"
convention — the `Eligible couriers read available missions` RLS policy encodes
exactly that predicate plus `driver_has_capability(...)`. Package missions
therefore enter the normal courier pool with no separate dispatch path.

## Payment path

Envoyer never touches the wallet model. It creates a payment intent on the
existing provider-neutral contract; Orange Money is the active rail. Refunds go
through `payment_refund_requests` (now accepting `source_module='package'`).

### Production finalisation (DEF-015 — CLOSED 2026-08-03)

`confirm_payment_intent` (the canonical admin/manual production confirmation
RPC) now has a `source_module = 'package'` branch:

1. accepts `pending | processing | authorized`;
2. confirms the intent and writes the `provider_confirmed` reconciliation event;
3. calls `package_delivery_finalize_from_intent(intent_id)` — never duplicating
   mission creation;
4. replay of an already-confirmed package intent re-enters the (idempotent)
   finaliser and returns the existing mission, creating no second mission,
   secret, reconciliation event, earning or support issue;
5. on finalisation failure the intent moves to `needs_review`, a high-severity
   `payment_failed` support issue is created and linked, a `provider_failed`
   reconciliation event is written, and the RPC returns the `needs_review` row
   (it deliberately does **not** re-raise, because raising would roll the
   recovery trail back). The admin UI surfaces this as an explicit failure.

No wallet, master-wallet or driver-earning movement occurs at confirmation.
Driver earning is still created only at trusted delivery completion.
`om_sandbox_finalize_authorized_intent` is unchanged and remains isolated.

`choppay_capture_payment_intent` is a wallet-hold capture path; Envoyer never
creates wallet holds and `wallet_public_enabled` is OFF, so it is not an active
package route. The Orange Money webhook edge function is still a documented
TODO stub with no live dispatch.

`envoyer_enabled` remains OFF — the flag now gates product rollout, not a known
finalisation gap.

## Capability & privacy

- Mission visibility: RLS policy *Eligible couriers read available missions*
  requires `driver_has_capability(auth.uid(), mission_required_capability(type))`,
  so a driver without `package_delivery` cannot see or accept package missions.
- Courier view exposes recipient name and phone (operationally required for
  hand-off) and never the verification codes — matching the ride/food policy
  where the assigned courier sees the contact of the party they must meet.
- Sandbox package rows carry `is_sandbox = true` and are excluded from
  earnings credit and production totals.
