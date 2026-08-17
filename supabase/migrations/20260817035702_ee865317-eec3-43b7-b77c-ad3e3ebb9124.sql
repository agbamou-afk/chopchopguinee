DO $$
DECLARE src text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO src FROM pg_proc WHERE proname='_qa_node4_marche_r8';
  src := replace(src, 'normalized_unit_price_gnf, canonical_base_unit, comparable, zone_commune',
                      'normalized_unit_price_gnf, canonical_base_unit');
  src := replace(src, 'INTO v_price, v_err, v_j, v_res', 'INTO v_price, v_err');
  EXECUTE src;
END $$;

DELETE FROM public._qa_board_run2;
DO $$
DECLARE r jsonb;
BEGIN
  r := public._qa_node4_marche_r8();
  INSERT INTO public._qa_board_run2(suite,total,failed,err)
  VALUES ('_qa_node4_marche_r8', (r->>'total')::int, (r->>'failed')::int, left((r->'failures')::text, 8000));
EXCEPTION WHEN OTHERS THEN
  INSERT INTO public._qa_board_run2(suite,total,failed,err) VALUES ('_qa_node4_marche_r8',NULL,NULL,SQLERRM);
END $$;