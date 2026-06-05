# CHOPCHOP Release QA Checklist

Pilot-critical flows. Each item must pass on the latest build before declaring release candidate. Owning agent is in brackets — that agent is responsible for the test passing and for the fix if it doesn't.

Status legend: `[ ]` not verified · `[x]` verified pass · `[!]` blocker.

---

## 1. Branded email signup confirmation  *(Platform, QA & Security)*
- [ ] New signup triggers branded confirmation email (not the default Supabase template)
- [ ] Sender domain matches the configured email domain
- [ ] Confirmation link lands back on the correct app route
- [ ] Confirmed user becomes authenticated and reaches the right post-auth target

## 2. Client signup  *(Platform, QA & Security)*
- [ ] Email + password signup succeeds
- [ ] +224 prefix is prefilled on phone field; phone stored as `+224XXXXXXXXX`
- [ ] Legal consent captured in `user_legal_consents`
- [ ] Profile completion route reached when profile incomplete
- [ ] Client lands on the client home after onboarding

## 3. Driver signup and application  *(Platform → Rides for application UI)*
- [ ] Driver signup branch reachable from auth/onboarding
- [ ] Driver application form submits to `driver_applications`
- [ ] Pending driver cannot toggle online
- [ ] Pending driver sees a clear "in review" state

## 4. Admin driver approval  *(Admin & Operations)*
- [ ] Driver application appears in `DriversAdmin`
- [ ] God-admin can approve / reject through safe RPC
- [ ] Approval updates `driver_profiles` correctly
- [ ] Rejected/pending drivers cannot accept rides

## 5. Driver / client mode switch  *(Rides + Platform review)*
- [ ] Approved driver can switch into driver mode
- [ ] Non-driver users do not see driver mode toggle
- [ ] Switching mode does not break routing or auth state
- [ ] Header/tab labels recolor for driver mode

## 6. ChopWallet top-up (request)  *(ChopWallet)*
- [ ] Customer can open `TopUpOrangeMoney`
- [ ] Customer sees the active configured OM receiving number
- [ ] Customer can create a top-up request via `wallet_topup_om_create`
- [ ] Request appears in `list_my_topup_requests` with correct status

## 7. Customer-first OM reconciliation  *(ChopWallet)*
- [ ] Customer pastes OM code via `submit_customer_om_code`
- [ ] When matching admin receipt is present, `om_auto_match` credits exactly once
- [ ] Customer sees confirmed status via `get_my_topup_om_status`
- [ ] Wallet balance updates through `wallet_topup_om_credit` only

## 8. Admin-first OM reconciliation  *(ChopWallet + Admin shell)*
- [ ] Admin can enter OM receipt in `WalletReconciliation`
- [ ] When matching customer code arrives later, auto-match credits exactly once
- [ ] Receipt without a customer code stays in the awaiting-customer queue
- [ ] No silent credit without a matching pair

## 9. Wallet mismatch / duplicate protection  *(ChopWallet)*
- [ ] Duplicate OM reference cannot credit twice
- [ ] Amount mismatch creates a conflict, not a credit
- [ ] Conflict appears in the admin reconciliation queue
- [ ] No frontend code path mutates `wallets` or `wallet_transactions` directly

## 10. Admin real-data-only check  *(Admin & Operations)*
- [ ] Every admin tab renders real data, an honest empty state, or "À connecter"
- [ ] No mock arrays, no placeholder users, no fake KPIs
- [ ] Command center counts match underlying tables
- [ ] Support, risk, reports, live ops all sourced from real tables

## 11. Account deletion / test account cleanup  *(Platform, QA & Security)*
- [ ] God-admin can hard-delete a clean test account via `admin-delete-user`
- [ ] Account with financial history is anonymized, not deleted
- [ ] Edge function returns structured JSON errors that surface in the UI
- [ ] Service-role key remains server-only
- [ ] Self-deletion request path still works

## 12. Maps / auth fallback  *(Platform, QA & Security)*
- [ ] `maps-config` requires auth and rate-limits correctly
- [ ] When maps fail, UI degrades gracefully (no white screen)
- [ ] Location permission prompt behaves per `PermissionCenter`
- [ ] Driver online still blocked when location is denied

## 13. Under Construction popup + signup nudge sequencing  *(Platform, QA & Security)*
- [ ] Onboarding → ~1s → Under Construction popup appears
- [ ] Closing UC → ~10s → signup nudge appears (for eligible guests)
- [ ] Both modals never visible simultaneously
- [ ] Dismissal storage keys remain separate and do not cross-contaminate
- [ ] No interruption to auth, legal, driver application, booking, or active trip flows

## 14. Security scan review  *(Platform, QA & Security)*
- [ ] No Error-level findings open
- [ ] No P0 / P1 findings open
- [ ] Any ignored finding has a justification in security memory
- [ ] RLS posture reviewed for `wallets`, `wallet_transactions`, `topup_requests`, `driver_applications`, `profiles`, `user_pins`
- [ ] No raw sensitive SELECT policies added to silence the scanner

---

## Sign-off

- [ ] All 14 sections passed
- [ ] Build clean (typecheck + bundle)
- [ ] Release captain approval recorded