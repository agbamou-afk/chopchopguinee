DO $mig$
DECLARE s text; s0 text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO s
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r5_runtime';
  s0 := s;

  s := replace(s, 'v_item_off uuid; v_item_r2 uuid;', 'v_item_off uuid; v_item_r2 uuid; v_item_r3 uuid;');
  IF s = s0 THEN RAISE EXCEPTION 'p1'; END IF; s0 := s;

  s := replace(s,
    E'VALUES (v_resto2,\'QA R5 Plat Unmapped\',100000,true) RETURNING id INTO v_item_r2;',
    E'VALUES (v_resto2,\'QA R5 Plat Unmapped\',100000,true) RETURNING id INTO v_item_r2;\n    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)\n      VALUES (v_resto3,\'QA R5 Plat Ferme\',100000,true) RETURNING id INTO v_item_r3;');
  IF s = s0 THEN RAISE EXCEPTION 'p2'; END IF; s0 := s;

  s := replace(s,
    E'v_q := public.repas_quote_preview(v_resto3,\n      jsonb_build_array(jsonb_build_object(\'menu_item_id\',v_item,\'qty\',1)),',
    E'v_q := public.repas_quote_preview(v_resto3,\n      jsonb_build_array(jsonb_build_object(\'menu_item_id\',v_item_r3,\'qty\',1)),');
  IF s = s0 THEN RAISE EXCEPTION 'p3'; END IF; s0 := s;

  s := replace(s,
    E'v_q := public.repas_quote_preview(v_resto3,\n        jsonb_build_array(jsonb_build_object(\'menu_item_id\',v_item,\'qty\',1)), \'delivery\', 9.51, -13.70);',
    E'v_q := public.repas_quote_preview(v_resto3,\n        jsonb_build_array(jsonb_build_object(\'menu_item_id\',v_item_r3,\'qty\',1)), \'delivery\', 9.51, -13.70);');
  IF s = s0 THEN RAISE EXCEPTION 'p4'; END IF;

  EXECUTE s;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r5_runtime() FROM PUBLIC, anon, authenticated;

DELETE FROM public._qa_s13_results WHERE part = 351;
INSERT INTO public._qa_s13_results(part, result)
VALUES (351, public._qa_node3_repas_r5_runtime());