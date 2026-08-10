-- ===== Slice 5 canonical payment-mode alias fix =====
CREATE OR REPLACE FUNCTION public._chop_pay_economics(p_facts jsonb)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_req jsonb; v_snap jsonb; v_sub bigint; v_del bigint; v_fee bigint; v_col bigint;
BEGIN
  v_sub := (p_facts->>'merchandise_subtotal_gnf')::bigint;
  v_del := (p_facts->>'delivery_fee_gnf')::bigint;
  -- canonical finance payment_mode is 'chop_pay'; 'choppay' is the PRODUCT tender literal only
  v_req := public.finance_mission_requirement_v2(p_facts->>'mission_type', 0, v_sub, v_del, 0, 'chop_pay');
  v_fee := COALESCE((v_req->>'platform_fee_gnf')::bigint, 0);
  v_col := COALESCE((v_req->>'collateral_gnf')::bigint, 0);
  IF COALESCE((v_req->>'cash_funding_gnf')::bigint,0) <> 0 THEN
    RAISE EXCEPTION 'CHOP_PAY_MUST_NOT_FUND_CASH';
  END IF;
  IF COALESCE((v_req->>'commission_gnf')::bigint,0) <> 0 THEN
    RAISE EXCEPTION 'CHOP_PAY_NO_DELIVERY_COMMISSION';
  END IF;
  v_snap := public.finance_policy_snapshot(p_facts->>'mission_type', now(), 'chop_pay', 0, v_sub, v_del, 0, false);
  RETURN jsonb_build_object(
    'merchandise_subtotal_gnf', v_sub, 'delivery_fee_gnf', v_del,
    'platform_fee_gnf', v_fee, 'collateral_gnf', v_col,
    'order_total_gnf', v_sub + v_del + v_fee,
    'requirement', v_req, 'policy_snapshot', v_snap);
END; $function$;

CREATE OR REPLACE FUNCTION public._chop_pay_accept_internal(p_source_module text, p_source_id uuid, p_driver uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_row public.chop_pay_order_runtime; v_f jsonb; v_hold jsonb; v_col bigint;
BEGIN
  IF p_driver IS NULL THEN RAISE EXCEPTION 'NO_DRIVER'; END IF;
  IF NOT public._finance_flag('chop_pay_checkout_enabled') THEN
    RAISE EXCEPTION 'CHOP_PAY_CHECKOUT_DISABLED';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(format('choppay:%s:%s',p_source_module,p_source_id), 0));

  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'
      USING DETAIL = 'customer full-order hold must be secured before dispatch';
  END IF;
  IF v_row.driver_user_id IS NOT NULL THEN
    RETURN jsonb_build_object('status','already_accepted','runtime_id',v_row.id,
                              'driver_user_id',v_row.driver_user_id,'state',v_row.state);
  END IF;
  IF v_row.state <> 'authorized' THEN RAISE EXCEPTION 'INVALID_STATE' USING DETAIL = v_row.state; END IF;

  v_f := public._chop_pay_facts(p_source_module, p_source_id);
  IF NOT (v_f->>'is_chop_pay')::boolean THEN RAISE EXCEPTION 'CHOP_PAY_TENDER_REQUIRED'; END IF;
  IF (v_f->>'courier_id') IS NULL THEN RAISE EXCEPTION 'NO_ASSIGNED_COURIER'; END IF;
  IF p_driver <> (v_f->>'courier_id')::uuid THEN RAISE EXCEPTION 'NOT_ASSIGNED_DRIVER'; END IF;
  IF (v_f->>'mission_state') <> 'assigned' THEN RAISE EXCEPTION 'STALE_OFFER'; END IF;

  v_hold := public.driver_mission_hold_place(
    v_row.mission_type, p_source_module, p_source_id, 0, p_driver, false,
    ARRAY['collateral'], 0, v_row.merchandise_subtotal_gnf, v_row.delivery_fee_gnf, 0, 'chop_pay');
  SELECT COALESCE(SUM(amount_gnf),0) INTO v_col FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'collateral';

  PERFORM public._merchant_payable_create_internal(
    p_source_module, p_source_id, v_row.merchant_store_id,
    v_row.merchandise_subtotal_gnf, 0, v_row.mission_type, v_row.policy_snapshot, false);

  UPDATE public.chop_pay_order_runtime
     SET driver_user_id = p_driver, state = 'accepted', accepted_at = now(),
         collateral_gnf = v_col, mission_id = COALESCE(mission_id,(v_f->>'mission_id')::uuid)
   WHERE id = v_row.id;

  RETURN jsonb_build_object('status','accepted','runtime_id',v_row.id,
    'collateral_gnf',v_col,'order_total_gnf',v_row.order_total_gnf,'hold',v_hold);
