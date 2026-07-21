# Orange Money Rail — Launch Mode

## Product model
CHOPCHOP launches with **Orange Money as the primary payment rail** for
customers, and as the payout rail for drivers. The public "CHOP Wallet"
surface is archived behind the `wallet_public_enabled` feature flag
(default off). The internal wallet ledger remains fully active for
accounting, holds, cancellation fees, driver balances, master wallet,
and audit.

## Customer flow (launch)
1. Customer chooses a service (ride, repas, marché).
2. Payment prompt leads with Orange Money.
3. Customer sends OM to the CHOPCHOP receiving number, submits the OM code.
4. **Operator verifies manually** — no automatic crediting.
5. Confirmation reflects in Activité (order/ride history).

## Driver flow (launch)
1. Driver accumulates earnings in the internal ledger.
2. Driver requests a cashout from `Retrait`.
3. Admin verifies and marks the request paid with the Orange Money reference.

## Feature flag
- Key: `wallet_public_enabled`
- Default: `false`
- Managed at: `/admin/flags` (Super Admin only)
- Effect when `false`: hides public wallet UI, reframes hero/tiles/tabs as OM-first. Ledger unaffected.

## Roadmap (not in this pivot)
- Direct provider webhook confirmation (partial automation).
- Public CHOP Wallet re-enable once webhooks + reconciliation SLAs are proven.
- MTN Money as a second rail (adapter scaffold already present).

## Rules
- Never mutate `wallets.balance_gnf` or `wallet_transactions` from the client.
- Every credit flows through a SECURITY DEFINER RPC.
- Never promise instant credit for Orange Money at launch.