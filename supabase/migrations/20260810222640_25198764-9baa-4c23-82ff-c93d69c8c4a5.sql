CREATE OR REPLACE FUNCTION public._qa_s5_run4()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  r jsonb := '[]'::jsonb; v_pass int; v_total int;
  v_master_before bigint; v_master_after bigint;
  v_cust uuid; v_cust2 uuid; v_drv uuid; v_own uuid; v_own2 uuid; v_rando uuid;
  v_store uuid; v_store2 uuid; v_rest uuid; v_fo uuid; v_ms uuid;
  v_j jsonb; v_err text; v_n bigint; v_b bigint; v_b2 bigint;
BEGIN
  SELECT balance_gnf INTO v_master_before FROM public.wallets WHERE party_type='master' LIMIT 1;
  BEGIN
    v_cust:=gen_random_uuid(); v_cust2:=gen_random_uuid(); v_drv:=gen_random_uuid();
    v_own:=gen_random_uuid(); v_own2:=gen_random_uuid(); v_rando:=gen_random_uuid();
    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,capabilities)
      VALUES (v_drv,'approved','moto',ARRAY['repas_delivery','marche_delivery']);
    INSERT INTO public.wallets(owner_user_id,party_type,balance_gnf)
      VALUES (v_drv,'driver',9000000),(v_cust,'client',9000000),(v_cust2,'client',9000000);
    INSERT INTO public.merchant_stores(owner_user_id,slug,name,status,onboarding_status)
      VALUES (v_own,'qa-s5d-'||substr(v_own::text,1,8),'QA S5D Store','active','approved') RETURNING id INTO v_store;
    INSERT INTO public.merchant_stores(owner_user_id,slug,name,status,onboarding_status)
      VALUES (v_own2,'qa-s5d2-'||substr(v_own2::text,1,8),'QA S5D Store2','active','approved') RETURNING id INTO v_store2;
    INSERT INTO public.food_restaurants(slug,name,owner_user_id,merchant_store_id,status)
      VALUES ('qa-s5d-r-'||substr(v_own::text,1,8),'QA S5D Resto',v_own,v_store,'active') RETURNING id INTO v_rest;
    UPDATE public.feature_flags SET enabled=true WHERE key IN ('chop_pay_checkout_enabled','cancellation_policy_enabled');

    -- N. FROZEN ECONOMICS SURVIVE A NEW EFFECTIVE-DATED POLICY
    INSERT INTO public.food_orders(user_id,restaurant_id,fulfillment,payment_method,subtotal_gnf)
      VALUES (v_cust,v_rest,'delivery','choppay',150000) RETURNING id INTO v_fo;
    INSERT INTO public.missions(type,customer_id,ref_food_order_id,estimated_earning_gnf,merchant_store_id)
      VALUES ('food_delivery',v_cust,v_fo,25000,v_store) RETURNING id INTO v_ms;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    PERFORM public.chop_pay_authorize_order('repas', v_fo);
    BEGIN
      UPDATE public.finance_policies SET transaction_fee_bps = 500 WHERE mission_type='repas';
      r := r || public._qa_s5_ok('N0 applied finance policy rows are immutable', false, 'update succeeded');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('N0 applied finance policy rows are immutable', true, v_err);
    END;
    INSERT INTO public.finance_policies (mission_type, commission_bps, fixed_commission_gnf, min_driver_balance_gnf,
      collateral_mode, collateral_pct_bps, collateral_fixed_gnf, collateral_min_gnf, collateral_max_gnf,
      require_collateral_before_offer, effective_from, enabled, note, transaction_fee_bps, fee_basis,
      cash_funding_mode, cash_funding_pct_bps, cash_funding_max_gnf, cancel_before_dispatch_bps,
      cancel_after_dispatch_bps, max_declared_value_gnf, cancel_basis, collateral_basis, claims_exposure_max_gnf)
    SELECT mission_type, commission_bps, fixed_commission_gnf, min_driver_balance_gnf,
      collateral_mode, 9000, collateral_fixed_gnf, collateral_min_gnf, collateral_max_gnf,
      require_collateral_before_offer, now(), true, 'qa s5 future policy', 500, fee_basis,
      cash_funding_mode, cash_funding_pct_bps, cash_funding_max_gnf, 1500,
      2000, max_declared_value_gnf, cancel_basis, collateral_basis, claims_exposure_max_gnf
      FROM public.finance_policies WHERE mission_type='repas' ORDER BY effective_from DESC LIMIT 1;
    SELECT order_total_gnf, platform_fee_gnf INTO v_b, v_b2 FROM public.chop_pay_order_runtime WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('N1 authorized order economics stay frozen after a new policy takes effect',
      v_b = 176500 AND v_b2 = 1500, format('total=%s fee=%s',v_b,v_b2));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_ms);
    SELECT collateral_gnf INTO v_b FROM public.chop_pay_order_runtime WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('N2 collateral still uses the frozen 50% snapshot (not the new 90%)', v_b = 75000, v_b::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_j := public.chop_pay_customer_cancel('repas', v_fo, 'qa_frozen_basis');
    r := r || public._qa_s5_ok('N3 cancellation uses the frozen 10% after-dispatch basis, not the new 20%',
      (v_j->>'cancellation_charge_gnf')::bigint = 17500, v_j::text);

    -- O. CROSS-PARTICIPANT AUTHORIZATION MATRIX
    INSERT INTO public.food_orders(user_id,restaurant_id,fulfillment,payment_method,subtotal_gnf)
      VALUES (v_cust,v_rest,'delivery','choppay',150000) RETURNING id INTO v_fo;
    INSERT INTO public.missions(type,customer_id,ref_food_order_id,estimated_earning_gnf,merchant_store_id)
      VALUES ('food_delivery',v_cust,v_fo,25000,v_store) RETURNING id INTO v_ms;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    BEGIN
      PERFORM public.chop_pay_authorize_order('repas', v_fo);
      r := r || public._qa_s5_ok('O1 a customer cannot authorize another customer order', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('O1 a customer cannot authorize another customer order', true, v_err);
    END;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    PERFORM public.chop_pay_authorize_order('repas', v_fo);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    BEGIN
      PERFORM public.chop_pay_customer_cancel('repas', v_fo, 'qa_not_mine');
      r := r || public._qa_s5_ok('O2 a customer cannot cancel another customer order', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('O2 a customer cannot cancel another customer order', true, v_err);
    END;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_ms);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own2), true);
    BEGIN
      PERFORM public.chop_pay_merchant_accept('repas', v_fo);
      r := r || public._qa_s5_ok('O3 a merchant cannot capture another merchant order', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('O3 a merchant cannot capture another merchant order', true, v_err);
    END;
    BEGIN
      PERFORM public.chop_pay_merchant_prepare('repas', v_fo);
      r := r || public._qa_s5_ok('O4 a merchant cannot start preparation on another merchant order', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('O4 a merchant cannot start preparation on another merchant order', true, v_err);
    END;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_rando), true);
    BEGIN
      PERFORM public.chop_pay_customer_hold_place('repas', v_fo, 1000, 'repas', v_cust, false, '{}'::jsonb);
      r := r || public._qa_s5_ok('O5 an ordinary user cannot place a raw customer hold', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('O5 an ordinary user cannot place a raw customer hold', true, v_err);
    END;
    BEGIN
      PERFORM public.chop_pay_customer_capture('repas', v_fo, v_store, 150000, v_drv, 25000, 0, 1500, true);
      r := r || public._qa_s5_ok('O6 an ordinary user cannot drive a raw customer capture', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('O6 an ordinary user cannot drive a raw customer capture', true, v_err);
    END;

    -- Q. JOURNAL INVARIANTS
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j JOIN public.ledger_postings p ON p.journal_id=j.id
      GROUP BY j.id HAVING SUM(p.amount_gnf) <> 0) q;
    r := r || public._qa_s5_ok('Q1 every ledger journal balances to zero', v_n=0, v_n::text);
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j JOIN public.ledger_postings p ON p.journal_id=j.id
      GROUP BY j.id HAVING count(*) FILTER (WHERE p.amount_gnf <> 0) < 2) q;
    r := r || public._qa_s5_ok('Q2 every journal has at least two non-zero postings', v_n=0, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
      WHERE COALESCE(captured_gnf,0) + COALESCE(released_gnf,0) > amount_gnf;
    r := r || public._qa_s5_ok('Q3 captured + released never exceeds the reserved amount', v_n=0, v_n::text);
    SELECT count(*) INTO v_n FROM (
      SELECT reference FROM public.wallet_transactions WHERE reference IS NOT NULL
      GROUP BY reference HAVING count(*) > 1) q;
    r := r || public._qa_s5_ok('Q4 no duplicate financial reference exists', v_n=0, v_n::text);

    RAISE EXCEPTION 'QA_S5_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S5_ROLLBACK' THEN
      r := r || public._qa_s5_ok('HARNESS_PART4_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  SELECT balance_gnf INTO v_master_after FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || public._qa_s5_ok('Z0 master wallet naturally restored by rollback',
    v_master_after = v_master_before AND v_master_after = -100435, format('master=%s',v_master_after));
  SELECT count(*) INTO v_n FROM public.finance_policies WHERE note='qa s5 future policy';
  r := r || public._qa_s5_ok('Z1 no QA finance policy row survives the rollback', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-s5%';
  r := r || public._qa_s5_ok('Z2 no QA store residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.chop_pay_order_runtime;
  r := r || public._qa_s5_ok('Z3 no Chop Pay runtime residue', v_n=0, v_n::text);

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('total',v_total,'passed',v_pass,'failed',v_total-v_pass,
    'failures',(SELECT COALESCE(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(r) x WHERE NOT (x->>'ok')::boolean));
END; $fn$;

REVOKE ALL ON FUNCTION public._qa_s5_run4() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN INSERT INTO public._qa_s5_results(report) SELECT public._qa_s5_run4(); END $$;