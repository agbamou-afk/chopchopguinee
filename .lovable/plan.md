# Node 5 Final Closeout — Sequential Execution Plan (A → E)

Scope: close out Node 5. No A15, no new architecture, no invented finance law. Each step has a STOP/GO gate; a failed gate stops the sequence and downgrades the final verdict rather than being worked around.

Pre-plan facts confirmed read-only this session:
- `account_access_terminations` holds **14 pending rows**, not 6: the 6 real legacy closed accounts (all `profiles.account_status='deleted'`) plus **8 rows whose profile no longer exists** (QA-fixture users rolled back). The worker will record those 8 as `ACCOUNT_NOT_CLOSED` failures, which would leave permanent non-zero `failed` noise in the final census. This is queue hygiene, and it is a new finding not yet in the closeout doc.
- Wallet columns are `owner_user_id` / `balance_gnf` / `held_gnf` (naming matters for step C queries).
- Existing money primitives: `wallet_internal_transfer`, `wallet_internal_transfer_v2`, `wallet_admin_credit` (credit only), `driver_payout_request_create` / `driver_cashout_create_request` / `_payout_order_create_internal` / `finance_confirm_manual_om_payout`, `chop_pay_customer_refund`, `admin_promotional_credit_treasury`. Whether any is lawful for an involuntary balance on a closed account is exactly what step C decides — it is not assumed here.

---

## Step A — Docs-only closeout refresh (verdict unchanged)

- **Inputs / read-only checks:** current `docs/identity/NODE5_FINAL_CLOSEOUT.md`; re-read live census (closed-account lanes, roles, driver status/presence, ride offers, recovery rows, governance rows, ledger posting count/sum); `_qa_node5_identity_final_remediation` last measured result; full-board count; queue row breakdown above.
- **Permitted mutation:** `docs/identity/NODE5_FINAL_CLOSEOUT.md` only. No code, DB, migration, policy, function, harness or live row.
- **Content:** replace the stale pre-remediation census with the post-remediation one; record the remediation surface (`auth_uid_active`, `pgrst_pre_request`, `admin_account_closure_reconcile`, termination queue + worker); record removal of the temporary harness token slot and one-time runner; record the corrected census predicates; record the 14-vs-6 queue finding; restate both open blockers verbatim. **Verdict stays HOLD** in this step — A never upgrades a verdict.
- **Evidence:** doc diff plus the read-only query outputs quoted inside it; `git status --porcelain` clean after commit.
- **Rollback / fail-closed:** docs-only, revert the file. If any census query disagrees with the claimed certified state, write the discrepancy into the doc as a new blocker and stop the sequence.
- **GO condition:** doc reflects measured current state, no unverified claim, tree clean.

## Step B — Prove actual auth termination (or name the exact blocker)

- **Inputs / read-only checks:** `supabase/functions/account-access-termination-worker/index.ts`; `supabase/config.toml` `verify_jwt` for that function; queue rows; per-user auth state before invocation (banned-until, credentials, sessions) read through the sanctioned admin path.
- **Permitted mutation:** invoking the deployed worker against the **6 real closed accounts only**; the auth-side ban + session/refresh revocation it performs; the queue rows it records. Nothing else. Do not hand-edit `account_access_terminations`, do not touch `auth` schema directly, do not create a new token, do not relax `verify_jwt`, do not broaden the worker's authority.
- **Sanctioned invocation paths, in order:** (1) service-role invocation if a service-role path is available to this session without minting a new credential; (2) an active `god_admin` / `operations_admin` session obtained through the sanctioned session-minting flow with user approval. If neither is available, stop.
- **Queue hygiene sub-decision:** the 8 profile-less rows must be resolved before the queue can ever read clean. Preferred order — first confirm those 8 `auth.users` rows genuinely no longer exist; if they do not, the correct fix is a small governed change so the worker/record path classifies a non-existent user as *already inaccessible / terminated* rather than `ACCOUNT_NOT_CLOSED`, since access is provably impossible. If that requires a code or function change, it is proposed and gated, not slipped in. Never delete queue rows to make a census look clean.
- **Evidence required:** for each of the 6 — worker response body, post-run `banned_until` populated on the auth user, sessions count 0, and `account_access_terminations.status='terminated'`. Queue state alone is explicitly **not** accepted as proof.
- **Rollback / fail-closed:** banning is reversible via the same admin API if a wrong target is hit; the worker already refuses any target that is not `account_status='deleted'`. On partial success, record exactly which UUIDs are proven and which are not.
- **GO condition:** all 6 show ban + zero sessions + `terminated`, with evidence captured. Otherwise blocker 1 stays open, is written up with the exact reason (e.g. "no sanctioned service-role or admin session obtainable in this context"), and the sequence continues to C with LOCK already impossible.

