# CHOPCHOP finance policy freeze (Slice 0 — canonical)

This document is the single source of truth for launch money rules. Where any
other document disagrees, **this one wins**. Superseded statements are listed at
the bottom.

## 1. Ride / Bonbonna
- Payment: **cash** or **Chop Pay**. Orange Money direct checkout stays archived.
- Driver commission: **10%** of the authoritative final fare.
- Collateral: none.
- Minimum available driver balance: 5 000 GNF.

## 2. Repas / Marché — CASH order
- The courier funds **100% of the authoritative merchandise subtotal**, plus the
  applicable driver-side platform fee, **from unrestricted funds only**.
  Promotional starting credit may never fund merchandise principal.
- The merchant is paid internally by CHOPCHOP.
- The customer later pays physical cash for merchandise + delivery + the
  disclosed fee.
- Hold kind: `cash_funding` (rejects restricted funds by construction).

## 3. Repas / Marché — CHOP PAY order
- The customer prepays.
- The courier holds **50% merchandise-subtotal collateral** (cap 500 000 GNF
  Repas, 1 000 000 GNF Marché).
- Collateral release and delivery earning are **two distinct ledger entries**.
  Released collateral is never labelled earnings.

## 4. Envoyer
- Courier collateral: **75% of the accepted declared value** (cap 375 000 GNF,
  i.e. 75% of the declared-value cap).
- Default maximum declared value: **500 000 GNF**. 500 000 → 375 000 GNF
  collateral; a declared value above the cap is refused by policy when runtime
  uses it.
- Mandatory photos and a truthful declaration are required.
- Residual approved exposure may be handled by a **CHOPCHOP claims reserve after
  investigation**. This is never marketed as automatic insurance.

## 5. Transaction fee
- Default **1%** on non-ride services, God Admin editable, effective-dated.
- Explicit bases: Repas/Marché → `merchandise_subtotal`; Envoyer →
  `declared_value`; Ride/Bonbonna → `none`.

## 6. Cancellation
- **5%** before driver dispatch, **10%** after dispatch.
- Provider-caused failures are exempt.
- Repas: customer cancellation is **prohibited once the kitchen marks
  preparation started**.
- Cash cancellation debt accrues to `driver_profiles.cash_debt_gnf` /
  customer-side debt and must be settled before new cash missions.

## 7. Closed-loop activation structure
Separate flags, all OFF at launch except the inbound OM top-up rail:
`chop_pay_enabled`, `chop_pay_checkout_enabled`, `chop_pay_p2p_enabled`,
`driver_cashout_enabled`, `merchant_om_settlement_enabled`,
`driver_starter_credit_enabled`, `cash_order_funding_enabled`,
`driver_balance_gate_enabled`, `om_direct_checkout_enabled`.
ON: `om_topup_enabled`.

## 8. Merchant internal wallets
Merchants hold an internal `merchant` wallet (a CHOPCHOP liability). Settlement
to external Orange Money is separately gated and OFF.

## 9. New-driver starting credit — 25 000 GNF, RESTRICTED
Every newly **approved** driver receives a one-time **25 000 GNF** restricted
promotional credit inside the existing driver ledger wallet.

**Eligibility** — approved driver profile, identity document and vehicle photo
present, not banned, not frozen, wallet active, no duplicate-identity signal.
Never granted on signup or an incomplete application. Exactly one grant per
driver and per normalized phone identity; duplicates route to review.
Amount is God Admin configurable, effective-dated and audited
(`driver_starter_credit_policies`, `admin_set_starter_credit_policy`).

**Allowed uses** — commission holds/captures, mission collateral holds and
authorized collateral captures, configured driver-side platform/service fees.

**Prohibited uses** — cash-out, merchant settlement payout, P2P transfer,
customer purchases or Chop Pay ecosystem spending, transfer to any other wallet,
Repas/Marché cash-order merchandise principal, customer refunds, any external
Orange Money payout.

**Waterfall (canonical order)**
| Operation | Funding order |
| --- | --- |
| commission, platform_fee | promotional credit **first**, then unrestricted |
| cash_funding (merchandise principal) | **unrestricted only** — restricted funds rejected |
| collateral | proportional to available buckets, fully traceable |

Every hold snapshots `unrestricted_gnf` / `promo_gnf`. Release returns each
amount to its original bucket; capture permanently reduces the corresponding
bucket. No operation converts restricted funds into unrestricted funds.

**Driver experience** — total balance, available unrestricted balance,
`Bonus de démarrage CHOPCHOP`, held collateral/commission/cash-out, and the
note: *« Ce bonus de 25 000 GNF peut servir aux cautions et frais CHOPCHOP. Il
ne peut pas être retiré ni transféré. »* The bonus is excluded from
`Montant retirable` and from cash-out availability.

**Treasury** — issuance is a promotional expense / restricted platform-funded
credit, not customer cash-in and not driver earnings. The master wallet carries
the matching entry. `admin_promotional_credit_treasury()` separates outstanding
promotional credit from unrestricted driver liability. Unused restricted credit
is never revenue and creates no external cash asset.

**Reversal** — normally used credit is never clawed back. Fraud-confirmed
duplicate grants may be reversed only by an audited God Admin action, capped at
the unused amount, blocked while promotional holds are outstanding, and never
driving unrestricted funds negative.

## Superseded statements
- Envoyer collateral **50%** (all earlier docs) → **75%**.
- Envoyer collateral cap 250 000 GNF → **375 000 GNF** with a 500 000 GNF
  declared-value cap.
- Any claim that the starting credit is withdrawable, transferable, or may fund
  cash-order merchandise principal → **false**.
- Repas/Marché "100% collateral" provisional defaults → cash-order **funding**
  (100% of subtotal, unrestricted) is distinct from Chop Pay **collateral** (50%).