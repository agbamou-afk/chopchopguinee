CREATE OR REPLACE FUNCTION public._qa_s5_run3()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $qa$
DECLARE
  r jsonb := '[]'::jsonb;
  v_pass int; v_total int;
  v_master_before bigint; v_master_after bigint; v_m0 bigint;
  v_cust uuid; v_cust2 uuid; v_drv uuid; v_own uuid; v_own2 uuid; v_adm uuid; v_rando uuid;
  v_store uuid; v_store2 uuid; v_rest uuid; v_listing uuid;
  v_fo uuid; v_ms uuid; v_off uuid; v_j jsonb; v_err text; v_txt text;
  v_n bigint; v_b bigint; v_b2 bigint; v_c0 bigint; v_mer0 bigint; v_mer1 bigint;
BEGIN
  SELECT balance_gnf INTO v_master_before FROM public.wallets WHERE party_type='master' LIMIT 1;

  BEGIN
    v_cust:=gen_random_uuid(); v_cust2:=gen_random_uuid(); v_drv:=gen_random_uuid();
    v_own:=gen_random_uuid(); v_own2:=gen_random_uuid(); v_adm:=gen_random_uuid(); v_rando:=gen_random_uuid();
    INSERT INTO public.admin_users(user_id, admin_role, status) VALUES (v_adm,'finance_admin','active');
    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,capabilities)
      VALUES (v_drv,'approved','moto',ARRAY['repas_delivery','marche_delivery']);
    INSERT INTO public.wallets(owner_user_id,party_type,balance_gnf)
      VALUES (v_drv,'driver',9000000),(v_cust,'client',9000000),(v_cust2,'client',9000000);
    INSERT INTO public.merchant_stores(owner_user_id,slug,name,status,onboarding_status)
      VALUES (v_own,'qa-s5c-'||substr(v_own::text,1,8),'QA S5C Store','active','approved') RETURNING id INTO v_store;
    INSERT INTO public.merchant_stores(owner_user_id,slug,name,status,onboarding_status)
      VALUES (v_own2,'qa-s5c2-'||substr(v_own2::text,1,8),'QA S5C Store2','active','approved') RETURNING id INTO v_store2;
    INSERT INTO public.food_restaurants(slug,name,owner_user_id,merchant_store_id,status)
      VALUES ('qa-s5c-r-'||substr(v_own::text,1,8),'QA S5C Resto',v_own,v_store,'active') RETURNING id INTO v_rest;
    INSERT INTO public.marketplace_listings(seller_id,kind,category,title,price_gnf,status,visibility,store_id)
      VALUES (v_own,'merchant','alimentation','QA S5C Listing',150000,'active','public',v_store) RETURNING id INTO v_listing;
    UPDATE public.feature_flags SET enabled=true WHERE key IN ('chop_pay_checkout_enabled','cancellation_policy_enabled');

    -- L. DISPUTE close_no_value
    INSERT INTO public.food_orders(user_id,restaurant_id,fulfillment,payment_method,subtotal_gnf)
      VALUES (v_cust,v_rest,'delivery','choppay',150000) RETURNING id INTO v_fo;
    INSERT INTO public.missions(type,customer_id,ref_food_order_id,estimated_earning_gnf,merchant_store_id)
      VALUES ('food_delivery',v_cust,v_fo,25000,v_store) RETURNING id INTO v_ms;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    PERFORM public.chop_pay_authorize_order('repas', v_fo);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_ms);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own), true);
    PERFORM public.chop_pay_merchant_accept('repas', v_fo);
    PERFORM public.chop_pay_merchant_prepare('repas', v_fo);
    PERFORM public.chop_pay_dispute_open('repas', v_fo, 'qa_close_no_value');
    SELECT balance_gnf INTO v_c0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_m0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    SELECT balance_gnf INTO v_mer0 FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    v_j := public.admin_chop_pay_dispute_resolve('repas', v_fo, 'close_no_value', 'qa_close');
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s5_ok('L1 close_no_value leaves no stranded customer hold',
      v_b2 = 0 AND v_b >= v_c0, format('bal=%s base=%s held=%s',v_b,v_c0,v_b2));
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('L2 close_no_value releases driver collateral and pays no earning',
      v_b = 9000000 AND v_b2 = 0, format('bal=%s held=%s',v_b,v_b2));
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('L3 close_no_value creates no new platform revenue', v_b = v_m0, v_b::text);
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    r := r || public._qa_s5_ok('L4 close_no_value creates no NEW merchant value (prior capture retained)',
      v_b = v_mer0, format('bal=%s base=%s',v_b,v_mer0));
    SELECT state INTO v_txt FROM public.chop_pay_order_runtime WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('L5 runtime leaves the disputed state', v_txt <> 'disputed', v_txt);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
      WHERE source_id=v_fo AND state NOT IN ('captured','released','reversed');
    r := r || public._qa_s5_ok('L6 no encumbrance remains open on the order', v_n=0, v_n::text);
    v_j := public.admin_chop_pay_dispute_resolve('repas', v_fo, 'close_no_value', 'qa_replay');
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('L7 close_no_value replay zero movement', v_b = v_m0, v_j::text);

    -- M. MARCHE CHOP PAY END TO END + TENDER DENIAL
    SELECT balance_gnf INTO v_mer1 FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    INSERT INTO public.marketplace_offers(listing_id,merchant_store_id,buyer_user_id,merchant_user_id,
      offer_amount_gnf,status,metadata)
      VALUES (v_listing,v_store,v_cust2,v_own,150000,'accepted','{"payment_method":"choppay"}'::jsonb)
      RETURNING id INTO v_off;
    INSERT INTO public.missions(type,customer_id,ref_market_order_id,estimated_earning_gnf,merchant_store_id)
      VALUES ('marketplace_delivery',v_cust2,v_off,25000,v_store) RETURNING id INTO v_ms;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    v_j := public.chop_pay_authorize_order('marche', v_off);
    r := r || public._qa_s5_ok('M1 Marche Chop Pay authorization holds exactly 176500',
      (v_j->>'order_total_gnf')::bigint = 176500, v_j::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_ms);
    SELECT collateral_gnf, state INTO v_b, v_txt FROM public.chop_pay_order_runtime WHERE source_id=v_off;
    r := r || public._qa_s5_ok('M2 Marche collateral 75000 = 50% of merchandise only',
      v_b=75000 AND v_txt='accepted', format('col=%s state=%s',v_b,v_txt));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own), true);
    PERFORM public.chop_pay_merchant_accept('marche', v_off);
    PERFORM public.chop_pay_merchant_prepare('marche', v_off);
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    r := r || public._qa_s5_ok('M3 Marche merchant captured exactly 150000', v_b - v_mer1 = 150000,
      format('bal=%s base=%s',v_b,v_mer1));
    SELECT balance_gnf INTO v_m0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_confirm_pickup(v_ms);
    PERFORM public.mission_confirm_dropoff(v_ms);
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('M4 Marche driver +25000 digital earning, collateral released',
      v_b = 9025000 AND v_b2 = 0, format('bal=%s held=%s',v_b,v_b2));
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('M5 Marche platform fee 1500', v_b = v_m0 + 1500, v_b::text);
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    r := r || public._qa_s5_ok('M6 Marche customer -176500 total, hold resolved',
      v_b = 9000000 - 176500 AND v_b2 = 0, format('bal=%s held=%s',v_b,v_b2));
    SELECT state INTO v_txt FROM public.chop_pay_order_runtime WHERE source_id=v_off;
    r := r || public._qa_s5_ok('M7 Marche runtime completed', v_txt='completed', v_txt);

    INSERT INTO public.marketplace_offers(listing_id,merchant_store_id,buyer_user_id,merchant_user_id,
      offer_amount_gnf,status,metadata)
      VALUES (v_listing,v_store,v_cust2,v_own,150000,'accepted','{}'::jsonb) RETURNING id INTO v_off;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    BEGIN
      PERFORM public.chop_pay_authorize_order('marche', v_off);
      r := r || public._qa_s5_ok('M8 absent tender cannot be authorized as Chop Pay', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('M8 absent tender cannot be authorized as Chop Pay', true, v_err);
    END;
    UPDATE public.marketplace_offers SET metadata='{"payment_method":"cash"}'::jsonb WHERE id=v_off;
    BEGIN
      PERFORM public.chop_pay_authorize_order('marche', v_off);
      r := r || public._qa_s5_ok('M9 explicit cash order is not routed through the Chop Pay engine', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('M9 explicit cash order is not routed through the Chop Pay engine', true, v_err);
    END;
    SELECT count(*) INTO v_n FROM public.chop_pay_order_runtime WHERE source_id=v_off;
    r := r || public._qa_s5_ok('M10 no Chop Pay runtime created for a cash order', v_n=0, v_n::text);

    -- N. FROZEN ECONOMICS SURVIVE A LATER POLICY CHANGE
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
      cash_funding_mode, cash_funding_pct_bps, cash_funding_max_gnf, 4000,
      5000, max_declared_value_gnf, cancel_basis, collateral_basis, claims_exposure_max_gnf
      FROM public.finance_policies WHERE mission_type='repas' ORDER BY effective_from DESC LIMIT 1;
    SELECT order_total_gnf, platform_fee_gnf INTO v_b, v_b2 FROM public.chop_pay_order_runtime WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('N1 authorized order economics stay frozen after a new policy takes effect',
      v_b = 176500 AND v_b2 = 1500, format('total=%s fee=%s',v_b,v_b2));
    r := r || public._qa_s5_ok('N1b the later policy really is live and different',
      (public.finance_mission_requirement_v2('repas',0,150000,25000,0,'chop_pay')->>'collateral_gnf')::bigint = 135000,
      (public.finance_mission_requirement_v2('repas',0,150000,25000,0,'chop_pay'))::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_ms);
    SELECT collateral_gnf INTO v_b FROM public.chop_pay_order_runtime WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('N2 collateral still uses the frozen 50% snapshot', v_b = 75000, v_b::text);
    SELECT COALESCE(SUM(amount_gnf),0), COALESCE(SUM(unrestricted_gnf),0) INTO v_b, v_b2
      FROM public.mission_financial_holds WHERE source_id=v_fo AND kind='collateral';
    r := r || public._qa_s5_ok('N2b exactly 75000 was actually reserved from the courier',
      v_b = 75000 AND v_b2 = 75000, format('held=%s unrestricted=%s',v_b,v_b2));
    SELECT held_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('N2c courier wallet held balance equals the frozen collateral', v_b = 75000, v_b::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_j := public.chop_pay_customer_cancel('repas', v_fo, 'qa_frozen_basis');
    r := r || public._qa_s5_ok('N3 cancellation uses the frozen 10% after-dispatch basis',
      (v_j->>'cancellation_charge_gnf')::bigint = 17500, v_j::text);
    SELECT held_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('N3b frozen collateral returns to the original funding buckets', v_b = 0, v_b::text);

    -- N4. INSUFFICIENT FUNDS FOR THE FROZEN COLLATERAL ROLLS THE CLAIM BACK
    INSERT INTO public.food_orders(user_id,restaurant_id,fulfillment,payment_method,subtotal_gnf)
      VALUES (v_cust,v_rest,'delivery','choppay',150000) RETURNING id INTO v_fo;
    INSERT INTO public.missions(type,customer_id,ref_food_order_id,estimated_earning_gnf,merchant_store_id)
      VALUES ('food_delivery',v_cust,v_fo,25000,v_store) RETURNING id INTO v_ms;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    PERFORM public.chop_pay_authorize_order('repas', v_fo);
    UPDATE public.wallets SET balance_gnf = 1000 WHERE owner_user_id=v_drv AND party_type='driver';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN
      PERFORM public.mission_claim(v_ms);
      r := r || public._qa_s5_ok('N4 a courier without the frozen collateral cannot claim', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('N4 a courier without the frozen collateral cannot claim',
        v_err LIKE 'INSUFFICIENT_DRIVER_BALANCE%', v_err);
    END;
    SELECT courier_id::text, state::text INTO v_txt, v_err FROM public.missions WHERE id=v_ms;
    r := r || public._qa_s5_ok('N4b courier assignment rolled back atomically',
      v_txt IS NULL, format('courier=%s state=%s',v_txt,v_err));
    SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_id=v_fo AND kind='collateral';
    r := r || public._qa_s5_ok('N4c no partial collateral hold was written', v_n=0, v_n::text);
    UPDATE public.wallets SET balance_gnf = 9000000 WHERE owner_user_id=v_drv AND party_type='driver';

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
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_rando), true);
    BEGIN
      PERFORM public.chop_pay_customer_hold_place('repas', v_fo, 1000, 'repas', v_cust, false, '{}'::jsonb);
      r := r || public._qa_s5_ok('O4 an ordinary user cannot place a raw customer hold', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('O4 an ordinary user cannot place a raw customer hold', true, v_err);
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

    RAISE EXCEPTION 'QA_S5_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S5_ROLLBACK' THEN
      r := r || public._qa_s5_ok('HARNESS_PART3_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  -- P. PRIVILEGE MATRIX
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname LIKE '\_chop\_pay\_%'
     AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  r := r || public._qa_s5_ok('P1 all raw _chop_pay_* helpers are service_role only', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('admin_chop_pay_cancel','admin_chop_pay_dispute_resolve')
     AND has_function_privilege('anon', p.oid, 'EXECUTE');
  r := r || public._qa_s5_ok('P2 anon cannot execute the admin Chop Pay wrappers', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.proname IN ('chop_pay_authorize_order','chop_pay_customer_cancel','chop_pay_dispute_open',
                       'chop_pay_merchant_accept','chop_pay_merchant_prepare','chop_pay_merchant_reject')
     AND NOT has_function_privilege('authenticated', p.oid, 'EXECUTE');
  r := r || public._qa_s5_ok('P3 participant Chop Pay RPCs are executable by authenticated users', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.proname IN ('chop_pay_customer_hold_place','chop_pay_customer_capture','chop_pay_customer_refund',
                       'wallet_internal_transfer','om_auto_match','wallet_topup_om_credit','ride_accept','ride_dispatch')
     AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  r := r || public._qa_s5_ok('P4 Slice 1-4 money primitives remain closed to anon and authenticated', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname LIKE '\_qa\_s5%'
     AND (has_function_privilege('anon', p.oid,'EXECUTE') OR has_function_privilege('authenticated', p.oid,'EXECUTE'));
  r := r || public._qa_s5_ok('P5 QA harness itself is not reachable by app roles', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname = '_driver_exact_hold_place_internal'
     AND (has_function_privilege('anon', p.oid,'EXECUTE') OR has_function_privilege('authenticated', p.oid,'EXECUTE'));
  r := r || public._qa_s5_ok('P6 the exact-collateral primitive is service_role only', v_n=0, v_n::text);

  SELECT balance_gnf INTO v_master_after FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || public._qa_s5_ok('Z0 master wallet naturally restored by rollback',
    v_master_after = v_master_before AND v_master_after = -100435, format('master=%s',v_master_after));
  SELECT count(*) INTO v_n FROM public.chop_pay_order_runtime;
  r := r || public._qa_s5_ok('Z1 no Chop Pay runtime residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_payables WHERE funding_source='customer_choppay';
  r := r || public._qa_s5_ok('Z2 no QA payable residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.feature_flags WHERE enabled AND key <> 'om_topup_enabled'
    AND key IN ('chop_pay_enabled','chop_pay_checkout_enabled','chop_pay_p2p_enabled','driver_balance_gate_enabled',
                'driver_starter_credit_enabled','cash_order_funding_enabled','driver_cashout_enabled',
                'merchant_om_settlement_enabled','om_direct_checkout_enabled','cancellation_policy_enabled');
  r := r || public._qa_s5_ok('Z3 canonical finance flags: only om_topup_enabled is ON', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.finance_policies WHERE note = 'qa s5 future policy';
  r := r || public._qa_s5_ok('Z4 no QA finance policy row survives the rollback', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-s5%';
  r := r || public._qa_s5_ok('Z5 no QA store/restaurant/listing residue', v_n=0, v_n::text);

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('total',v_total,'passed',v_pass,'failed',v_total-v_pass,
    'failures',(SELECT COALESCE(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(r) x WHERE NOT (x->>'ok')::boolean));
END; $qa$;

REVOKE ALL ON FUNCTION public._qa_s5_run3() FROM PUBLIC, anon, authenticated;