## Step C — Finance-law audit of the 29,448 GNF (audit-only)

- **Inputs / read-only checks:** the wallet row (`owner_user_id`, `party_type`, `balance_gnf`, `held_gnf`, `status`), its `wallet_transactions` and ledger postings; the source definitions of every candidate primitive listed above; `docs/product/chop-pay-canonical-operating-policy.md` and `docs/finance/CHOPCHOP_FINANCE_POLICY_FREEZE.md`; the flags gating payout/cashout rails; `_account_closure_blockers` behaviour for `WALLET_BALANCE_NONZERO`.
- **Permitted mutation:** **none.** This step is audit-only by design. No balance change, no ledger entry, no new function, no new flag.
- **Test each candidate against four questions:** (1) does it already exist and is it enabled; (2) is it lawful for an *involuntary* disposition on a *closed* account, or does it require the account holder to initiate; (3) does it keep the ledger balanced with full provenance; (4) is a governance actor authorised to trigger it today. A "yes" on all four is a lawful path; anything less is not.
- **Evidence:** a short table of candidate → verdict → the code/policy line that decides it.
- **Rollback / fail-closed:** nothing to roll back. If no candidate passes all four, the blocker stands and the correct outcome is a documented gap plus a named future decision owner — not an invented sweep, transfer, zeroing or "unclaimed funds" account.
- **GO condition for closing blocker 2:** a lawful existing path is identified **and** the user explicitly approves executing it as a separate step. Absent that, blocker 2 remains open.

## Step D — Final micro-certification + linter delta audit

- **Inputs:** `_qa_node5_identity_final_remediation`, the Node 5 A2–A14 suites, and the full board; DB/security linter; `tsgo --noEmit`; vitest; production build.
- **Permitted mutation:** none beyond test/QA execution. If a suite fails, fix the smallest lawful cause or report it — do not adjust an assertion to make it pass.
- **Linter:** enumerate all 662 findings and prove the +4 vs the accepted A14 baseline of 658 is exactly the new remediation surface (`pgrst_pre_request`, the remediation QA function, and the closure/termination helpers), each a signed-in-executable `SECURITY DEFINER` warning of the already-accepted class — not a new exposure. If any of the 4 is a different class, it becomes a blocker.
- **Evidence:** suite counts with 0 failures, the per-finding +4 attribution list, gate results.
- **GO condition:** 0 assertion failures, +4 fully attributed and accepted-class, gates green.

## Step E — Verdict

- **LOCK** only if blocker 1 is proven closed in B **and** blocker 2 is genuinely closed in C (lawful path found *and* executed under approval), and D is green.
- Otherwise **HOLD**, with the residual blockers stated exactly and per-UUID, plus what specifically would close each. A legacy or environmental blocker is still a live blocker; it is not accepted debt.
- Final doc update to `docs/identity/NODE5_FINAL_CLOSEOUT.md` carries the verdict, the evidence, and the confirmed clean tree.

---

## Technical notes

- Worker authority model is already service-role or active `god_admin`/`operations_admin`; no change is proposed to it.
- The known boundary stays documented: banning plus refresh revocation stops new and refreshed tokens, while an already-issued access JWT remains cryptographically valid until expiry — `auth_uid_active()` on RLS surfaces and the `pgrst_pre_request` hook cover that window.
- Steps run strictly A → B → C → D → E. B's outcome does not block C or D from running; it only constrains E.
