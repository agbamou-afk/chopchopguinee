CREATE OR REPLACE FUNCTION public._qa_node4_marche_r3()
 RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_buy uuid; v_buy2 uuid; v_merch uuid; v_merch2 uuid; v_other uuid; v_adm uuid;
  v_store uuid; v_store2 uuid;
  l_fix uuid; l_neg uuid; l_quote uuid; l_one uuid; l_s2 uuid; l_paused uuid; l_legacy uuid;
  v_err text; v_n int; v_res jsonb; v_res2 jsonb; v_o1 uuid; v_o2 uuid; v_off uuid; v_off2 uuid;
  v_row public.marketplace_listings; v_ord public.marche_orders; v_item public.marche_order_items;
  v_src text; v_flags0 jsonb; v_flags1 jsonb; v_key text;
  v_w0 bigint; v_w1 bigint; v_wt0 bigint; v_wt1 bigint; v_lj0 bigint; v_lj1 bigint;
  v_ms0 bigint; v_ms1 bigint; v_pi0 bigint; v_pi1 bigint; v_lp0 bigint; v_lp1 bigint;
  v_demo0 bigint; v_demo1 bigint; v_total0 bigint; v_total1 bigint; v_none0 bigint; v_none1 bigint;
  v_reserved0 bigint; v_reserved1 bigint;
