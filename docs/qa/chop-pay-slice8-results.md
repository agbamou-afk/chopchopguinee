# Chop Pay — Slice 8 QA results (centralized cancellation + customer debt)

Policy authority: `docs/product/chop-pay-canonical-operating-policy.md`.
Run date: 2026-08-11. Harness: self-rolling-back plpgsql, fixtures discarded.

**Result: 66 / 66 assertions PASS, 0 failures. Slice 8 exit gate: PASS.**

---

## 1. Audit findings — duplicated cancellation logic removed

| Location | Before | After |
| --- | --- | --- |
| `ride_cancel` | inline `(fare * bps) / 10000` | calls `_cancellation_compute` |
| `_customer_cancellation_debt_create_internal` | own basis + bps arithmetic | calls `_cancellation_compute` |
| `_chop_pay_cancel_internal` | own basis + bps arithmetic | calls `_cancellation_compute` |
| `package_delivery_cancel` | `floor(quoted_amount * 0.10)` regardless of stage or snapshot | calls `_cancellation_compute` on the frozen `delivery_fee` basis |
| `package_delivery_cancel_preview` | hard-coded 10% of the whole quoted amount (**DEF-FIN-S8-002**) | proxies `cancellation_quote` |
| `PackageDeliveries.tsx` | built a `window.confirm` string from preview fields | shared `CancellationConfirmDialog` |

DEF-FIN-S8-002 (Envoyer preview ignored the 5% pre-dispatch rule and used the
full quoted amount as basis) is **closed** in this slice.

## 2. Canonical calculator and RPCs

- `_cancellation_compute(snapshot, stage, fare, subtotal, delivery_fee, responsible_party)`
  — IMMUTABLE, service-role only. **The only place a cancellation amount is
  derived, anywhere in the product.**
- `cancellation_quote(service, source_id, source_module)` — authenticated,
  self-only, participant-scoped. Serves ride / cash_order / chop_pay_order /
  package. Returns cancelability, stage, lock reason, basis, bps, fee, cash
  debt, refundable amount and the snapshot reference.
- `customer_cash_eligibility()`, `_customer_cash_restricted(uid)`,
  `_block_new_cash_exposure` trigger.
- `customer_cancellation_debt_repay(debt_id, amount)`,
  `customer_cancellation_debts_overview()`,
  `_customer_cancellation_debt_settle_internal(...)`.
- Reused unchanged: `_ledger_post`, `_ledger_reverse`,
  `_customer_cancellation_debt_create_internal`, `customer_cancellation_debt_waive`,
  `_package_cancel_release_internal`, `_chop_pay_customer_release_internal`.
  No parallel accounting system was created.

## 3. Assertion results

### A. Quote = execution (3/3)
| Case | Result |
| --- | --- |
| A1 all cancellation paths call the one calculator | PASS |
| A2 hard-coded Envoyer 10% formula removed | PASS |
| A3 Envoyer preview proxies the canonical quote | PASS |

### B. Ride / Bonbonna — 100 000 GNF anchor (6/6)
| Case | Result |
| --- | --- |
| B1 pre-dispatch → 5 000 GNF exactly (500 bps) | PASS |
| B2 post-dispatch → 10 000 GNF exactly (1000 bps) | PASS |
| B3 driver-caused → 0 | PASS |
| B4 platform-caused → 0 | PASS |
| B5 provider-caused → 0 | PASS |
| B6 basis kind is `fare` | PASS |

### C. Repas — 150 000 + 25 000 anchor (5/5)
| Case | Result |
| --- | --- |
| C1 basis 175 000, pre-dispatch → 8 750 | PASS |
| C2 post-dispatch → 17 500 | PASS |
| C3 merchant rejection → 0 fee | PASS |
| C4 `preparing` lock denies cancellation (`REPAS_CANCELLATION_LOCKED`) | PASS |
| C5 lock caused zero finance mutation | PASS |

### D. Marché (3/3)
| Case | Result |
| --- | --- |
| D1 basis 175 000 → 8 750 | PASS |
| D2 post-dispatch → 17 500 | PASS |
| D3 1% platform transaction fee excluded from the basis | PASS |

### E. Envoyer — declared 500 000, fee 25 000 (5/5)
| Case | Result |
| --- | --- |
| E1 basis = delivery fee 25 000, kind `delivery_fee` | PASS |
| E2 pre-dispatch → 1 250 | PASS |
| E3 post-dispatch → 2 500 | PASS |
| E4 declared 500 000 cannot change the fee | PASS |
| E5 never bills 500 000 or 525 000 | PASS |

Post-custody (`custody_established`) and `claim_open` both return
`cancelable = false`, so no path releases the 75% collateral or unfreezes a
claim through normal cancellation.

### F. Debt / restriction / repayment (16/16)
| Case | Result |
| --- | --- |
| F1 cash cancellation creates a 10 000 debt | PASS |
| F2 exactly one debt row per source | PASS |
| F3 replay returns `already_exists` | PASS |
| F3b replay created no second debt | PASS |
| F4 driver-caused creates zero debt (`exempt`) | PASS |
| F5 outstanding debt restricts new cash exposure | PASS |
| F6 partial repayment collects exactly 4 000 | PASS |
| F7 restriction persists while outstanding | PASS |
| F8 cannot over-collect beyond available funds (2 000) | PASS |
| F9 outstanding exact (4 000), never negative | PASS |
| F10 full repayment clears the debt | PASS |
| F11 full repayment restores cash eligibility automatically | PASS |
| F12 repayment after settlement is inert | PASS |
| F13 customer wallet debited exactly 10 000 | PASS |
| F13b collected total equals the fee, no overcollection | PASS |
| F14/F15 waiver records `waived_gnf`, never `paid_gnf`, distinct ledger action | PASS |

