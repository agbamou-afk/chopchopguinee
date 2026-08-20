DO $$
DECLARE fn text; j jsonb; nf int; nt int; out2 jsonb := '[]'::jsonb;
BEGIN
  DELETE FROM public._qa_s13_results WHERE part = 4106;
  PERFORM public._qa_node3_repas_r8_discovery();
  FOREACH fn IN ARRAY ARRAY['_qa_node3_repas_r7_ext','_qa_node3_repas_r7_readtruth','_qa_node3_repas_r7_semantics'] LOOP
    BEGIN
      EXECUTE format('SELECT to_jsonb(public.%I())', fn) INTO j;
      out2 := out2 || jsonb_build_object('fn', fn, 'total', j->'total', 'failed', j->'failed');
    EXCEPTION WHEN OTHERS THEN
      out2 := out2 || jsonb_build_object('fn', fn, 'error', SQLERRM);
    END;
  END LOOP;
  FOREACH fn IN ARRAY ARRAY['_qa_node1_bonbonna_matrix','_qa_node1_bonbonna_sweeper','_qa_node3_repas_r8_channel',
                            '_qa_node3_repas_r8_extra','_qa_node4_marche_r5','_qa_node4_marche_r9','_qa_node4_marche_r9_backlink'] LOOP
    BEGIN
      EXECUTE format('SELECT to_jsonb(public.%I())', fn) INTO j;
      IF jsonb_typeof(j) = 'array' THEN
        SELECT count(*), count(*) FILTER (WHERE (e->>'ok')::boolean IS NOT TRUE)
          INTO nt, nf FROM jsonb_array_elements(j) e;
        out2 := out2 || jsonb_build_object('fn', fn, 'total', nt, 'failed', nf,
          'failing', (SELECT jsonb_agg(e->>'label') FROM jsonb_array_elements(j) e WHERE (e->>'ok')::boolean IS NOT TRUE));
      ELSE
        out2 := out2 || jsonb_build_object('fn', fn, 'total', j->'total', 'failed', j->'failed');
      END IF;
    EXCEPTION WHEN OTHERS THEN
      out2 := out2 || jsonb_build_object('fn', fn, 'error', SQLERRM);
    END;
  END LOOP;
  INSERT INTO public._qa_s13_results(part, result) VALUES (4106, out2);
END $$;