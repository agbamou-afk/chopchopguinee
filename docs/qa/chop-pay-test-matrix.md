# Chop Pay test matrix (chop-pay-ledger-revival)

Legend: PASS (executed) · PASS(code) (inspection) · YELLOW (needs real external evidence) · TODO (not yet built).

| # | Case | Result |
| --- | --- | --- |
| A | Direct OM checkout absent from every public service | PASS(code) — no component consumes the OM checkout flags; `useOmCheckoutEnabled` now requires `om_direct_checkout_enabled` (off) |
| B | OM top-up still available and honest | PASS(code) — `TopUpOrangeMoney` + `wallet_topup_om_create` unchanged, manual-verification copy retained |
| C | Duplicate top-up reference cannot credit twice | PASS(code) — pre-existing `om_auto_match` / `wallet_topup_om_credit` guards, unchanged |
| D | Rejected top-up creates zero balance | PASS(code) — unchanged reconciliation path |
| E | Finance confirmation credits exactly once | PASS(code) — unchanged |
| F | Chop Pay balance = ledger truth | PASS — balances read only from `wallets`; no client mutation path |
| G | Held funds cannot be spent or transferred | PASS(code) — available = balance − held everywhere server-side |
| H | P2P transfer atomic and idempotent | PASS(code) — pre-existing `wallet_p2p_transfer` |
| I | Recipient enumeration protected | PASS(code) — pre-existing `wallet_p2p_lookup_recipient` masking |
| J | Sufficient-balance driver eligible | PASS — `driver_financial_eligibility` returns eligible when available ≥ required |
| K | Insufficient-balance driver blocked | PASS — `driver_mission_hold_place` raises `INSUFFICIENT_DRIVER_BALANCE` |
| L | Top-up restores eligibility automatically | PASS(code) — eligibility is computed live, no staff step |
| M | Acceptance holds estimated commission once | PASS — `UNIQUE (source_module, source_id, kind)`; replay returns `already_held` |
| N | Completion captures configured commission once | PASS(code) — state guard `held → captured` |
| O | Excess reserve released | PASS(code) — capture releases full hold, moves only `LEAST(due, reserved)` |
| P | Cancellation releases/captures per policy | PASS(code) — `driver_mission_hold_release` |
| Q | Rate change affects future missions only | PASS — capture recomputes from the stored `policy_snapshot` |
| R/S/T | Repas / Marché / Envoyer collateral held once | PASS — verified via `finance_mission_requirement` (Repas 120 000 → 120 000 collateral + 12 000 commission). **Historical record: those rates were the provisional defaults of that run and are superseded by `docs/product/chop-pay-canonical-operating-policy.md` (Repas Chop Pay collateral 50%, delivery commission 0%).** |
| U | Delivery releases collateral, credits earning separately | PASS(code) — earning path untouched (`wallet_credit_mission_earning`) |
| V | Dispute freezes collateral, no silent confiscation | PASS(code) — `driver_mission_hold_freeze` + audited `driver_collateral_resolve` |
| W | Sandbox produces zero production delta | PASS(code) — `is_sandbox` flag carried on every hold |
| X | Cross-driver/cross-user access denied | PASS(code) — RLS: drivers read only their own holds; RPCs check `auth.uid()` |
| Y | Offline/reconnect creates no duplicate hold | PASS — unique constraint |
| Z | Zero balance blocks new offers only | PASS(code) — gate applies to placement, not to history/support/active missions |
| AA | God Admin policy edits audited | PASS(code) — `admin_set_finance_policy` writes before/after to `audit_logs` |
| AB | Finance/Ops policy write denied | PASS(code) — `is_god_admin` check; UI read-only |
| AC | Merchant settlement reconciles | PASS(code) — settlement path unchanged |
| AD | Customer hold/capture/refund works | PASS(code) — unchanged ledger RPCs |
| AE | Flag OFF hides UI, preserves history | PASS(code) — flag only branches rendering |
| AF | Bonbonna casing / internal `toktok` intact | PASS(code) — untouched |
| AG | Password recovery functional | PASS(code) — untouched |
| AH | Envoyer / Home rail / Repas navigation unaffected | PASS(code) — untouched |
| AI | Typecheck / build clean | PASS |
| AJ | Mobile 360×800 / 390×844 / 412×915 | PASS(code) — new surfaces use existing `max-w-md` mobile layout primitives |

## Not yet built (open slices)
- Wiring `driver_mission_hold_place` into `ride_accept` / `driver_offer_accept` / `mission_claim` (Slice B/C runtime integration).
- Wiring `driver_mission_commission_capture` into `ride_complete` / mission completion.
- Chop Pay ecosystem checkout hold at service creation (Slice E).