Restriction semantics: outstanding debt blocks **new cash exposure only**.
Authentication, history, receipts, support and Chop Pay flows stay open, and
already-active jobs are untouched.

### G. Snapshot immutability (5/5)
Method: accept at 500/1000 bps, insert a later effective-dated ride policy at
2500/4000 bps, re-quote.

| Case | Result |
| --- | --- |
| G1 accepted transaction keeps frozen 5% → 5 000 | PASS |
| G2 accepted transaction keeps frozen 10% → 10 000 | PASS |
| G3 new transaction uses new 25% → 25 000 | PASS |
| G4 new transaction uses new 40% → 40 000 | PASS |
| G5 exactly one canonical calculator exists | PASS |

### H. Ledger / idempotency (5/5)
| Case | Result |
| --- | --- |
| H1 cancellation journals written | PASS |
| H2 every journal zero-sum | PASS |
| H3 no duplicate platform cancellation revenue (1 charge per source) | PASS |
| H4 three partial collections, each posted once | PASS |
| H5 every cancellation journal is source-linked | PASS |

Collection idempotency is keyed on the pre-state
(`cancel-collect:<debt_id>:<paid_gnf>`), so a replayed partial payment cannot
double-post. Releases post `*_released`, never a refund action, preserving
Slice 7 history/receipt truth.

### I. Privileges (10/10)
| Case | Result |
| --- | --- |
| I1 calculator closed to anon and authenticated | PASS |
| I2 quote denied to anon, allowed to authenticated (self-only in body) | PASS |
| I3 repayment denied to anon, self-only | PASS |
| I4 waiver never exposed to anon or authenticated | PASS |
| I5 collection primitive closed | PASS |
| I6 settle internal service-role only | PASS |
| I7 package release internal service-role only | PASS |
| I8 restriction helper service-role only | PASS |
| I9 no Slice 3–7 privilege regression on raw primitives | PASS |
| I10 no `auth.uid() IS NULL` trusted shortcut | PASS |

Cross-customer access raises `forbidden` (42501) in every quote branch; drivers
and merchants have no path to create, collect or waive customer debt.

### J. Cleanup / posture (7/7)
| Case | Result |
| --- | --- |
| J1 master wallet unchanged by harness (−100 435, held 0) | PASS |
| J2 zero debt fixture residue | PASS |
| J3 zero wallet fixture residue | PASS |
| J4 zero policy fixture residue | PASS |
| J5 zero ledger fixture residue | PASS |
| J6 no finance rail activated | PASS |
| J7 `om_topup_enabled` preserved ON | PASS |

No immutable trigger was disabled, no journal deleted, no wallet reset.
**DEF-FIN-001** (master wallet −100 435 GNF) is unchanged and carried forward.

## 4. Product surfaces

| Surface | Change |
| --- | --- |
| `src/lib/finance/cancellation.ts` | new client layer: quote, debts overview, repayment. Zero arithmetic. |
| `src/components/finance/CancellationConfirmDialog.tsx` | single confirmation surface; renders server quote fields verbatim, French-first truthful copy |
| `src/components/finance/CancellationDebtPanel.tsx` | outstanding debt + explicit repayment, states that only new cash orders are blocked |
| `src/components/trip/RealtimeTripScreen.tsx` | ride cancel now quotes, then calls `ride_cancel` |
| `src/components/chopPay/ChopPayOrderPanel.tsx` | customer cancel quotes first; lock routes to the dispute path |
| `src/components/envoyer/PackageDeliveries.tsx` | `window.confirm` replaced by the shared dialog |
| `src/components/views/WalletView.tsx` | mounts the debt panel |

`src/test/slice8-cancellation-truth.test.ts` adds 5 source-level guards that
fail CI if any surface reintroduces percentage or basis arithmetic.

## 5. Build evidence

- `tsgo --noEmit -p tsconfig.app.json` — clean.
- Vitest — 20/20 pass (4 files).
- Production build — success in 17.53 s.

## 6. YELLOW register (carried forward)

1. **PWA chunk size** — `index` 2 167 kB and `mapbox-gl` 1 781 kB exceed the
   500 kB warning threshold. Pre-existing, not introduced by Slice 8.
2. **Visual QA — YELLOW.** No authenticated preview session was available, so
   the new dialog and debt panel were verified by type check, unit guards and
   production build only, not by an authenticated screenshot run.
3. **DEF-FIN-001** — platform master wallet at −100 435 GNF. Finance
   reconciliation follow-up. Not credited or normalized.
4. Supabase linter still reports the pre-existing 543 project-wide findings
   (RLS-enabled-no-policy INFO on internal tables, mutable search_path WARNs on
   legacy functions). No new finding originates from Slice 8; every function
   added in this slice sets `search_path`.

## 7. Exit gate

Frontend preview and server execution both consume `_cancellation_compute`
through the frozen policy snapshot. There is no React percentage math and no
duplicated formula left in the codebase. **Slice 8 exit gate: PASS.**