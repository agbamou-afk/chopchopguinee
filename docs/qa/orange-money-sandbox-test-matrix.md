# Orange Money Sandbox — QA Test Matrix

Run in staging with `om_environment=true`, `om_sandbox_enabled=true`,
`om_checkout_enabled=true`, and the per-module checkout flags on for
the modules you are testing.

| # | Scenario | Expected |
|---|---|---|
| A | `wallet_public_enabled=false` | Home service tiles + `/wallet` all read "OM Wallet". No "ChopWallet" wording. |
| B | Open OM Wallet tile | Neutral payment center loads. No internal balance. |
| C | `wallet_public_enabled=true` | Legacy ChopWallet naming and surface return safely. |
| D | Ride checkout, `OM-SBX-SUCCESS-001` | Server authorizes intent, exactly one ride created. |
| E | Same sandbox ref submitted twice | Idempotent — no duplicate authorization, no duplicate ride. |
| F | Ride checkout, `OM-SBX-REJECT-001` | Intent → `failed`. No ride. |
| G | Ride checkout, `OM-SBX-REVIEW-001` | Intent → `in_review`. No ride finalized. |
| H | Ride checkout, `OM-SBX-EXPIRED-001` | Intent → `expired`. Source cannot be finalized. |
| I | Ride cancellation before driver assignment | Full sandbox refund. No fee. |
| J | Ride cancellation after driver assignment | 10% simulated fee to a sandbox master shadow row. Real master wallet unchanged. |
| K | Repas checkout, `OM-SBX-SUCCESS-001` | Order confirmed only after authorization. |
| L | Repas duplicate sandbox submission | No duplicate order, no duplicate capture. |
| M | Marché offer, `OM-SBX-SUCCESS-001` | Payment authorized before progression. |
| N | `OM-SBX-REFUND-001` on captured intent | Refund state reached, sandbox audit event emitted. |
| O | Submit `OM-SBX-SUCCESS-001` in production/manual mode | Rejected server-side. |
| P | Production dashboards / master wallet / Ops Command Center | Sandbox rows excluded. Totals unchanged. |
| Q | Driver earnings + cashout | Sandbox excluded. Eligibility unaffected. |
| R | Admin `/admin/payments` | Sandbox and Live/manual visibly separated via filter. |
| S | Cross-user RLS check | User A cannot read User B's payment intent. |
| T | Mobile 390x844 | OM Wallet tile + payment center render cleanly, no wrap, no keyboard occlusion. |
| U | Build | `bun run build` clean. |

See `docs/finance/orange-money-sandbox.md` for the reference table and
isolation invariants.

## Slice A verification (2026-07-26)

Executed via SQL harness against the deployed `om_payment_submit_sandbox_reference`
RPC. All rows pass. Row IDs map to Slice A goals, not the full A–U grid above.

| Row | Scenario | Result |
|---|---|---|
| A1 | SUCCESS ref (`  om-sbx-success-001 `, mixed case + padding) on owned sandbox intent | intent → `authorized`, `authorized_at` set, event stored |
| A2 | Same SUCCESS ref replayed | `idempotent=true`, no duplicate provider event, no duplicate transition |
| A3 | Live-looking ref (`OM-12345678`) via sandbox RPC | rejected `live_reference_rejected_on_sandbox_rpc` |
| A4 | Sandbox ref on live intent (`is_sandbox=false`) | rejected `not_a_sandbox_intent` |
| A5 | Sandbox ref on another user's sandbox intent | rejected `forbidden` |
| A6 | REJECT / REVIEW / EXPIRED / DUPLICATE deterministic outcomes | intents → `failed` / `needs_review` / `expired` / `needs_review` |
| A6b | DUPLICATE reference re-used across a fresh sandbox intent | duplicate branch fires, second intent stays `pending`, no double-authorization |
| A7 | `confirm_payment_intent` invoked against a sandbox intent | rejected before wallet touch (admin gate + `sandbox_intent_use_om_payment_submit_sandbox_reference` guard) |
| A8 | Master wallet balance before vs after full run | delta = 0 |
| A9 | Non-sandbox provider events created during the run | 0 |

Sandbox path never invokes `wallet_hold`, `wallet_capture`, `wallet_release`,
`wallet_settle_merchant_revenue`, `wallet_credit_mission_earning`, or
`wallet_pay_merchant*`. Driver / merchant / master balances therefore cannot move.
## Slice C — Refund lifecycle + authoritative ride fare

Harness: `/tmp/qa_slice_c.sql`, transactional rollback against staging,
2026-07-26. All rows GREEN except N which is code-review only
(harness cannot UPDATE `food_orders` under RLS).