BEGIN
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;
  SELECT count(*) INTO v_w0 FROM public.wallets;
  SELECT count(*) INTO v_wt0 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj0 FROM public.ledger_journals;
  SELECT count(*) INTO v_ms0 FROM public.missions;
  SELECT count(*) INTO v_pi0 FROM public.payment_intents;
  SELECT count(*) INTO v_lp0 FROM public.ledger_postings;
  SELECT count(*) INTO v_total0 FROM public.marketplace_listings;
  SELECT count(*) INTO v_none0 FROM public.marketplace_listings WHERE store_id IS NULL;
  SELECT count(*) INTO v_demo0 FROM public.v_marche_listing_truth WHERE is_demo;
  SELECT COALESCE(sum(quantity_reserved),0) INTO v_reserved0 FROM public.marketplace_listings;

  -- ================= A. STRUCTURAL LAW =================
  r := r || public._qa_s13_ok('N4R3.A1 canonical order table exists',
        to_regclass('public.marche_orders') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R3.A2 canonical order line table exists',
        to_regclass('public.marche_order_items') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R3.A3 listings carry quantity_reserved NOT NULL DEFAULT 0',
        EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='marketplace_listings'
                   AND column_name='quantity_reserved' AND is_nullable='NO' AND column_default='0'), NULL);
  r := r || public._qa_s13_ok('N4R3.A4 reserved stock can never be negative',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marketplace_listings_qty_reserved_nonneg'), NULL);
  r := r || public._qa_s13_ok('N4R3.A5 reserved stock can never exceed finite stock',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marketplace_listings_qty_reserved_within_stock'), NULL);
  r := r || public._qa_s13_ok('N4R3.A6 idempotency key unique per buyer',
        EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='marche_orders_buyer_request_key'), NULL);
  r := r || public._qa_s13_ok('N4R3.A7 order line indexes exist',
        EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='marche_order_items_order_idx')
    AND EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='marche_order_items_listing_idx'), NULL);
  r := r || public._qa_s13_ok('N4R3.A8 order status vocabulary constrained',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_orders_status_legal'), NULL);
  r := r || public._qa_s13_ok('N4R3.A9 line total arithmetic constrained',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_order_items_total_exact'), NULL);
  r := r || public._qa_s13_ok('N4R3.A10 order/store/status indexes exist',
        EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='marche_orders_store_idx')
    AND EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='marche_orders_status_idx'), NULL);
  r := r || public._qa_s13_ok('N4R3.A11 canonical truth exposes reservation arithmetic',
        pg_get_viewdef('public.v_marche_listing_truth'::regclass, true) LIKE '%quantity_available%'
    AND pg_get_viewdef('public.v_marche_listing_truth'::regclass, true) LIKE '%quantity_reserved%', NULL);
  r := r || public._qa_s13_ok('N4R3.A12 truth still speaks R1/R1.5 refusal vocabulary',
        pg_get_viewdef('public.v_marche_listing_truth'::regclass, true) LIKE '%MERCHANT_STORE_REQUIRED%'
    AND pg_get_viewdef('public.v_marche_listing_truth'::regclass, true) LIKE '%STORE_NOT_APPROVED%'
    AND pg_get_viewdef('public.v_marche_listing_truth'::regclass, true) LIKE '%DEMO_SUPPLY%'
    AND pg_get_viewdef('public.v_marche_listing_truth'::regclass, true) LIKE '%OUT_OF_STOCK%', NULL);

  v_src := (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='marche_order_commit');
  r := r || public._qa_s13_ok('N4R3.A13 commit locks listing rows deterministically FOR UPDATE',
        v_src LIKE '%ORDER BY id FOR UPDATE%', NULL);
  r := r || public._qa_s13_ok('N4R3.A14 commit refuses client-authored money',
        v_src LIKE '%CLIENT_PRICE_NOT_ALLOWED%', NULL);
  r := r || public._qa_s13_ok('N4R3.A15 commit enforces single-store law',
        v_src LIKE '%SINGLE_STORE_ONLY%', NULL);
  r := r || public._qa_s13_ok('N4R3.A16 commit consumes canonical truth',
        v_src LIKE '%v_marche_listing_truth%', NULL);
  r := r || public._qa_s13_ok('N4R3.A17 order mutation primitives are definer with pinned search_path',
        (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND proname IN ('marche_order_commit','marche_order_cancel','marche_order_get',
                          'marche_orders_for_buyer','marche_orders_for_merchant','marche_orders_admin',
                          'marche_order_release_expired')
          AND prosecdef AND proconfig::text LIKE '%search_path=public%') = 7, NULL);
  r := r || public._qa_s13_ok('N4R3.A18 direct order CRUD denied to anon/authenticated',
        NOT has_table_privilege('authenticated','public.marche_orders','SELECT')
    AND NOT has_table_privilege('authenticated','public.marche_orders','INSERT')
    AND NOT has_table_privilege('authenticated','public.marche_orders','UPDATE')
    AND NOT has_table_privilege('authenticated','public.marche_orders','DELETE')
    AND NOT has_table_privilege('anon','public.marche_orders','SELECT')
    AND NOT has_table_privilege('anon','public.marche_orders','INSERT')
    AND NOT has_table_privilege('anon','public.marche_orders','UPDATE')
    AND NOT has_table_privilege('anon','public.marche_orders','DELETE'), NULL);
  r := r || public._qa_s13_ok('N4R3.A19 direct order-line CRUD denied to anon/authenticated',
        NOT has_table_privilege('authenticated','public.marche_order_items','SELECT')
    AND NOT has_table_privilege('authenticated','public.marche_order_items','INSERT')
    AND NOT has_table_privilege('authenticated','public.marche_order_items','UPDATE')
    AND NOT has_table_privilege('authenticated','public.marche_order_items','DELETE')
    AND NOT has_table_privilege('anon','public.marche_order_items','SELECT')
    AND NOT has_table_privilege('anon','public.marche_order_items','INSERT')
    AND NOT has_table_privilege('anon','public.marche_order_items','UPDATE')
    AND NOT has_table_privilege('anon','public.marche_order_items','DELETE'), NULL);
  r := r || public._qa_s13_ok('N4R3.A20 RLS enabled on both order tables',
        (SELECT bool_and(relrowsecurity) FROM pg_class
          WHERE oid IN ('public.marche_orders'::regclass,'public.marche_order_items'::regclass)), NULL);
  r := r || public._qa_s13_ok('N4R3.A21 anon cannot execute any order authority',
        NOT has_function_privilege('anon','public.marche_order_commit(jsonb)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_order_cancel(uuid,text)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_order_get(uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_orders_for_buyer(integer,integer)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_orders_for_merchant(uuid,integer,integer)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_orders_admin(integer,integer)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R3.A22 signed-in buyers may execute the sanctioned RPCs',
        has_function_privilege('authenticated','public.marche_order_commit(jsonb)','EXECUTE')
    AND has_function_privilege('authenticated','public.marche_order_cancel(uuid,text)','EXECUTE')
    AND has_function_privilege('authenticated','public.marche_order_get(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R3.A23 reservation sweeper is service/admin-only',
        NOT has_function_privilege('anon','public.marche_order_release_expired(integer)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public.marche_order_release_expired(integer)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R3.A24 has_role remains not executable by anon',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R3.A25 order guard forbids finance columns in R3',
        (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='marche_order_guard')
          LIKE '%FINANCE_NOT_IN_R3%', NULL);
  r := r || public._qa_s13_ok('N4R3.A26 order lines are immutable by trigger',
        (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='marche_order_item_guard')
          LIKE '%ORDER_LINE_IMMUTABLE%', NULL);
  r := r || public._qa_s13_ok('N4R3.A27 R2 offer machine untouched',
        (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='marche_offer_transition_guard')
          LIKE '%COUNTER_AWAITS_BUYER%', NULL);
  r := r || public._qa_s13_ok('N4R3.A28 sanitized order payload never exposes minimum price',
        (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='marche_order_json')
          NOT LIKE '%minimum_price%', NULL);

  -- ================= B. RUNTIME =================
  BEGIN
    v_buy := gen_random_uuid(); v_buy2 := gen_random_uuid(); v_merch := gen_random_uuid();
    v_merch2 := gen_random_uuid(); v_other := gen_random_uuid(); v_adm := gen_random_uuid();
    PERFORM public._qa_s13_user(v_buy,'n43b');   PERFORM public._qa_s13_user(v_buy2,'n43b2');
    PERFORM public._qa_s13_user(v_merch,'n43m'); PERFORM public._qa_s13_user(v_merch2,'n43m2');
    PERFORM public._qa_s13_user(v_other,'n43o'); PERFORM public._qa_s13_user(v_adm,'n43a');
    PERFORM public._qa_s13_admin(v_adm);

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status)
      VALUES (v_merch,'qa-n43-a-'||substr(v_merch::text,1,8),'QA N43 Store A','active','approved')
      RETURNING id INTO v_store;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status)
      VALUES (v_merch2,'qa-n43-b-'||substr(v_merch2::text,1,8),'QA N43 Store B','active','approved')
      RETURNING id INTO v_store2;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    l_fix := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N43 Fixed Item',
      'category','Autre','price_gnf',50000,'quantity_in_stock',5,'publish',true));
    l_neg := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N43 Negotiable Item',
      'category','Autre','price_gnf',80000,'quantity_in_stock',2,'publish',true));
    l_quote := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N43 Quote Item',
      'category','Autre','price_gnf',30000,'quantity_in_stock',3,'publish',true));
    l_one := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N43 Last Unit',
      'category','Autre','price_gnf',20000,'quantity_in_stock',1,'publish',true));
    l_paused := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N43 Paused Item',
      'category','Autre','price_gnf',15000,'quantity_in_stock',3,'publish',false));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch2), true);
    l_s2 := public.marche_listing_create(jsonb_build_object('store_id',v_store2,'title','QA N43 Other Store Item',
      'category','Autre','price_gnf',25000,'quantity_in_stock',4,'publish',true));

    PERFORM set_config('request.jwt.claims','', true);
    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.marketplace_listings
       SET pricing_mode='negotiable', allow_offers=true, is_negotiable=true,
           asking_price_gnf=80000, minimum_price_gnf=777777
     WHERE id = l_neg;
    UPDATE public.marketplace_listings SET pricing_mode='quote', allow_offers=true WHERE id = l_quote;
    INSERT INTO public.marketplace_listings(seller_id, store_id, kind, category, title,
      price_gnf, pricing_mode, status, visibility, availability, quantity_in_stock)
      VALUES (v_other, NULL, 'community','Autre','QA N43 Legacy Community',9000,'fixed','active','public','available',3)
      RETURNING id INTO l_legacy;
    PERFORM set_config('marche.rpc','', true);

    -- B1 happy path fixed-price
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_key := 'qa-n43-key-fix-'||substr(v_buy::text,1,8);
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id', v_key,
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_fix, 'qty', 2)),
      'delivery_address','Kaloum, Conakry','dropoff_lat',9.509,'dropoff_lng',-13.712));
    v_o1 := (v_res->>'id')::uuid;
    r := r || public._qa_s13_ok('N4R3.B1 fixed-price order commits in a non-money state',
          v_res->>'status' = 'committed', v_res->>'status');
    r := r || public._qa_s13_ok('N4R3.B1b server derives the merchandise subtotal',
          (v_res->>'merchandise_subtotal_gnf')::bigint = 100000, v_res->>'merchandise_subtotal_gnf');
    r := r || public._qa_s13_ok('N4R3.B1c item_count and line_count frozen',
          (v_res->>'item_count')::int = 2 AND (v_res->>'line_count')::int = 1,
          v_res->>'item_count');
    r := r || public._qa_s13_ok('N4R3.B1d line freezes qty * canonical unit price',
          (v_res->'items'->0->>'unit_price_gnf')::bigint = 50000
      AND (v_res->'items'->0->>'line_total_gnf')::bigint = 100000
      AND (v_res->'items'->0->>'qty')::int = 2, v_res->'items'->0->>'line_total_gnf');
    r := r || public._qa_s13_ok('N4R3.B1e store and title snapshots frozen on the line',
          (v_res->'items'->0->>'store_id')::uuid = v_store
      AND v_res->'items'->0->>'title' = 'QA N43 Fixed Item', v_res->'items'->0->>'title');
    r := r || public._qa_s13_ok('N4R3.B1f destination metadata persisted for future fulfilment',
          v_res->>'delivery_address' = 'Kaloum, Conakry'
      AND (v_res->>'dropoff_lat')::double precision = 9.509
      AND (v_res->>'dropoff_lng')::double precision = -13.712, NULL);
    r := r || public._qa_s13_ok('N4R3.B1g no finance is attached in R3',
          v_res->>'merchant_fee_gnf' IS NULL AND v_res->>'delivery_charge_gnf' IS NULL
      AND v_res->>'fee_policy_id' IS NULL, NULL);
    r := r || public._qa_s13_ok('N4R3.B1h merchant identity resolved server-side',
          (v_res->>'merchant_store_id')::uuid = v_store AND (v_res->>'merchant_user_id')::uuid = v_merch, NULL);

    -- B2 reservation truth
    SELECT * INTO v_row FROM public.marketplace_listings WHERE id = l_fix;
    r := r || public._qa_s13_ok('N4R3.B2 commitment reserves stock immediately',
          v_row.quantity_reserved = 2, v_row.quantity_reserved::text);
    v_res2 := public.marche_listing_truth(l_fix);
    r := r || public._qa_s13_ok('N4R3.B2b canonical availability drops by the reserved quantity',
          (v_res2->>'quantity_available')::int = 3 AND (v_res2->>'quantity_reserved')::int = 2,
          v_res2->>'quantity_available');
    r := r || public._qa_s13_ok('N4R3.B2c listing stays orderable while units remain',
          (v_res2->>'is_orderable')::boolean, v_res2->>'refusal_reason');

    -- B3 idempotency
    v_res2 := public.marche_order_commit(jsonb_build_object(
      'client_request_id', v_key,
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_fix, 'qty', 2)),
      'delivery_address','Kaloum, Conakry','dropoff_lat',9.509,'dropoff_lng',-13.712));
    r := r || public._qa_s13_ok('N4R3.B3 identical key + payload returns the same order',
          (v_res2->>'id')::uuid = v_o1, v_res2->>'id');
    SELECT * INTO v_row FROM public.marketplace_listings WHERE id = l_fix;
    r := r || public._qa_s13_ok('N4R3.B3b replay reserves stock exactly once',
          v_row.quantity_reserved = 2, v_row.quantity_reserved::text);
    SELECT count(*) INTO v_n FROM public.marche_orders WHERE buyer_user_id = v_buy AND client_request_id = v_key;
    r := r || public._qa_s13_ok('N4R3.B3c exactly one order row for the key', v_n = 1, v_n::text);
    v_err := NULL;
    BEGIN
      PERFORM public.marche_order_commit(jsonb_build_object(
        'client_request_id', v_key,
        'items', jsonb_build_array(jsonb_build_object('listing_id', l_fix, 'qty', 3))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B3d same key with a changed payload is refused',
          v_err = 'IDEMPOTENCY_CONFLICT', v_err);
    v_err := NULL;
    BEGIN
      PERFORM public.marche_order_commit(jsonb_build_object(
        'items', jsonb_build_array(jsonb_build_object('listing_id', l_fix, 'qty', 1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B3e a commitment key is mandatory',
          v_err = 'CLIENT_REQUEST_ID_REQUIRED', v_err);

    -- B4 client cannot author money
    v_err := NULL;
    BEGIN
      PERFORM public.marche_order_commit(jsonb_build_object(
        'client_request_id','qa-n43-price-attack-1',
        'items', jsonb_build_array(jsonb_build_object('listing_id', l_fix, 'qty', 1, 'unit_price_gnf', 1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B4 client-sent unit price is refused',
          v_err = 'CLIENT_PRICE_NOT_ALLOWED', v_err);
    v_err := NULL;
    BEGIN
      PERFORM public.marche_order_commit(jsonb_build_object(
        'client_request_id','qa-n43-price-attack-2','merchandise_subtotal_gnf', 1,
        'items', jsonb_build_array(jsonb_build_object('listing_id', l_fix, 'qty', 1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B4b client-sent subtotal is refused',
          v_err = 'CLIENT_PRICE_NOT_ALLOWED', v_err);
    v_err := NULL;
    BEGIN
      PERFORM public.marche_order_commit(jsonb_build_object(
        'client_request_id','qa-n43-price-attack-3',
        'items', jsonb_build_array(jsonb_build_object('listing_id', l_fix, 'qty', 1, 'line_total_gnf', 1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B4c client-sent line total is refused',
          v_err = 'CLIENT_PRICE_NOT_ALLOWED', v_err);

    -- B5 quantity law
    FOR v_n IN 1..1 LOOP END LOOP;
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-qty-0',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_fix, 'qty', 0))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B5 zero quantity refused', v_err = 'INVALID_QUANTITY', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-qty-neg',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_fix, 'qty', -3))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B5b negative quantity refused', v_err = 'INVALID_QUANTITY', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-qty-over',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_fix, 'qty', 9))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B5c quantity beyond availability refused',
          v_err = 'INSUFFICIENT_STOCK', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-empty',
      'items', '[]'::jsonb));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B5d empty basket refused', v_err = 'EMPTY_BASKET', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-dupe',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_fix,'qty',1),
                                 jsonb_build_object('listing_id', l_fix,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B5e duplicate line refused', v_err = 'DUPLICATE_LINE', v_err);
    SELECT * INTO v_row FROM public.marketplace_listings WHERE id = l_fix;
    r := r || public._qa_s13_ok('N4R3.B5f refused commitments never reserve stock',
          v_row.quantity_reserved = 2, v_row.quantity_reserved::text);

    -- B6 supply doctrine at commit
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-single-store',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_fix,'qty',1),
                                 jsonb_build_object('listing_id', l_s2,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B6 mixed-store basket refused SINGLE_STORE_ONLY',
          v_err = 'SINGLE_STORE_ONLY', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-quote',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_quote,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B6b quote supply is not orderable in R3',
          v_err = 'QUOTE_NOT_ORDERABLE', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-paused',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_paused,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B6c unpublished supply refused with canonical reason',
          v_err IN ('LISTING_PAUSED','LISTING_PRIVATE'), v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-legacy',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_legacy,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B6d storeless legacy supply refused MERCHANT_STORE_REQUIRED',
          v_err = 'MERCHANT_STORE_REQUIRED', v_err);
    UPDATE public.merchant_stores SET onboarding_status='submitted' WHERE id = v_store2;
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-unappr',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_s2,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B6e unapproved store supply refused STORE_NOT_APPROVED',
          v_err = 'STORE_NOT_APPROVED', v_err);
    UPDATE public.merchant_stores SET onboarding_status='approved' WHERE id = v_store2;
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-nolisting',
      'items', jsonb_build_array(jsonb_build_object('listing_id', gen_random_uuid(),'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B6f unknown listing refused', v_err = 'LISTING_NOT_FOUND', v_err);

    -- B7 self purchase / auth
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-self',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_fix,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B7 seller cannot buy their own supply',
          v_err = 'SELF_PURCHASE_NOT_ALLOWED', v_err);
    PERFORM set_config('request.jwt.claims','', true);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-anon',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_fix,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B7b unauthenticated commitment refused', v_err = 'AUTH_REQUIRED', v_err);

    -- B8 negotiable path through R2
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_off := public.create_marketplace_offer(l_neg, 60000, 'QA offer', 'cash');
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-neg-pending',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_neg,'qty',1,'offer_id', v_off))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B8 pending offer cannot source an order',
          v_err = 'OFFER_NOT_AGREED', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-neg-nooffer',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_neg,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B8b negotiable supply requires an agreement',
          v_err = 'OFFER_REQUIRED', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-fix-offer',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_fix,'qty',1,'offer_id', v_off))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B8c fixed-price supply refuses an offer reference',
          v_err = 'OFFER_NOT_APPLICABLE', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.merchant_respond_marketplace_offer(v_off, 'counter', 70000, 'QA counter');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-neg-countered',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_neg,'qty',1,'offer_id', v_off))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B8d countered offer cannot source an order',
          v_err = 'OFFER_NOT_AGREED', v_err);
    PERFORM public.buyer_respond_marketplace_offer(v_off, 'accept', NULL);
    SELECT agreed_amount_gnf INTO v_n FROM public.marketplace_offers WHERE id = v_off;
    r := r || public._qa_s13_ok('N4R3.B8e R2 agreement froze the counter amount', v_n = 70000, v_n::text);

    v_res := public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-neg-ok-'||substr(v_buy::text,1,8),
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_neg,'qty',1,'offer_id', v_off))));
    v_o2 := (v_res->>'id')::uuid;
    r := r || public._qa_s13_ok('N4R3.B8f negotiated order uses exactly the agreed amount',
          (v_res->'items'->0->>'unit_price_gnf')::bigint = 70000
      AND (v_res->>'merchandise_subtotal_gnf')::bigint = 70000, v_res->>'merchandise_subtotal_gnf');
    r := r || public._qa_s13_ok('N4R3.B8g negotiated order references the sourcing agreement',
          (v_res->>'source_offer_id')::uuid = v_off, v_res->>'source_offer_id');
    r := r || public._qa_s13_ok('N4R3.B8h the R2 offer itself is not mutated by ordering',
          (SELECT status FROM public.marketplace_offers WHERE id = v_off) = 'accepted', NULL);
    r := r || public._qa_s13_ok('N4R3.B8i negotiated commitment reserved its unit',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id = l_neg) = 1, NULL);
    r := r || public._qa_s13_ok('N4R3.B8j sanitized order never leaks the secret floor price',
          v_res::text NOT LIKE '%777777%', NULL);

    -- another buyer cannot borrow the agreement
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy2), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-steal-offer',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_neg,'qty',1,'offer_id', v_off))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B8k another buyer cannot use a foreign agreement',
          v_err = 'OFFER_NOT_FOR_THIS_BUYER', v_err);

    -- rejected offer path
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy2), true);
    v_off2 := public.create_marketplace_offer(l_neg, 55000, 'QA offer 2', 'cash');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.merchant_respond_marketplace_offer(v_off2, 'reject', NULL, 'no');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy2), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-rejected',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_neg,'qty',1,'offer_id', v_off2))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B8l rejected offer cannot source an order',
          v_err = 'OFFER_NOT_AGREED', v_err);

    -- B9 snapshot immutability after merchant edits
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.marche_listing_update(l_fix, jsonb_build_object('title','QA N43 Fixed Item RENAMED','price_gnf', 99000));
    SELECT * INTO v_item FROM public.marche_order_items WHERE order_id = v_o1;
    r := r || public._qa_s13_ok('N4R3.B9 title snapshot survives a later merchant edit',
          v_item.title_snapshot = 'QA N43 Fixed Item', v_item.title_snapshot);
    r := r || public._qa_s13_ok('N4R3.B9b unit price snapshot survives a later price change',
          v_item.unit_price_gnf = 50000 AND v_item.line_total_gnf = 100000, v_item.unit_price_gnf::text);
    SELECT * INTO v_ord FROM public.marche_orders WHERE id = v_o1;
    r := r || public._qa_s13_ok('N4R3.B9c committed subtotal is not repriced by merchant edits',
          v_ord.merchandise_subtotal_gnf = 100000, v_ord.merchandise_subtotal_gnf::text);
    v_err := NULL;
    BEGIN UPDATE public.marche_order_items SET unit_price_gnf = 1 WHERE id = v_item.id;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B9d order lines are physically immutable',
          v_err = 'ORDER_LINE_IMMUTABLE', v_err);
    v_err := NULL;
    BEGIN UPDATE public.marche_orders SET merchandise_subtotal_gnf = 1 WHERE id = v_o1;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B9e committed monetary truth is physically immutable',
          v_err = 'ORDER_IMMUTABLE', v_err);
    v_err := NULL;
    BEGIN UPDATE public.marche_orders SET merchant_fee_gnf = 1000 WHERE id = v_o1;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B9f fee columns cannot be populated in R3',
          v_err = 'FINANCE_NOT_IN_R3', v_err);
    v_err := NULL;
    BEGIN UPDATE public.marche_orders SET status = 'committed', buyer_user_id = v_buy2 WHERE id = v_o1;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B9g order ownership cannot be reassigned',
          v_err = 'ORDER_IMMUTABLE', v_err);

    -- B10 last-unit contention (row-lock protected)
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-race-a',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_one,'qty',1))));
    r := r || public._qa_s13_ok('N4R3.B10 first buyer captures the final unit',
          v_res->>'status' = 'committed', v_res->>'status');
    r := r || public._qa_s13_ok('N4R3.B10b final unit is now fully reserved',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id = l_one) = 1, NULL);
    v_res2 := public.marche_listing_truth(l_one);
    r := r || public._qa_s13_ok('N4R3.B10c canonical truth turns OUT_OF_STOCK once reserved',
          (v_res2->>'is_orderable')::boolean = false AND v_res2->>'refusal_reason' = 'OUT_OF_STOCK',
          v_res2->>'refusal_reason');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy2), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-race-b',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_one,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B10d second buyer cannot oversell the same unit',
          v_err = 'OUT_OF_STOCK', v_err);
    SELECT count(*) INTO v_n FROM public.marche_order_items WHERE listing_id = l_one;
    r := r || public._qa_s13_ok('N4R3.B10e exactly one commitment exists for the final unit', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.marketplace_listings
      WHERE quantity_in_stock IS NOT NULL AND quantity_reserved > quantity_in_stock;
    r := r || public._qa_s13_ok('N4R3.B10f no listing anywhere is over-reserved', v_n = 0, v_n::text);

    -- B11 cancellation releases exactly once
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_order_cancel(v_o1, 'QA cancel');
    r := r || public._qa_s13_ok('N4R3.B11 buyer can cancel a committed order',
          v_res->>'status' = 'cancelled' AND v_res->>'cancel_reason' = 'QA cancel', v_res->>'status');
    r := r || public._qa_s13_ok('N4R3.B11b cancellation releases the reservation',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id = l_fix) = 0, NULL);
    v_res2 := public.marche_order_cancel(v_o1, 'QA cancel again');
    r := r || public._qa_s13_ok('N4R3.B11c cancel replay is idempotent',
          v_res2->>'status' = 'cancelled' AND v_res2->>'cancel_reason' = 'QA cancel', v_res2->>'cancel_reason');
    r := r || public._qa_s13_ok('N4R3.B11d replay never double-releases stock',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id = l_fix) = 0, NULL);
    SELECT count(*) INTO v_n FROM public.marketplace_listings WHERE quantity_reserved < 0;
    r := r || public._qa_s13_ok('N4R3.B11e reserved stock never goes negative', v_n = 0, v_n::text);
    r := r || public._qa_s13_ok('N4R3.B11f released unit is orderable again',
          (public.marche_listing_truth(l_fix)->>'is_orderable')::boolean, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_other), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_cancel(v_o2, 'hijack');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B11g a third party cannot cancel someone else order',
          v_err = 'NOT_AUTHORIZED', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_res := public.marche_order_cancel(v_o2, 'merchant refusal');
    r := r || public._qa_s13_ok('N4R3.B11h merchant may cancel an order on their own store',
          v_res->>'status' = 'cancelled', v_res->>'status');
    r := r || public._qa_s13_ok('N4R3.B11i negotiated cancellation released its unit',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id = l_neg) = 0, NULL);

    -- B12 read isolation
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    r := r || public._qa_s13_ok('N4R3.B12 buyer reads their own order',
          (public.marche_order_get(v_o1)->>'id')::uuid = v_o1, NULL);
    SELECT count(*) INTO v_n FROM jsonb_array_elements(public.marche_orders_for_buyer(50,0)) x
      WHERE (x->>'buyer_user_id')::uuid <> v_buy;
    r := r || public._qa_s13_ok('N4R3.B12b buyer feed contains only their own orders', v_n = 0, v_n::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_other), true);
    r := r || public._qa_s13_ok('N4R3.B12c a third party cannot read the order',
          public.marche_order_get(v_o1) IS NULL, NULL);
    SELECT jsonb_array_length(public.marche_orders_for_buyer(50,0)) INTO v_n;
    r := r || public._qa_s13_ok('N4R3.B12d a third party buyer feed is empty', v_n = 0, v_n::text);
    SELECT jsonb_array_length(public.marche_orders_for_merchant(NULL,50,0)) INTO v_n;
    r := r || public._qa_s13_ok('N4R3.B12e a non-merchant merchant feed is empty', v_n = 0, v_n::text);
    SELECT jsonb_array_length(public.marche_orders_admin(100,0)) INTO v_n;
    r := r || public._qa_s13_ok('N4R3.B12f a non-admin admin feed is empty', v_n = 0, v_n::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    r := r || public._qa_s13_ok('N4R3.B12g merchant reads orders placed on their store',
          (public.marche_order_get(v_o1)->>'id')::uuid = v_o1, NULL);
    SELECT count(*) INTO v_n FROM jsonb_array_elements(public.marche_orders_for_merchant(NULL,50,0)) x
      WHERE (x->>'merchant_store_id')::uuid <> v_store;
    r := r || public._qa_s13_ok('N4R3.B12h merchant feed is scoped to their own stores', v_n = 0, v_n::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch2), true);
    r := r || public._qa_s13_ok('N4R3.B12i another merchant cannot read a foreign store order',
          public.marche_order_get(v_o1) IS NULL, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    r := r || public._qa_s13_ok('N4R3.B12j admin can read any order through the sanitized RPC',
          (public.marche_order_get(v_o1)->>'id')::uuid = v_o1, NULL);
    SELECT jsonb_array_length(public.marche_orders_admin(100,0)) INTO v_n;
    r := r || public._qa_s13_ok('N4R3.B12k admin feed returns orders', v_n >= 2, v_n::text);
    r := r || public._qa_s13_ok('N4R3.B12l sanitized feeds never contain the secret floor price',
          public.marche_orders_admin(100,0)::text NOT LIKE '%777777%', NULL);

    -- B13 hostile role probes
    v_n := public._qa_node4_probe('anon', NULL, 'SELECT count(*)::int FROM public.marche_orders');
    r := r || public._qa_s13_ok('N4R3.B13 anon cannot enumerate orders', v_n = -1, v_n::text);
    v_n := public._qa_node4_probe('anon', NULL, 'SELECT count(*)::int FROM public.marche_order_items');
    r := r || public._qa_s13_ok('N4R3.B13b anon cannot enumerate order lines', v_n = -1, v_n::text);
    v_n := public._qa_node4_probe('authenticated', v_buy, 'SELECT count(*)::int FROM public.marche_orders');
    r := r || public._qa_s13_ok('N4R3.B13c signed-in users cannot read the order table directly', v_n = -1, v_n::text);
    v_n := public._qa_node4_probe('authenticated', v_buy,
      format('UPDATE public.marketplace_listings SET quantity_reserved = 0 WHERE id = %L; SELECT 1', l_fix));
    r := r || public._qa_s13_ok('N4R3.B13d signed-in users cannot rewrite reserved stock', v_n = -1, v_n::text);
    v_n := public._qa_node4_probe('anon', NULL,
      'SELECT count(*)::int FROM public.marche_listings_discover(NULL,NULL,NULL,''recent'',20,0)');
    r := r || public._qa_s13_ok('N4R3.B13e anon discovery still works without has_role', v_n >= 0, v_n::text);
    v_n := public._qa_node4_probe('authenticated', v_buy,
      'SELECT jsonb_array_length(public.marche_orders_for_buyer(10,0))');
    r := r || public._qa_s13_ok('N4R3.B13f buyer feed is reachable through the RPC as authenticated',
          v_n >= 1, v_n::text);

    -- B14 reservation expiry sweeper
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_order_commit(jsonb_build_object('client_request_id','qa-n43-exp-'||substr(v_buy::text,1,8),
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_fix,'qty',1))));
    v_o1 := (v_res->>'id')::uuid;
    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.marche_orders SET reservation_expires_at = now() - interval '1 minute' WHERE id = v_o1;
    PERFORM set_config('marche.rpc','', true);
    r := r || public._qa_s13_ok('N4R3.B14 reservation held before sweeping',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id = l_fix) = 1, NULL);
    v_n := public.marche_order_release_expired(50);
    r := r || public._qa_s13_ok('N4R3.B14b sweeper released the due reservation', v_n >= 1, v_n::text);
    r := r || public._qa_s13_ok('N4R3.B14c swept order is terminal expired',
          (SELECT status FROM public.marche_orders WHERE id = v_o1) = 'expired', NULL);
    r := r || public._qa_s13_ok('N4R3.B14d swept reservation returned to availability',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id = l_fix) = 0, NULL);
    r := r || public._qa_s13_ok('N4R3.B14e sweeper replay is idempotent',
          public.marche_order_release_expired(50) = 0, NULL);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_cancel(v_o1, 'after expiry');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R3.B14f cancelling an expired order is a no-op, not a second release',
          v_err IS NULL AND (SELECT quantity_reserved FROM public.marketplace_listings WHERE id = l_fix) = 0, v_err);

    -- B15 finance abstinence
    SELECT count(*) INTO v_n FROM public.marche_orders
     WHERE merchant_fee_gnf IS NOT NULL OR delivery_charge_gnf IS NOT NULL OR fee_policy_id IS NOT NULL;
    r := r || public._qa_s13_ok('N4R3.B15 no order carries fee or delivery money in R3', v_n = 0, v_n::text);
    r := r || public._qa_s13_ok('N4R3.B15b commit never touches payment intents',
          v_src NOT LIKE '%payment_intent%' AND v_src NOT LIKE '%wallet%'
      AND v_src NOT LIKE '%ledger%' AND v_src NOT LIKE '%mission%', NULL);
    r := r || public._qa_s13_ok('N4R3.B15c commit never consumes finance policy',
          v_src NOT LIKE '%finance_policies%' AND v_src NOT LIKE '%transaction_fee_bps%', NULL);

  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok('N4R3.FIXTURE runtime block completed without unhandled error', false, SQLERRM);
  END;

  -- ================= CLEANUP =================
  PERFORM set_config('request.jwt.claims','', true);
  PERFORM set_config('marche.rpc','1', true);
  DELETE FROM public.marche_order_items WHERE order_id IN
    (SELECT id FROM public.marche_orders WHERE buyer_user_id IN (v_buy, v_buy2, v_merch, v_other));
  DELETE FROM public.marche_orders WHERE buyer_user_id IN (v_buy, v_buy2, v_merch, v_other);
  PERFORM set_config('marche.rpc','', true);
  DELETE FROM public.marketplace_offers WHERE buyer_user_id IN (v_buy, v_buy2)
     OR merchant_user_id IN (v_merch, v_merch2);
  DELETE FROM public.listing_images WHERE listing_id IN (l_fix,l_neg,l_quote,l_one,l_s2,l_paused,l_legacy);
  DELETE FROM public.listing_metrics WHERE listing_id IN (l_fix,l_neg,l_quote,l_one,l_s2,l_paused,l_legacy);
  DELETE FROM public.marketplace_listings WHERE seller_id IN (v_buy,v_buy2,v_merch,v_merch2,v_other,v_adm);
  DELETE FROM public.account_bans WHERE user_id IN (v_buy,v_buy2,v_merch,v_merch2,v_other,v_adm);
  DELETE FROM public.merchant_stores WHERE owner_user_id IN (v_merch, v_merch2);
  DELETE FROM public.admin_users WHERE user_id = v_adm;
  DELETE FROM public.wallet_transactions WHERE from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (v_buy,v_buy2,v_merch,v_merch2,v_other,v_adm))
     OR to_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (v_buy,v_buy2,v_merch,v_merch2,v_other,v_adm));
  DELETE FROM public.wallets WHERE owner_user_id IN (v_buy,v_buy2,v_merch,v_merch2,v_other,v_adm);
  DELETE FROM auth.users WHERE id IN (v_buy,v_buy2,v_merch,v_merch2,v_other,v_adm);

  -- ================= SYSTEMIC =================
  SELECT count(*) INTO v_w1 FROM public.wallets;
  SELECT count(*) INTO v_wt1 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj1 FROM public.ledger_journals;
  SELECT count(*) INTO v_ms1 FROM public.missions;
  SELECT count(*) INTO v_pi1 FROM public.payment_intents;
  SELECT count(*) INTO v_lp1 FROM public.ledger_postings;
  SELECT count(*) INTO v_total1 FROM public.marketplace_listings;
  SELECT count(*) INTO v_none1 FROM public.marketplace_listings WHERE store_id IS NULL;
  SELECT count(*) INTO v_demo1 FROM public.v_marche_listing_truth WHERE is_demo;
  SELECT COALESCE(sum(quantity_reserved),0) INTO v_reserved1 FROM public.marketplace_listings;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;

  r := r || public._qa_s13_ok('N4R3.S1 zero wallet / ledger / mission / payment drift',
        v_w1=v_w0 AND v_wt1=v_wt0 AND v_lj1=v_lj0 AND v_ms1=v_ms0 AND v_pi1=v_pi0 AND v_lp1=v_lp0,
        format('%s/%s/%s/%s/%s/%s', v_w1-v_w0, v_wt1-v_wt0, v_lj1-v_lj0, v_ms1-v_ms0, v_pi1-v_pi0, v_lp1-v_lp0));
  r := r || public._qa_s13_ok('N4R3.S2 feature flags byte-identical', v_flags1 = v_flags0, NULL);
  r := r || public._qa_s13_ok('N4R3.S3 demo quarantine intact, nothing deleted',
        v_demo1 = v_demo0 AND v_demo1 > 0, v_demo1::text);
  r := r || public._qa_s13_ok('N4R3.S4 production listing population unchanged',
        v_total1 = v_total0, format('%s->%s', v_total0, v_total1));
  r := r || public._qa_s13_ok('N4R3.S4b storeless quarantine population unchanged',
        v_none1 = v_none0, format('%s->%s', v_none0, v_none1));
  r := r || public._qa_s13_ok('N4R3.S5 production reserved stock returns to its baseline',
        v_reserved1 = v_reserved0, format('%s->%s', v_reserved0, v_reserved1));
  SELECT count(*) INTO v_n FROM public.marketplace_listings WHERE title LIKE 'QA N43%';
  r := r || public._qa_s13_ok('N4R3.S6 zero listing fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_orders WHERE client_request_id LIKE 'qa-n43-%';
  r := r || public._qa_s13_ok('N4R3.S6b zero order fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_order_items i
    LEFT JOIN public.marche_orders o ON o.id = i.order_id WHERE o.id IS NULL;
  r := r || public._qa_s13_ok('N4R3.S6c zero orphan order lines', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE id IN (v_buy,v_buy2,v_merch,v_merch2,v_other,v_adm);
  r := r || public._qa_s13_ok('N4R3.S6d zero auth fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-n43-%';
  r := r || public._qa_s13_ok('N4R3.S6e zero store fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marketplace_listings
   WHERE quantity_reserved < 0 OR (quantity_in_stock IS NOT NULL AND quantity_reserved > quantity_in_stock);
  r := r || public._qa_s13_ok('N4R3.S7 global reservation invariant holds', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.v_marche_listing_truth
   WHERE is_orderable AND (store_id IS NULL OR kind <> 'merchant'::listing_kind);
  r := r || public._qa_s13_ok('N4R3.S8 R1.5 supply doctrine still holds', v_n = 0, v_n::text);
  r := r || public._qa_s13_ok('N4R3.S9 has_role still not executable by anon',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);

  RETURN public._qa_s13_summary(32, r);
END $function$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r3() FROM PUBLIC, anon, authenticated;