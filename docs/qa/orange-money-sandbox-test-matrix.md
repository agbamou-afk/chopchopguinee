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