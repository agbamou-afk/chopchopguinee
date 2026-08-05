# Chop Pay ledger and settlement

Policy authority: `docs/product/chop-pay-canonical-operating-policy.md`.
This file describes mechanics only; it never defines rates or bases.

Reuses the existing internal ledger — no parallel wallet engine.

## Parties (`wallets.party_type`)
`client` (customer Chop Pay) · `driver` (operating balance) ·
`merchant` (payable) · `agent` · `master` (platform).

## Balances
- `balance_gnf` — total ledger balance
- `held_gnf` — reserved (holds, commission reserves, collateral)
- available = `balance_gnf - held_gnf` (never negative in UI)

## Core RPCs (pre-existing, unchanged)
`wallet_hold`, `wallet_capture`, `wallet_release`,
`wallet_internal_transfer(_v2)`, `wallet_p2p_transfer`,
`wallet_p2p_lookup_recipient`, `wallet_topup_om_create`,
`wallet_topup_om_credit`, `admin_record_om_receipt`, `om_auto_match`,
`wallet_admin_credit`, `wallet_settle_merchant_revenue`,
`wallet_pay_merchant_store`, `driver_cashout_*`.

## New RPCs (Chop Pay revival)
`finance_policy_current`, `finance_mission_requirement`,
`driver_balance_summary`, `driver_financial_eligibility`,
`driver_mission_hold_place`, `driver_mission_hold_release`,
`driver_mission_commission_capture`, `driver_mission_hold_freeze`,
`driver_collateral_resolve`, `admin_set_finance_policy`.

All are `SECURITY DEFINER` with `SET search_path = public` and explicit
authorization checks.

## Idempotency
Every mission hold is keyed by `UNIQUE (source_module, source_id, kind)`
in `mission_financial_holds`. A replayed placement returns
`{"status":"already_held"}` and writes nothing. Capture and release are
state-guarded (`held` → `captured`/`released` once).

## Settlement
Chop Pay orders: customer hold → capture → merchant merchandise amount
less commission, driver delivery earning, platform commission to master.
Collateral is never merchant revenue and never a driver earning.
