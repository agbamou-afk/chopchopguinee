DO $do$
DECLARE src text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE proname='_qa_node4_marche_r14';

  src := replace(src,
$old$    PERFORM public.marche_listing_update(l_a, jsonb_build_object('price_gnf', 13000));
    PERFORM public.marche_listing_update(l_a, jsonb_build_object('price_gnf', 11000));$old$,
$new$    PERFORM public.marche_listing_update(l_a, jsonb_build_object('price_gnf', 13000));
    r := r || public._qa_s13_ok('N4R14.H0a the merchant price change actually persisted',
          (SELECT price_gnf FROM public.marketplace_listings WHERE id=l_a)=13000,
          (SELECT price_gnf::text FROM public.marketplace_listings WHERE id=l_a));
    v_res := public.marche_price_ingest_merchant_ask(l_a);
    r := r || public._qa_s13_ok('N4R14.H0b the 13 000 GNF ask is observable evidence',
          (v_res->>'ingested')::boolean OR v_res->>'reason'='ALREADY_OBSERVED', v_res::text);
    PERFORM public.marche_listing_update(l_a, jsonb_build_object('price_gnf', 11000));$new$);

  src := replace(src,
$old$    v_res := public.marche_listings_discover(NULL,NULL,NULL,NULL,5000,0);
    r := r || public._qa_s13_ok('N4R14.J1 discovery clamps a hostile page size',
          jsonb_array_length(COALESCE(v_res->'items', v_res)) <= 200,
          jsonb_array_length(COALESCE(v_res->'items', v_res))::text);
    v_res := public.marche_orders_for_buyer(100000,0);
    r := r || public._qa_s13_ok('N4R14.J2 a buyer order list stays bounded',
          jsonb_array_length(COALESCE(v_res->'items', v_res)) <= 500, NULL);$old$,
$new$    SELECT count(*) INTO v_n FROM public.marche_listings_discover(NULL,NULL,NULL,NULL,5000,0);
    r := r || public._qa_s13_ok('N4R14.J1 discovery clamps a hostile page size', v_n <= 200, v_n::text);
    v_res := public.marche_orders_for_buyer(100000,0);
    r := r || public._qa_s13_ok('N4R14.J2 a buyer order list stays bounded',
          COALESCE(jsonb_array_length(v_res->'items'), jsonb_array_length(v_res), 0) <= 500, NULL);$new$);

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r14() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS %s',
    quote_literal(src));
END
$do$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r14() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._qa_node4_marche_r14() FROM anon;
REVOKE ALL ON FUNCTION public._qa_node4_marche_r14() FROM authenticated;