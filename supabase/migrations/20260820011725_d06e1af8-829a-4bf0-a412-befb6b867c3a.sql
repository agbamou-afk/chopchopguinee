CREATE OR REPLACE FUNCTION public._qa_node4_marche_r9_backlink()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_buy uuid := gen_random_uuid(); v_mer uuid := gen_random_uuid();
  v_mer2 uuid := gen_random_uuid();
  v_drv uuid := gen_random_uuid(); v_drv2 uuid := gen_random_uuid();
  v_store uuid; v_store2 uuid; l_a uuid; v_res jsonb; v_j jsonb;
  v_o1 uuid; v_o2 uuid; v_mid uuid; v_n bigint; v_err text;
  v_ms0 bigint; v_rep0 bigint;
BEGIN
  SELECT count(*) INTO v_ms0 FROM public.missions;
  SELECT count(*) INTO v_rep0 FROM public.marche_reputation_events;

  BEGIN
    PERFORM public._qa_s13_user(v_buy,'n49k');
    PERFORM public._qa_s13_user(v_mer,'n49km');
    PERFORM public._qa_s13_user(v_mer2,'n49km2');
    PERFORM public._qa_s13_driver(v_drv,'n49kd',0);
    PERFORM public._qa_s13_driver(v_drv2,'n49kd2',0);

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status,
                                       latitude, longitude, address_label)
      VALUES (v_mer,'qa-n49k-'||substr(v_mer::text,1,8),'QA N49K Boutique','active','approved',
              9.5370,-13.6785,'QA Madina') RETURNING id INTO v_store;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status,
                                       latitude, longitude, address_label)
      VALUES (v_mer2,'qa-n49k2-'||substr(v_mer2::text,1,8),'QA N49K Boutique 2','active','approved',
              9.5371,-13.6786,'QA Madina 2') RETURNING id INTO v_store2;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_mer), true);
    l_a := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N49K Riz',
      'category','Alimentation','price_gnf',10000,'quantity_in_stock',40,'publish',true));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n49k-o1','delivery_address','QA Kaloum',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    v_o1 := (v_res->>'id')::uuid;
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n49k-o2','delivery_address','QA Kaloum',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    v_o2 := (v_res->>'id')::uuid;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_mer), true);
    PERFORM public.marche_merchant_transition(v_o1,'accept',NULL);
    PERFORM public.marche_merchant_transition(v_o1,'prepare',NULL);
    PERFORM public.marche_merchant_transition(v_o1,'ready',NULL);
    v_res := public.marche_dispatch_request(v_o1);
    v_mid := (v_res->>'mission_id')::uuid;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_mid);
    PERFORM public.marche_courier_transition(v_o1,'arrive_store');
    PERFORM public.marche_courier_transition(v_o1,'collect');
    PERFORM public.marche_courier_transition(v_o1,'start_delivery');
    PERFORM public.marche_courier_transition(v_o1,'deliver');
    PERFORM set_config('request.jwt.claims','', true);

    -- o2 is force-delivered WITHOUT any mission (pickup-like truth)
    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.marche_orders
       SET fulfillment_state='delivered', delivered_at=now(), fulfillment_updated_at=now()
     WHERE id = v_o2;
    PERFORM set_config('marche.rpc','', true);

    r := r || public._qa_s13_ok('N4R9.K0 canonical dispatch writes every backlink',
      (SELECT ref_market_order_id = v_o1 AND merchant_store_id = v_store
              AND type::text='marketplace_delivery' AND state::text='delivered'
              AND courier_id = v_drv FROM public.missions WHERE id=v_mid), NULL);
    r := r || public._qa_s13_ok('N4R9.K1 the order mission link itself is immutable',
      (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
        WHERE c.relname='marche_orders' AND NOT t.tgisinternal) > 0, NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.K2 canonical link exposes exactly store + delivery driver',
      jsonb_array_length(v_j->'subjects')=2
      AND (SELECT count(*) FROM jsonb_array_elements(v_j->'subjects') s
            WHERE s->>'subject_kind'='delivery_driver')=1, v_j::text);

    -- (a) the delivered mission points at ANOTHER order
    PERFORM set_config('request.jwt.claims','', true);
    UPDATE public.missions SET ref_market_order_id = v_o2 WHERE id = v_mid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.K3 a delivered mission backlinked to another order exposes no driver',
      jsonb_array_length(v_j->'subjects')=1
      AND (v_j->'subjects'->0->>'subject_kind')='merchant_store', v_j::text);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o1,
      'subject_kind','delivery_driver','overall_score',5));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.K4 submitting against a mismatched backlink fails closed',
      v_err IS NOT NULL AND v_err <> '', v_err);
    r := r || public._qa_s13_ok('N4R9.K5 no driver reputation was written on a mismatched link',
      (SELECT count(*) FROM public.marche_reputation_events
        WHERE transaction_id=v_o1 AND subject_kind='delivery_driver')=0, NULL);

    -- (b) right order backlink, WRONG store
    PERFORM set_config('request.jwt.claims','', true);
    UPDATE public.missions SET ref_market_order_id=v_o1, merchant_store_id=v_store2 WHERE id=v_mid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.K6 a mission carrying another store exposes no driver',
      jsonb_array_length(v_j->'subjects')=1, v_j::text);

    -- (c) right order + store, WRONG mission type
    PERFORM set_config('request.jwt.claims','', true);
    UPDATE public.missions SET merchant_store_id=v_store, type='package_delivery' WHERE id=v_mid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.K7 a non marketplace_delivery mission exposes no driver',
      jsonb_array_length(v_j->'subjects')=1, v_j::text);

    -- (d) canonical shape but NOT delivered
    PERFORM set_config('request.jwt.claims','', true);
    UPDATE public.missions SET type='marketplace_delivery', state='delivering' WHERE id=v_mid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.K8 an undelivered mission exposes no driver',
      jsonb_array_length(v_j->'subjects')=1, v_j::text);

    -- (e) canonical shape, delivered, but NO courier
    PERFORM set_config('request.jwt.claims','', true);
    UPDATE public.missions SET state='delivered', courier_id=NULL WHERE id=v_mid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.K9 a courierless delivered mission exposes no driver',
      jsonb_array_length(v_j->'subjects')=1, v_j::text);

    -- (f) delivered order with no mission at all
    v_j := public.marche_reputation_eligibility('merchant_order', v_o2);
    r := r || public._qa_s13_ok('N4R9.K10 a delivered order without any mission exposes no driver',
      (v_j->>'eligible')::boolean AND jsonb_array_length(v_j->'subjects')=1
      AND (v_j->'subjects'->0->>'subject_kind')='merchant_store', v_j::text);

    -- (g) restore every canonical backlink: the exact courier becomes rateable
    PERFORM set_config('request.jwt.claims','', true);
    UPDATE public.missions SET courier_id=v_drv WHERE id=v_mid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.K11 the canonical backlink restores driver eligibility',
      (SELECT count(*) FROM jsonb_array_elements(v_j->'subjects') s
        WHERE s->>'subject_kind'='delivery_driver')=1, v_j::text);
    r := r || public._qa_s13_ok('N4R9.K12 eligibility still never leaks courier or mission identity',
      v_j::text NOT LIKE '%'||v_drv::text||'%' AND v_j::text NOT LIKE '%'||v_mid::text||'%', NULL);
    v_res := public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o1,
      'subject_kind','delivery_driver','overall_score',4));
    r := r || public._qa_s13_ok('N4R9.K13 the rated subject is the exact canonical courier',
      v_res->>'status'='RECORDED'
      AND (SELECT subject_user_id FROM public.marche_reputation_events
            WHERE id=(v_res->>'event_id')::uuid) = v_drv, v_res::text);
    r := r || public._qa_s13_ok('N4R9.K14 no other driver received reputation from this order',
      (SELECT count(*) FROM public.marche_reputation_events WHERE subject_user_id=v_drv2)=0, NULL);
    r := r || public._qa_s13_ok('N4R9.K15 resolver enforces every canonical backlink column',
      (SELECT pg_get_functiondef(oid) FROM pg_proc
        WHERE oid='public._marche_reputation_resolve(text,uuid,uuid)'::regprocedure)
        LIKE '%ref_market_order_id = o.id%'
      AND (SELECT pg_get_functiondef(oid) FROM pg_proc
        WHERE oid='public._marche_reputation_resolve(text,uuid,uuid)'::regprocedure)
        LIKE '%merchant_store_id = o.merchant_store_id%'
      AND (SELECT pg_get_functiondef(oid) FROM pg_proc
        WHERE oid='public._marche_reputation_resolve(text,uuid,uuid)'::regprocedure)
        LIKE '%marketplace_delivery%', NULL);

    PERFORM set_config('request.jwt.claims','', true);
    RAISE EXCEPTION 'QA_N4R9K_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_N4R9K_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS_R9K_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims','', true);
  PERFORM set_config('marche.rpc','', true);
  SELECT count(*) INTO v_n FROM public.missions;
  r := r || public._qa_s13_ok('N4R9.K16 zero mission residue', v_n = v_ms0, format('%s->%s', v_ms0, v_n));
  SELECT count(*) INTO v_n FROM public.marche_reputation_events;
  r := r || public._qa_s13_ok('N4R9.K17 zero reputation residue', v_n = v_rep0, format('%s->%s', v_rep0, v_n));
  RETURN r;
END $function$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r9_backlink() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r9_backlink() TO service_role;