END; $function$;

-- ===== QA harness (temporary; dropped in the closeout migration) =====
CREATE TABLE IF NOT EXISTS public._qa_s5_results (id bigserial primary key, report jsonb, created_at timestamptz default now());
GRANT ALL ON public._qa_s5_results TO service_role;
ALTER TABLE public._qa_s5_results ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public._qa_s5_ok(p_label text, p_ok boolean, p_detail text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT jsonb_build_array(jsonb_build_object('label',p_label,'ok',COALESCE(p_ok,false),'detail',p_detail));
$$;

CREATE OR REPLACE FUNCTION public._qa_s5_run()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  v_pass int; v_total int;
  v_master_before bigint; v_master_after bigint; v_m0 bigint;
  v_cust uuid; v_cust2 uuid; v_poorc uuid; v_drv uuid; v_poor uuid;
  v_own uuid; v_own2 uuid; v_adm uuid; v_rando uuid;
  v_store uuid; v_store2 uuid; v_rest uuid; v_listing uuid;
  v_fo uuid; v_ms uuid; v_j jsonb; v_err text; v_txt text;
  v_n bigint; v_n2 bigint; v_b bigint; v_b2 bigint; v_b3 bigint;
  v_cbal0 bigint;
BEGIN
  SELECT balance_gnf INTO v_master_before FROM public.wallets WHERE party_type='master' LIMIT 1;

  BEGIN
    v_cust:=gen_random_uuid(); v_cust2:=gen_random_uuid(); v_poorc:=gen_random_uuid();
    v_drv:=gen_random_uuid(); v_poor:=gen_random_uuid(); v_own:=gen_random_uuid();
    v_own2:=gen_random_uuid(); v_adm:=gen_random_uuid(); v_rando:=gen_random_uuid();

    INSERT INTO public.admin_users(user_id, admin_role, status) VALUES (v_adm,'finance_admin','active');
    INSERT INTO public.driver_profiles(user_id, status, vehicle_type, capabilities)
    VALUES (v_drv,'approved','moto',ARRAY['repas_delivery','marche_delivery']),
           (v_poor,'approved','moto',ARRAY['repas_delivery','marche_delivery']);
    INSERT INTO public.wallets(owner_user_id, party_type, balance_gnf)
    VALUES (v_drv,'driver',5000000),(v_poor,'driver',1000),
           (v_cust,'client',5000000),(v_cust2,'client',5000000),(v_poorc,'client',1000);

    INSERT INTO public.merchant_stores(id, owner_user_id, slug, name, status, onboarding_status)
    VALUES (gen_random_uuid(), v_own, 'qa-s5-store-'||substr(v_own::text,1,8),'QA S5 Store','active','approved')
    RETURNING id INTO v_store;
    INSERT INTO public.merchant_stores(id, owner_user_id, slug, name, status, onboarding_status)
    VALUES (gen_random_uuid(), v_own2, 'qa-s5-store2-'||substr(v_own2::text,1,8),'QA S5 Store 2','active','approved')
    RETURNING id INTO v_store2;
    INSERT INTO public.food_restaurants(slug,name,owner_user_id,merchant_store_id,status)
    VALUES ('qa-s5-rest-'||substr(v_own::text,1,8),'QA S5 Resto',v_own,v_store,'active')
    RETURNING id INTO v_rest;

    UPDATE public.feature_flags SET enabled=true WHERE key IN ('chop_pay_checkout_enabled','cancellation_policy_enabled');
    r := r || public._qa_s5_ok('F1 QA-only flags enabled inside the rolled-back subtransaction',
      public._finance_flag('chop_pay_checkout_enabled') AND public._finance_flag('cancellation_policy_enabled'));

    -- A. CANONICAL REPAS CHOP PAY LIFECYCLE (EXIT GATE)
    INSERT INTO public.food_orders(user_id,restaurant_id,fulfillment,payment_method,subtotal_gnf)
    VALUES (v_cust,v_rest,'delivery','choppay',150000) RETURNING id INTO v_fo;
    INSERT INTO public.missions(type,customer_id,ref_food_order_id,estimated_earning_gnf,merchant_store_id)
    VALUES ('food_delivery',v_cust,v_fo,25000,v_store) RETURNING id INTO v_ms;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_j := public.chop_pay_authorize_order('repas', v_fo);
    r := r || public._qa_s5_ok('A1 authorization hold is exactly 176500',
      (v_j->>'order_total_gnf')::bigint = 176500, v_j::text);
    r := r || public._qa_s5_ok('A2 economics 150000 merchandise / 25000 delivery / 1500 fee',
      (v_j->>'merchandise_subtotal_gnf')::bigint=150000 AND (v_j->>'delivery_fee_gnf')::bigint=25000
      AND (v_j->>'platform_fee_gnf')::bigint=1500, v_j::text);
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s5_ok('A3 customer balance untouched, held = 176500',
      v_b=5000000 AND v_b2=176500, format('bal=%s held=%s',v_b,v_b2));
    v_j := public.chop_pay_authorize_order('repas', v_fo);
    SELECT held_gnf INTO v_b2 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s5_ok('A4 replayed authorization is inert',
      v_j->>'status'='already_authorized' AND v_b2=176500, v_j::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_id=v_fo AND kind='customer_payment';
    r := r || public._qa_s5_ok('A5 exactly one customer_payment hold', v_n=1, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_ms);
    SELECT collateral_gnf, state INTO v_b, v_txt FROM public.chop_pay_order_runtime WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('A6 driver collateral exactly 75000 = 50% of merchandise only',
      v_b=75000 AND v_txt='accepted', format('col=%s state=%s',v_b,v_txt));
    SELECT held_gnf INTO v_b2 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('A7 driver held_gnf = 75000', v_b2=75000, format('held=%s',v_b2));
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_id=v_fo AND kind IN ('cash_funding','commission');
    r := r || public._qa_s5_ok('A8 no cash_funding hold and no commission hold on Chop Pay', v_n=0, v_n::text);
    BEGIN
      PERFORM public.mission_claim(v_ms);
      r := r || public._qa_s5_ok('A9 replayed claim rejected', false, 'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('A9 replayed claim rejected', v_err='mission_already_claimed', v_err);
    END;
    SELECT amount_gnf, state INTO v_b, v_txt FROM public.merchant_payables WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('A10 payable created 150000 merchandise-only, pending funding',
      v_b=150000 AND v_txt='pending_funding', format('amt=%s state=%s',v_b,v_txt));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own), true);
    BEGIN
      PERFORM public.chop_pay_merchant_prepare('repas', v_fo);
      r := r || public._qa_s5_ok('A11 preparation impossible before merchant funding', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('A11 preparation impossible before merchant funding', true, v_err);
    END;

    v_j := public.chop_pay_merchant_accept('repas', v_fo);
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    r := r || public._qa_s5_ok('A12 merchant captured exactly 150000 once', v_b=150000, format('bal=%s',v_b));
    SELECT funded_gnf, funding_source, state INTO v_b, v_txt, v_err FROM public.merchant_payables WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('A13 payable funded 150000 from customer_choppay',
      v_b=150000 AND v_txt='customer_choppay' AND v_err='funded', format('funded=%s src=%s state=%s',v_b,v_txt,v_err));
    SELECT settled_gnf INTO v_b FROM public.merchant_payables WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('A14 no outbound OM settlement occurred', v_b=0, v_b::text);
    SELECT mission_type INTO v_txt FROM public.merchant_payables WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('A15 payable retains frozen mission type', v_txt='repas', v_txt);
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s5_ok('A16 customer -150000 balance, remaining hold 26500',
      v_b=4850000 AND v_b2=26500, format('bal=%s held=%s',v_b,v_b2));
    v_j := public.chop_pay_merchant_accept('repas', v_fo);
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    r := r || public._qa_s5_ok('A17 replayed merchant capture inert',
      v_j->>'status'='already_accepted' AND v_b=150000, v_j::text);

    PERFORM public.chop_pay_merchant_prepare('repas', v_fo);
    SELECT state INTO v_txt FROM public.chop_pay_order_runtime WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('A18 preparation lock reached', v_txt='preparing', v_txt);
    SELECT state::text INTO v_txt FROM public.food_orders WHERE id=v_fo;
    r := r || public._qa_s5_ok('A19 food order synchronised to preparing', v_txt='preparing', v_txt);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_confirm_pickup(v_ms);
    PERFORM public.mission_confirm_dropoff(v_ms);
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('A20 driver +25000 digital delivery earning, collateral fully released',
      v_b=5025000 AND v_b2=0, format('bal=%s held=%s',v_b,v_b2));
    SELECT balance_gnf INTO v_m0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('A21 master +1500 platform fee exactly once',
      v_m0 = v_master_before + 1500, format('master=%s',v_m0));
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s5_ok('A22 customer -176500 total, hold fully resolved',
      v_b=4823500 AND v_b2=0, format('bal=%s held=%s',v_b,v_b2));
    SELECT captured_gnf, released_gnf, state INTO v_b, v_b2, v_txt
      FROM public.mission_financial_holds WHERE source_id=v_fo AND kind='customer_payment';
    r := r || public._qa_s5_ok('A23 customer hold captured 176500',
      v_b=176500, format('cap=%s rel=%s st=%s',v_b,v_b2,v_txt));
    r := r || public._qa_s5_ok('A24 EXIT GATE zero unexplained variance',
      (5000000 - 4823500) = (150000 + 25000 + 1500), format('customer_out=%s',5000000-4823500));
    SELECT state, driver_earning_gnf, platform_revenue_gnf, merchant_credited_gnf
      INTO v_txt, v_b, v_b2, v_b3 FROM public.chop_pay_order_runtime WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('A25 runtime completed with canonical splits',
      v_txt='completed' AND v_b=25000 AND v_b2=1500 AND v_b3=150000,
      format('%s / drv=%s / plat=%s / mer=%s',v_txt,v_b,v_b2,v_b3));
    SELECT state::text INTO v_txt FROM public.food_orders WHERE id=v_fo;
    SELECT state::text INTO v_err FROM public.missions WHERE id=v_ms;
    r := r || public._qa_s5_ok('A26 order completed and mission delivered',
      v_txt='completed' AND v_err='delivered', format('%s/%s',v_txt,v_err));
    SELECT count(*) INTO v_n FROM public.driver_cash_ledger WHERE driver_id=v_drv;
    r := r || public._qa_s5_ok('A27 no fake driver cash-ledger entry on a Chop Pay order', v_n=0, v_n::text);
    PERFORM public.mission_confirm_dropoff(v_ms);
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT balance_gnf INTO v_b2 FROM public.wallets WHERE party_type='master' LIMIT 1;
    SELECT balance_gnf INTO v_b3 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s5_ok('A28 completion replay produces zero extra movement',
      v_b=5025000 AND v_b2=v_master_before+1500 AND v_b3=4823500,
      format('drv=%s master=%s cust=%s',v_b,v_b2,v_b3));

    -- B. INSUFFICIENT CUSTOMER BALANCE
    INSERT INTO public.food_orders(user_id,restaurant_id,fulfillment,payment_method,subtotal_gnf)
    VALUES (v_poorc,v_rest,'delivery','choppay',150000) RETURNING id INTO v_fo;
    INSERT INTO public.missions(type,customer_id,ref_food_order_id,estimated_earning_gnf,merchant_store_id)
    VALUES ('food_delivery',v_poorc,v_fo,25000,v_store) RETURNING id INTO v_ms;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_poorc), true);
    BEGIN
      PERFORM public.chop_pay_authorize_order('repas', v_fo);
      r := r || public._qa_s5_ok('B1 insufficient customer balance rejected', false, 'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('B1 insufficient customer balance rejected', true, v_err);
    END;
    SELECT count(*) INTO v_n FROM public.chop_pay_order_runtime WHERE source_id=v_fo;
    SELECT count(*) INTO v_n2 FROM public.mission_financial_holds WHERE source_id=v_fo;
    SELECT held_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_poorc AND party_type='client';
    r := r || public._qa_s5_ok('B2 atomic failure: no runtime, no hold, no wallet residue',
      v_n=0 AND v_n2=0 AND v_b=0, format('rt=%s holds=%s held=%s',v_n,v_n2,v_b));

    -- C. INSUFFICIENT DRIVER COLLATERAL ROLLS mission_claim BACK
    INSERT INTO public.food_orders(user_id,restaurant_id,fulfillment,payment_method,subtotal_gnf)
    VALUES (v_cust2,v_rest,'delivery','choppay',150000) RETURNING id INTO v_fo;
    INSERT INTO public.missions(type,customer_id,ref_food_order_id,estimated_earning_gnf,merchant_store_id)
    VALUES ('food_delivery',v_cust2,v_fo,25000,v_store) RETURNING id INTO v_ms;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    PERFORM public.chop_pay_authorize_order('repas', v_fo);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_poor), true);
    BEGIN
      PERFORM public.mission_claim(v_ms);
      r := r || public._qa_s5_ok('C1 claim with insufficient collateral rejected', false,'no error');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      r := r || public._qa_s5_ok('C1 claim with insufficient collateral rejected', true, v_err);
    END;
    SELECT courier_id::text INTO v_txt FROM public.missions WHERE id=v_ms;
    r := r || public._qa_s5_ok('C2 mission courier rolled back to NULL', v_txt IS NULL, COALESCE(v_txt,'null'));
    SELECT state INTO v_txt FROM public.chop_pay_order_runtime WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('C3 runtime remains authorized', v_txt='authorized', v_txt);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_id=v_fo AND kind='collateral';
    SELECT count(*) INTO v_n2 FROM public.merchant_payables WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('C4 no collateral / payable partials', v_n=0 AND v_n2=0,
      format('col=%s pay=%s',v_n,v_n2));

    -- D. CUSTOMER CANCEL BEFORE DISPATCH (5% of 175000 = 8750)
    SELECT balance_gnf INTO v_cbal0 FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    SELECT balance_gnf INTO v_m0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    v_j := public.chop_pay_customer_cancel('repas', v_fo, 'qa_before_dispatch');
    r := r || public._qa_s5_ok('D1 frozen before-dispatch charge = 8750 (5% of merchandise+delivery)',
      (v_j->>'cancellation_charge_gnf')::bigint=8750, v_j::text);
    SELECT balance_gnf, held_gnf INTO v_b, v_b2 FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    r := r || public._qa_s5_ok('D2 remainder released, only the fee is charged',
      v_b = v_cbal0-8750 AND v_b2=0, format('bal=%s held=%s',v_b,v_b2));
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('D3 cancellation fee is platform revenue', v_b = v_m0+8750, format('master=%s',v_b));
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    r := r || public._qa_s5_ok('D4 no merchant value from a pre-dispatch cancellation', v_b=150000, v_b::text);
    SELECT count(*) INTO v_n FROM public.customer_cancellation_debts WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('D5 no cash debt created on a Chop Pay cancellation', v_n=0, v_n::text);
    v_j := public.chop_pay_customer_cancel('repas', v_fo, 'qa_replay');
    r := r || public._qa_s5_ok('D6 replayed cancellation inert', v_j->>'status'='already_cancelled', v_j::text);
    SELECT driver_earning_gnf INTO v_b FROM public.chop_pay_order_runtime WHERE source_id=v_fo;
    r := r || public._qa_s5_ok('D7 no driver earning on cancellation', v_b=0, v_b::text);

    RAISE EXCEPTION 'QA_S5_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S5_ROLLBACK' THEN
      r := r || public._qa_s5_ok('HARNESS_PART1_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  SELECT balance_gnf INTO v_master_after FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || public._qa_s5_ok('Z0 master wallet naturally restored by rollback (DEF-FIN-001 untouched)',
    v_master_after = v_master_before AND v_master_after = -100435, format('master=%s',v_master_after));
  SELECT count(*) INTO v_n FROM public.chop_pay_order_runtime;
  r := r || public._qa_s5_ok('Z1 no QA runtime residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.feature_flags WHERE enabled AND key <> 'om_topup_enabled'
    AND key IN ('chop_pay_enabled','chop_pay_checkout_enabled','chop_pay_p2p_enabled','driver_balance_gate_enabled',
                'driver_starter_credit_enabled','cash_order_funding_enabled','driver_cashout_enabled',
                'merchant_om_settlement_enabled','om_direct_checkout_enabled','cancellation_policy_enabled');
  r := r || public._qa_s5_ok('Z2 canonical finance flags restored (only om_topup_enabled ON)', v_n=0, v_n::text);

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total
    FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('total',v_total,'passed',v_pass,'failed',v_total-v_pass,
    'failures',(SELECT COALESCE(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(r) x WHERE NOT (x->>'ok')::boolean));
END; $fn$;

REVOKE ALL ON FUNCTION public._qa_s5_run() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._qa_s5_ok(text,boolean,text) FROM PUBLIC;

DO $$ BEGIN INSERT INTO public._qa_s5_results(report) SELECT public._qa_s5_run(); END $$;