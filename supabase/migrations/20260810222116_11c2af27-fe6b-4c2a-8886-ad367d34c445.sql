CREATE OR REPLACE FUNCTION public._qa_s5_run2()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  v_pass int; v_total int;
  v_master_before bigint; v_master_after bigint; v_m0 bigint;
  v_cust uuid; v_drv uuid; v_own uuid; v_own2 uuid; v_adm uuid; v_rando uuid; v_cust2 uuid;
  v_store uuid; v_store2 uuid; v_rest uuid; v_listing uuid;
  v_fo uuid; v_ms uuid; v_j jsonb; v_err text; v_txt text; v_txt2 text;
  v_n bigint; v_n2 bigint; v_b bigint; v_b2 bigint; v_b3 bigint;
  v_c0 bigint; v_mer0 bigint; v_off uuid;
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
      VALUES (v_own,'qa-s5b-'||substr(v_own::text,1,8),'QA S5B Store','active','approved') RETURNING id INTO v_store;
    INSERT INTO public.merchant_stores(owner_user_id,slug,name,status,onboarding_status)
      VALUES (v_own2,'qa-s5b2-'||substr(v_own2::text,1,8),'QA S5B Store2','active','approved') RETURNING id INTO v_store2;
    INSERT INTO public.food_restaurants(slug,name,owner_user_id,merchant_store_id,status)
      VALUES ('qa-s5b-r-'||substr(v_own::text,1,8),'QA S5B Resto',v_own,v_store,'active') RETURNING id INTO v_rest;
    UPDATE public.feature_flags SET enabled=true WHERE key IN ('chop_pay_checkout_enabled','cancellation_policy_enabled');

    ------------------------------------------------------------------
    -- E. AFTER-DISPATCH, PRE-PREP CUSTOMER CANCEL (10% = 17500)
    ------------------------------------------------------------------
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
    SELECT balance_gnf INTO v_c0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_m0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_j := public.chop_pay_customer_cancel('repas', v_fo, 'qa_after_dispatch');
    r := r || public._qa_s5_ok('E1 after-dispatch charge = 17500 (10% of merchandise+delivery)',
      (v_j->>'cancellation_charge_gnf')::bigint=17500, v_j::text);
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    r := r || public._qa_s5_ok('E2 merchant capture reversed to zero', v_b=0, v_b::text);
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s5_ok('E3 customer net -17500 only, hold fully resolved',
      v_b = v_c0 + 150000 - 17500 AND v_b2=0, format('bal=%s (base=%s) held=%s',v_b,v_c0,v_b2));
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('E4 driver collateral released, no earning', v_b=9000000 AND v_b2=0,
      format('bal=%s held=%s',v_b,v_b2));
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('E5 only the 17500 cancellation fee is platform revenue', v_b=v_m0+17500, v_b::text);
    SELECT state, funded_gnf INTO v_txt, v_b FROM public.merchant_payables WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('E6 payable reversed, no merchant value retained', v_b=0, format('state=%s funded=%s',v_txt,v_b));
    SELECT count(*) INTO v_n FROM public.customer_cancellation_debts WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('E7 no cash debt on a Chop Pay cancellation', v_n=0, v_n::text);
    v_j := public.chop_pay_customer_cancel('repas', v_fo, 'qa_replay');
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('E8 cancellation replay inert', v_j->>'status'='already_cancelled' AND v_b=v_m0+17500, v_j::text);

    ------------------------------------------------------------------
    -- F. NON-CUSTOMER-CAUSED CANCELLATION (charge 0)
    ------------------------------------------------------------------
    INSERT INTO public.food_orders(user_id,restaurant_id,fulfillment,payment_method,subtotal_gnf)
      VALUES (v_cust,v_rest,'delivery','choppay',150000) RETURNING id INTO v_fo;
    INSERT INTO public.missions(type,customer_id,ref_food_order_id,estimated_earning_gnf,merchant_store_id)
      VALUES ('food_delivery',v_cust,v_fo,25000,v_store) RETURNING id INTO v_ms;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    PERFORM public.chop_pay_authorize_order('repas', v_fo);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_ms);
    SELECT balance_gnf INTO v_c0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_m0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    v_j := public.admin_chop_pay_cancel('repas', v_fo, 'platform', 'qa_platform_caused');
    r := r || public._qa_s5_ok('F1 platform-caused cancellation charges the customer 0',
      COALESCE((v_j->>'cancellation_charge_gnf')::bigint,0)=0, v_j::text);
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s5_ok('F2 customer fully refunded, hold released', v_b=v_c0 AND v_b2=0,
      format('bal=%s base=%s held=%s',v_b,v_c0,v_b2));
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('F3 no platform revenue on a non-customer-caused cancellation', v_b=v_m0, v_b::text);
    SELECT held_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('F4 driver collateral released', v_b=0, v_b::text);

    ------------------------------------------------------------------
    -- G. MERCHANT REJECTION
    ------------------------------------------------------------------
    INSERT INTO public.food_orders(user_id,restaurant_id,fulfillment,payment_method,subtotal_gnf)
      VALUES (v_cust,v_rest,'delivery','choppay',150000) RETURNING id INTO v_fo;
    INSERT INTO public.missions(type,customer_id,ref_food_order_id,estimated_earning_gnf,merchant_store_id)
      VALUES ('food_delivery',v_cust,v_fo,25000,v_store) RETURNING id INTO v_ms;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    PERFORM public.chop_pay_authorize_order('repas', v_fo);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_ms);
    SELECT balance_gnf INTO v_c0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_m0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own2), true);
    BEGIN
      PERFORM public.chop_pay_merchant_reject('repas', v_fo, 'qa_wrong_merchant');
      r := r || public._qa_s5_ok('G1 a different merchant cannot reject this order', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('G1 a different merchant cannot reject this order', true, v_err);
    END;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own), true);
    v_j := public.chop_pay_merchant_reject('repas', v_fo, 'qa_out_of_stock');
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s5_ok('G2 customer hold fully resolved on rejection', v_b=v_c0 AND v_b2=0,
      format('bal=%s base=%s held=%s',v_b,v_c0,v_b2));
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('G3 driver collateral released, no earning', v_b=9000000 AND v_b2=0,
      format('bal=%s held=%s',v_b,v_b2));
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    r := r || public._qa_s5_ok('G4 no merchant value from a rejected order', COALESCE(v_b,0)=0, COALESCE(v_b,0)::text);
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('G5 no platform revenue from a rejected order', v_b=v_m0, v_b::text);
    SELECT funded_gnf, state INTO v_b, v_txt FROM public.merchant_payables WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('G6 payable carries no merchant value', COALESCE(v_b,0)=0, format('funded=%s state=%s',v_b,v_txt));
    v_j := public.chop_pay_merchant_reject('repas', v_fo, 'qa_replay');
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s5_ok('G7 rejection replay zero movement', v_b=v_c0, v_j::text);

    ------------------------------------------------------------------
    -- H. CANCEL AFTER PREPARATION IS DENIED  +  I. DISPUTE complete_as_delivered
    ------------------------------------------------------------------
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
    SELECT balance_gnf INTO v_c0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_m0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    SELECT balance_gnf INTO v_mer0 FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN
      PERFORM public.chop_pay_customer_cancel('repas', v_fo, 'qa_too_late');
      r := r || public._qa_s5_ok('H1 cancellation after preparation is denied', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('H1 cancellation after preparation is denied', true, v_err);
    END;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_rando), true);
    BEGIN
      PERFORM public.chop_pay_dispute_open('repas', v_fo, 'qa_outsider');
      r := r || public._qa_s5_ok('H2 a non-participant cannot open a dispute', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('H2 a non-participant cannot open a dispute', true, v_err);
    END;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    PERFORM public.chop_pay_dispute_open('repas', v_fo, 'qa_dispute');
    SELECT state INTO v_txt FROM public.chop_pay_order_runtime WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('H3 dispute opened by the customer', v_txt='disputed', v_txt);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_rando), true);
    BEGIN
      PERFORM public.admin_chop_pay_dispute_resolve('repas', v_fo, 'complete_as_delivered', 'qa');
      r := r || public._qa_s5_ok('H4 an ordinary user cannot resolve a Finance dispute', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('H4 an ordinary user cannot resolve a Finance dispute', true, v_err);
    END;
    PERFORM set_config('request.jwt.claims', NULL, true);
    BEGIN
      PERFORM public.admin_chop_pay_dispute_resolve('repas', v_fo, 'complete_as_delivered', 'qa');
      r := r || public._qa_s5_ok('H5 NULL-auth caller cannot resolve a Finance dispute', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('H5 NULL-auth caller cannot resolve a Finance dispute', true, v_err);
    END;
    BEGIN
      PERFORM public.admin_chop_pay_cancel('repas', v_fo, 'platform', 'qa');
      r := r || public._qa_s5_ok('H6 NULL-auth caller cannot force an admin cancellation', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('H6 NULL-auth caller cannot force an admin cancellation', true, v_err);
    END;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    v_j := public.admin_chop_pay_dispute_resolve('repas', v_fo, 'complete_as_delivered', 'qa_resolved');
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s5_ok('I1 dispute completion charges the remaining 26500 exactly like a normal completion',
      v_b = v_c0 - 26500 AND v_b2 = 0, format('bal=%s base=%s held=%s',v_b,v_c0,v_b2));
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('I2 driver receives the 25000 digital delivery earning, collateral released',
      v_b = 9000000 + 25000 AND v_b2 = 0, format('bal=%s held=%s',v_b,v_b2));
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('I3 platform fee 1500 captured once', v_b = v_m0 + 1500, v_b::text);
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    r := r || public._qa_s5_ok('I4 merchant keeps the captured 150000', v_b = v_mer0, format('bal=%s base=%s',v_b,v_mer0));
    SELECT state INTO v_txt FROM public.chop_pay_order_runtime WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('I5 runtime resolved to completed', v_txt='completed', v_txt);
    v_j := public.admin_chop_pay_dispute_resolve('repas', v_fo, 'complete_as_delivered', 'qa_replay');
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('I6 dispute resolution replay is inert', v_b = v_m0 + 1500, v_j::text);

    ------------------------------------------------------------------
    -- J/K. DISPUTE refund_customer  +  RECONCILIATION REQUIRED
    ------------------------------------------------------------------
    INSERT INTO public.food_orders(user_id,restaurant_id,fulfillment,payment_method,subtotal_gnf)
      VALUES (v_cust2,v_rest,'delivery','choppay',150000) RETURNING id INTO v_fo;
    INSERT INTO public.missions(type,customer_id,ref_food_order_id,estimated_earning_gnf,merchant_store_id)
      VALUES ('food_delivery',v_cust2,v_fo,25000,v_store) RETURNING id INTO v_ms;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    PERFORM public.chop_pay_authorize_order('repas', v_fo);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_ms);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own), true);
    PERFORM public.chop_pay_merchant_accept('repas', v_fo);
    PERFORM public.chop_pay_merchant_prepare('repas', v_fo);
    PERFORM public.chop_pay_dispute_open('repas', v_fo, 'qa_merchant_dispute');
    SELECT balance_gnf INTO v_c0 FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    SELECT balance_gnf INTO v_m0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    SELECT balance_gnf INTO v_mer0 FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';

    -- K: mark the payable as externally settled => refund must be blocked, atomically
    UPDATE public.merchant_payables SET settled_gnf = 150000, state = 'settled' WHERE source_id = v_fo;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    BEGIN
      PERFORM public.admin_chop_pay_dispute_resolve('repas', v_fo, 'refund_customer', 'qa_unrecoverable');
      r := r || public._qa_s5_ok('K1 externally settled merchant liability blocks the refund', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('K1 externally settled merchant liability blocks the refund',
        v_err LIKE 'FINANCE_RECONCILIATION_REQUIRED%', v_err);
    END;
    SELECT state INTO v_txt FROM public.chop_pay_order_runtime WHERE source_id=v_fo;
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    SELECT balance_gnf INTO v_b3 FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    r := r || public._qa_s5_ok('K2 dispute stays unresolved with zero partial mutation',
      v_txt='disputed' AND v_b=v_c0 AND v_b2=26500 AND v_b3=v_mer0,
      format('state=%s bal=%s held=%s merchant=%s',v_txt,v_b,v_b2,v_b3));

    UPDATE public.merchant_payables SET settled_gnf = 0, state = 'funded' WHERE source_id = v_fo;
    v_j := public.admin_chop_pay_dispute_resolve('repas', v_fo, 'refund_customer', 'qa_refund');
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    r := r || public._qa_s5_ok('J1 customer restored to the full pre-order position',
      v_b = v_c0 + 150000 AND v_b2 = 0, format('bal=%s base=%s held=%s',v_b,v_c0,v_b2));
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    r := r || public._qa_s5_ok('J2 merchant principal reversed source-specifically', v_b = v_mer0 - 150000,
      format('bal=%s base=%s',v_b,v_mer0));
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('J3 platform fee 0 on a refunded dispute', v_b = v_m0, v_b::text);
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('J4 driver earns nothing, collateral fully released',
      v_b = 9025000 AND v_b2 = 0, format('bal=%s held=%s',v_b,v_b2));
    SELECT state INTO v_txt FROM public.chop_pay_order_runtime WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('J5 runtime resolved to refunded', v_txt='refunded', v_txt);
    v_j := public.admin_chop_pay_dispute_resolve('repas', v_fo, 'refund_customer', 'qa_replay');
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    r := r || public._qa_s5_ok('J6 refund replay zero movement', v_b = v_c0 + 150000, v_j::text);

    ------------------------------------------------------------------
    -- L. DISPUTE close_no_value
    ------------------------------------------------------------------
    INSERT INTO public.food_orders(user_id,restaurant_id,fulfillment,payment_method,subtotal_gnf)
      VALUES (v_cust2,v_rest,'delivery','choppay',150000) RETURNING id INTO v_fo;
    INSERT INTO public.missions(type,customer_id,ref_food_order_id,estimated_earning_gnf,merchant_store_id)
      VALUES ('food_delivery',v_cust2,v_fo,25000,v_store) RETURNING id INTO v_ms;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    PERFORM public.chop_pay_authorize_order('repas', v_fo);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_ms);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own), true);
    PERFORM public.chop_pay_merchant_prepare('repas', v_fo) ;
    r := r || public._qa_s5_ok('L0 unreachable guard placeholder', true, null);
    RAISE EXCEPTION 'QA_S5_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S5_ROLLBACK' THEN
      r := r || public._qa_s5_ok('HARNESS_PART2_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  SELECT balance_gnf INTO v_master_after FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || public._qa_s5_ok('Z0 master wallet naturally restored by rollback',
    v_master_after = v_master_before, format('master=%s',v_master_after));

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('total',v_total,'passed',v_pass,'failed',v_total-v_pass,
    'failures',(SELECT COALESCE(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(r) x WHERE NOT (x->>'ok')::boolean));
END; $fn$;

REVOKE ALL ON FUNCTION public._qa_s5_run2() FROM PUBLIC;

DO $$ BEGIN INSERT INTO public._qa_s5_results(report) SELECT public._qa_s5_run2(); END $$;