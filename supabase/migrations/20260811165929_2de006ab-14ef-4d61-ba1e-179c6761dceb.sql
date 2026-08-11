CREATE OR REPLACE FUNCTION public._qa_s13_run3()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_own uuid; v_dpromo uuid; v_drv uuid;
  v_store uuid; v_rest uuid; v_o1 uuid; v_o2 uuid; v_o3 uuid; v_mis uuid; v_sfx text;
  v_lst uuid; v_m1 uuid; v_m2 uuid; v_mmis uuid;
  v_err text; v_n bigint; v_res jsonb; v_q jsonb; v_e jsonb;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_pay bigint; v_pay0 bigint; v_bal0 bigint; v_bal1 bigint; v_held bigint;
  v_mw bigint; v_mw0 bigint;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  BEGIN
    v_cust := gen_random_uuid(); v_own := gen_random_uuid();
    v_dpromo := gen_random_uuid(); v_drv := gen_random_uuid();
    v_sfx := substr(replace(gen_random_uuid()::text,'-',''),1,10);
    PERFORM public._qa_s13_user(v_cust,'c'); PERFORM public._qa_s13_user(v_own,'m');
    PERFORM public._qa_s13_user(v_dpromo,'dp'); PERFORM public._qa_s13_user(v_drv,'dv');

    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,id_doc_url,vehicle_photo_url)
    VALUES (v_dpromo,'approved','moto','x','y'),(v_drv,'approved','moto','x','y')
    ON CONFLICT (user_id) DO UPDATE SET status='approved';

    PERFORM public._qa_s13_wallet(v_cust,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_dpromo,'driver',0,0);
    PERFORM public._qa_s13_wallet(v_drv,'driver',500000,0);

    INSERT INTO public.merchant_stores(owner_user_id, name, slug, status, merchant_status, onboarding_status)
    VALUES (v_own,'QA S13 Store','qa-s13-store-'||v_sfx,'active','active','approved') RETURNING id INTO v_store;
    INSERT INTO public.food_restaurants(slug, name, merchant_store_id, owner_user_id, status)
    VALUES ('qa-s13-resto-'||v_sfx,'QA S13 Resto', v_store, v_own, 'active')
    RETURNING id INTO v_rest;

    PERFORM public._qa_s13_flag('cash_order_funding_enabled', true);
    PERFORM public._qa_s13_flag('chop_pay_enabled', true);
    PERFORM public._qa_s13_flag('chop_pay_checkout_enabled', true);
    PERFORM public._qa_s13_flag('driver_balance_gate_enabled', true);

    -- ================= B: REPAS CASH ORDER =================
    INSERT INTO public.food_orders(user_id, restaurant_id, subtotal_gnf, payment_method, state, fulfillment)
    VALUES (v_cust, v_rest, 100000, 'cash', 'placed', 'delivery') RETURNING id INTO v_o1;
    INSERT INTO public.missions(type, customer_id, ref_food_order_id, estimated_earning_gnf, state)
    VALUES ('food_delivery', v_cust, v_o1, 15000, 'assigned') RETURNING id INTO v_mis;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_q := public.cash_order_quote('repas', v_o1);
    v_e := COALESCE(v_q->'economics', v_q);
    r := r || public._qa_s13_ok('B1.1 courier funds 100% of merchandise subtotal (100000)',
      (v_e->>'cash_funding_gnf')::bigint = 100000, v_e->>'cash_funding_gnf');
    r := r || public._qa_s13_ok('B1.2 platform fee = 1% of merchandise subtotal (1000)',
      (v_e->>'platform_fee_gnf')::bigint = 1000, v_e->>'platform_fee_gnf');
    r := r || public._qa_s13_ok('B1.3 customer cash due = subtotal + delivery + fee (116000)',
      (v_e->>'cash_due_gnf')::bigint = 116000, v_e->>'cash_due_gnf');
    r := r || public._qa_s13_ok('B1.4 delivery fee is not part of funding principal',
      (v_e->>'cash_funding_gnf')::bigint = (v_e->>'merchandise_subtotal_gnf')::bigint, v_e->>'cash_funding_gnf');
    r := r || public._qa_s13_ok('B1.5 cash order carries no delivery commission',
      COALESCE((v_e->>'commission_gnf')::bigint,0) = 0, v_e->>'commission_gnf');

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own), true);
    BEGIN v_res := public.cash_order_merchant_prepare('repas', v_o1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B4.1 kitchen cannot start preparing before funding is secured',
      v_err <> 'NO_ERROR', v_err);

    PERFORM public._qa_s13_flag('driver_starter_credit_enabled', true);
    PERFORM set_config('request.jwt.claims', '', true);
    v_res := public.driver_starter_credit_grant(v_dpromo);
    r := r || public._qa_s13_ok('B2.1 promo-only courier holds 25000 restricted credit',
      v_res->>'status' = 'granted', v_res::text);
    UPDATE public.missions SET courier_id = v_dpromo WHERE id = v_mis;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_dpromo), true);
    BEGIN v_res := public.cash_order_accept('repas', v_o1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B2.2 restricted starting credit can never fund merchandise principal',
      v_err <> 'NO_ERROR', v_err);
    SELECT count(*) INTO v_n FROM public.cash_order_runtime WHERE source_id = v_o1;
    r := r || public._qa_s13_ok('B2.3 refused funding created no cash-order runtime', v_n = 0, v_n::text);

    UPDATE public.missions SET courier_id = v_drv WHERE id = v_mis;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN v_res := public.cash_order_accept('repas', v_o1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B3.1 funded acceptance succeeds', v_err = 'NO_ERROR', COALESCE(v_res::text, v_err));
    SELECT COALESCE(sum(amount_gnf),0) INTO v_held FROM public.mission_financial_holds
      WHERE source_id = v_o1 AND kind = 'cash_funding';
    r := r || public._qa_s13_ok('B3.2 funding hold equals the merchandise subtotal (100000)',
      v_held = 100000, v_held::text);
    SELECT COALESCE(sum(promo_gnf),0) INTO v_n FROM public.mission_financial_holds
      WHERE source_id = v_o1 AND kind = 'cash_funding';
    r := r || public._qa_s13_ok('B3.3 no restricted credit consumed by merchandise funding', v_n = 0, v_n::text);

    v_res := public.cash_order_accept('repas', v_o1);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_id=v_o1 AND kind='cash_funding';
    r := r || public._qa_s13_ok('B5.1 duplicate acceptance creates no second funding hold', v_n = 1, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_dpromo), true);
    BEGIN v_res := public.cash_order_merchant_prepare('repas', v_o1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B5.3 unrelated actor cannot drive another merchant order',
      v_err <> 'NO_ERROR', v_err);

    -- merchant accepts: merchandise funding is secured from the courier hold
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own), true);
    BEGIN v_res := public.cash_order_merchant_accept('repas', v_o1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT COALESCE(funded_gnf,0) INTO v_pay FROM public.merchant_payables
      WHERE source_module='repas' AND source_id = v_o1;
    r := r || public._qa_s13_ok('B4.2 merchant payable funded at merchant acceptance (100000)',
      v_err = 'NO_ERROR' AND v_pay = 100000, format('%s funded=%s', v_err, v_pay));
    BEGIN v_res := public.cash_order_merchant_accept('repas', v_o1); EXCEPTION WHEN OTHERS THEN NULL; END;
    SELECT COALESCE(funded_gnf,0), count(*) INTO v_pay0, v_n FROM public.merchant_payables
      WHERE source_module='repas' AND source_id = v_o1 GROUP BY funded_gnf;
    r := r || public._qa_s13_ok('B5.2 duplicate merchant acceptance funds the merchant only once',
      v_pay0 = v_pay AND v_n = 1, format('%s vs %s (rows %s)', v_pay0, v_pay, v_n));

    BEGIN v_res := public.cash_order_merchant_prepare('repas', v_o1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B4.3 preparation allowed once funding is secured', v_err = 'NO_ERROR', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN v_res := public.cash_order_customer_cancel('repas', v_o1, 'qa'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B7.1 Repas customer cancellation refused once preparation started',
      v_err <> 'NO_ERROR', v_err);

    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT balance_gnf INTO v_mw0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN v_res := public.cash_order_complete_cash('repas', v_o1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT balance_gnf INTO v_mw FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('B6.1 platform fee captured to the master wallet (1000)',
      v_err = 'NO_ERROR' AND v_mw - v_mw0 = 1000, format('%s %s -> %s', v_err, v_mw0, v_mw));
    SELECT held_gnf INTO v_held FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s13_ok('B6.2 funding hold fully resolved on completion', v_held = 0, v_held::text);
    BEGIN v_res := public.cash_order_complete_cash('repas', v_o1); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN v_res := public.cash_order_complete_cash('repas', v_o1); EXCEPTION WHEN OTHERS THEN NULL; END;
    SELECT balance_gnf INTO v_n FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s13_ok('B6.3 duplicate completion moves 0 additional GNF (courier)',
      v_n = v_bal1, format('%s vs %s', v_n, v_bal1));
    SELECT balance_gnf INTO v_n FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('B6.4 duplicate completion moves 0 additional GNF (platform)',
      v_n = v_mw, format('%s vs %s', v_n, v_mw));

    -- ================= C: REPAS CHOP PAY ORDER =================
    INSERT INTO public.food_orders(user_id, restaurant_id, subtotal_gnf, payment_method, state, fulfillment)
    VALUES (v_cust, v_rest, 200000, 'wallet', 'placed', 'delivery') RETURNING id INTO v_o2;
    INSERT INTO public.missions(type, customer_id, ref_food_order_id, estimated_earning_gnf, state, courier_id)
    VALUES ('food_delivery', v_cust, v_o2, 20000, 'assigned', v_drv) RETURNING id INTO v_mis;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN v_q := public.chop_pay_quote('repas', v_o2); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_q := '{}'::jsonb; END;
    v_e := COALESCE(v_q->'economics', v_q);
    r := r || public._qa_s13_ok('C1.1 courier collateral = 50% of merchandise subtotal only (100000)',
      (v_e->>'collateral_gnf')::bigint = 100000, COALESCE(v_e::text, v_err));
    r := r || public._qa_s13_ok('C1.2 delivery fee excluded from the collateral basis',
      COALESCE((v_e#>>'{requirement,collateral_basis_gnf}')::bigint,
               (v_e->>'merchandise_subtotal_gnf')::bigint) = 200000, v_e::text);

    SELECT balance_gnf, held_gnf INTO v_bal0, v_held FROM public.wallets
      WHERE owner_user_id = v_cust AND party_type = 'client';
    BEGIN v_res := public.chop_pay_authorize_order('repas', v_o2); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf, held_gnf INTO v_bal1, v_n FROM public.wallets
      WHERE owner_user_id = v_cust AND party_type = 'client';
    r := r || public._qa_s13_ok('C2.1 customer authorization holds funds without spending them',
      v_err = 'NO_ERROR' AND v_bal1 = v_bal0 AND v_n > v_held,
      format('%s bal %s held %s->%s', v_err, v_bal1, v_held, v_n));
    BEGIN v_res := public.chop_pay_authorize_order('repas', v_o2); EXCEPTION WHEN OTHERS THEN NULL; END;
    SELECT held_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('C2.2 duplicate authorization does not double-hold customer funds',
      v_bal0 = v_n, format('%s vs %s', v_bal0, v_n));

    INSERT INTO public.food_orders(user_id, restaurant_id, subtotal_gnf, payment_method, state, fulfillment)
    VALUES (v_cust, v_rest, 50000, 'wallet', 'placed', 'delivery') RETURNING id INTO v_o3;
    PERFORM public._qa_s13_flag('chop_pay_checkout_enabled', false);
    BEGIN v_res := public.chop_pay_authorize_order('repas', v_o3); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C3.1 Chop Pay checkout rail OFF blocks new authorizations',
      v_err <> 'NO_ERROR', v_err);
    SELECT count(*) INTO v_n FROM public.chop_pay_order_runtime WHERE source_id = v_o3;
    r := r || public._qa_s13_ok('C3.2 blocked authorization created no runtime record', v_n = 0, v_n::text);
    PERFORM public._qa_s13_flag('chop_pay_checkout_enabled', true);

    -- ================= D: MARCHE CASH ORDER =================
    INSERT INTO public.marketplace_listings(seller_id, category, title, merchant_store_id)
    VALUES (v_own, 'divers', 'QA S13 Article', v_store) RETURNING id INTO v_lst;
    INSERT INTO public.marketplace_offers(listing_id, merchant_store_id, buyer_user_id, merchant_user_id,
      offer_amount_gnf, status, metadata)
    VALUES (v_lst, v_store, v_cust, v_own, 150000, 'accepted', '{"payment_method":"cash"}'::jsonb)
    RETURNING id INTO v_m1;
    INSERT INTO public.missions(type, customer_id, ref_market_order_id, estimated_earning_gnf, state, courier_id)
    VALUES ('marketplace_delivery', v_cust, v_m1, 25000, 'assigned', v_drv) RETURNING id INTO v_mmis;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN v_q := public.cash_order_quote('marche', v_m1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_q := '{}'::jsonb; END;
    v_e := COALESCE(v_q->'economics', v_q);
    r := r || public._qa_s13_ok('D1.1 Marche courier funds 100% of merchandise (150000)',
      (v_e->>'cash_funding_gnf')::bigint = 150000, COALESCE(v_e::text, v_err));
    r := r || public._qa_s13_ok('D1.2 Marche platform fee = 1% of merchandise (1500)',
      (v_e->>'platform_fee_gnf')::bigint = 1500, v_e->>'platform_fee_gnf');
    r := r || public._qa_s13_ok('D1.3 Marche customer cash due = 150000 + 25000 + 1500 = 176500',
      (v_e->>'cash_due_gnf')::bigint = 176500, v_e->>'cash_due_gnf');

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN v_res := public.cash_order_accept('marche', v_m1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D2.1 Marche funded acceptance succeeds', v_err = 'NO_ERROR', v_err);
    SELECT COALESCE(sum(amount_gnf),0) INTO v_held FROM public.mission_financial_holds
      WHERE source_id = v_m1 AND kind = 'cash_funding';
    r := r || public._qa_s13_ok('D2.2 Marche funding hold equals merchandise subtotal (150000)',
      v_held = 150000, v_held::text);
    BEGIN v_res := public.cash_order_accept('marche', v_m1); EXCEPTION WHEN OTHERS THEN NULL; END;
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
      WHERE source_id = v_m1 AND kind = 'cash_funding';
    r := r || public._qa_s13_ok('D2.3 Marche duplicate acceptance creates no second hold', v_n = 1, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own), true);
    BEGIN v_res := public.cash_order_merchant_reject('marche', v_m1, 'qa'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D3.1 Marche merchant rejection before funding succeeds',
      v_err = 'NO_ERROR', COALESCE(v_res::text, v_err));
    SELECT COALESCE(held_gnf,0) INTO v_held FROM public.wallets
      WHERE owner_user_id = v_drv AND party_type = 'driver';
    r := r || public._qa_s13_ok('D3.2 Marche rejection releases the courier funding hold',
      v_held = 0, v_held::text);
    BEGIN v_res := public.cash_order_merchant_reject('marche', v_m1, 'qa'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D3.3 Marche duplicate rejection is inert',
      v_res->>'status' = 'already_rejected', COALESCE(v_res::text, v_err));

    -- ================= E: MARCHE CHOP PAY ORDER =================
    INSERT INTO public.marketplace_offers(listing_id, merchant_store_id, buyer_user_id, merchant_user_id,
      offer_amount_gnf, status, metadata)
    VALUES (v_lst, v_store, v_cust, v_own, 150000, 'accepted', '{"payment_method":"choppay"}'::jsonb)
    RETURNING id INTO v_m2;
    INSERT INTO public.missions(type, customer_id, ref_market_order_id, estimated_earning_gnf, state, courier_id)
    VALUES ('marketplace_delivery', v_cust, v_m2, 25000, 'assigned', v_drv) RETURNING id INTO v_mmis;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN v_q := public.chop_pay_quote('marche', v_m2); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_q := '{}'::jsonb; END;
    v_e := COALESCE(v_q->'economics', v_q);
    r := r || public._qa_s13_ok('E1.1 Marche Chop Pay order total = 176500 (canonical anchor)',
      (v_e->>'order_total_gnf')::bigint = 176500, COALESCE(v_e::text, v_err));
    r := r || public._qa_s13_ok('E1.2 Marche Chop Pay platform fee = 1500',
      (v_e->>'platform_fee_gnf')::bigint = 1500, v_e->>'platform_fee_gnf');
    r := r || public._qa_s13_ok('E1.3 Marche Chop Pay courier collateral = 50% of merchandise (75000)',
      (v_e->>'collateral_gnf')::bigint = 75000, v_e->>'collateral_gnf');

    SELECT balance_gnf, held_gnf INTO v_bal0, v_held FROM public.wallets
      WHERE owner_user_id = v_cust AND party_type = 'client';
    BEGIN v_res := public.chop_pay_authorize_order('marche', v_m2); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf, held_gnf INTO v_bal1, v_n FROM public.wallets
      WHERE owner_user_id = v_cust AND party_type = 'client';
    r := r || public._qa_s13_ok('E2.1 Marche authorization holds exactly the order total (176500)',
      v_err = 'NO_ERROR' AND v_bal1 = v_bal0 AND v_n - v_held = 176500,
      format('%s bal %s held %s->%s', v_err, v_bal1, v_held, v_n));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_dpromo), true);
    BEGIN v_res := public.chop_pay_merchant_accept('marche', v_m2); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('E2.2 unrelated actor cannot capture merchandise on a Chop Pay order',
      v_err <> 'NO_ERROR', v_err);

    SELECT COALESCE(sum(funded_gnf),0) INTO v_pay0 FROM public.merchant_payables
      WHERE source_module='marche' AND source_id = v_m2;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own), true);
    BEGIN v_res := public.chop_pay_merchant_accept('marche', v_m2); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT COALESCE(sum(funded_gnf),0) INTO v_pay FROM public.merchant_payables
      WHERE source_module='marche' AND source_id = v_m2;
    r := r || public._qa_s13_ok('E3.1 merchant funded exactly the merchandise amount (150000)',
      v_err = 'NO_ERROR' AND v_pay - v_pay0 = 150000, format('%s %s -> %s', v_err, v_pay0, v_pay));
    BEGIN v_res := public.chop_pay_merchant_accept('marche', v_m2); EXCEPTION WHEN OTHERS THEN NULL; END;
    SELECT COALESCE(sum(funded_gnf),0) INTO v_n FROM public.merchant_payables
      WHERE source_module='marche' AND source_id = v_m2;
    r := r || public._qa_s13_ok('E3.2 duplicate merchant acceptance captures nothing more',
      v_n = v_pay, format('%s vs %s', v_n, v_pay));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN v_res := public.chop_pay_customer_cancel('marche', v_m2, 'qa'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('E4.1 Chop Pay cancellation refused once merchandise is funded',
      v_err <> 'NO_ERROR', v_err);

    -- ================= LEDGER INTEGRITY =================
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j
       JOIN public.ledger_postings p ON p.journal_id = j.id
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('B13.1 no imbalanced journal after order fixtures', v_n = 0, v_n::text);
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings;
    r := r || public._qa_s13_ok('B13.2 global ledger sum is zero', v_n = 0, v_n::text);

    RAISE EXCEPTION 'QA_S13_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S13_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS_PART3_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', '', true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z3.1 master wallet DEF-FIN-001 unchanged (-100435)',
    v_master1 = v_master0 AND v_master1 = -100435, v_master1::text);
  r := r || public._qa_s13_ok('Z3.2 live feature flags byte-identical after fixture rollback',
    v_flags1 = v_flags0, NULL);

  RETURN public._qa_s13_summary(3, r);
END $function$;

REVOKE ALL ON FUNCTION public._qa_s13_run3() FROM PUBLIC, anon, authenticated;

INSERT INTO public._qa_s13_results(part, result) SELECT 3, public._qa_s13_run3();