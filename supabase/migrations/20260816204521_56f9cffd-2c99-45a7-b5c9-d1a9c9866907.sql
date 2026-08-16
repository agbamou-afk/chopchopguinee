CREATE OR REPLACE FUNCTION public.marche_fulfillment_observation_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
BEGIN
  IF COALESCE(current_setting('marche.fulfillment_derive', true),'') = '1' THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'FULFILLMENT_OBSERVATION_DERIVED_ONLY';
END $fn$;

CREATE OR REPLACE FUNCTION public.marche_fulfillment_recompute_observations(p_order_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  p public.marche_fulfillment_profiles;
  m record; v_start timestamptz; v_end timestamptz; v_n int := 0;
BEGIN
  SELECT * INTO p FROM public.marche_fulfillment_profiles WHERE order_id = p_order_id;
  IF p.order_id IS NULL THEN RETURN 0; END IF;

  FOR m IN
    SELECT * FROM (VALUES
      ('COMMIT_TO_MERCHANT_ACCEPTED','ORDER_COMMITTED','MERCHANT_ACCEPTED'),
      ('MERCHANT_ACCEPTED_TO_READY','MERCHANT_ACCEPTED','MERCHANT_READY'),
      ('COURIER_ENGAGED_TO_STORE_ARRIVAL','COURIER_ENGAGED','COURIER_AT_STORE'),
      ('SHOPPING_START_TO_COMPLETE','SHOPPING_STARTED','SHOPPING_COMPLETED'),
      ('PICKUP_TO_DELIVERED','PICKED_UP','DELIVERED'),
      ('COMMIT_TO_DELIVERED','ORDER_COMMITTED','DELIVERED')
    ) AS v(metric, s_evt, e_evt)
  LOOP
    SELECT min(occurred_at) INTO v_start FROM public.marche_fulfillment_events
      WHERE order_id = p_order_id AND event_type = m.s_evt;
    SELECT min(occurred_at) INTO v_end FROM public.marche_fulfillment_events
      WHERE order_id = p_order_id AND event_type = m.e_evt;
    CONTINUE WHEN v_start IS NULL OR v_end IS NULL OR v_end < v_start;

    PERFORM set_config('marche.fulfillment_derive','1', true);
    INSERT INTO public.marche_fulfillment_observations(
      order_id, metric_name, duration_seconds, start_event_at, end_event_at,
      merchant_store_id, fulfillment_mode, distance_m, distance_bucket,
      basket_units, distinct_products, basket_bucket, observed_at)
    VALUES (p_order_id, m.metric, floor(EXTRACT(EPOCH FROM (v_end - v_start)))::bigint, v_start, v_end,
      p.merchant_store_id, p.fulfillment_mode, p.distance_m, public.marche_distance_bucket(p.distance_m),
      p.basket_units, p.distinct_products, public.marche_basket_bucket(p.basket_units, p.distinct_products),
      v_end)
    ON CONFLICT (order_id, metric_name) DO NOTHING;
    PERFORM set_config('marche.fulfillment_derive','', true);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $fn$;

DO $diag$
DECLARE
  v_buy uuid := gen_random_uuid(); v_merch uuid := gen_random_uuid();
  v_store uuid; l_a uuid; v_o uuid; v_res jsonb; v_now timestamptz := now();
  v_out jsonb;
BEGIN
  PERFORM public._qa_s13_user(v_buy,'d435b'); PERFORM public._qa_s13_user(v_merch,'d435m');
  INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status, latitude, longitude)
    VALUES (v_merch,'diag-n435-'||substr(v_merch::text,1,8),'DIAG N435','active','approved',9.5370,-13.6785)
    RETURNING id INTO v_store;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
  l_a := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','DIAG N435 Riz',
    'category','Alimentation','price_gnf',10000,'quantity_in_stock',50,'publish',true));
  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
  v_res := public.marche_order_commit(jsonb_build_object(
    'client_request_id','diag-n435-0001',
    'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
  v_o := (v_res->>'id')::uuid;
  PERFORM public.marche_fulfillment_event_append(v_o,'PICKED_UP', v_now + interval '1500 seconds','diag', v_o::text,'p','courier');
  PERFORM public.marche_fulfillment_event_append(v_o,'DELIVERED', v_now + interval '2400 seconds','diag', v_o::text,'d','courier');

  SELECT jsonb_build_object(
    'events', (SELECT jsonb_agg(jsonb_build_object('t',event_type,'at',occurred_at) ORDER BY occurred_at)
                 FROM public.marche_fulfillment_events WHERE order_id=v_o),
    'obs', (SELECT jsonb_agg(jsonb_build_object('m',metric_name,'d',duration_seconds,'s',start_event_at,'e',end_event_at))
                 FROM public.marche_fulfillment_observations WHERE order_id=v_o),
    'order_created_at', (SELECT created_at FROM public.marche_orders WHERE id=v_o),
    'now', v_now
  ) INTO v_out;
  INSERT INTO public._qa_s13_results(part, result) VALUES (9435, v_out);

  PERFORM set_config('request.jwt.claims','', true);
  PERFORM set_config('marche.rpc','1', true);
  PERFORM set_config('marche.fulfillment_derive','1', true);
  DELETE FROM public.marche_order_items WHERE order_id = v_o;
  DELETE FROM public.marche_orders WHERE id = v_o;
  PERFORM set_config('marche.rpc','', true);
  PERFORM set_config('marche.fulfillment_derive','', true);
  DELETE FROM public.listing_images WHERE listing_id = l_a;
  DELETE FROM public.listing_metrics WHERE listing_id = l_a;
  DELETE FROM public.marketplace_listings WHERE id = l_a;
  DELETE FROM public.merchant_stores WHERE id = v_store;
  DELETE FROM public.account_bans WHERE user_id IN (v_buy,v_merch);
  DELETE FROM public.wallet_transactions WHERE from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch))
     OR to_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch));
  DELETE FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch);
  DELETE FROM auth.users WHERE id IN (v_buy,v_merch);
END $diag$;