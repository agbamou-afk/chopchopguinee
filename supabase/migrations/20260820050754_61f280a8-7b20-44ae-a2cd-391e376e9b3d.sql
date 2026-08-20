CREATE OR REPLACE FUNCTION public._qa_node4_marche_r11()
RETURNS jsonb LANGUAGE plpgsql AS $qa$
DECLARE
  r jsonb := '[]'::jsonb;
  v_buy uuid; v_merch uuid; v_merch2 uuid; v_adm uuid; v_drv uuid;
  v_store uuid; v_store2 uuid; l_a uuid;
  v_res jsonb; v_o1 uuid; v_o2 uuid; v_off uuid; v_off_x uuid;
  v_ops jsonb; v_ops2 jsonb; v_ck jsonb; v_rc jsonb; v_au jsonb;
  v_err text; v_n int; v_pay uuid; v_pay_x uuid; v_pay_bad uuid; v_po uuid; v_ev uuid;
  v_w0 bigint; v_w1 bigint; v_wt0 bigint; v_wt1 bigint; v_lj0 bigint; v_lj1 bigint;
  v_pi0 bigint; v_pi1 bigint; v_mp0 bigint; v_mp1 bigint; v_ss0 bigint; v_ss1 bigint;
  v_cp0 bigint; v_cp1 bigint; v_of0 bigint; v_of1 bigint;
  v_reserved0 bigint; v_reserved1 bigint; v_flags0 jsonb; v_flags1 jsonb;
