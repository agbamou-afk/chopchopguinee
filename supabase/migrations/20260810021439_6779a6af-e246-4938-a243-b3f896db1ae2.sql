CREATE OR REPLACE FUNCTION public._qa_s4_run()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  v_pass int; v_total int;
  v_master_before bigint; v_master_after bigint;
  v_cust uuid; v_drv uuid; v_poor uuid; v_own uuid; v_adm uuid;
  v_store uuid; v_rest uuid; v_listing uuid;
  v_fo uuid; v_fo2 uuid; v_fo3 uuid; v_fo4 uuid; v_fo5 uuid; v_fo6 uuid; v_fo7 uuid; v_fo8 uuid;
  v_ms uuid; v_ms2 uuid; v_ms4 uuid; v_ms5 uuid; v_ms6 uuid; v_ms7 uuid; v_ms8 uuid;
  v_off uuid; v_off2 uuid; v_off3 uuid;
  v_mo uuid; v_mo2 uuid; v_mo3 uuid;
  v_j jsonb; v_err text; v_n bigint; v_n2 bigint; v_b bigint; v_b2 bigint; v_txt text;
  v_dwbal bigint; v_dwheld bigint; v_mwbal bigint;
BEGIN
  SELECT balance_gnf INTO v_master_before FROM public.wallets WHERE party_type = 'master' LIMIT 1;

  BEGIN
    v_cust := gen_random_uuid(); v_drv := gen_random_uuid();
    v_poor := gen_random_uuid(); v_own := gen_random_uuid(); v_adm := gen_random_uuid();

    INSERT INTO public.admin_users(user_id, admin_role, status) VALUES (v_adm, 'finance_admin', 'active');

    INSERT INTO public.driver_profiles(user_id, status, vehicle_type, capabilities)
    VALUES (v_drv, 'approved', 'moto', ARRAY['repas_delivery','marche_delivery']),
           (v_poor, 'approved', 'moto', ARRAY['repas_delivery','marche_delivery']);

    INSERT INTO public.wallets(owner_user_id, party_type, balance_gnf)
    VALUES (v_drv, 'driver', 5000000), (v_poor, 'driver', 1000);

    INSERT INTO public.driver_promo_credits(driver_user_id, grant_key, granted_gnf, state)
    VALUES (v_drv, 'qa_s4_promo_' || v_drv::text, 25000, 'active');

    INSERT INTO public.merchant_stores(id, owner_user_id, slug, name, status, onboarding_status)
    VALUES (gen_random_uuid(), v_own, 'qa-s4-store-' || substr(v_own::text,1,8), 'QA S4 Store', 'active', 'approved')
    RETURNING id INTO v_store;

    INSERT INTO public.food_restaurants(slug, name, owner_user_id, merchant_store_id, status)
    VALUES ('qa-s4-rest-' || substr(v_own::text,1,8), 'QA S4 Resto', v_own, v_store, 'active')
    RETURNING id INTO v_rest;

    INSERT INTO public.marketplace_listings(seller_id, kind, category, title, price_gnf, status,
      visibility, pricing_mode, allow_offers, quantity_in_stock, store_id)
    VALUES (v_own, 'merchant', 'alimentation', 'QA S4 Listing', 150000, 'active',
      'public', 'negotiable', true, 10, v_store)
    RETURNING id INTO v_listing;

    UPDATE public.feature_flags SET enabled = true WHERE key = 'cash_order_funding_enabled';
    r := r || public._qa_s4_ok('F0 fixtures + flag ON for QA',
      public._finance_flag('cash_order_funding_enabled'));

    INSERT INTO public.food_orders(user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf)
    VALUES (v_cust, v_rest, 'delivery', 'cash', 150000) RETURNING id INTO v_fo;
    INSERT INTO public.missions(type, customer_id, ref_food_order_id, estimated_earning_gnf, merchant_store_id)
    VALUES ('food_delivery', v_cust, v_fo, 25000, v_store) RETURNING id INTO v_ms;

    -- ============================================================
    -- A. CANONICAL REPAS CASH LIFECYCLE (150000 / 25000 / 1500)
    -- ============================================================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_ms);

    SELECT count(*) INTO v_n FROM public.cash_order_runtime WHERE source_id = v_fo;
    r := r || public._qa_s4_ok('A1 real mission_claim creates runtime atomically', v_n = 1);

    SELECT merchandise_subtotal_gnf, delivery_fee_gnf, platform_fee_gnf, cash_due_gnf
      INTO v_b, v_n, v_n2, v_b2 FROM public.cash_order_runtime WHERE source_id = v_fo;
    r := r || public._qa_s4_ok('A2 economics 150000/25000/1500 -> cash due 176500',
      v_b = 150000 AND v_n = 25000 AND v_n2 = 1500 AND v_b2 = 176500,
      format('sub=%s del=%s fee=%s due=%s', v_b, v_n, v_n2, v_b2));

    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_id = v_fo AND kind IN ('cash_funding','platform_fee') AND state = 'held';
    r := r || public._qa_s4_ok('A3 cash_funding + platform_fee holds placed', v_n = 2);

    SELECT promo_gnf INTO v_n FROM public.mission_financial_holds
     WHERE source_id = v_fo AND kind = 'cash_funding';
    r := r || public._qa_s4_ok('A4 restricted promo NEVER funds merchandise principal', v_n = 0,
      format('promo_in_cash_funding=%s', v_n));
    SELECT promo_gnf INTO v_n FROM public.mission_financial_holds
     WHERE source_id = v_fo AND kind = 'platform_fee';
    r := r || public._qa_s4_ok('A5 restricted promo MAY fund the 1% platform fee', v_n = 1500,
      format('promo_in_fee=%s', v_n));

    SELECT held_gnf INTO v_dwheld FROM public.wallets WHERE owner_user_id = v_drv AND party_type='driver';
    r := r || public._qa_s4_ok('A6 driver held_gnf = 151500 after acceptance', v_dwheld = 151500,
      format('held=%s', v_dwheld));

    SELECT state INTO v_txt FROM public.missions WHERE id = v_ms;
    r := r || public._qa_s4_ok('A7 mission moved to heading_to_pickup', v_txt = 'heading_to_pickup', v_txt);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own), true);
    PERFORM public.cash_order_merchant_accept('repas', v_fo);
    SELECT balance_gnf INTO v_mwbal FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    r := r || public._qa_s4_ok('A8 merchant credited exactly +150000 once', v_mwbal = 150000,
      format('merchant_balance=%s', v_mwbal));
    SELECT state INTO v_txt FROM public.food_orders WHERE id = v_fo;
    r := r || public._qa_s4_ok('A9 food order synchronised to confirmed', v_txt = 'confirmed', v_txt);

    v_j := public.cash_order_merchant_accept('repas', v_fo);
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    r := r || public._qa_s4_ok('A10 replayed merchant accept is inert',
      v_j->>'status' = 'already_accepted' AND v_b = 150000);

    PERFORM public.cash_order_merchant_prepare('repas', v_fo);
    SELECT state INTO v_txt FROM public.cash_order_runtime WHERE source_id = v_fo;
    r := r || public._qa_s4_ok('A11 preparation lock reached', v_txt = 'preparing', v_txt);
    SELECT state INTO v_txt FROM public.food_orders WHERE id = v_fo;
    r := r || public._qa_s4_ok('A12 food order synchronised to preparing', v_txt = 'preparing', v_txt);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN
      PERFORM public.cash_order_complete_cash('repas', v_fo);
      r := r || public._qa_s4_ok('A13 completion blocked before custody', false, 'no error raised');
    EXCEPTION WHEN OTHERS THEN
      r := r || public._qa_s4_ok('A13 completion blocked before custody',
        SQLERRM LIKE '%CUSTODY_NOT_ESTABLISHED%', SQLERRM);
    END;

    PERFORM public.mission_confirm_pickup(v_ms);
    PERFORM public.mission_confirm_dropoff(v_ms);

    SELECT state, cash_collected_gnf, cash_principal_recovery_gnf,
           cash_delivery_earning_gnf, cash_fee_recovery_gnf
      INTO v_txt, v_n, v_n2, v_b2, v_dwbal FROM public.cash_order_runtime WHERE source_id = v_fo;
    r := r || public._qa_s4_ok('A14 canonical dropoff completes runtime with cash fields',
      v_txt='completed' AND v_n=176500 AND v_n2=150000 AND v_b2=25000 AND v_dwbal=1500,
      format('%s collected=%s princ=%s earn=%s fee=%s', v_txt, v_n, v_n2, v_b2, v_dwbal));

    SELECT state INTO v_txt FROM public.food_orders WHERE id = v_fo;
    r := r || public._qa_s4_ok('A15 food order completed', v_txt = 'completed', v_txt);
    SELECT state INTO v_txt FROM public.missions WHERE id = v_ms;
    r := r || public._qa_s4_ok('A16 mission delivered', v_txt = 'delivered', v_txt);

    SELECT count(*) INTO v_n FROM public.wallet_transactions
     WHERE related_user_id = v_drv AND type IN ('ride_earning','mission_earning')
       AND related_entity = 'repas:' || v_fo::text;
    r := r || public._qa_s4_ok('A17 no fake driver wallet earning credit for physical cash', v_n = 0);

    SELECT balance_gnf, held_gnf INTO v_dwbal, v_dwheld
      FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s4_ok('A18 driver wallet out exactly 151500 (150000+1500)',
      v_dwbal = 5000000 - 151500 AND v_dwheld = 0, format('bal=%s held=%s', v_dwbal, v_dwheld));

    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master';
    r := r || public._qa_s4_ok('A19 master captured exactly +1500 once',
      v_b = v_master_before + 1500, format('master=%s', v_b));

    v_j := public.cash_order_complete_cash('repas', v_fo);
    SELECT balance_gnf INTO v_b2 FROM public.wallets WHERE party_type='master';
    r := r || public._qa_s4_ok('A20 replayed completion adds zero',
      v_j->>'status' = 'already_completed' AND v_b2 = v_b);

    SELECT COALESCE(SUM(p.amount_gnf),0) INTO v_n FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id = p.journal_id WHERE j.source_id = v_fo;
    r := r || public._qa_s4_ok('A21 economic drift on the source is exactly 0', v_n = 0,
      format('sum=%s', v_n));

    SELECT count(*) INTO v_n FROM public.ledger_journals j
     WHERE j.source_id = v_fo
       AND ((SELECT count(*) FROM public.ledger_postings p WHERE p.journal_id=j.id AND p.amount_gnf<>0) < 2);
    r := r || public._qa_s4_ok('A22 every journal has >=2 non-zero postings', v_n = 0);

    -- ============================================================
    -- B. NEGATIVE / GUARD PATHS (Repas)
    -- ============================================================
    INSERT INTO public.food_orders(user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf)
    VALUES (v_cust, v_rest, 'delivery', 'cash', 150000) RETURNING id INTO v_fo2;
    INSERT INTO public.missions(type, customer_id, ref_food_order_id, estimated_earning_gnf, merchant_store_id)
    VALUES ('food_delivery', v_cust, v_fo2, 25000, v_store) RETURNING id INTO v_ms2;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_poor), true);
    BEGIN
      PERFORM public.mission_claim(v_ms2);
      v_err := NULL;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT courier_id::text INTO v_txt FROM public.missions WHERE id = v_ms2;
    SELECT count(*) INTO v_n FROM public.cash_order_runtime WHERE source_id = v_fo2;
    SELECT count(*) INTO v_n2 FROM public.mission_financial_holds WHERE source_id = v_fo2;
    SELECT count(*) INTO v_b FROM public.merchant_payables WHERE source_id = v_fo2;
    r := r || public._qa_s4_ok('B1 insufficient funds -> claim rejected, courier NULL, no runtime/holds/payable',
      v_err LIKE '%INSUFFICIENT_DRIVER_BALANCE%' AND v_txt IS NULL AND v_n=0 AND v_n2=0 AND v_b=0,
      COALESCE(v_err,'no error'));

    BEGIN
      UPDATE public.food_orders SET state = 'confirmed' WHERE id = v_fo2;
      v_err := NULL;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s4_ok('B2 cash order direct state write denied before any runtime exists',
      v_err LIKE '%CASH_ORDER_STATE_ENGINE_ONLY%', COALESCE(v_err,'no error'));

    INSERT INTO public.food_orders(user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf)
    VALUES (v_cust, v_rest, 'delivery', 'wallet', 90000) RETURNING id INTO v_fo3;
    BEGIN
      UPDATE public.food_orders SET state = 'confirmed' WHERE id = v_fo3;
      v_err := NULL;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT state INTO v_txt FROM public.food_orders WHERE id = v_fo3;
    r := r || public._qa_s4_ok('B3 non-cash direct lifecycle still works',
      v_err IS NULL AND v_txt = 'confirmed', COALESCE(v_err, v_txt));

    UPDATE public.feature_flags SET enabled = false WHERE key = 'cash_order_funding_enabled';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN
      PERFORM public.mission_claim(v_ms2);
      v_err := NULL;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT courier_id::text INTO v_txt FROM public.missions WHERE id = v_ms2;
    SELECT count(*) INTO v_n FROM public.cash_order_runtime WHERE source_id = v_fo2;
    r := r || public._qa_s4_ok('B4 flag OFF rolls back claim entirely (no partial assignment)',
      v_err LIKE '%CASH_ORDER_FUNDING_DISABLED%' AND v_txt IS NULL AND v_n = 0, COALESCE(v_err,'no error'));
    BEGIN
      UPDATE public.food_orders SET state = 'confirmed' WHERE id = v_fo2;
      v_err := NULL;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s4_ok('B5 flag OFF does not open a legacy direct-write bypass',
      v_err LIKE '%CASH_ORDER_STATE_ENGINE_ONLY%', COALESCE(v_err,'no error'));
    UPDATE public.feature_flags SET enabled = true WHERE key = 'cash_order_funding_enabled';

    -- ============================================================
    -- C. CUSTOMER CANCELLATION + MERCHANT REJECTION
    -- ============================================================
    INSERT INTO public.food_orders(user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf)
    VALUES (v_cust, v_rest, 'delivery', 'cash', 150000) RETURNING id INTO v_fo4;
    INSERT INTO public.missions(type, customer_id, ref_food_order_id, estimated_earning_gnf, merchant_store_id)
    VALUES ('food_delivery', v_cust, v_fo4, 25000, v_store) RETURNING id INTO v_ms4;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_ms4);
    SELECT held_gnf INTO v_dwheld FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_j := public.cash_order_customer_cancel('repas', v_fo4, 'qa cancel');
    SELECT count(*) INTO v_n FROM public.customer_cancellation_debts WHERE source_id = v_fo4;
    SELECT held_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT state INTO v_txt FROM public.cash_order_runtime WHERE source_id = v_fo4;
    r := r || public._qa_s4_ok('C1 customer cancel after dispatch: one debt, holds released, runtime cancelled',
      v_j->>'stage' = 'after_dispatch' AND v_n = 1 AND v_b = v_dwheld - 151500 AND v_txt = 'cancelled',
      format('debts=%s held=%s state=%s', v_n, v_b, v_txt));
    SELECT state INTO v_txt FROM public.missions WHERE id = v_ms4;
    SELECT state INTO v_err FROM public.food_orders WHERE id = v_fo4;
    r := r || public._qa_s4_ok('C2 source + mission coherent after cancellation',
      v_txt = 'failed' AND v_err = 'cancelled', format('mission=%s order=%s', v_txt, v_err));
    v_j := public.cash_order_customer_cancel('repas', v_fo4, 'qa cancel');
    SELECT count(*) INTO v_n2 FROM public.customer_cancellation_debts WHERE source_id = v_fo4;
    r := r || public._qa_s4_ok('C3 replayed cancellation creates no second debt',
      v_j->>'status' = 'already_cancelled' AND v_n2 = 1);

    INSERT INTO public.food_orders(user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf)
    VALUES (v_cust, v_rest, 'delivery', 'cash', 150000) RETURNING id INTO v_fo5;
    INSERT INTO public.missions(type, customer_id, ref_food_order_id, estimated_earning_gnf, merchant_store_id)
    VALUES ('food_delivery', v_cust, v_fo5, 25000, v_store) RETURNING id INTO v_ms5;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_ms5);
    SELECT held_gnf INTO v_dwheld FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT balance_gnf INTO v_mwbal FROM public.wallets WHERE party_type='master';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own), true);
    PERFORM public.cash_order_merchant_reject('repas', v_fo5, 'rupture stock');
    SELECT held_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT state INTO v_txt FROM public.merchant_payables WHERE source_id = v_fo5;
    SELECT count(*) INTO v_n FROM public.customer_cancellation_debts WHERE source_id = v_fo5;
    SELECT balance_gnf INTO v_b2 FROM public.wallets WHERE party_type='master';
    r := r || public._qa_s4_ok('C4 merchant rejection: holds released, payable reversed, no debt, no fee revenue',
      v_b = v_dwheld - 151500 AND v_txt = 'reversed' AND v_n = 0 AND v_b2 = v_mwbal,
      format('held=%s payable=%s debts=%s', v_b, v_txt, v_n));
    SELECT m.state::text || '/' || o.state::text INTO v_txt
      FROM public.missions m JOIN public.food_orders o ON o.id = v_fo5 WHERE m.id = v_ms5;
    r := r || public._qa_s4_ok('C5 rejected cash mission + order no longer active', v_txt = 'failed/cancelled', v_txt);
    v_j := public.cash_order_merchant_reject('repas', v_fo5, 'again');
    r := r || public._qa_s4_ok('C6 replayed rejection inert', v_j->>'status' = 'already_rejected');

    -- ============================================================
    -- D. MARCHE EXPLICIT TENDER
    -- ============================================================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_off := public.create_marketplace_offer(v_listing, 150000, 'qa cash', 'cash');
    SELECT metadata->>'payment_method' INTO v_txt FROM public.marketplace_offers WHERE id = v_off;
    r := r || public._qa_s4_ok('D1 Marche cash tender persisted atomically in offer creation',
      v_txt = 'cash', COALESCE(v_txt,'null'));

    BEGIN
      PERFORM public.create_marketplace_offer(v_listing, 150000, 'qa bad', 'bitcoin');
      v_err := NULL;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT count(*) INTO v_n FROM public.marketplace_offers
     WHERE listing_id = v_listing AND buyer_message = 'qa bad';
    r := r || public._qa_s4_ok('D2 invalid tender rolls back offer creation entirely',
      v_err LIKE '%INVALID_TENDER%' AND v_n = 0, COALESCE(v_err,'no error'));

    UPDATE public.marketplace_offers SET status = 'accepted' WHERE id = v_off;
    INSERT INTO public.missions(type, customer_id, ref_market_order_id, estimated_earning_gnf, merchant_store_id)
    VALUES ('marketplace_delivery', v_cust, v_off, 25000, v_store) RETURNING id INTO v_mo;

    INSERT INTO public.marketplace_offers(listing_id, merchant_store_id, buyer_user_id, merchant_user_id,
      offer_amount_gnf, status) VALUES (v_listing, v_store, v_cust, v_own, 150000, 'accepted')
    RETURNING id INTO v_off2;
    INSERT INTO public.missions(type, customer_id, ref_market_order_id, estimated_earning_gnf, merchant_store_id)
    VALUES ('marketplace_delivery', v_cust, v_off2, 25000, v_store) RETURNING id INTO v_mo2;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN
      PERFORM public.mission_claim(v_mo2);
      v_err := NULL;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT courier_id::text INTO v_txt FROM public.missions WHERE id = v_mo2;
    SELECT count(*) INTO v_n FROM public.cash_order_runtime WHERE source_id = v_off2;
    SELECT count(*) INTO v_n2 FROM public.mission_financial_holds WHERE source_id = v_off2;
    r := r || public._qa_s4_ok('D3 NULL Marche tender -> MARCHE_TENDER_REQUIRED, no assignment/runtime/holds',
      v_err LIKE '%MARCHE_TENDER_REQUIRED%' AND v_txt IS NULL AND v_n = 0 AND v_n2 = 0,
      COALESCE(v_err,'no error'));
    r := r || public._qa_s4_ok('D4 missing tender is never interpreted as cash',
      public._cash_order_is_cash('marche', v_off2) = false);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_off3 := public.create_marketplace_offer(v_listing, 120000, 'qa choppay', 'choppay');
    UPDATE public.marketplace_offers SET status = 'accepted' WHERE id = v_off3;
    INSERT INTO public.missions(type, customer_id, ref_market_order_id, estimated_earning_gnf, merchant_store_id)
    VALUES ('marketplace_delivery', v_cust, v_off3, 25000, v_store) RETURNING id INTO v_mo3;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_mo3);
    SELECT count(*) INTO v_n FROM public.cash_order_runtime WHERE source_id = v_off3;
    SELECT count(*) INTO v_n2 FROM public.mission_financial_holds WHERE source_id = v_off3;
    SELECT courier_id::text INTO v_txt FROM public.missions WHERE id = v_mo3;
    r := r || public._qa_s4_ok('D5 explicit choppay keeps the non-cash branch (no cash engine)',
      v_n = 0 AND v_n2 = 0 AND v_txt = v_drv::text, format('runtime=%s holds=%s', v_n, v_n2));

    -- ============================================================
    -- E. MARCHE REAL CASH LIFECYCLE
    -- ============================================================
    PERFORM public.mission_claim(v_mo);
    SELECT merchandise_subtotal_gnf, platform_fee_gnf, cash_due_gnf INTO v_b, v_n, v_b2
      FROM public.cash_order_runtime WHERE source_id = v_off;
    r := r || public._qa_s4_ok('E1 Marche cash claim creates runtime + economics atomically',
      v_b = 150000 AND v_n = 1500 AND v_b2 = 176500, format('sub=%s fee=%s due=%s', v_b, v_n, v_b2));
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_id = v_off AND state = 'held';
    r := r || public._qa_s4_ok('E2 Marche holds placed', v_n = 2);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own), true);
    SELECT balance_gnf INTO v_mwbal FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    PERFORM public.cash_order_merchant_accept('marche', v_off);
    PERFORM public.cash_order_merchant_prepare('marche', v_off);
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    SELECT state INTO v_txt FROM public.cash_order_runtime WHERE source_id = v_off;
    r := r || public._qa_s4_ok('E3 Marche merchant funded once + preparation substate',
      v_b = v_mwbal + 150000 AND v_txt = 'preparing', format('merchant=%s state=%s', v_b, v_txt));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_confirm_pickup(v_mo);
    SELECT balance_gnf INTO v_mwbal FROM public.wallets WHERE party_type='master';
    PERFORM public.mission_confirm_dropoff(v_mo);
    SELECT fulfillment_status INTO v_err FROM public.marketplace_offers WHERE id = v_off;
    SELECT state::text INTO v_txt FROM public.missions WHERE id = v_mo;
    r := r || public._qa_s4_ok('E4 Marche delivered: runtime completed + fulfillment delivered + mission delivered',
      (SELECT state FROM public.cash_order_runtime WHERE source_id=v_off) = 'completed'
      AND v_err = 'delivered' AND v_txt = 'delivered',
      format('offer=%s mission=%s', v_err, v_txt));
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master';
    r := r || public._qa_s4_ok('E5 Marche platform fee captured exactly once (+1500)',
      v_b = v_mwbal + 1500, format('master delta=%s', v_b - v_mwbal));
    SELECT count(*) INTO v_n FROM public.wallet_transactions
     WHERE related_user_id = v_drv AND type IN ('ride_earning','mission_earning')
       AND related_entity = 'marche:' || v_off::text;
    r := r || public._qa_s4_ok('E6 no driver wallet earning credit on Marche cash', v_n = 0);
    v_j := public.cash_order_complete_cash('marche', v_off);
    SELECT balance_gnf INTO v_b2 FROM public.wallets WHERE party_type='master';
    r := r || public._qa_s4_ok('E7 Marche completion replay adds zero',
      v_j->>'status' = 'already_completed' AND v_b2 = v_b);
    SELECT COALESCE(SUM(p.amount_gnf),0) INTO v_n FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id = p.journal_id WHERE j.source_id = v_off;
    r := r || public._qa_s4_ok('E8 Marche ledger drift 0', v_n = 0);

    -- ============================================================
    -- F. POST-PREPARATION DISPUTE ECONOMICS
    -- ============================================================
    INSERT INTO public.food_orders(user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf)
    VALUES (v_cust, v_rest, 'delivery', 'cash', 150000) RETURNING id INTO v_fo6;
    INSERT INTO public.missions(type, customer_id, ref_food_order_id, estimated_earning_gnf, merchant_store_id)
    VALUES ('food_delivery', v_cust, v_fo6, 25000, v_store) RETURNING id INTO v_ms6;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_ms6);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own), true);
    PERFORM public.cash_order_merchant_accept('repas', v_fo6);
    PERFORM public.cash_order_merchant_prepare('repas', v_fo6);
    PERFORM public.cash_order_dispute_open('repas', v_fo6, 'colis perdu');

    SELECT balance_gnf INTO v_mwbal FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    BEGIN
      PERFORM public._merchant_payable_reverse_internal('repas', v_fo6, v_store, gen_random_uuid(), 'qa', v_adm);
      v_err := NULL;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    r := r || public._qa_s4_ok('F1 BENEFICIARY_MISMATCH blocks arbitrary reversal, no value moves',
      v_err LIKE '%BENEFICIARY_MISMATCH%' AND v_b = v_mwbal, COALESCE(v_err,'no error'));

    SELECT balance_gnf, held_gnf INTO v_dwbal, v_dwheld
      FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT balance_gnf INTO v_b2 FROM public.wallets WHERE party_type='master';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    v_j := public.admin_cash_order_dispute_resolve('repas', v_fo6, 'release_driver_funding', 'qa release');
    SELECT balance_gnf INTO v_mwbal FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    SELECT balance_gnf, held_gnf INTO v_b, v_n FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT state INTO v_txt FROM public.merchant_payables WHERE source_id = v_fo6;
    r := r || public._qa_s4_ok('F2 release_driver_funding restores captured principal to the driver',
      v_b = v_dwbal + 150000 AND v_n = v_dwheld - 1500 AND v_txt = 'reversed',
      format('driver=%s held=%s payable=%s', v_b, v_n, v_txt));
    SELECT balance_gnf INTO v_b2 FROM public.wallets WHERE party_type='master';
    SELECT count(*) INTO v_n2 FROM public.mission_financial_holds
     WHERE source_id = v_fo6 AND state IN ('held','frozen','partially_captured');
    r := r || public._qa_s4_ok('F3 fee hold released, zero platform fee revenue, nothing encumbered',
      v_n2 = 0 AND (v_j->'result'->>'platform_fee_captured_gnf') = '0');
    SELECT COALESCE(SUM(amount_gnf),0) INTO v_n FROM public.ledger_postings
     WHERE journal_id IN (SELECT id FROM public.ledger_journals WHERE source_id = v_fo6);
    r := r || public._qa_s4_ok('F4 reversal journals balanced (drift 0 on disputed source)', v_n = 0);
    v_j := public.admin_cash_order_dispute_resolve('repas', v_fo6, 'release_driver_funding', 'replay');
    SELECT balance_gnf INTO v_n FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s4_ok('F5 dispute resolution replay moves zero',
      v_j->>'status' = 'already_resolved' AND v_n = v_b);

    INSERT INTO public.food_orders(user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf)
    VALUES (v_cust, v_rest, 'delivery', 'cash', 150000) RETURNING id INTO v_fo7;
    INSERT INTO public.missions(type, customer_id, ref_food_order_id, estimated_earning_gnf, merchant_store_id)
    VALUES ('food_delivery', v_cust, v_fo7, 25000, v_store) RETURNING id INTO v_ms7;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_ms7);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own), true);
    PERFORM public.cash_order_merchant_accept('repas', v_fo7);
    PERFORM public.cash_order_merchant_prepare('repas', v_fo7);
    PERFORM public.cash_order_dispute_open('repas', v_fo7, 'litige');
    SELECT balance_gnf INTO v_mwbal FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    SELECT balance_gnf, held_gnf INTO v_dwbal, v_dwheld FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT balance_gnf INTO v_b2 FROM public.wallets WHERE party_type='master';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    PERFORM public.admin_cash_order_dispute_resolve('repas', v_fo7, 'close_no_value', 'qa close');
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    SELECT balance_gnf, held_gnf INTO v_n, v_n2 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s4_ok('F6 close_no_value: merchant + driver principal unchanged',
      v_b = v_mwbal AND v_n = v_dwbal, format('merchant=%s driver=%s', v_b, v_n));
    r := r || public._qa_s4_ok('F7 close_no_value releases the stuck platform-fee hold',
      v_n2 = v_dwheld - 1500, format('held %s -> %s', v_dwheld, v_n2));
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master';
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_id = v_fo7 AND state IN ('held','frozen','partially_captured');
    r := r || public._qa_s4_ok('F8 close_no_value captures no fee revenue and leaves nothing encumbered',
      v_b = v_b2 AND v_n = 0);

    INSERT INTO public.food_orders(user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf)
    VALUES (v_cust, v_rest, 'delivery', 'cash', 150000) RETURNING id INTO v_fo8;
    INSERT INTO public.missions(type, customer_id, ref_food_order_id, estimated_earning_gnf, merchant_store_id)
    VALUES ('food_delivery', v_cust, v_fo8, 25000, v_store) RETURNING id INTO v_ms8;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_ms8);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_own), true);
    PERFORM public.cash_order_merchant_accept('repas', v_fo8);
    PERFORM public.cash_order_merchant_prepare('repas', v_fo8);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_confirm_pickup(v_ms8);
    PERFORM public.cash_order_dispute_open('repas', v_fo8, 'contestation livraison');
    SELECT balance_gnf INTO v_b2 FROM public.wallets WHERE party_type='master';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    PERFORM public.admin_cash_order_dispute_resolve('repas', v_fo8, 'complete_as_delivered', 'qa deliver');
    SELECT cash_collected_gnf, cash_principal_recovery_gnf, cash_delivery_earning_gnf, cash_fee_recovery_gnf
      INTO v_n, v_n2, v_b, v_dwbal FROM public.cash_order_runtime WHERE source_id = v_fo8;
    r := r || public._qa_s4_ok('F9 complete_as_delivered populates true cash recovery fields',
      v_n = 176500 AND v_n2 = 150000 AND v_b = 25000 AND v_dwbal = 1500,
      format('%s/%s/%s/%s', v_n, v_n2, v_b, v_dwbal));
    SELECT o.state::text || '/' || m.state::text INTO v_txt
      FROM public.food_orders o JOIN public.missions m ON m.id = v_ms8 WHERE o.id = v_fo8;
    r := r || public._qa_s4_ok('F10 complete_as_delivered completes source + mission', v_txt = 'completed/delivered', v_txt);
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master';
    SELECT count(*) INTO v_n FROM public.wallet_transactions
     WHERE related_user_id = v_drv AND type IN ('ride_earning','mission_earning')
       AND related_entity = 'repas:' || v_fo8::text;
    r := r || public._qa_s4_ok('F11 fee captured exactly once, no wallet earning credit',
      v_b = v_b2 + 1500 AND v_n = 0, format('master delta=%s', v_b - v_b2));
    v_j := public.admin_cash_order_dispute_resolve('repas', v_fo8, 'complete_as_delivered', 'replay');
    SELECT balance_gnf INTO v_n FROM public.wallets WHERE party_type='master';
    r := r || public._qa_s4_ok('F12 dispute completion replay adds zero',
      v_j->>'status' = 'already_resolved' AND v_n = v_b);

    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE public.cash_order_runtime SET state = 'disputed', disputed_at = now(),
           dispute_resolution = NULL, resolved_at = NULL, resolved_by = NULL
     WHERE source_id = v_fo8;
    UPDATE public.merchant_payables SET state = 'settled', settled_gnf = amount_gnf,
           funded_gnf = amount_gnf, funding_source = 'driver_cash_funding'
     WHERE source_id = v_fo8;
    SELECT balance_gnf INTO v_mwbal FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    SELECT balance_gnf INTO v_dwbal FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    BEGIN
      PERFORM public.admin_cash_order_dispute_resolve('repas', v_fo8, 'release_driver_funding', 'qa unrecoverable');
      v_err := NULL;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_own AND party_type='merchant';
    SELECT balance_gnf INTO v_b2 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT state INTO v_txt FROM public.cash_order_runtime WHERE source_id = v_fo8;
    r := r || public._qa_s4_ok('F13 settled payable -> FINANCE_RECONCILIATION_REQUIRED, no fabricated value',
      v_err LIKE '%FINANCE_RECONCILIATION_REQUIRED%' AND v_b = v_mwbal AND v_b2 = v_dwbal
      AND v_txt = 'disputed', COALESCE(v_err,'no error'));

    -- ============================================================
    -- G. PRIVILEGE MATRIX
    -- ============================================================
    SELECT count(*) INTO v_n FROM pg_proc p
      JOIN pg_namespace ns ON ns.oid = p.pronamespace
     WHERE ns.nspname = 'public'
       AND p.proname IN ('_merchant_payable_create_internal','_merchant_payable_fund_internal',
         '_merchant_payable_reverse_internal','_driver_mission_hold_release_internal',
         '_customer_cancellation_debt_create_internal','_cash_order_accept_internal',
         '_cash_order_complete_internal','_cash_order_capture_platform_fee','_ledger_post',
         '_ledger_reverse','_promo_consume')
       AND (p.proacl IS NULL
            OR has_function_privilege('anon', p.oid, 'EXECUTE')
            OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
    r := r || public._qa_s4_ok('G1 raw money primitives are service-role only', v_n = 0,
      format('violations=%s', v_n));

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
     WHERE ns.nspname='public'
       AND p.proname IN ('cash_order_merchant_accept','cash_order_merchant_reject',
         'cash_order_merchant_prepare','cash_order_complete_cash','cash_order_customer_cancel',
         'cash_order_dispute_open','admin_cash_order_dispute_resolve','mission_claim',
         'create_marketplace_offer')
       AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
    r := r || public._qa_s4_ok('G2 participant/admin cash RPCs remain callable by authenticated', v_n = 9,
      format('granted=%s/9', v_n));

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
     WHERE ns.nspname='public' AND p.proname IN ('mission_claim','create_marketplace_offer')
       AND has_function_privilege('anon', p.oid, 'EXECUTE');
    r := r || public._qa_s4_ok('G3 mission_claim + create_marketplace_offer anon=false', v_n = 0);

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
     WHERE ns.nspname='public'
       AND p.proname IN ('ride_accept','ride_dispatch','wallet_internal_transfer',
                         'om_auto_match','wallet_topup_om_credit')
       AND (p.proacl IS NULL OR has_function_privilege('anon', p.oid, 'EXECUTE')
            OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
    r := r || public._qa_s4_ok('G4 Slice 3 inbound-OM / ride guards preserved', v_n = 0,
      format('violations=%s', v_n));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN
      PERFORM public.admin_cash_order_dispute_resolve('repas', v_fo8, 'close_no_value', 'hack');
      v_err := NULL;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s4_ok('G5 non-finance caller cannot resolve a dispute',
      v_err LIKE '%Not authorized%', COALESCE(v_err,'no error'));

    -- ============================================================
    -- H. GLOBAL LEDGER INVARIANTS FOR THE WHOLE RUN
    -- ============================================================
    SELECT count(*) INTO v_n FROM public.ledger_journals j
     WHERE j.created_at > now() - interval '10 minutes'
       AND (SELECT COALESCE(SUM(amount_gnf),0) FROM public.ledger_postings p WHERE p.journal_id=j.id) <> 0;
    r := r || public._qa_s4_ok('H1 all journals created in this run balance to 0', v_n = 0);

    SELECT count(*) INTO v_n FROM public.mission_financial_holds h
     WHERE h.driver_user_id IN (v_drv, v_poor)
       AND h.captured_gnf + h.released_gnf > h.amount_gnf;
    r := r || public._qa_s4_ok('H2 captured + released never exceeds reserved amount', v_n = 0);

    SELECT count(*) INTO v_n FROM public.ledger_journals j
     WHERE j.source_id IN (v_fo, v_fo4, v_fo5, v_fo6, v_fo7, v_fo8, v_off)
       AND j.source_module NOT IN ('repas','marche');
    r := r || public._qa_s4_ok('H3 source attribution exact on every journal', v_n = 0);

    SELECT count(*) INTO v_n FROM public.ledger_journals j
     WHERE j.created_at > now() - interval '10 minutes'
       AND (SELECT count(*) FROM public.ledger_postings p
             WHERE p.journal_id = j.id AND p.amount_gnf <> 0) < 2;
    r := r || public._qa_s4_ok('H4 every journal in this run has >=2 non-zero postings', v_n = 0);

    RAISE EXCEPTION 'QA_S4_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S4_ROLLBACK' THEN
      r := r || public._qa_s4_ok('HARNESS_COMPLETED_WITHOUT_UNEXPECTED_ERROR', false, SQLERRM);
    END IF;
  END;

  SELECT balance_gnf INTO v_master_after FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || public._qa_s4_ok('Z1 master wallet unchanged at -100435 after rollback',
    v_master_after = -100435 AND v_master_after = v_master_before, format('master=%s', v_master_after));

  SELECT count(*) INTO v_n FROM public.cash_order_runtime;
  r := r || public._qa_s4_ok('Z2 zero cash_order_runtime rows remain', v_n = 0, format('rows=%s', v_n));
  SELECT count(*) INTO v_n FROM public.mission_financial_holds;
  r := r || public._qa_s4_ok('Z3 zero mission_financial_holds remain', v_n = 0, format('rows=%s', v_n));
  SELECT count(*) INTO v_n FROM public.merchant_payables;
  r := r || public._qa_s4_ok('Z4 zero merchant_payables remain', v_n = 0, format('rows=%s', v_n));
  SELECT count(*) INTO v_n FROM public.customer_cancellation_debts;
  r := r || public._qa_s4_ok('Z5 zero customer_cancellation_debts remain', v_n = 0, format('rows=%s', v_n));
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-s4-%';
  r := r || public._qa_s4_ok('Z6 zero QA merchant stores remain', v_n = 0);
  SELECT count(*) INTO v_n FROM public.food_restaurants WHERE slug LIKE 'qa-s4-%';
  r := r || public._qa_s4_ok('Z7 zero QA restaurants remain', v_n = 0);
  SELECT count(*) INTO v_n FROM public.marketplace_listings WHERE title = 'QA S4 Listing';
  r := r || public._qa_s4_ok('Z8 zero QA listings/offers remain', v_n = 0);
  SELECT count(*) INTO v_n FROM public.driver_promo_credits WHERE grant_key LIKE 'qa_s4_promo_%';
  r := r || public._qa_s4_ok('Z9 zero QA promo credits remain', v_n = 0);
  SELECT count(*) INTO v_n FROM public.ledger_journals WHERE created_at > now() - interval '10 minutes';
  r := r || public._qa_s4_ok('Z10 zero QA ledger journals persisted', v_n = 0, format('rows=%s', v_n));
  SELECT count(*) INTO v_n FROM public.audit_logs WHERE created_at > now() - interval '10 minutes';
  r := r || public._qa_s4_ok('Z11 zero QA audit rows persisted', v_n = 0, format('rows=%s', v_n));

  SELECT count(*) INTO v_n FROM public.feature_flags
   WHERE key IN ('cash_order_funding_enabled','driver_cashout_enabled','merchant_om_settlement_enabled',
     'om_checkout_enabled','om_direct_checkout_enabled','om_environment','om_marche_checkout_enabled',
     'om_payout_reconciliation_enabled','om_provider_mode','om_repas_checkout_enabled',
     'om_ride_checkout_enabled','om_sandbox_enabled') AND enabled;
  SELECT count(*) INTO v_n2 FROM public.feature_flags WHERE key = 'om_topup_enabled' AND enabled;
  r := r || public._qa_s4_ok('Z12 canonical flags: only om_topup_enabled ON', v_n = 0 AND v_n2 = 1,
    format('other_on=%s topup_on=%s', v_n, v_n2));

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total
    FROM jsonb_array_elements(r) x;

  RETURN jsonb_build_object(
    'total', v_total, 'passed', v_pass, 'failed', v_total - v_pass,
    'failures', (SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) FROM jsonb_array_elements(r) x
                  WHERE NOT (x->>'ok')::boolean),
    'assertions', r);
END; $fn$;

REVOKE ALL ON FUNCTION public._qa_s4_run() FROM PUBLIC, anon, authenticated;

INSERT INTO public._qa_s4_results (report) SELECT public._qa_s4_run();