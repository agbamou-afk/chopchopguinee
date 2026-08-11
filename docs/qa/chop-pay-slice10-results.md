# Slice 10 — Full Financial Regression + Staged Activation

Head at start: `c26e08fb4be9d9f6c93021e4765cec2e10e3de24` (Slice 9 stable).
Scope: regression + independent per-stage server gating. No accounting
architecture reopened.

## 1. Canonical stage → flag → enforcement map

| Stage | Rail | Canonical flag | Server enforcement point(s) | UI enforcement |
| --- | --- | --- | --- | --- |
| 1 | Ride / Bonbonna cash + commission gate | `driver_balance_gate_enabled` | `ride_dispatch`, `ride_accept` (commission reserve / eligibility) | `DriverOperatingBalanceCard`, offer accept surfaces |
| 2 | Repas / Marché cash orders + merchant wallets | `cash_order_funding_enabled` | `cash_order_quote`, `_cash_order_accept_internal` | cash order panels |
| 3 | Envoyer collateral + claims | `envoyer_enabled`, `envoyer_declared_value_enabled`, `envoyer_claims_enabled` | `package_delivery_create_checkout` (`_envoyer_enabled`), `package_claim_open` | Envoyer flow + admin claims queue |
| 4 | Chop Pay ecosystem spending | `chop_pay_checkout_enabled` | `_chop_pay_customer_hold_internal`, `_chop_pay_accept_internal`, `_package_choppay_hold_internal`, `chop_pay_quote` | `ChopPayOrderPanel`, checkout tender selection |
| 5 | Merchant Orange Money settlement | `merchant_om_settlement_enabled` | `merchant_settlement_complete` (**added this slice**), `merchant_finance_overview` | admin settlement queue |
| 6 | Driver payout | `driver_cashout_enabled` | `driver_cashout_create_request`, `driver_cashout_mark_paid` (**added this slice**) | `DriverCashoutSheet`, `/admin/driver-cashouts` |
| 7 | P2P transfers | `chop_pay_p2p_enabled` | `wallet_p2p_transfer` (**added this slice**) | `SendMoneySheet` |
| — | OM inbound top-up (already canonical) | `om_topup_enabled` | `wallet_topup_om_create`, `om_auto_match`, `wallet_topup_om_credit` | `TopUpOrangeMoney` |

`chop_pay_enabled` / `wallet_public_enabled` are **surface visibility only**.
They never imply any stage. Verified by assertions B1–B3.

## 2. Audit findings (pre-existing defects, fixed this slice)

| # | Severity | Finding | Fix |
| --- | --- | --- | --- |
| D1 | P1 | `wallet_p2p_transfer` had **no** server flag gate — a stale client could move money while Stage 7 was "off". | Gate on `chop_pay_p2p_enabled`. |
| D2 | P1 | `driver_cashout_create_request` / `driver_cashout_mark_paid` had **no** server gate. | Gate on `driver_cashout_enabled`. |
| D3 | P1 | `merchant_settlement_complete` had **no** server gate. | Gate on `merchant_om_settlement_enabled`. |
| D4 | P2 | `anon` retained EXECUTE on payout / P2P / recipient-lookup functions. | REVOKEd; asserted by D1 check. |

Stage 1–4 gates already existed at their true enforcement points; two
initial harness assertions pointed at the wrong internal routine and were
corrected (harness bug, not a product defect).

## 3. Assertions

Harness: `public._qa_s10_run()` (fixtures executed inside a sub-transaction
and rolled back; results persisted to `_qa_s10_results`).

**Total 21 · PASS 21 · FAIL 0.**

| Group | Assertions | Result |
| --- | --- | --- |
| A — runtime stage gates with all stages OFF (cashout, P2P, claims, settlement) | 4 | PASS |
| B — non-implication (umbrella ON, Stage 4 ON, Stage 5 ON never enable 5/6/7) | 5 | PASS |
| C — engine-level flag enforcement (Stages 1–4) | 4 | PASS |
| D — `anon` has zero EXECUTE on finance primitives | 1 | PASS |
| E — ledger zero-sum and ≥2 legs on every journal | 2 | PASS |
| F — OM inbound strict evidence retained (payer phone, needs_review parking) | 2 | PASS |
| G — flag state unchanged after run; `om_topup_enabled` still ON | 2 | PASS |
| H — master wallet baseline `-100435` GNF unchanged | 1 | PASS |

## 4. Stage activation status

| Stage | Before | After | Decision |
| --- | --- | --- | --- |
| 1 Ride/Bonbonna | `driver_balance_gate_enabled=false` | unchanged | HOLD — activation is an operator decision in `/admin/flags`; gate proven |
| 2 Repas/Marché cash | `cash_order_funding_enabled=false` | unchanged | HOLD |
| 3 Envoyer | all envoyer flags `false` | unchanged | HOLD |
| 4 Chop Pay spend | `chop_pay_checkout_enabled=false` | unchanged | HOLD |
| 5 Merchant OM settlement | `false` | unchanged | **HOLD — no real outbound provider capability exists.** |
| 6 Driver payout | `false` | unchanged | **HOLD — no recorded operational approval.** |
| 7 P2P | `false` | unchanged | **HOLD — separate review required.** |
| OM inbound | `om_topup_enabled=true` | unchanged | remains ON (canonical inbound rail) |

No flag was flipped by this slice. The god-admin control plane
(`admin_set_feature_flag`) remains the only activation path and is
audit-logged.

## 5. Privileges after this slice

- `anon`: no EXECUTE on `wallet_p2p_%`, `driver_cashout_%`,
  `wallet_topup_om_credit`, `om_auto_match`, `merchant_settlement_complete`.
- Credit / payout primitives stay `service_role` + participant/admin wrappers.
- `_qa_s10_run` was never granted to `anon` / `authenticated`.

## 6. Build / QA evidence

- `tsgo -p tsconfig.app.json --noEmit` — clean.
- `vitest run` — 4 files, 20 tests, all pass.
- `bun run build` — success (20.75s), PWA `generateSW`, 130 precache entries.

## 7. Cleanup

`_qa_s10_run()` and `_qa_s10_results` dropped after recording results.
Master wallet unchanged at **-100435 GNF**.

## 8. YELLOW register

1. **Authenticated visual QA not possible** — preview session is signed out
   (`LOVABLE_BROWSER_AUTH_STATUS=signed_out`), so admin-UI activation
   screenshots could not be captured. Server gating proven at the RPC layer.
2. **Stage 5 has no outbound provider** — settlement remains a manual,
   evidence-backed operation; do not activate until a real payout rail exists.
3. **Lifecycle fixtures reused from Slices 4–9** — this slice re-proves gating,
   privileges and ledger invariants rather than re-running each service
   lifecycle end to end; those remain covered by their own slice harnesses.

## 9. Verdict

**Slice 10 — PASS** (21/21). All seven stages are independently gated on the
server; no stage can be implied by another or by the umbrella flag.