BEGIN
  SELECT count(*) INTO v_w0 FROM public.wallets;
  SELECT count(*) INTO v_wt0 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj0 FROM public.ledger_journals;
  SELECT count(*) INTO v_pi0 FROM public.payment_intents;
  SELECT count(*) INTO v_mp0 FROM public.merchant_payables;
  SELECT count(*) INTO v_ss0 FROM public.merchant_settlement_requests;
  SELECT count(*) INTO v_cp0 FROM public.chop_pay_order_runtime;
  SELECT count(*) INTO v_of0 FROM public.marketplace_offers;
  SELECT COALESCE(sum(quantity_reserved),0) INTO v_reserved0 FROM public.marketplace_listings;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  -- ===== A. STRUCTURAL =====
  r := r || public._qa_s13_ok('N4R11.A1 order ops RPC exists and is definer',
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='marche_merchant_order_ops' AND prosecdef), NULL);
  r := r || public._qa_s13_ok('N4R11.A2 cockpit RPC exists and is definer',
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='marche_merchant_orders_cockpit' AND prosecdef), NULL);
  r := r || public._qa_s13_ok('N4R11.A3 settlement receipt RPC exists and is definer',
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='marche_order_settlement_receipt' AND prosecdef), NULL);
  r := r || public._qa_s13_ok('N4R11.A4 finance audit RPC exists and is definer',
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='marche_finance_order_audit' AND prosecdef), NULL);
  r := r || public._qa_s13_ok('N4R11.A5 every R11 definer pins search_path',
        NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname IN
          ('marche_merchant_order_ops','marche_merchant_orders_cockpit','marche_order_settlement_receipt',
           'marche_finance_order_audit','_marche_order_tender','_marche_order_money',
           '_marche_order_finance_bridge',
           '_marche_merchant_allowed_actions','_marche_merchant_ops_authorized','_marche_order_ops_bucket')
          AND NOT (COALESCE(array_to_string(proconfig,','),'') LIKE '%search_path=public%')), NULL);
  r := r || public._qa_s13_ok('N4R11.A6 anon cannot execute any R11 RPC',
        NOT has_function_privilege('anon','public.marche_merchant_order_ops(uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_merchant_orders_cockpit(uuid,text,integer,integer)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_order_settlement_receipt(uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_finance_order_audit(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R11.A7 R11 internals are not client-callable',
        NOT has_function_privilege('authenticated','public._marche_order_money(public.marche_orders)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._marche_order_tender(public.marche_orders)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._marche_order_finance_bridge(public.marche_orders)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._marche_merchant_allowed_actions(public.marche_orders)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._marche_merchant_ops_authorized(public.marche_orders,uuid)','EXECUTE'), NULL);
  r := r || public._qa_node4_marche_r11_a8();
  r := r || public._qa_s13_ok('N4R11.A9 R11 created no parallel finance table',
        (SELECT count(*) FROM information_schema.tables WHERE table_schema='public'
          AND (table_name LIKE 'marche_payable%' OR table_name LIKE 'marche_settlement%'
               OR table_name LIKE 'marche_payout%')) = 0, NULL);
  r := r || public._qa_s13_ok('N4R11.A10 read models perform no writes',
        NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname IN
          ('marche_merchant_order_ops','marche_order_settlement_receipt','marche_finance_order_audit',
           '_marche_order_money','_marche_order_tender','_marche_order_finance_bridge')
          AND provolatile = 'v'), NULL);
  r := r || public._qa_s13_ok('N4R11.A11 read models never invent a tender',
        (SELECT prosrc FROM pg_proc WHERE proname='_marche_order_tender') LIKE '%Mode non renseigné%', NULL);
  r := r || public._qa_s13_ok('N4R11.A12 money model reads only canonical payables',
        (SELECT prosrc FROM pg_proc WHERE proname='_marche_order_money') LIKE '%public.merchant_payables%'
    AND (SELECT prosrc FROM pg_proc WHERE proname='_marche_order_money') LIKE '%payout_settlement_allocations%', NULL);
  r := r || public._qa_s13_ok('N4R11.A13 anon still cannot execute has_role (P15.5 preserved)',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R11.A14 finance identity bridge exists and is definer',
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='_marche_order_finance_bridge' AND prosecdef), NULL);
  r := r || public._qa_s13_ok('N4R11.A15 finance lookups key only on the bridged finance source',
        (SELECT prosrc FROM pg_proc WHERE proname='_marche_order_money') LIKE '%finance_source_id%'
    AND (SELECT prosrc FROM pg_proc WHERE proname='_marche_order_tender') LIKE '%finance_source_id%'
    AND (SELECT prosrc FROM pg_proc WHERE proname='_marche_order_money') NOT LIKE '%source_id = p_order.id%'
    AND (SELECT prosrc FROM pg_proc WHERE proname='_marche_order_tender') NOT LIKE '%p_order_id%', NULL);
  r := r || public._qa_s13_ok('N4R11.A16 legacy two-uuid tender signature is gone',
        NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='_marche_order_tender'
          AND oid::regprocedure::text LIKE '%(uuid,uuid)%'), NULL);

  BEGIN
    -- ===== FIXTURES =====
    v_buy := gen_random_uuid(); v_merch := gen_random_uuid(); v_merch2 := gen_random_uuid();
    v_adm := gen_random_uuid(); v_drv := gen_random_uuid();
    PERFORM public._qa_s13_user(v_buy,'n411b');
    PERFORM public._qa_s13_user(v_merch,'n411m');
    PERFORM public._qa_s13_user(v_merch2,'n411m2');
    PERFORM public._qa_s13_user(v_adm,'n411a');
    PERFORM public._qa_s13_driver(v_drv,'n411d',0);
    PERFORM public._qa_s13_admin(v_adm);

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status, latitude, longitude, address_label)
      VALUES (v_merch,'qa-n411-a-'||substr(v_merch::text,1,8),'QA N411 Store A','active','approved',9.5370,-13.6785,'QA Madina')
      RETURNING id INTO v_store;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status, latitude, longitude)
      VALUES (v_merch2,'qa-n411-b-'||substr(v_merch2::text,1,8),'QA N411 Store B','active','approved',9.5380,-13.6700)
      RETURNING id INTO v_store2;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    l_a := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N411 Riz',
      'category','Alimentation','price_gnf',10000,'quantity_in_stock',10,'publish',true));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n411-main-0001',
      'delivery_address','QA Kaloum, Conakry',
      'dropoff_lat', 9.5550, 'dropoff_lng', -13.6785,
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 2))));
    v_o1 := (v_res->>'id')::uuid;

    -- ===== B. AUTHORITY =====
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_order_ops(v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R11.B1 buyer cannot read merchant operations', v_err='NOT_AUTHORIZED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch2), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_order_ops(v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R11.B2 another store owner cannot read it', v_err='NOT_AUTHORIZED', v_err);

    v_ck := public.marche_merchant_orders_cockpit(NULL,NULL,40,0);
    r := r || public._qa_s13_ok('N4R11.B3 cockpit is store-scoped, foreign orders invisible',
          NOT (v_ck->'items' @> jsonb_build_array(jsonb_build_object('order_id', v_o1))), NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_order_ops(v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R11.B4 a courier cannot read merchant money', v_err='NOT_AUTHORIZED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_finance_order_audit(v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R11.B5 a plain admin is not finance-privileged',
          v_err='NOT_AUTHORIZED', v_err);

    -- ===== C. OPERATIONS TRUTH =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.C1 committed order is action_required',
          v_ops->>'ops_bucket' = 'action_required', v_ops->>'ops_bucket');
    r := r || public._qa_s13_ok('N4R11.C2 committed order allows accept + reject only',
          (v_ops->'allowed_actions') @> '["accept","reject"]'::jsonb
      AND jsonb_array_length(v_ops->'allowed_actions') = 2, v_ops->>'allowed_actions');
    r := r || public._qa_s13_ok('N4R11.C3 ops exposes canonical order items',
          jsonb_array_length(v_ops->'items') = 1, NULL);
    r := r || public._qa_s13_ok('N4R11.C4 no courier is claimed before dispatch',
          (v_ops->>'courier_assigned')::boolean = false, NULL);

    PERFORM public.marche_merchant_transition(v_o1,'accept',NULL);
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.C5 accepted order allows prepare + reject',
          (v_ops->'allowed_actions') @> '["prepare","reject"]'::jsonb
      AND jsonb_array_length(v_ops->'allowed_actions') = 2, v_ops->>'allowed_actions');
    r := r || public._qa_s13_ok('N4R11.C6 accepted order sits in preparing bucket',
          v_ops->>'ops_bucket' = 'preparing', v_ops->>'ops_bucket');

    PERFORM public.marche_merchant_transition(v_o1,'prepare',NULL);
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.C7 preparing order allows ready + reject',
          (v_ops->'allowed_actions') @> '["ready","reject"]'::jsonb
      AND jsonb_array_length(v_ops->'allowed_actions') = 2, v_ops->>'allowed_actions');

    PERFORM public.marche_merchant_transition(v_o1,'ready',NULL);
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.C8 ready order offers dispatch',
          (v_ops->'allowed_actions') @> '["request_dispatch"]'::jsonb, v_ops->>'allowed_actions');

    PERFORM public.marche_dispatch_request(v_o1);
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.C9 dispatched order can no longer be rejected or re-dispatched',
          NOT ((v_ops->'allowed_actions') @> '["reject"]'::jsonb)
      AND NOT ((v_ops->'allowed_actions') @> '["request_dispatch"]'::jsonb), v_ops->>'allowed_actions');
    r := r || public._qa_s13_ok('N4R11.C10 dispatched order is in_delivery',
          v_ops->>'ops_bucket' = 'in_delivery', v_ops->>'ops_bucket');
    r := r || public._qa_s13_ok('N4R11.C11 courier presence is server truth',
          (v_ops->>'courier_assigned')::boolean = true, NULL);

    -- ===== D. TENDER TRUTH — DIRECT FIXED-PRICE ORDER =====
    r := r || public._qa_s13_ok('N4R11.D1 a direct order has no payment method',
          v_ops->'tender'->>'payment_method' = 'unknown'
      AND (v_ops->'tender'->>'payment_connected')::boolean = false,
          v_ops->'tender'->>'payment_method');
    r := r || public._qa_s13_ok('N4R11.D2 unrecorded tender is stated honestly in French',
          v_ops->'tender'->>'label' = 'Mode non renseigné', v_ops->'tender'->>'label');
    r := r || public._qa_s13_ok('N4R11.D3 tender carries no evidence source when absent',
          (v_ops->'tender'->'evidence_source') = 'null'::jsonb, NULL);
    r := r || public._qa_s13_ok('N4R11.D4 the refusal reason names the missing bridge',
          v_ops->'tender'->>'reason' = 'NO_SOURCE_OFFER', v_ops->'tender'->>'reason');
    r := r || public._qa_s13_ok('N4R11.D5 an unpaid order is never recorded as tendered',
          (v_ops->'tender'->>'recorded')::boolean = false, NULL);

    -- ===== E. MONEY TRUTH (no payable yet) =====
    r := r || public._qa_s13_ok('N4R11.E1 absent payable is not_yet_payable',
          v_ops->'money'->>'settlement_state' = 'not_yet_payable', v_ops->'money'->>'settlement_state');
    r := r || public._qa_s13_ok('N4R11.E2 absent payable never claims settled',
          (v_ops->'money'->>'settled')::boolean = false, NULL);
    r := r || public._qa_s13_ok('N4R11.E3 money mirrors frozen R4 economics verbatim',
          (v_ops->'money'->>'merchant_payable_gnf')::bigint =
            (SELECT merchant_payable_gnf FROM public.marche_orders WHERE id=v_o1)
      AND (v_ops->'money'->>'merchant_fee_gnf')::bigint =
            (SELECT merchant_fee_gnf FROM public.marche_orders WHERE id=v_o1), NULL);
    v_rc := public.marche_order_settlement_receipt(v_o1);
    r := r || public._qa_s13_ok('N4R11.E4 no receipt exists without a payable',
          (v_rc->>'receipt_available')::boolean = false
      AND (v_rc->>'settled')::boolean = false, NULL);
    r := r || public._qa_s13_ok('N4R11.E5 unbridged money states payment is not connected',
          (v_ops->'money'->>'payment_connected')::boolean = false, NULL);

    -- ===== K. IDENTITY-COINCIDENCE REGRESSIONS =====
    -- An unrelated offer with a REAL chop_pay runtime and a REAL payable.
    INSERT INTO public.marketplace_offers(listing_id, merchant_store_id, buyer_user_id,
        merchant_user_id, offer_amount_gnf, status)
      VALUES (l_a, v_store, v_buy, v_merch, 33000, 'pending') RETURNING id INTO v_off_x;
    INSERT INTO public.chop_pay_order_runtime(order_key, source_module, source_id, mission_type,
        customer_user_id, merchandise_subtotal_gnf, order_total_gnf, state)
      VALUES ('qa-n411-cpx-'||v_off_x::text,'marche',v_off_x,'marketplace_delivery',
        v_buy, 33000, 33000, 'authorized');
    INSERT INTO public.merchant_payables(payable_key, source_module, source_id, merchant_store_id,
        merchant_user_id, mission_type, subtotal_gnf, deduction_gnf, amount_gnf,
        funded_gnf, settled_gnf, state, funding_source)
      VALUES ('qa-n411-px-'||v_off_x::text,'marche',v_off_x, v_store, v_merch,'marketplace_delivery',
        33000, 330, 32670, 32670, 32670, 'settled', 'chop_pay')
      RETURNING id INTO v_pay_x;

    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.K1 a direct order inherits no foreign tender',
          v_ops->'tender'->>'payment_method' = 'unknown'
      AND (v_ops->'tender'->>'payment_connected')::boolean = false,
          v_ops->'tender'->>'payment_method');
    r := r || public._qa_s13_ok('N4R11.K2 a direct order inherits no foreign payable',
          v_ops->'money'->>'settlement_state' = 'not_yet_payable'
      AND (v_ops->'money'->>'payable_present')::boolean = false,
          v_ops->'money'->>'settlement_state');
    r := r || public._qa_s13_ok('N4R11.K3 a foreign settled payable never shows as settled here',
          (v_ops->'money'->>'settled')::boolean = false, NULL);

    -- A payable keyed to the CANONICAL ORDER ID is not canonical finance identity.
    INSERT INTO public.merchant_payables(payable_key, source_module, source_id, merchant_store_id,
        merchant_user_id, mission_type, subtotal_gnf, deduction_gnf, amount_gnf,
        funded_gnf, settled_gnf, state, funding_source)
      VALUES ('qa-n411-pbad-'||v_o1::text,'marche',v_o1, v_store, v_merch,'marketplace_delivery',
        20000, 200, 19800, 19800, 19800, 'settled', 'unknown')
      RETURNING id INTO v_pay_bad;

    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.K4 a payable keyed to the order id is not read as truth',
          v_ops->'money'->>'settlement_state' = 'not_yet_payable'
      AND (v_ops->'money'->>'settled')::boolean = false, v_ops->'money'->>'settlement_state');
    v_rc := public.marche_order_settlement_receipt(v_o1);
    r := r || public._qa_s13_ok('N4R11.K5 no receipt is produced from a wrongly keyed payable',
          (v_rc->>'receipt_available')::boolean = false, NULL);

    PERFORM set_config('request.jwt.claims','', true);
    v_au := public.marche_finance_order_audit(v_o1);
    r := r || public._qa_s13_ok('N4R11.K6 finance audit flags the wrongly keyed payable',
          (v_au->'mismatch_codes') @> '["PAYABLE_KEYED_TO_ORDER_ID_NOT_CANONICAL"]'::jsonb,
          v_au->>'mismatch_codes');
    r := r || public._qa_s13_ok('N4R11.K7 audit reports the missing bridge explicitly',
          v_au->'finance_bridge'->>'reason' = 'NO_SOURCE_OFFER'
      AND (v_au->'finance_bridge'->>'bridged')::boolean = false, v_au->>'finance_bridge');
    DELETE FROM public.merchant_payables WHERE id = v_pay_bad; v_pay_bad := NULL;

    -- ===== L. BRIDGED ORDER (exact source_offer_id) =====
    INSERT INTO public.marketplace_offers(listing_id, merchant_store_id, buyer_user_id,
        merchant_user_id, offer_amount_gnf, status)
      VALUES (l_a, v_store, v_buy, v_merch, 20000, 'pending') RETURNING id INTO v_off;
    INSERT INTO public.marche_orders(buyer_user_id, merchant_store_id, merchant_user_id,
        merchandise_subtotal_gnf, item_count, line_count, client_request_id, request_fingerprint,
        source_offer_id, merchant_fee_gnf, merchant_payable_gnf, delivery_address,
        status, fulfillment_state)
      VALUES (v_buy, v_store, v_merch, 20000, 1, 1, 'qa-n411-bridged-0002','qa-n411-fp-0002',
        v_off, 200, 19800, 'QA Kaloum, Conakry', 'committed', 'committed')
      RETURNING id INTO v_o2;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_ops2 := public.marche_merchant_order_ops(v_o2);
    r := r || public._qa_s13_ok('N4R11.L1 a bridged order without a rail is still unknown',
          v_ops2->'tender'->>'payment_method' = 'unknown'
      AND v_ops2->'tender'->>'reason' = 'PAYMENT_RAIL_NOT_INITIATED', v_ops2->'tender'->>'reason');
    r := r || public._qa_s13_ok('N4R11.L2 a bridged order picks up no foreign offer tender',
          (v_ops2->'tender'->>'payment_connected')::boolean = false, NULL);

    INSERT INTO public.chop_pay_order_runtime(order_key, source_module, source_id, mission_type,
        customer_user_id, merchandise_subtotal_gnf, order_total_gnf, state)
      VALUES ('qa-n411-cp-'||v_off::text,'marche',v_off,'marketplace_delivery',
        v_buy, 20000, 20000, 'authorized');
    v_ops2 := public.marche_merchant_order_ops(v_o2);
    r := r || public._qa_s13_ok('N4R11.L3 the exact bridged rail is reported as Chop Pay',
          v_ops2->'tender'->>'payment_method' = 'chop_pay'
      AND (v_ops2->'tender'->>'payment_connected')::boolean = true
      AND v_ops2->'tender'->>'evidence_source' = 'chop_pay_order_runtime',
          v_ops2->'tender'->>'payment_method');
    r := r || public._qa_s13_ok('N4R11.L4 the tender names its finance source identity',
          v_ops2->'tender'->>'finance_source_id' = v_off::text, NULL);
    r := r || public._qa_s13_ok('N4R11.L5 a connected rail is still not a settlement',
          v_ops2->'money'->>'settlement_state' = 'not_yet_payable', v_ops2->'money'->>'settlement_state');

    -- ===== F. MONEY TRUTH (canonical payable on the bridged identity) =====
    INSERT INTO public.merchant_payables(payable_key, source_module, source_id, merchant_store_id,
        merchant_user_id, mission_type, subtotal_gnf, deduction_gnf, amount_gnf,
        funded_gnf, settled_gnf, state, funding_source)
      VALUES ('qa-n411-'||v_off::text, 'marche', v_off, v_store, v_merch, 'marketplace_delivery',
        20000, 200, 19800, 0, 0, 'pending_funding', 'chop_pay')
      RETURNING id INTO v_pay;

    v_ops2 := public.marche_merchant_order_ops(v_o2);
    r := r || public._qa_s13_ok('N4R11.F1 unfunded payable reads pending_funding',
          v_ops2->'money'->>'settlement_state' = 'pending_funding', v_ops2->'money'->>'settlement_state');
    r := r || public._qa_s13_ok('N4R11.F2 outstanding equals the full payable while unsettled',
          (v_ops2->'money'->>'outstanding_gnf')::bigint = (v_ops2->'money'->>'payable_amount_gnf')::bigint, NULL);
    r := r || public._qa_s13_ok('N4R11.F2b payable is resolved through the bridged identity',
          v_ops2->'money'->>'payable_source_id' = v_off::text, NULL);

    UPDATE public.merchant_payables SET state='due', funded_gnf=amount_gnf WHERE id=v_pay;
    v_ops2 := public.marche_merchant_order_ops(v_o2);
    r := r || public._qa_s13_ok('N4R11.F3 funded payable reads funded_or_due',
          v_ops2->'money'->>'settlement_state' = 'funded_or_due', v_ops2->'money'->>'settlement_state');
    r := r || public._qa_s13_ok('N4R11.F4 funded is not settled',
          (v_ops2->'money'->>'settled')::boolean = false, NULL);

    UPDATE public.merchant_payables SET settled_gnf = 1 WHERE id=v_pay;
    v_ops2 := public.marche_merchant_order_ops(v_o2);
    r := r || public._qa_s13_ok('N4R11.F5 partial settlement is stated as partial',
          v_ops2->'money'->>'settlement_state' = 'partially_settled', v_ops2->'money'->>'settlement_state');

    UPDATE public.merchant_payables SET settled_gnf = amount_gnf, state='settled' WHERE id=v_pay;
    v_ops2 := public.marche_merchant_order_ops(v_o2);
    r := r || public._qa_s13_ok('N4R11.F6 full settlement reads settled',
          v_ops2->'money'->>'settlement_state' = 'settled'
      AND (v_ops2->'money'->>'settled')::boolean = true, v_ops2->'money'->>'settlement_state');
    r := r || public._qa_s13_ok('N4R11.F7 settled outstanding is zero',
          (v_ops2->'money'->>'outstanding_gnf')::bigint = 0, NULL);

    UPDATE public.merchant_payables SET state='reversed' WHERE id=v_pay;
    v_ops2 := public.marche_merchant_order_ops(v_o2);
    r := r || public._qa_s13_ok('N4R11.F8 reversed payable overrides settled display',
          v_ops2->'money'->>'settlement_state' = 'reversed', v_ops2->'money'->>'settlement_state');
    UPDATE public.merchant_payables SET state='settled' WHERE id=v_pay;

    -- the direct order must remain untouched by all of this
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.K8 the direct order stays not_yet_payable throughout',
          v_ops->'money'->>'settlement_state' = 'not_yet_payable'
      AND v_ops->'tender'->>'payment_method' = 'unknown', v_ops->'money'->>'settlement_state');

    -- ===== G. RECEIPT / EVIDENCE LAW =====
    v_rc := public.marche_order_settlement_receipt(v_o2);
    r := r || public._qa_s13_ok('N4R11.G1 settled payable without allocation yields no receipt',
          (v_rc->>'receipt_available')::boolean = false, NULL);

    INSERT INTO public.payout_orders(order_key, party_user_id, party_type, source_kind, merchant_store_id, destination_msisdn,
        provider, environment, requested_principal_gnf, provider_fee_gnf, fee_borne_by,
        merchant_liability_debit_gnf, recipient_net_gnf, expected_provider_transfer_gnf,
        reservation_gnf, settled_gnf, status)
      VALUES ('qa-n411-po-'||v_o2::text, v_merch, 'merchant','merchant_settlement', v_store, '+224620000000','orange_money','sandbox',
        (SELECT amount_gnf FROM public.merchant_payables WHERE id=v_pay), 0, 'platform',
        (SELECT amount_gnf FROM public.merchant_payables WHERE id=v_pay),
        (SELECT amount_gnf FROM public.merchant_payables WHERE id=v_pay),
        (SELECT amount_gnf FROM public.merchant_payables WHERE id=v_pay),
        0, (SELECT amount_gnf FROM public.merchant_payables WHERE id=v_pay), 'settled')
      RETURNING id INTO v_po;
    INSERT INTO public.payout_settlement_allocations(payout_order_id, merchant_payable_id, amount_gnf)
      VALUES (v_po, v_pay, (SELECT amount_gnf FROM public.merchant_payables WHERE id=v_pay));

    v_rc := public.marche_order_settlement_receipt(v_o2);
    r := r || public._qa_s13_ok('N4R11.G2 allocation produces a receipt',
          (v_rc->>'receipt_available')::boolean = true
      AND jsonb_array_length(v_rc->'allocations') = 1, NULL);
    r := r || public._qa_s13_ok('N4R11.G3 allocation without reconciled evidence is not evidence_backed',
          (v_rc->'allocations'->0->>'evidence_backed')::boolean = false, NULL);
    r := r || public._qa_s13_ok('N4R11.G4 receipt never fabricates a provider reference',
          (v_rc->'allocations'->0->'provider_reference') = 'null'::jsonb, NULL);

    INSERT INTO public.payout_provider_evidence(payout_order_id, provider, provider_reference,
        recipient_msisdn, amount_gnf, provider_status, environment, reconciliation_state)
      VALUES (v_po,'orange_money','QA-N411-REF-0001','+224620000000',
        (SELECT amount_gnf FROM public.merchant_payables WHERE id=v_pay),'SUCCESS','sandbox','reconciled')
      RETURNING id INTO v_ev;

    v_rc := public.marche_order_settlement_receipt(v_o2);
    r := r || public._qa_s13_ok('N4R11.G5 reconciled evidence makes the allocation evidence_backed',
          (v_rc->'allocations'->0->>'evidence_backed')::boolean = true, NULL);
    r := r || public._qa_s13_ok('N4R11.G6 receipt shows the real provider reference',
          v_rc->'allocations'->0->>'provider_reference' = 'QA-N411-REF-0001', NULL);
    v_rc := public.marche_order_settlement_receipt(v_o1);
    r := r || public._qa_s13_ok('N4R11.G7 the direct order gets no receipt from a foreign payout',
          (v_rc->>'receipt_available')::boolean = false, NULL);

    -- ===== H. FINANCE AUDIT =====
    PERFORM set_config('request.jwt.claims','', true);
    v_au := public.marche_finance_order_audit(v_o2);
    r := r || public._qa_s13_ok('N4R11.H1 consistent order audits clean',
          (v_au->>'clean')::boolean = true, v_au->>'mismatch_codes');

    UPDATE public.merchant_payables SET amount_gnf = amount_gnf + 500 WHERE id=v_pay;
    v_au := public.marche_finance_order_audit(v_o2);
    r := r || public._qa_s13_ok('N4R11.H2 payable/order divergence is flagged',
          (v_au->'mismatch_codes') @> '["ORDER_PAYABLE_AMOUNT_MISMATCH"]'::jsonb, v_au->>'mismatch_codes');
    r := r || public._qa_s13_ok('N4R11.H3 a settled state below the payable is flagged',
          (v_au->'mismatch_codes') @> '["SETTLED_STATE_WITHOUT_FULL_SETTLEMENT"]'::jsonb, v_au->>'mismatch_codes');
    UPDATE public.merchant_payables SET amount_gnf = amount_gnf - 500 WHERE id=v_pay;

    UPDATE public.merchant_payables SET settled_gnf = settled_gnf - 1 WHERE id=v_pay;
    v_au := public.marche_finance_order_audit(v_o2);
    r := r || public._qa_s13_ok('N4R11.H4 allocation coverage divergence is flagged',
          (v_au->'mismatch_codes') @> '["ALLOCATION_COVERAGE_MISMATCH"]'::jsonb, v_au->>'mismatch_codes');
    UPDATE public.merchant_payables SET settled_gnf = amount_gnf WHERE id=v_pay;

    UPDATE public.payout_provider_evidence SET reconciliation_state='mismatch' WHERE id=v_ev;
    v_au := public.marche_finance_order_audit(v_o2);
    r := r || public._qa_s13_ok('N4R11.H5 settlement without reconciled evidence is flagged',
          (v_au->'mismatch_codes') @> '["SETTLEMENT_WITHOUT_RECONCILED_EVIDENCE"]'::jsonb, v_au->>'mismatch_codes');
    UPDATE public.payout_provider_evidence SET reconciliation_state='reconciled' WHERE id=v_ev;

    UPDATE public.payout_orders SET status='needs_review' WHERE id=v_po;
    v_au := public.marche_finance_order_audit(v_o2);
    r := r || public._qa_s13_ok('N4R11.H6 a payout needing review is flagged',
          (v_au->'mismatch_codes') @> '["PAYOUT_ORDER_NEEDS_REVIEW"]'::jsonb, v_au->>'mismatch_codes');
    UPDATE public.payout_orders SET status='settled' WHERE id=v_po;

    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.marche_orders SET fulfillment_state='delivered', delivered_at=now() WHERE id=v_o1;
    PERFORM set_config('marche.rpc','', true);
    v_au := public.marche_finance_order_audit(v_o1);
    r := r || public._qa_s13_ok('N4R11.H7 delivery without any payment rail is flagged honestly',
          (v_au->'mismatch_codes') @> '["DELIVERED_WITHOUT_PAYMENT_RAIL"]'::jsonb, v_au->>'mismatch_codes');

    -- ===== I. COCKPIT =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_ck := public.marche_merchant_orders_cockpit(v_store,NULL,40,0);
    r := r || public._qa_s13_ok('N4R11.I1 cockpit returns the merchant own orders',
          jsonb_array_length(v_ck->'items') = 2, v_ck->>'counts');
    r := r || public._qa_s13_ok('N4R11.I2 cockpit counts the completed bucket',
          (v_ck->'counts'->>'completed')::int = 1, v_ck->>'counts');
    v_ck := public.marche_merchant_orders_cockpit(v_store,'action_required',40,0);
    r := r || public._qa_s13_ok('N4R11.I3 bucket filtering excludes non-matching orders',
          jsonb_array_length(v_ck->'items') = 1
      AND v_ck->'items'->0->>'order_id' = v_o2::text, v_ck->>'items');
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_orders_cockpit(v_store,'not_a_bucket',10,0);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R11.I4 an unknown bucket is refused', v_err='UNKNOWN_BUCKET', v_err);
    v_ck := public.marche_merchant_orders_cockpit(v_store2,NULL,40,0);
    r := r || public._qa_s13_ok('N4R11.I5 cockpit refuses to leak a foreign store',
          jsonb_array_length(v_ck->'items') = 0, NULL);

    -- ===== J. NO MUTATION =====
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.J1 reading operations does not move the lifecycle',
          v_ops->>'fulfillment_state' =
            (SELECT fulfillment_state FROM public.marche_orders WHERE id=v_o1), NULL);
    SELECT count(*) INTO v_n FROM public.marche_fulfillment_transitions WHERE order_id=v_o1;
    PERFORM public.marche_merchant_order_ops(v_o1);
    PERFORM public.marche_order_settlement_receipt(v_o1);
    r := r || public._qa_s13_ok('N4R11.J2 read models append no transition',
          (SELECT count(*) FROM public.marche_fulfillment_transitions WHERE order_id=v_o1) = v_n, NULL);
    r := r || public._qa_s13_ok('N4R11.J3 read models create no payable',
          (SELECT count(*) FROM public.merchant_payables
            WHERE source_module='marche' AND source_id IN (v_o1, v_o2)) = 0, NULL);

  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok('N4R11.X fixture run raised', false, SQLERRM);
  END;

  -- ===== CLEANUP =====
  PERFORM set_config('request.jwt.claims','', true);
  PERFORM set_config('marche.rpc','1', true);
  DELETE FROM public.payout_provider_evidence WHERE payout_order_id = v_po;
  DELETE FROM public.payout_settlement_allocations WHERE merchant_payable_id IN (v_pay, v_pay_x, v_pay_bad);
  DELETE FROM public.payout_orders WHERE id = v_po;
  DELETE FROM public.merchant_payables WHERE id IN (v_pay, v_pay_x, v_pay_bad);
  DELETE FROM public.chop_pay_order_runtime WHERE source_module='marche' AND source_id IN (v_off, v_off_x);
  DELETE FROM public.marche_fulfillment_transitions WHERE order_id IN (v_o1, v_o2);
  DELETE FROM public.marche_fulfillment_observations WHERE order_id IN (v_o1, v_o2);
  DELETE FROM public.marche_fulfillment_events WHERE order_id IN (v_o1, v_o2);
  DELETE FROM public.marche_fulfillment_profiles WHERE order_id IN (v_o1, v_o2);
  DELETE FROM public.marche_order_items WHERE order_id IN (v_o1, v_o2);
  UPDATE public.marche_orders SET mission_id = NULL WHERE id IN (v_o1, v_o2);
  DELETE FROM public.mission_events WHERE mission_id IN
    (SELECT id FROM public.missions WHERE ref_market_order_id IN (v_o1, v_o2));
  DELETE FROM public.missions WHERE ref_market_order_id IN (v_o1, v_o2);
  DELETE FROM public.marche_orders WHERE id IN (v_o1, v_o2);
  DELETE FROM public.marketplace_offers WHERE id IN (v_off, v_off_x);
  PERFORM set_config('marche.rpc','', true);
  DELETE FROM public.marketplace_listings WHERE store_id IN (v_store, v_store2);
  DELETE FROM public.merchant_stores WHERE id IN (v_store, v_store2);
  DELETE FROM public.user_roles WHERE user_id IN (v_buy,v_merch,v_merch2,v_adm,v_drv);
  DELETE FROM public.admin_users WHERE user_id = v_adm;
  DELETE FROM public.driver_profiles WHERE user_id = v_drv;
  DELETE FROM public.wallet_transactions WHERE from_wallet_id IN
      (SELECT id FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch,v_merch2,v_adm,v_drv))
     OR to_wallet_id IN
      (SELECT id FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch,v_merch2,v_adm,v_drv));
  DELETE FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch,v_merch2,v_adm,v_drv);
  DELETE FROM auth.users WHERE id IN (v_buy,v_merch,v_merch2,v_adm,v_drv);

  -- ===== S. SYSTEMIC =====
  SELECT count(*) INTO v_w1 FROM public.wallets;
  SELECT count(*) INTO v_wt1 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj1 FROM public.ledger_journals;
  SELECT count(*) INTO v_pi1 FROM public.payment_intents;
  SELECT count(*) INTO v_mp1 FROM public.merchant_payables;
  SELECT count(*) INTO v_ss1 FROM public.merchant_settlement_requests;
  SELECT count(*) INTO v_cp1 FROM public.chop_pay_order_runtime;
  SELECT count(*) INTO v_of1 FROM public.marketplace_offers;
  SELECT COALESCE(sum(quantity_reserved),0) INTO v_reserved1 FROM public.marketplace_listings;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;

  r := r || public._qa_s13_ok('N4R11.S1 zero wallet / ledger / payment drift',
        v_w1=v_w0 AND v_wt1=v_wt0 AND v_lj1=v_lj0 AND v_pi1=v_pi0,
        format('%s/%s/%s/%s', v_w1-v_w0, v_wt1-v_wt0, v_lj1-v_lj0, v_pi1-v_pi0));
  r := r || public._qa_s13_ok('N4R11.S2 zero payable / settlement drift',
        v_mp1=v_mp0 AND v_ss1=v_ss0, format('%s/%s', v_mp1-v_mp0, v_ss1-v_ss0));
  r := r || public._qa_s13_ok('N4R11.S3 reserved stock returns to baseline',
        v_reserved1=v_reserved0, format('%s->%s', v_reserved0, v_reserved1));
  r := r || public._qa_s13_ok('N4R11.S4 feature flags byte-identical', v_flags1=v_flags0, NULL);
  SELECT count(*) INTO v_n FROM public.marche_orders WHERE client_request_id LIKE 'qa-n411-%';
  r := r || public._qa_s13_ok('N4R11.S5 zero order fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-n411-%';
  r := r || public._qa_s13_ok('N4R11.S6 zero store fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marketplace_listings WHERE title LIKE 'QA N411%';
  r := r || public._qa_s13_ok('N4R11.S7 zero listing fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.payout_provider_evidence WHERE provider_reference LIKE 'QA-N411-%';
  r := r || public._qa_s13_ok('N4R11.S8 zero payout evidence residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE id IN (v_buy,v_merch,v_merch2,v_adm,v_drv);
  r := r || public._qa_s13_ok('N4R11.S9 zero auth fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.payout_settlement_allocations a
    LEFT JOIN public.merchant_payables p ON p.id=a.merchant_payable_id WHERE p.id IS NULL;
  r := r || public._qa_s13_ok('N4R11.S10 zero orphan settlement allocation', v_n=0, v_n::text);
  r := r || public._qa_s13_ok('N4R11.S11 zero chop pay runtime drift', v_cp1=v_cp0, format('%s', v_cp1-v_cp0));
  r := r || public._qa_s13_ok('N4R11.S12 zero offer fixture drift', v_of1=v_of0, format('%s', v_of1-v_of0));

  RETURN r;
END $qa$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r11() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r11() TO postgres, service_role;
