DO $do$
DECLARE fn text; res jsonb; acc jsonb := '[]'::jsonb;
  names text[] := ARRAY[
    '_qa_node4_marche_r1','_qa_node4_marche_r15','_qa_node4_marche_r2','_qa_node4_marche_r3',
    '_qa_node4_marche_r35','_qa_node4_marche_r4','_qa_node4_marche_r5','_qa_node4_marche_r6',
    '_qa_node4_marche_r65','_qa_node4_marche_r7','_qa_node4_marche_r8','_qa_node4_marche_r9',
    '_qa_node4_marche_r10','_qa_node4_marche_r11','_qa_node4_marche_r12','_qa_node4_marche_r13',
    '_qa_node4_marche_r14'];
BEGIN
  FOREACH fn IN ARRAY names LOOP
    EXECUTE format('SELECT to_jsonb(t) FROM public.%I() t', fn) INTO res;
    acc := acc || jsonb_build_object('suite', fn, 'total', res->'total', 'failed', res->'failed',
                                     'failures', COALESCE(res->'failures','[]'::jsonb));
  END LOOP;
  INSERT INTO public._qa_s13_results(part, result) VALUES (941, jsonb_build_object('board', acc));
END $do$;