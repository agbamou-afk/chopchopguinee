# CHOP CHOP — Canonical Chop Pay Operating Policy

**Status:** FROZEN (Slice 0), 2026-08-05.
**Authority:** This is the ONLY authoritative source for CHOPCHOP money rules
(payment matrix, commission, collateral, funding, fees, cancellation, starting
credit, payout restrictions, activation flags, treasury classification).
Every other document — product, architecture, release, QA, memory, migration
comments — is subordinate. Where any of them disagrees, **this document wins**.

Runtime note: Slice 0 is documentation only. Nothing here activates a feature.
Where seeded database values differ from this document, the document is
canonical and the data must be corrected in a later authorized slice
(see §13 Open items).

---

## 1. Service payment matrix

| Service | Cash | Chop Pay | Direct Orange Money |
| --- | --- | --- | --- |
| Ride / Moto | Yes | Yes | Archived (OFF) |
| Bonbonna | Yes | Yes | Archived (OFF) |
| Repas | Yes | Yes | Archived (OFF) |
| Marché | Yes | Yes | Archived (OFF) |
| Envoyer (delivery fee) | Yes | Yes | Archived (OFF) |

- Repas and Marché: **no mixed tender in v1** — one order is entirely cash or
  entirely Chop Pay.
- **Customer cash-out: OFF at launch.**
- **Customer P2P: OFF at launch.**
- **Direct Orange Money checkout: archived / OFF.**
- Orange Money is retained only for (a) inbound customer/driver top-up and
  (b) controlled future merchant settlement and reconciliation.

## 2. Ride / Bonbonna

- Default driver commission: **10% of the authoritative completed fare.**
- God Admin editable, **effective-dated**, and **snapshotted onto the mission**
  at acceptance. Rate changes are never retroactive.
- Cash ride: the customer pays the driver physically; CHOPCHOP commission is
  captured from the driver's operating balance.
- Chop Pay ride: internal hold → capture → split.
- Insufficient eligible balance **pauses new offers only**. It never seizes
  funds, cancels an accepted mission, or blocks an in-progress mission.
- Minimum available driver balance: 5 000 GNF.

## 3. Repas / Marché — CASH orders

- The courier funds **100% of the authoritative merchandise/food subtotal**
  from **UNRESTRICTED driver funds only**.
- The restricted 25 000 GNF starter credit may **never** fund merchandise
  principal.
- An applicable CHOPCHOP driver-side / non-ride platform fee **may** draw on
  permitted restricted credit under the allocation policy in §7 and §8.
- The merchant/restaurant is paid **internally through its merchant wallet**
  before or at the moment preparation is authorized, per the canonical state
  transition. **The kitchen/store cannot begin preparation until funding is
  secured.**
- The customer later pays physical cash for merchandise subtotal + delivery fee
  + the disclosed applicable fee.
- The **delivery fee is not part of the funding principal**; it is the courier's
  physical cash earning.
- Merchant wallets are **CHOPCHOP liabilities** and require controlled
  settlement infrastructure before cash Repas/Marché launch.

## 4. Repas / Marché — CHOP PAY orders

- The customer prepays / holds the **full authoritative order amount**.
- Courier collateral: **50% of the authoritative merchandise subtotal only**.
- **Excluded from the collateral basis:** delivery fee, tip, tax, platform and
  service fees.
- Collateral release and delivery earning are **separate ledger events**.
  Released collateral is **never** labelled or displayed as earnings.
- Default delivery-driver commission: **0%**, unless a future effective-dated
  God Admin policy states otherwise.
- The non-ride platform transaction fee (§7) remains a separate line.

## 5. Envoyer

- **Mandatory truthful declared value** and **mandatory real private package
  photos**.
- Default maximum accepted declared value: **500 000 GNF**.
- Courier collateral: **75% of the accepted declared value**
  (500 000 → 375 000 GNF).
- Remaining potential approved exposure may be handled by a **CHOPCHOP claims
  reserve, only after investigation**. This is **never** called or marketed as
  automatic insurance.
- The 1% non-ride fee basis is the **delivery/service fee**, never the declared
  package value.
- Default delivery-driver commission: **0%**.
- Successful completion **releases** collateral; a dispute **freezes** it;
  capture happens only through an authorized, audited resolution after evidence
  review.

## 6. New-driver starting credit

- **25 000 GNF** default **restricted** CHOPCHOP starting credit.
- Granted **exactly once**, **after approved identity/vehicle verification** —
  never at signup, never on an incomplete application. One grant per driver and
  per normalized phone identity; duplicates route to review.
- God Admin configurable **for future drivers only**, effective-dated and
  audited.
- **Allowed uses:** ride/Bonbonna commission, permitted CHOPCHOP driver-side
  fees, mission collateral, authorized collateral loss.
- **Prohibited uses:** cash-out, P2P, purchases, transfers, merchant
  settlement, customer refunds, direct OM payout, and Repas/Marché cash-order
  merchandise principal.
- Holds must preserve **restricted vs unrestricted source attribution**.
  Released collateral returns to its **original bucket**. No operation converts
  restricted funds into unrestricted funds.
- Classification: **promotional restricted liability/expense** — not a top-up,
  not earnings, not an asset, not revenue.
- Driver-facing wording: shown as `Bonus de démarrage CHOPCHOP`, excluded from
  `Montant retirable`.

