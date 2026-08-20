DO $$
DECLARE fn text; txt text; out2 jsonb := '[]'::jsonb;
BEGIN
  DELETE FROM public._qa_s13_results WHERE part = 4105;
  FOREACH fn IN ARRAY ARRAY[
    '_qa_node3_repas_r7_tracking_receipt','_qa_node3_repas_r7_ext','_qa_node3_repas_r7_readtruth',
    '_qa_node3_repas_r7_semantics','_qa_node3_repas_r5','_qa_node4_marche_r7_obs_kind',
    '_qa_node1_bonbonna_matrix','_qa_node1_bonbonna_sweeper','_qa_node3_repas_r8_channel',
    '_qa_node3_repas_r8_extra','_qa_node4_marche_r5','_qa_node4_marche_r9','_qa_node4_marche_r9_backlink']
  LOOP
    BEGIN
      EXECUTE format('SELECT (public.%I())::text', fn) INTO txt;
      out2 := out2 || jsonb_build_object('fn', fn, 'out', left(txt, 600));
    EXCEPTION WHEN OTHERS THEN
      out2 := out2 || jsonb_build_object('fn', fn, 'error', SQLERRM);
    END;
  END LOOP;
  INSERT INTO public._qa_s13_results(part, result) VALUES (4105, out2);
END $$;