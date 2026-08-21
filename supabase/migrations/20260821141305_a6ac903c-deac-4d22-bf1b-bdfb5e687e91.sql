DO $do$
DECLARE fn text; res jsonb; acc jsonb := '[]'::jsonb; t int; f int;
  names text[] := ARRAY[
    '_qa_node1_bonbonna_sweeper','_qa_node1_bonbonna_matrix',
    '_qa_node3_repas_r8_channel','_qa_node3_repas_r8_extra',
    '_qa_node4_marche_r5','_qa_node4_marche_r9','_qa_node4_marche_r11',
    '_qa_node4_marche_r12','_qa_node4_marche_r13','_qa_node4_marche_r14'];
BEGIN
  FOREACH fn IN ARRAY names LOOP
    EXECUTE format('SELECT public.%I()', fn) INTO res;
    IF jsonb_typeof(res) = 'array' THEN
      t := jsonb_array_length(res);
      SELECT count(*) INTO f FROM jsonb_array_elements(res) e WHERE (e->>'ok')::boolean IS NOT TRUE;
    ELSE
      t := (res->>'total')::int; f := (res->>'failed')::int;
    END IF;
    acc := acc || jsonb_build_object('suite', fn, 'total', t, 'failed', f);
  END LOOP;
  -- TABLE-returning suite
  SELECT count(*), count(*) FILTER (WHERE NOT ok) INTO t, f FROM public._qa_node3_repas_r5();
  acc := acc || jsonb_build_object('suite','_qa_node3_repas_r5','total',t,'failed',f);
  INSERT INTO public._qa_s13_results(part, result) VALUES (942, jsonb_build_object('board', acc));
END $do$;