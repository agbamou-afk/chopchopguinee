DO $mig$
DECLARE s text; s0 text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO s
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r5_runtime';
  s0 := s;

  s := replace(s, 'v_item uuid; v_item2 uuid; v_item_off uuid;',
                  'v_item uuid; v_item2 uuid; v_item_off uuid; v_item_r2 uuid;');
  IF s = s0 THEN RAISE EXCEPTION 'patch1 failed'; END IF; s0 := s;

  s := replace(s,
    E'VALUES (v_resto,\'QA R5 Plat Indispo\',7000,false) RETURNING id INTO v_item_off;',
    E'VALUES (v_resto,\'QA R5 Plat Indispo\',7000,false) RETURNING id INTO v_item_off;\n    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)\n      VALUES (v_resto2,\'QA R5 Plat Unmapped\',100000,true) RETURNING id INTO v_item_r2;');
  IF s = s0 THEN RAISE EXCEPTION 'patch2 failed'; END IF; s0 := s;

  s := replace(s,
    E'v_q := public.repas_quote_preview(v_resto2,\n      jsonb_build_array(jsonb_build_object(\'menu_item_id\',v_item,\'qty\',1)),',
    E'v_q := public.repas_quote_preview(v_resto2,\n      jsonb_build_array(jsonb_build_object(\'menu_item_id\',v_item_r2,\'qty\',1)),');
  IF s = s0 THEN RAISE EXCEPTION 'patch3 failed'; END IF; s0 := s;

  s := replace(s,
    E'BEGIN PERFORM public.repas_order_create(v_resto2,\n        jsonb_build_array(jsonb_build_object(\'menu_item_id\',v_item,\'qty\',1)),',
    E'BEGIN PERFORM public.repas_order_create(v_resto2,\n        jsonb_build_array(jsonb_build_object(\'menu_item_id\',v_item_r2,\'qty\',1)),');
  IF s = s0 THEN RAISE EXCEPTION 'patch4 failed'; END IF; s0 := s;

  s := replace(s,
    E'v_err LIKE \'%DELIVERY_DISTANCE_UNVERIFIABLE%\' OR v_err LIKE \'%ITEM_WRONG_RESTAURANT%\', v_err);',
    E'v_err LIKE \'%DELIVERY_DISTANCE_UNVERIFIABLE%\', v_err);');
  IF s = s0 THEN RAISE EXCEPTION 'patch5 failed'; END IF;

  EXECUTE s;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r5_runtime() FROM PUBLIC, anon, authenticated;

DELETE FROM public._qa_s13_results WHERE part = 351;
INSERT INTO public._qa_s13_results(part, result)
VALUES (351, public._qa_node3_repas_r5_runtime());