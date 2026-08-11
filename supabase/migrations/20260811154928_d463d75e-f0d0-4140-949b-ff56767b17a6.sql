CREATE TABLE IF NOT EXISTS public._qa_s12_results (
  seq serial primary key, id text, ok boolean, detail text
);
TRUNCATE public._qa_s12_results;

DO $qa$
DECLARE
  ADMIN uuid := '2e547148-69f3-43f6-80f8-264de2d8fa67';
  CLIENTU uuid := '0c9fe3ba-bb2c-4067-95d2-4006e5fbcb09';
  STOREID uuid := '7e6613d1-9956-4522-88d9-1aa5e0ed0e6b';
  b jsonb; a jsonb; ex jsonb;
  po_id uuid;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', ADMIN, 'role','authenticated')::text, true);

  b := public.finance_treasury_overview();

  -- ============ E. SECURITY ============
  INSERT INTO public._qa_s12_results(id, ok, detail) VALUES
   ('E1_anon_denied_overview',
    NOT has_function_privilege('anon','public.finance_treasury_overview()','EXECUTE'),
    'anon EXECUTE on finance_treasury_overview'),
   ('E2_anon_denied_exceptions',
    NOT has_function_privilege('anon','public.finance_treasury_exceptions()','EXECUTE'),
    'anon EXECUTE on finance_treasury_exceptions'),
   ('E3_anon_denied_drilldown',
    NOT has_function_privilege('anon','public.finance_treasury_drilldown(text,int)','EXECUTE'),
    'anon EXECUTE on finance_treasury_drilldown'),
   ('E4_facts_service_role_only',
    NOT has_function_privilege('authenticated','public._finance_treasury_facts()','EXECUTE')
    AND NOT has_function_privilege('anon','public._finance_treasury_facts()','EXECUTE'),
    'raw fact primitive restricted to service_role'),
   ('E5_no_null_uid_shortcut',
    NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace nsp ON nsp.oid=p.pronamespace
                WHERE nsp.nspname='public'
                  AND p.proname IN ('finance_treasury_overview','finance_treasury_exceptions',
                                    'finance_treasury_drilldown','_finance_treasury_gate')
                  AND p.prosrc ~* 'IS NULL[[:space:]]+OR'),
    'no auth.uid() IS NULL privilege shortcut in new treasury functions'),
   ('E6_gate_enforced_in_bodies',
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace nsp ON nsp.oid=p.pronamespace
      WHERE nsp.nspname='public'
        AND p.proname IN ('finance_treasury_overview','finance_treasury_exceptions','finance_treasury_drilldown')
        AND p.prosrc LIKE '%_finance_treasury_gate()%') = 3,
    'all three public treasury RPCs call the role gate'),
   ('E7_search_path_fixed',
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace nsp ON nsp.oid=p.pronamespace
      WHERE nsp.nspname='public'
        AND p.proname IN ('finance_treasury_overview','finance_treasury_exceptions',
                          'finance_treasury_drilldown','_finance_treasury_gate','_finance_treasury_facts')
        AND array_to_string(p.proconfig,',') LIKE '%search_path=public%') = 5,
    'fixed search_path on all treasury functions'),
   ('E8_ledger_postings_closed',
    NOT has_table_privilege('authenticated','public.ledger_postings','INSERT')
    AND NOT has_table_privilege('authenticated','public.ledger_postings','UPDATE')
    AND NOT has_table_privilege('anon','public.ledger_postings','SELECT'),
    'raw ledger mutation primitives remain closed to app roles'),
   ('E9_admin_can_read',
    b ? 'verified_assets_gnf',
    'god_admin session received the treasury overview');

  -- ============ F. PRE-STATE ============
  INSERT INTO public._qa_s12_results(id, ok, detail) VALUES
   ('F1_master_wallet_frozen',
    (b->>'master_wallet_balance_gnf')::bigint = -100435
      AND (b->>'master_wallet_held_gnf')::bigint = 0,
    'DEF-FIN-001 master wallet reported as -100435 / held 0'),
   ('F2_stage_flags_off',
    NOT (SELECT enabled FROM public.feature_flags WHERE key='merchant_om_settlement_enabled')
    AND NOT (SELECT enabled FROM public.feature_flags WHERE key='driver_cashout_enabled')
    AND NOT (SELECT enabled FROM public.feature_flags WHERE key='chop_pay_p2p_enabled'),
    'Stage 5/6/7 remain OFF'),
   ('F3_om_topup_on',
    (SELECT enabled FROM public.feature_flags WHERE key='om_topup_enabled'),
    'om_topup_enabled remains ON'),
   ('F4_all_journals_zero_sum',
    NOT EXISTS (
      SELECT 1 FROM public.ledger_journals j
      LEFT JOIN public.ledger_postings p ON p.journal_id=j.id
      GROUP BY j.id HAVING COALESCE(SUM(p.amount_gnf),0) <> 0),
    'every journal sums to zero');

  -- ============ B. BASELINE EXCEPTIONS ============
  SELECT jsonb_agg(jsonb_build_object('code',code,'amount',amount_gnf,'sev',severity,'acct',account_code))
    INTO ex FROM public.finance_treasury_exceptions();

  INSERT INTO public._qa_s12_results(id, ok, detail) VALUES
   ('B1_coverage_named_and_exact',
    EXISTS (SELECT 1 FROM jsonb_array_elements(ex) e
            WHERE e->>'code' IN ('TREASURY_SHORTFALL','TREASURY_SURPLUS')
              AND (e->>'amount')::bigint =
                  (b->>'verified_assets_gnf')::bigint - (b->>'covered_obligations_gnf')::bigint),
    'coverage delta emitted as named, exactly-quantified exception'),
   ('B2_wallet_ledger_mismatch_customer',
    EXISTS (SELECT 1 FROM jsonb_array_elements(ex) e
            WHERE e->>'code'='WALLET_LEDGER_MISMATCH' AND e->>'acct'='L_CUSTOMER_CHOPPAY'
              AND (e->>'amount')::bigint = (b->>'total_customer_liability_gnf')::bigint),
    'pre-ledger customer wallet balances surfaced as explicit mismatch'),
   ('B3_wallet_ledger_mismatch_driver',
    EXISTS (SELECT 1 FROM jsonb_array_elements(ex) e
            WHERE e->>'code'='WALLET_LEDGER_MISMATCH' AND e->>'acct'='L_DRIVER_UNRESTRICTED'),
    'driver wallet vs ledger mismatch surfaced'),
   ('B4_provider_clearing_mismatch',
    EXISTS (SELECT 1 FROM jsonb_array_elements(ex) e WHERE e->>'code'='PROVIDER_CLEARING_MISMATCH'),
    'provider clearing mismatch surfaced'),
   ('B5_master_deficit_exception',
    EXISTS (SELECT 1 FROM jsonb_array_elements(ex) e
            WHERE e->>'code'='MASTER_WALLET_DEFICIT' AND (e->>'amount')::bigint = -100435),
    'DEF-FIN-001 surfaced as its own exception, not normalized'),
   ('B6_no_balancing_plug',
    NOT EXISTS (SELECT 1 FROM jsonb_array_elements(ex) e
                WHERE e->>'code' ILIKE '%ADJUST%' OR e->>'code' ILIKE '%PLUG%'),
    'no inferred adjustment / balancing plug class exists'),
   ('B7_coverage_not_forced_zero',
    (b->>'treasury_coverage_delta_gnf')::bigint <> 0,
    'treasury coverage delta reported truthfully, not forced to zero');

  -- ============ A1: credited top-up = asset, not revenue ============
  INSERT INTO public.topup_requests(reference, client_user_id, amount_gnf, confirmation_code,
                                    status, provider, environment, expires_at)
  VALUES ('QA_S12_TOPUP_CREDITED', CLIENTU, 700000, 'QA12A', 'credited','orange_money','production', now()+interval '1 day');
  a := public.finance_treasury_overview();
  INSERT INTO public._qa_s12_results(id, ok, detail) VALUES
   ('A1_topup_is_asset_not_revenue',
    (a->>'verified_assets_gnf')::bigint = (b->>'verified_assets_gnf')::bigint + 700000
    AND (a->>'captured_revenue_gnf')::bigint = (b->>'captured_revenue_gnf')::bigint,
    'credited top-up raised assets by exactly 700000 and revenue by 0'),
   ('A1b_topup_shifts_coverage_exactly',
    (a->>'treasury_coverage_delta_gnf')::bigint
      = (b->>'treasury_coverage_delta_gnf')::bigint + 700000,
    'coverage delta moved by exactly the asset amount'),
   ('B8_named_exception_tracks_fixture',
    EXISTS (SELECT 1 FROM public.finance_treasury_exceptions() e
            WHERE e.code IN ('TREASURY_SHORTFALL','TREASURY_SURPLUS')
              AND e.amount_gnf = (a->>'treasury_coverage_delta_gnf')::bigint),
    'named coverage exception reflects the exact new signed delta');
  DELETE FROM public.topup_requests WHERE reference='QA_S12_TOPUP_CREDITED';

  -- ============ C1: inbound needs_review ============
  INSERT INTO public.topup_requests(reference, client_user_id, amount_gnf, confirmation_code,
                                    status, provider, environment, expires_at, review_reason)
  VALUES ('QA_S12_TOPUP_REVIEW', CLIENTU, 55000, 'QA12C', 'needs_review','orange_money','production',
          now()+interval '1 day','qa amount mismatch');
  a := public.finance_treasury_overview();
  INSERT INTO public._qa_s12_results(id, ok, detail) VALUES
   ('C1_inbound_needs_review_no_credit',
    (a->>'inbound_om_unreconciled_gnf')::bigint = (b->>'inbound_om_unreconciled_gnf')::bigint + 55000
    AND (a->>'inbound_om_unreconciled_count')::int = (b->>'inbound_om_unreconciled_count')::int + 1
    AND (a->>'total_customer_liability_gnf')::bigint = (b->>'total_customer_liability_gnf')::bigint
    AND (a->>'verified_assets_gnf')::bigint = (b->>'verified_assets_gnf')::bigint,
    'needs_review inbound queued with zero wallet credit and zero asset recognition'),
   ('C1b_inbound_exception_and_drilldown',
    EXISTS (SELECT 1 FROM public.finance_treasury_exceptions() e WHERE e.code='INBOUND_OM_UNRECONCILED')
    AND EXISTS (SELECT 1 FROM public.finance_treasury_drilldown('INBOUND_OM_UNRECONCILED',200) d
                WHERE d.ref='QA_S12_TOPUP_REVIEW' AND d.amount_gnf=55000),
    'exception drills down to the exact source top-up row');
  DELETE FROM public.topup_requests WHERE reference='QA_S12_TOPUP_REVIEW';

  -- ============ A2 / B9: merchant payable ============
  INSERT INTO public.merchant_payables(payable_key, source_module, source_id, merchant_store_id,
                                       subtotal_gnf, amount_gnf, funded_gnf, state, funding_source)
  VALUES ('QA_S12_PAYABLE','repas', gen_random_uuid(), STOREID, 300000, 300000, 300000, 'funded','customer_choppay');
  a := public.finance_treasury_overview();
  INSERT INTO public._qa_s12_results(id, ok, detail) VALUES
   ('A2_payable_is_liability_not_revenue',
    (a->>'total_merchant_liability_gnf')::bigint = (b->>'total_merchant_liability_gnf')::bigint + 300000
    AND (a->>'merchant_payable_outstanding_gnf')::bigint = (b->>'merchant_payable_outstanding_gnf')::bigint + 300000
    AND (a->>'captured_revenue_gnf')::bigint = (b->>'captured_revenue_gnf')::bigint,
    'merchant payable classified as obligation, revenue unchanged'),
   ('B9_merchant_payable_mismatch_named',
    EXISTS (SELECT 1 FROM public.finance_treasury_exceptions() e
            WHERE e.code='MERCHANT_PAYABLE_MISMATCH'
              AND e.amount_gnf = (a->>'merchant_payable_outstanding_gnf')::bigint),
    'payable vs ledger difference emitted as explicit named exception');

  -- ============ A5: reservation is not a debit ============
  INSERT INTO public.payout_orders(order_key, party_type, party_user_id, merchant_store_id, source_kind,
     provider, destination_msisdn, environment, requested_principal_gnf, provider_fee_gnf,
     fee_borne_by, merchant_liability_debit_gnf, recipient_net_gnf, reservation_gnf,
     expected_provider_transfer_gnf, status)
  VALUES ('QA_S12_PAYOUT','merchant', ADMIN, STOREID, 'merchant_settlement','orange_money','+224620000001',
     'production', 200000, 0, 'recipient', 200000, 200000, 200000, 200000, 'reserved')
  RETURNING id INTO po_id;
  a := public.finance_treasury_overview();
  INSERT INTO public._qa_s12_results(id, ok, detail) VALUES
   ('A5_reservation_not_a_debit',
    (a->>'merchant_settlement_reserved_gnf')::bigint = (b->>'merchant_settlement_reserved_gnf')::bigint + 200000
    AND (a->>'merchant_payable_outstanding_gnf')::bigint = (b->>'merchant_payable_outstanding_gnf')::bigint + 300000
    AND (a->>'om_outbound_settled_gnf')::bigint = (b->>'om_outbound_settled_gnf')::bigint,
    'reservation raised reserved-only; payable untouched, no external payment');

  -- ============ C2 / C3: outbound evidence ============
  INSERT INTO public.payout_provider_evidence(payout_order_id, provider, provider_reference,
     recipient_msisdn, amount_gnf, fee_gnf, net_gnf, provider_status,
     environment, reconciliation_state, mismatch_reason)
  VALUES (po_id,'orange_money','QA-S12-EV-1','+224620000001', 199000, 0, 199000,
     'success','production','mismatch','amount_mismatch');
  a := public.finance_treasury_overview();
  INSERT INTO public._qa_s12_results(id, ok, detail) VALUES
   ('C2_outbound_mismatch_no_debit',
    (a->>'outbound_payout_unreconciled_gnf')::bigint = (b->>'outbound_payout_unreconciled_gnf')::bigint + 199000
    AND (a->>'outbound_payout_unreconciled_count')::int = (b->>'outbound_payout_unreconciled_count')::int + 1
    AND (a->>'merchant_payable_outstanding_gnf')::bigint = (b->>'merchant_payable_outstanding_gnf')::bigint + 300000
    AND (a->>'om_outbound_settled_gnf')::bigint = (b->>'om_outbound_settled_gnf')::bigint,
    'mismatched outbound evidence queued with zero payable debit and zero outbound cash'),
   ('C2b_outbound_drilldown_traceable',
    EXISTS (SELECT 1 FROM public.finance_treasury_drilldown('OUTBOUND_PAYOUT_UNRECONCILED',200) d
            WHERE d.source_ref = po_id::text AND d.amount_gnf = 199000),
    'outbound exception traces to evidence + payout order');

  UPDATE public.payout_provider_evidence
     SET reconciliation_state='reconciled', mismatch_reason=NULL
   WHERE provider_reference='QA-S12-EV-1';
  a := public.finance_treasury_overview();
  INSERT INTO public._qa_s12_results(id, ok, detail) VALUES
   ('C3_reconciled_leaves_queue',
    (a->>'outbound_payout_unreconciled_gnf')::bigint = (b->>'outbound_payout_unreconciled_gnf')::bigint
    AND (a->>'outbound_payout_unreconciled_count')::int = (b->>'outbound_payout_unreconciled_count')::int
    AND NOT EXISTS (SELECT 1 FROM public.finance_treasury_drilldown('OUTBOUND_PAYOUT_UNRECONCILED',200) d
                    WHERE d.source_ref = po_id::text),
    'reconciled evidence disappears from mismatch queue'),
   ('C4_reference_uniqueness_preserved',
    EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
            AND tablename='payout_provider_evidence' AND indexdef ILIKE '%unique%'
            AND indexdef ILIKE '%normalized_reference%'),
    'one-reference-one-settlement uniqueness index still enforced');

  DELETE FROM public.payout_provider_evidence WHERE provider_reference='QA-S12-EV-1';
  DELETE FROM public.payout_orders WHERE order_key='QA_S12_PAYOUT';
  DELETE FROM public.merchant_payables WHERE payable_key='QA_S12_PAYABLE';

  -- ============ A3: promo credit ============
  INSERT INTO public.driver_promo_credits(driver_user_id, grant_key, granted_gnf, state)
  VALUES (ADMIN,'QA_S12_PROMO', 25000, 'active');
  a := public.finance_treasury_overview();
  INSERT INTO public._qa_s12_results(id, ok, detail) VALUES
   ('A3_promo_separately_identifiable',
    (a->>'promotional_credit_liability_gnf')::bigint = (b->>'promotional_credit_liability_gnf')::bigint + 25000
    AND (a->>'captured_revenue_gnf')::bigint = (b->>'captured_revenue_gnf')::bigint
    AND (a->>'verified_assets_gnf')::bigint = (b->>'verified_assets_gnf')::bigint,
    'restricted promo obligation tracked separately, never asset or revenue'),
   ('A3b_promo_excluded_from_cash_cover',
    (a->>'covered_obligations_gnf')::bigint = (b->>'covered_obligations_gnf')::bigint - 25000,
    'platform-funded promo excluded from cash-backed obligations');
  DELETE FROM public.driver_promo_credits WHERE grant_key='QA_S12_PROMO';

  -- ============ A4: cancellation debt ============
  INSERT INTO public.customer_cancellation_debts(debt_key, customer_user_id, source_module, source_id,
     mission_type, stage, basis_gnf, applied_bps, amount_gnf, state)
  VALUES ('QA_S12_DEBT', CLIENTU, 'ride', gen_random_uuid(), 'ride','after_dispatch', 40000, 2500, 10000, 'outstanding');
  a := public.finance_treasury_overview();
  INSERT INTO public._qa_s12_results(id, ok, detail) VALUES
   ('A4_debt_is_receivable_not_cash',
    (a->>'cancellation_debt_receivable_gnf')::bigint = (b->>'cancellation_debt_receivable_gnf')::bigint + 10000
    AND (a->>'verified_assets_gnf')::bigint = (b->>'verified_assets_gnf')::bigint
    AND (a->>'captured_revenue_gnf')::bigint = (b->>'captured_revenue_gnf')::bigint,
    'cancellation debt raised receivable only — no cash, no revenue');
  UPDATE public.customer_cancellation_debts SET paid_gnf=4000, waived_gnf=1000 WHERE debt_key='QA_S12_DEBT';
  a := public.finance_treasury_overview();
  INSERT INTO public._qa_s12_results(id, ok, detail) VALUES
   ('A4b_debt_collected_waived_outstanding',
    (a->>'cancellation_debt_collected_gnf')::bigint = (b->>'cancellation_debt_collected_gnf')::bigint + 4000
    AND (a->>'cancellation_debt_waived_gnf')::bigint = (b->>'cancellation_debt_waived_gnf')::bigint + 1000
    AND (a->>'cancellation_debt_receivable_gnf')::bigint = (b->>'cancellation_debt_receivable_gnf')::bigint + 5000,
    'collected / waived / outstanding split reported from source truth');
  DELETE FROM public.customer_cancellation_debts WHERE debt_key='QA_S12_DEBT';

  -- ============ A6: revenue only from captured ledger ============
  a := public.finance_treasury_overview();
  INSERT INTO public._qa_s12_results(id, ok, detail) VALUES
   ('A6_revenue_only_from_captured_ledger',
    (a->>'captured_revenue_gnf')::bigint =
      (a#>>'{captured_revenue_breakdown,ride_commission_gnf}')::bigint
    + (a#>>'{captured_revenue_breakdown,transaction_fee_gnf}')::bigint
    + (a#>>'{captured_revenue_breakdown,cancellation_fee_gnf}')::bigint
    + (a#>>'{captured_revenue_breakdown,recovered_collateral_gnf}')::bigint
    AND (a->>'captured_revenue_gnf')::bigint =
      COALESCE((SELECT -SUM(amount_gnf) FROM public.ledger_postings
                WHERE account_code LIKE 'R\_%'),0),
    'captured revenue equals sum of R_* ledger accounts and its own breakdown');

  -- ============ D. CLAIMS ============
  INSERT INTO public.claims_reserves(claim_key, source_module, source_id,
     declared_value_gnf, authorized_gnf, state, evidence_ref, reason, authorized_by)
  VALUES ('QA_S12_CLAIM','envoyer', gen_random_uuid(),
     400000, 300000, 'allocated','QA-S12-CLAIM','qa fixture', ADMIN);
  a := public.finance_treasury_overview();
  INSERT INTO public._qa_s12_results(id, ok, detail) VALUES
   ('D1_open_claim_raises_exposure',
    (a->>'open_claims_exposure_gnf')::bigint = (b->>'open_claims_exposure_gnf')::bigint + 400000
    AND (a->>'recognized_claims_obligation_gnf')::bigint = (b->>'recognized_claims_obligation_gnf')::bigint + 300000
    AND (a->>'total_customer_liability_gnf')::bigint = (b->>'total_customer_liability_gnf')::bigint,
    'open claim raised exposure + recognized reserve without a paid liability'),
   ('D2_claim_reserve_mismatch_named',
    EXISTS (SELECT 1 FROM public.finance_treasury_exceptions() e
            WHERE e.code='CLAIM_RESERVE_MISMATCH'
              AND e.amount_gnf = (a->>'recognized_claims_obligation_gnf')::bigint),
    'claims reserve vs ledger difference emitted as named exception'),
   ('D3_claim_drilldown',
    EXISTS (SELECT 1 FROM public.finance_treasury_drilldown('CLAIM_RESERVE_MISMATCH',200) d
            WHERE d.ref='QA_S12_CLAIM' AND d.amount_gnf=300000),
    'claim exception drills down to the source claim');
  UPDATE public.claims_reserves SET state='paid', paid_gnf=300000 WHERE claim_key='QA_S12_CLAIM';
  a := public.finance_treasury_overview();
  INSERT INTO public._qa_s12_results(id, ok, detail) VALUES
   ('D4_settled_claim_clears_exposure',
    (a->>'open_claims_exposure_gnf')::bigint = (b->>'open_claims_exposure_gnf')::bigint
    AND (a->>'recognized_claims_obligation_gnf')::bigint = (b->>'recognized_claims_obligation_gnf')::bigint
    AND (a->>'claims_paid_gnf')::bigint = (b->>'claims_paid_gnf')::bigint + 300000,
    'settled claim leaves exposure and moves to paid'),
   ('D5_declared_value_policy_intact',
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
            AND table_name='claims_reserves' AND column_name='declared_value_gnf')
    AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
            AND table_name='package_deliveries' AND column_name='declared_value_gnf'),
    'Slice 6 declared-value schema untouched');
  DELETE FROM public.claims_reserves WHERE claim_key='QA_S12_CLAIM';

  -- ============ F. POST-STATE ============
  a := public.finance_treasury_overview();
  INSERT INTO public._qa_s12_results(id, ok, detail) VALUES
   ('F5_no_fixture_residue',
    NOT EXISTS (SELECT 1 FROM public.topup_requests WHERE reference LIKE 'QA\_S12%')
    AND NOT EXISTS (SELECT 1 FROM public.merchant_payables WHERE payable_key LIKE 'QA\_S12%')
    AND NOT EXISTS (SELECT 1 FROM public.payout_orders WHERE order_key LIKE 'QA\_S12%')
    AND NOT EXISTS (SELECT 1 FROM public.payout_provider_evidence WHERE provider_reference LIKE 'QA-S12%')
    AND NOT EXISTS (SELECT 1 FROM public.claims_reserves WHERE claim_key LIKE 'QA\_S12%')
    AND NOT EXISTS (SELECT 1 FROM public.customer_cancellation_debts WHERE debt_key LIKE 'QA\_S12%')
    AND NOT EXISTS (SELECT 1 FROM public.driver_promo_credits WHERE grant_key LIKE 'QA\_S12%'),
    'all fixtures rolled back'),
   ('F6_overview_returned_to_baseline',
    a = jsonb_set(b,'{generated_at}', a->'generated_at'),
    'post-run treasury snapshot identical to baseline'),
   ('F7_master_wallet_unchanged',
    (SELECT balance_gnf FROM public.wallets WHERE party_type='master') = -100435
    AND (SELECT held_gnf FROM public.wallets WHERE party_type='master') = 0,
    'master wallet untouched by the harness'),
   ('F8_no_outbound_money',
    (a->>'om_outbound_settled_gnf')::bigint = (b->>'om_outbound_settled_gnf')::bigint
    AND (SELECT COALESCE(SUM(settled_gnf),0) FROM public.payout_orders) = 0,
    'zero outbound money moved');

  PERFORM set_config('request.jwt.claims', '', true);
END
$qa$;