-- Refresh the R1-R4 harness expectations for the shipped R4.5 pickup rail.
DO $do$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r1_r4';

  v_def := replace(v_def,
    $x$'B0.13 commitment source carries the temporary pickup guard',
        v_args LIKE '%PICKUP_NOT_YET_SUPPORTED%', NULL);$x$,
    $x$'B0.13 commitment source refuses cash pickup (no canonical fee primitive)',
        v_args LIKE '%PICKUP_CASH_NOT_SUPPORTED%'
        AND v_args NOT LIKE '%PICKUP_NOT_YET_SUPPORTED%', NULL);$x$);

  v_def := replace(v_def,
    $x$'M1.1 cash pickup commitment fails closed (R4.5 not shipped)',
          v_err LIKE '%PICKUP_NOT_YET_SUPPORTED%', v_err);$x$,
    $x$'M1.1 cash pickup commitment fails closed (R4.5-C honest result)',
          v_err LIKE '%PICKUP_CASH_NOT_SUPPORTED%', v_err);$x$);

  v_def := replace(v_def,
    $x$    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'pickup','choppay', gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('M1.2 Chop Pay pickup commitment fails closed too',
          v_err LIKE '%PICKUP_NOT_YET_SUPPORTED%', v_err);$x$,
    $x$    BEGIN PERFORM public.repas_order_create(v_resto2,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item_other,'qty',1)),
        'pickup','choppay', gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('M1.2 Chop Pay pickup runs normal validation, not a categorical block',
          v_err LIKE '%RESTAURANT_CLOSED%', v_err);$x$);

  EXECUTE v_def;