| # | Case | Result |
|---|---|---|
| A | Authoritative ride fare: server computes 16117; client-supplied 15000 ignored; `metadata.client_display_amount_mismatch=true` | ✅ |
| B | Ride cancel before assignment: `fee_gnf=0`, `amount_gnf=intent`, refund `pending` | ✅ |
| C | Cancel replay idempotent (same `refund_request_id`) | ✅ |
| D | Ride cancel after assignment (driver assigned via `om_sandbox_assign_mock_driver`): `fee_gnf=1612` (10% of 16117), `refund=14505`, refund `pending` | ✅ |
| E | After-assignment cancel replay idempotent | ✅ |
| F | Refund SUCCESS via `OM-SBX-REFUND-001`: refund→`paid`, intent→`refunded` | ✅ |
| G | Refund SUCCESS replay idempotent | ✅ |
| H | Refund REVIEW via `OM-SBX-REFUND-REVIEW-001`: refund→`needs_review`, high-severity `payment_failed` support issue linked | ✅ |
| I | Sandbox ref on live refund row (rejected `not_a_sandbox_refund`) | ✅ |
| J | Live-looking `OM-PROD-*` ref rejected on sandbox RPC; unknown `OM-SBX-BOGUS-001` rejected | ✅ |
| K | Marché refund on unpaid offer (rejected `offer_not_refundable`) | ✅ |
| L | Cross-user refund submit rejected (`forbidden`) | ✅ |
| M | Repas eligible refund: pending → paid, food_order.payment_status='refunded' | ✅ |
| N | Repas ambiguous (`state='completed'`) → `needs_review` branch | ⚪ code-review only (harness RLS) |
| O | Marché eligible refund success: offer.payment_status='refunded' | ✅ |
| P | Duplicate provider reference on same intent rejected (`duplicate_provider_reference_on_intent`) | ✅ |
| Q | `test_run_id` propagation: 6 intents, 6 refund requests, 16 provider events, 22 recon events, 1 support issue | ✅ |
| R | Financial isolation: master wallet delta = 0, wallet_transactions delta = 0 across the whole run (including a 10% fee split) | ✅ |
| S | Production/manual regression: `confirm_payment_intent` / `fail_payment_intent` / capture RPCs still reject sandbox rows at the boundary; no changes to production flow | ✅ |
| T | Build/typecheck: migrations succeed; runtime linter noise pre-existing (unrelated `search_path` warnings on other functions) | ✅ |

## Slice D — God Admin control plane + archival + wallet refund UX

Harness: SQL harness against staging + manual UI walkthrough.

| # | Case | Result |
|---|---|---|
| A | God Admin opens `/admin/payments/sandbox` — sandbox-only metrics and test runs | ✅ |
| B | Finance Admin opens route — read-only, no simulate/archive buttons | ✅ |
| C | Operations Admin opens route — `ModulePage` denies (no `payments` view) | ✅ |
| D | Ordinary user opens `/admin/payments/sandbox` — AdminGuard denies | ✅ |
| E | Both flags off — inactive amber banner, all simulation controls hidden/disabled | ✅ |
| F | Both flags on — simulation controls appear for God Admin only | ✅ |
| G | Simulate Ride SUCCESS from admin — exactly one intent transitions, structured RPC result | ✅ |
| H | Replay same fixture — `idempotent=true` | ✅ |
| I | FINALIZE_FAIL fixture — needs_review + support issue linked | ✅ |
| J | Mock driver as ordinary user — `forbidden` | ✅ |
| K | Mock driver as Operations Admin — `forbidden` | ✅ |
| L | Mock driver as God Admin — driver attached, audit row written | ✅ |
| M | Ride cancel via admin — 10% fee split when driver assigned, else 0% | ✅ (Slice C parity) |
| N | Repas refund via admin | ✅ (Slice C parity) |
| O | Marché refund via admin | ✅ (Slice C parity) |
| P | OM Wallet refund card renders own refund state, amounts, Sandbox badge, support link | ✅ |
| Q | Cross-user refund invisible — RLS `refund_owner_read` scopes to `auth.uid()` | ✅ |
| R | `om_sandbox_archive_test_run` on active run — marks 6 intents / 6 refunds / N events / M recon / 1 support, `status='archived'` | ✅ |
| S | Archive replay — `idempotent=true` | ✅ |
| T | Simulate on archived run — trigger raises `sandbox_test_run_archived` | ✅ |
| U | Archive mixed/live run — refused (`refuse_archive_mixed_or_live_run`) | ✅ |
| V | Master wallet delta across full Slice D run + archive = 0; `wallet_transactions` delta = 0 | ✅ |
| W | Driver balance / `held_gnf` / cashout eligibility / merchant payable unchanged | ✅ |
| X | Production `admin_preview_payment_intents` excludes sandbox by default (Slice A guard) | ✅ |
| Y | Post-QA: both sandbox flags restored to `false`, provider mode manual | ✅ |
| Z | Build + typecheck clean (`bunx tsgo`), HMR flush 200 | ✅ |
