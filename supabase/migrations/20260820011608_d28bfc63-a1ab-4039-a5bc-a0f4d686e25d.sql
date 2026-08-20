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
  v_o1 uuid; v_o2 uuid; v_mid uuid; v_decoy uuid; v_n bigint; v_err text;
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

    r := r || public._qa_s13_ok('N4R9.K0 canonical dispatch writes every backlink',
      (SELECT ref_market_order_id = v_o1 AND merchant_store_id = v_store
              AND type::text='marketplace_delivery' AND state::text='delivered'
              AND courier_id = v_drv FROM public.missions WHERE id=v_mid), NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.K1 canonical link exposes exactly store + delivery driver',
      jsonb_array_length(v_j->'subjects')=2
      AND (SELECT count(*) FROM jsonb_array_elements(v_j->'subjects') s
            WHERE s->>'subject_kind'='delivery_driver')=1, v_j::text);

    PERFORM set_config('request.jwt.claims','', true);
    PERFORM set_config('marche.rpc','1', true);
    INSERT INTO public.missions(type,state,customer_id,merchant_id,merchant_store_id,
      pickup_address,dropoff_address,payload_summary,estimated_earning_gnf,
      ref_market_order_id,courier_id)
    VALUES ('marketplace_delivery','delivered',v_buy,v_mer,v_store,'QA Madina','QA Kaloum',
            'QA decoy foreign order',0,v_o2,v_drv2) RETURNING id INTO v_decoy;
    UPDATE public.marche_orders SET mission_id=v_decoy WHERE id=v_o1;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.K2 a delivered mission of another order exposes no driver',
      jsonb_array_length(v_j->'subjects')=1
      AND (v_j->'subjects'->0->>'subject_kind')='merchant_store', v_j::text);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o1,
      'subject_kind','delivery_driver','overall_score',5));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.K3 submitting against a foreign-order link fails closed',
      v_err IS NOT NULL AND v_err <> '', v_err);
    r := r || public._qa_s13_ok('N4R9.K4 no driver reputation was written on a mismatched link',
      (SELECT count(*) FROM public.marche_reputation_events
        WHERE transaction_id=v_o1 AND subject_kind='delivery_driver')=0, NULL);

    PERFORM set_config('request.jwt.claims','', true);
    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.missions SET ref_market_order_id=v_o1, merchant_store_id=v_store2 WHERE id=v_decoy;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.K5 a mission of another store exposes no driver',
      jsonb_array_length(v_j->'subjects')=1, v_j::text);

    PERFORM set_config('request.jwt.claims','', true);
    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.missions SET merchant_store_id=v_store, type='package_delivery' WHERE id=v_decoy;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.K6 a non marketplace_delivery mission exposes no driver',
      jsonb_array_length(v_j->'subjects')=1, v_j::text);

    PERFORM set_config('request.jwt.claims','', true);
    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.missions SET type='marketplace_delivery', state='delivering' WHERE id=v_decoy;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.K7 an undelivered mission exposes no driver',
      jsonb_array_length(v_j->'subjects')=1, v_j::text);

    PERFORM set_config('request.jwt.claims','', true);
    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.missions SET state='delivered', courier_id=NULL WHERE id=v_decoy;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.K8 a courierless delivered mission exposes no driver',
      jsonb_array_length(v_j->'subjects')=1, v_j::text);

    PERFORM set_config('request.jwt.claims','', true);
    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.marche_orders SET mission_id=NULL WHERE id=v_o1;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.K9 no mission means no delivery-driver subject',
      jsonb_array_length(v_j->'subjects')=1, v_j::text);

    PERFORM set_config('request.jwt.claims','', true);
    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.marche_orders SET mission_id=v_mid WHERE id=v_o1;
    PERFORM set_config('marche.rpc','', true);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.K10 the canonical backlink restores driver eligibility',
      (SELECT count(*) FROM jsonb_array_elements(v_j->'subjects') s
        WHERE s->>'subject_kind'='delivery_driver')=1, v_j::text);
    r := r || public._qa_s13_ok('N4R9.K11 eligibility still never leaks the courier id',
      v_j::text NOT LIKE '%'||v_drv::text||'%' AND v_j::text NOT LIKE '%'||v_mid::text||'%', NULL);
    v_res := public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o1,
      'subject_kind','delivery_driver','overall_score',4));
    r := r || public._qa_s13_ok('N4R9.K12 the rated subject is the exact canonical courier',
      v_res->>'status'='RECORDED'
      AND (SELECT subject_user_id FROM public.marche_reputation_events
            WHERE id=(v_res->>'event_id')::uuid) = v_drv, v_res::text);
    r := r || public._qa_s13_ok('N4R9.K13 the decoy courier received no reputation',
      (SELECT count(*) FROM public.marche_reputation_events WHERE subject_user_id=v_drv2)=0, NULL);
    r := r || public._qa_s13_ok('N4R9.K14 resolver reads every canonical backlink column',
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
  r := r || public._qa_s13_ok('N4R9.K15 zero mission residue', v_n = v_ms0, format('%s->%s', v_ms0, v_n));
  SELECT count(*) INTO v_n FROM public.marche_reputation_events;
  r := r || public._qa_s13_ok('N4R9.K16 zero reputation residue', v_n = v_rep0, format('%s->%s', v_rep0, v_n));
  RETURN r;
END $function$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r9_backlink() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r9_backlink() TO service_role;