END $do$;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_pickup()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_cust2 uuid; v_merch uuid; v_drv uuid;
  v_store uuid; v_resto uuid; v_item uuid; v_item2 uuid;
  v_o1 uuid; v_res jsonb; v_err text; v_n int; v_args text; v_def text;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_cp public.chop_pay_order_runtime; v_pay public.merchant_payables;
  v_pol public.finance_policies; v_q jsonb; v_qd jsonb;
  v_c0 bigint; v_c1 bigint; v_held bigint; v_unbalanced int;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  -- ============ P0. STATIC SECURITY / SHAPE ============
  r := r || public._qa_s13_ok('P0.1 repas_quote_preview exists',
        to_regprocedure('public.repas_quote_preview(uuid,jsonb,text)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('P0.2 repas_quote_preview closed to anon',
        NOT has_function_privilege('anon','public.repas_quote_preview(uuid,jsonb,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.3 pickup completion RPC closed to anon',
        NOT has_function_privilege('anon','public.chop_pay_merchant_pickup_complete(text,uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.4 raw chop pay hold internal still closed to authenticated',
        NOT has_function_privilege('authenticated','public._chop_pay_customer_hold_internal(text,uuid,uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.5 this harness is closed to anon/authenticated',
        NOT has_function_privilege('anon','public._qa_node3_repas_pickup()','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._qa_node3_repas_pickup()','EXECUTE'), NULL);

  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_chop_pay_facts';
  r := r || public._qa_s13_ok('P0.6 facts expose fulfillment and is_pickup',
        v_def LIKE '%''fulfillment''%' AND v_def LIKE '%''is_pickup''%', NULL);

  SELECT pg_get_functiondef(p.oid) INTO v_args FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='repas_order_create';
  r := r || public._qa_s13_ok('P0.7 categorical pickup block removed',
        v_args NOT LIKE '%PICKUP_NOT_YET_SUPPORTED%', NULL);
  r := r || public._qa_s13_ok('P0.8 cash pickup guard present at commitment',
        v_args LIKE '%PICKUP_CASH_NOT_SUPPORTED%', NULL);

  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_chop_pay_customer_hold_internal';
  r := r || public._qa_s13_ok('P0.9 hold refuses a pickup order that carries a mission',
        v_def LIKE '%PICKUP_MUST_HAVE_NO_MISSION%', NULL);
  r := r || public._qa_s13_ok('P0.10 hold refuses a pickup order with a delivery fee',
        v_def LIKE '%PICKUP_MUST_HAVE_ZERO_DELIVERY_FEE%', NULL);

  -- ============ P1. POLICY / ADMIN-EDITABLE FEE ============
  SELECT * INTO v_pol FROM public.finance_policies
   WHERE mission_type='repas' AND effective_from <= now()
   ORDER BY effective_from DESC LIMIT 1;
  r := r || public._qa_s13_ok('P1.1 an effective Repas policy exists', v_pol.id IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('P1.2 default Repas transaction fee is 1% (100 bps)',
        v_pol.transaction_fee_bps = 100, v_pol.transaction_fee_bps::text);
  r := r || public._qa_s13_ok('P1.3 fee basis is merchandise subtotal',
        v_pol.fee_basis = 'merchandise_subtotal', v_pol.fee_basis);

  SELECT pg_get_function_identity_arguments(p.oid) INTO v_args FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='admin_set_finance_policy';
  r := r || public._qa_s13_ok('P1.4 admin fee control accepts p_transaction_fee_bps',
        v_args LIKE '%p_transaction_fee_bps%', NULL);
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='admin_set_finance_policy';
  r := r || public._qa_s13_ok('P1.5 fee edits are god-admin only',
        v_def LIKE '%is_god_admin%', NULL);
  r := r || public._qa_s13_ok('P1.6 fee edits are append-only and effective-dated',
        v_def LIKE '%EFFECTIVE_FROM_NOT_MONOTONIC%' AND v_def LIKE '%BACKDATING_REJECTED%', NULL);

  BEGIN
    -- ============ FIXTURES ============
    v_cust := gen_random_uuid(); v_cust2 := gen_random_uuid();
    v_merch := gen_random_uuid(); v_drv := gen_random_uuid();
    PERFORM public._qa_s13_user(v_cust,'n3pc');
    PERFORM public._qa_s13_user(v_cust2,'n3px');
    PERFORM public._qa_s13_user(v_merch,'n3pm');
    PERFORM public._qa_s13_user(v_drv,'n3pd');
    PERFORM public._qa_s13_wallet(v_cust,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_cust2,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_merch,'merchant',0,0);
    PERFORM public._qa_s13_wallet(v_drv,'driver',900000,0);

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, delivery_available, status)
      VALUES (v_merch, 'qa-n3p-store-'||substr(v_merch::text,1,8), 'QA N3P Store', true, 'active')
      RETURNING id INTO v_store;
    INSERT INTO public.food_restaurants(owner_user_id, merchant_store_id, slug, name, status,
        is_open, delivery_available, pickup_available, choppay_enabled, prep_time_min)
      VALUES (v_merch, v_store, 'qa-n3p-resto-'||substr(v_merch::text,1,8), 'QA N3P Resto',
              'active', true, true, true, true, 20)
      RETURNING id INTO v_resto;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA Plat A',100000,true) RETURNING id INTO v_item;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA Plat B',50000,true) RETURNING id INTO v_item2;

    UPDATE public.feature_flags SET enabled = true WHERE key = 'chop_pay_checkout_enabled';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);

    -- ============ P2. CASH PICKUP FAILS CLOSED ============
    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'pickup','cash', gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P2.1 cash pickup is refused with an explicit code',
          v_err LIKE '%PICKUP_CASH_NOT_SUPPORTED%', v_err);
    SELECT count(*) INTO v_n FROM public.food_orders WHERE user_id = v_cust;
    r := r || public._qa_s13_ok('P2.2 refused cash pickup created zero orders', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.missions WHERE customer_id = v_cust;
    r := r || public._qa_s13_ok('P2.3 refused cash pickup created zero missions', v_n = 0, v_n::text);
    SELECT held_gnf INTO v_held FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('P2.4 refused cash pickup moved zero value', v_held = 0, v_held::text);

    -- ============ P3. QUOTE PREVIEW IS SERVER TRUTH ============
    v_q := public.repas_quote_preview(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                          jsonb_build_object('menu_item_id',v_item2,'qty',1)), 'pickup');
    r := r || public._qa_s13_ok('P3.1 pickup quote subtotal is repriced server-side',
          (v_q->>'merchandise_subtotal_gnf')::bigint = 150000, v_q->>'merchandise_subtotal_gnf');
    r := r || public._qa_s13_ok('P3.2 pickup quote carries no delivery fee',
          (v_q->>'delivery_fee_gnf')::bigint = 0, v_q->>'delivery_fee_gnf');
    r := r || public._qa_s13_ok('P3.3 pickup quote platform fee is 1% of merchandise',
          (v_q->>'platform_fee_gnf')::bigint = 1500, v_q->>'platform_fee_gnf');
    r := r || public._qa_s13_ok('P3.4 pickup quote total = merchandise + fee',
          (v_q->>'order_total_gnf')::bigint = 151500, v_q->>'order_total_gnf');
    r := r || public._qa_s13_ok('P3.5 pickup quote reports cash pickup as unsupported',
          (v_q->>'cash_pickup_supported')::boolean IS FALSE, v_q->>'cash_pickup_supported');
    v_qd := public.repas_quote_preview(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                          jsonb_build_object('menu_item_id',v_item2,'qty',1)), 'delivery');
    r := r || public._qa_s13_ok('P3.6 delivery quote still carries a courier fee',
          (v_qd->>'delivery_fee_gnf')::bigint > 0, v_qd->>'delivery_fee_gnf');
    r := r || public._qa_s13_ok('P3.7 pickup total is strictly cheaper than delivery total',
          (v_q->>'order_total_gnf')::bigint < (v_qd->>'order_total_gnf')::bigint, NULL);

    -- ============ P4. COMMITMENT SHAPE ============
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                          jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'pickup','choppay', gen_random_uuid(), 'IGNORED ADDRESS', 9.51, -13.70, 'Sans piment');
    v_o1 := (v_res->>'order_id')::uuid;
    r := r || public._qa_s13_ok('P4.1 Chop Pay pickup order is committed',
          v_o1 IS NOT NULL AND (v_res->>'fulfillment') = 'pickup', v_res::text);
    r := r || public._qa_s13_ok('P4.2 commitment returns no mission for pickup',
          (v_res->>'mission_id') IS NULL, v_res->>'mission_id');
    SELECT count(*) INTO v_n FROM public.missions WHERE ref_food_order_id = v_o1;
    r := r || public._qa_s13_ok('P4.3 no courier mission row exists for a pickup order', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.food_orders
     WHERE id = v_o1 AND delivery_address IS NULL AND delivery_lat IS NULL AND delivery_lng IS NULL;
    r := r || public._qa_s13_ok('P4.4 delivery-only fields are not stored on a pickup order', v_n = 1, v_n::text);

    SELECT * INTO v_cp FROM public.chop_pay_order_runtime
     WHERE source_module='repas' AND source_id=v_o1;
    r := r || public._qa_s13_ok('P4.5 pickup runtime carries no mission', v_cp.mission_id IS NULL, NULL);
    r := r || public._qa_s13_ok('P4.6 pickup runtime delivery fee is zero',
          v_cp.delivery_fee_gnf = 0, v_cp.delivery_fee_gnf::text);
    r := r || public._qa_s13_ok('P4.7 pickup runtime collateral is zero',
          v_cp.collateral_gnf = 0, v_cp.collateral_gnf::text);
    r := r || public._qa_s13_ok('P4.8 pickup runtime platform fee is the policy 1%',
          v_cp.platform_fee_gnf = 1500, v_cp.platform_fee_gnf::text);
    r := r || public._qa_s13_ok('P4.9 pickup runtime total = merchandise + fee',
          v_cp.order_total_gnf = 151500 AND v_cp.merchandise_subtotal_gnf = 150000,
          v_cp.order_total_gnf::text);
    r := r || public._qa_s13_ok('P4.10 runtime economics match the pre-commit quote',
          v_cp.order_total_gnf = (v_q->>'order_total_gnf')::bigint
          AND v_cp.platform_fee_gnf = (v_q->>'platform_fee_gnf')::bigint, NULL);
    r := r || public._qa_s13_ok('P4.11 policy snapshot is frozen on the runtime',
          (v_cp.policy_snapshot->>'transaction_fee_bps')::int = 100, v_cp.policy_snapshot::text);
    SELECT held_gnf, balance_gnf INTO v_held, v_c0
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('P4.12 customer holds exactly the pickup total',
          v_held = 151500, v_held::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='repas' AND source_id=v_o1 AND kind='collateral';
    r := r || public._qa_s13_ok('P4.13 no driver collateral hold is created for pickup', v_n = 0, v_n::text);

    -- ============ P5. LIFECYCLE ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    BEGIN PERFORM public.repas_merchant_transition(v_o1,'handoff'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P5.1 courier handoff is refused on a pickup order',
          v_err LIKE '%PICKUP_HAS_NO_COURIER_HANDOFF%', v_err);
    BEGIN PERFORM public.repas_merchant_transition(v_o1,'complete'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P5.2 pickup cannot complete before the food is ready',
          v_err LIKE '%ILLEGAL_TRANSITION%', v_err);

    PERFORM public.repas_merchant_transition(v_o1,'accept');
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime WHERE source_id=v_o1;
    r := r || public._qa_s13_ok('P5.3 merchant acceptance funds the pickup order',
          v_cp.state = 'merchant_accepted', v_cp.state);
    SELECT * INTO v_pay FROM public.merchant_payables
     WHERE source_module='repas' AND source_id=v_o1;
    r := r || public._qa_s13_ok('P5.4 merchandise is funded in full at acceptance',
          v_pay.funded_gnf = 150000 AND v_pay.amount_gnf = 150000 AND v_pay.state='funded',
          COALESCE(v_pay.state,'none'));

    PERFORM public.repas_merchant_transition(v_o1,'prepare');
    PERFORM public.repas_merchant_transition(v_o1,'ready');
    SELECT state::text INTO v_err FROM public.food_orders WHERE id=v_o1;
    r := r || public._qa_s13_ok('P5.5 pickup order reaches ready', v_err = 'ready', v_err);

    BEGIN PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
      PERFORM public.chop_pay_merchant_pickup_complete('repas', v_o1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P5.6 a stranger cannot confirm the pickup handover',
          v_err LIKE '%Not authorized%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);

    v_res := public.repas_merchant_transition(v_o1,'complete');
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime WHERE source_id=v_o1;
    r := r || public._qa_s13_ok('P5.7 pickup completes through the Chop Pay engine',
          v_cp.state = 'completed', v_cp.state);
    SELECT state::text INTO v_err FROM public.food_orders WHERE id=v_o1;
    r := r || public._qa_s13_ok('P5.8 food order is completed', v_err = 'completed', v_err);
    r := r || public._qa_s13_ok('P5.9 no driver earning is recorded for pickup',
          v_cp.driver_earning_gnf = 0, v_cp.driver_earning_gnf::text);
    r := r || public._qa_s13_ok('P5.10 platform revenue equals the 1% fee',
          v_cp.platform_revenue_gnf = 1500, v_cp.platform_revenue_gnf::text);
    r := r || public._qa_s13_ok('P5.11 merchant credit equals the merchandise subtotal',
          v_cp.merchant_credited_gnf = 150000, v_cp.merchant_credited_gnf::text);

    v_res := public.repas_merchant_transition(v_o1,'complete');
    r := r || public._qa_s13_ok('P5.12 repeated pickup completion is idempotent',
          (v_res->>'ok')::boolean, v_res::text);
    SELECT count(*) INTO v_n FROM public.ledger_journals
     WHERE source_module='repas' AND source_id=v_o1 AND journal_key LIKE '%platform_fee%';
    r := r || public._qa_s13_ok('P5.13 exactly one platform fee journal', v_n = 1, v_n::text);

    -- ============ P6. CONSERVATION ============
    SELECT balance_gnf, held_gnf INTO v_c1, v_held
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('P6.1 customer paid exactly merchandise + fee',
          v_c0 - v_c1 = 151500, (v_c0 - v_c1)::text);
    r := r || public._qa_s13_ok('P6.2 no residual customer hold after collection',
          v_held = 0, v_held::text);
    r := r || public._qa_s13_ok('P6.3 customer outflow reconciles to merchant + platform',
          (v_c0 - v_c1) = v_cp.merchant_credited_gnf + v_cp.platform_revenue_gnf
                          + v_cp.driver_earning_gnf, NULL);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='repas' AND source_id=v_o1 AND driver_user_id IS NOT NULL;
    r := r || public._qa_s13_ok('P6.4 no driver-side hold touched a pickup order', v_n = 0, v_n::text);
    SELECT count(*) INTO v_unbalanced FROM (
      SELECT j.id FROM public.ledger_journals j
        JOIN public.ledger_postings p ON p.journal_id = j.id
       WHERE j.created_at >= now() - interval '5 minutes'
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('P6.5 every journal created here is zero-sum',
          v_unbalanced = 0, v_unbalanced::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='repas' AND source_id=v_o1 AND (captured_gnf + released_gnf) > amount_gnf;
    r := r || public._qa_s13_ok('P6.6 no hold is over-consumed', v_n = 0, v_n::text);

    PERFORM set_config('request.jwt.claims', ''::text, true);
    RAISE EXCEPTION 'QA_NODE3_PICKUP_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE3_PICKUP_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS aborted before completion', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', ''::text, true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z4.1 master wallet unchanged after fixture rollback',
        v_master0 IS NOT DISTINCT FROM v_master1, v_master1::text);
  r := r || public._qa_s13_ok('Z4.2 feature flags byte-identical after fixture rollback',
        v_flags0 = v_flags1, NULL);
  SELECT count(*) INTO v_n FROM public.food_restaurants WHERE slug LIKE 'qa-n3p-%';
  r := r || public._qa_s13_ok('Z4.3 no restaurant fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.chop_pay_order_runtime c
    JOIN auth.users u ON u.id = c.customer_user_id WHERE u.email LIKE 'qa-s13-n3p%';
  r := r || public._qa_s13_ok('Z4.4 no Chop Pay runtime residue', v_n = 0, v_n::text);

  RETURN jsonb_build_object('part','node3_repas_pickup',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END; $function$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_pickup() FROM PUBLIC, anon, authenticated;