## 7. Non-ride transaction fee

- Default **1%**, God Admin editable, effective-dated, snapshotted per mission.

| Service | Fee basis |
| --- | --- |
| Repas | merchandise subtotal |
| Marché | merchandise subtotal |
| Envoyer | delivery / service fee **only** |
| Future P2P | transfer amount |
| Ride / Bonbonna | none (ride commission applies instead) |

- **No 1% fee** on: top-up, payout/settlement, refund, collateral release, or
  any internal ledger movement.
- Separate from ride commission, merchant commission and Orange Money provider
  fees.

## 8. Cancellation

- **5%** before driver dispatch; **10%** after driver dispatch.
- Exempt where the failure is provider-, platform-, merchant- or driver-caused
  and the customer is not responsible.
- Fee bases:
  - Ride / Bonbonna → quoted fare;
  - Repas / Marché → merchandise subtotal + delivery fee;
  - Envoyer → delivery fee only.
- **Repas: customer cancellation is prohibited once the kitchen marks
  `En préparation`.**
- Cash-order cancellation fees become **customer debt**, restrict future cash
  orders, and remain payable through Chop Pay.
- Policy is effective-dated and snapshotted.

## 9. Payout / settlement restrictions

- Launch is a **closed loop**: no customer cash-out, no public P2P.
- Driver cash-out infrastructure may be built, but **activation is OFF**.
- **Merchant settlement is operational accounts payable** and is **required
  before cash Repas/Marché launch**.
- Documented **future** payout defaults (not active): 10 000 GNF minimum,
  configured maximum 500 000 GNF, effective daily limit 250 000 GNF, one pending
  request at a time, registered Orange Money phone only, 1–5 minute estimate,
  one-minute cancellation window before processing, provider fee passed through,
  disputes/suspension block requests.
- **Outbound OM evidence and reconciliation are required before any ledger
  debit.**

## 10. Feature activation (granular, staged)

No monolithic "Chop Pay" switch may simultaneously expose balance, spending,
P2P, cash orders, payouts and settlement.

| Flag | Launch state |
| --- | --- |
| `om_topup_enabled` | ON |
| `chop_pay_enabled` | OFF |
| `chop_pay_checkout_enabled` | OFF |
| `chop_pay_p2p_enabled` | OFF |
| `driver_balance_gate_enabled` | OFF |
| `driver_starter_credit_enabled` | OFF |
| `cash_order_funding_enabled` | OFF |
| `driver_cashout_enabled` | OFF |
| `merchant_om_settlement_enabled` | OFF |
| `om_direct_checkout_enabled` | OFF (archived) |

Staged activation order: top-up → driver balance visibility → driver balance
gate → starter credit → Chop Pay checkout → cash-order funding → merchant
settlement → payouts. P2P and customer cash-out remain out of scope for launch.

## 11. Treasury classification

| Item | Classification |
| --- | --- |
| Customer Chop Pay balance | Liability |
| Driver operating balance (unrestricted) | Liability |
| Driver promotional starter credit | Restricted promotional liability / expense |
| Merchant wallet balance | Liability (accounts payable) |
| Mission collateral holds | Restricted liability (driver funds) |
| Cash-order funding holds | Restricted liability (driver funds) |
| Pending payouts | Liability |
| Captured commissions | **Revenue** |
| Captured service / transaction fees | **Revenue** |
| Top-ups | Not revenue |
| Released collateral | Not revenue, not earnings |

## 12. Superseded statements (repository-wide)

The following are **stale and must not be treated as current policy**:

| Stale statement | Canonical replacement |
| --- | --- |
| Envoyer collateral **50%** of declared value | **75%**, cap 375 000 GNF (§5) |
| Envoyer collateral cap 250 000 GNF | **375 000 GNF** (§5) |
| Repas/Marché collateral **100%** | Chop Pay collateral **50% of subtotal**; cash orders are **funding**, not collateral (§3, §4) |
| Universal **10%** driver commission across delivery missions | 10% applies to **ride/Bonbonna only**; delivery default **0%** (§2, §4, §5) |
| Starting bonus withdrawable / transferable / usable for cash-order principal | Restricted, non-withdrawable, non-transferable, never merchandise principal (§6) |
| Orange Money as direct checkout launch rail | Archived; top-up only (§1) |
| Customer or driver cash-out shown as an active launch feature | Both OFF at launch (§1, §9) |
| Delivery fee included in Repas/Marché collateral basis | Excluded (§4) |
| Released collateral labelled as earnings | Two separate ledger events; never earnings (§4, §11) |
| Envoyer 1% fee based on declared value | Basis is the delivery/service fee (§7) |

Historical migration comments and dated QA records are **not rewritten**; they
remain accurate records of what was applied at the time and are superseded by
this document.

## 13. Open items (require a later authorized slice)

1. Seeded `finance_policies` row for `envoyer` currently uses fee basis
   `declared_value`; canonical basis is the **delivery/service fee** (§7).
   Correction requires an authorized data/schema slice.
2. Cancellation-fee bases (§8) are frozen in policy but not yet represented as
   per-service basis columns in `finance_policies`.
3. Customer-side cash-order cancellation debt (§8) has no ledger primitive yet.
4. Merchant settlement infrastructure (§3, §9) is not built.
