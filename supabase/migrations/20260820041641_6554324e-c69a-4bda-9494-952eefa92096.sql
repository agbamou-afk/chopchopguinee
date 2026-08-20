DO $$
DECLARE f text; x jsonb; agg jsonb := '[]'::jsonb; t int; fl int;
BEGIN
  FOREACH f IN ARRAY ARRAY['_qa_node4_marche_r1','_qa_node4_marche_r15','_qa_node4_marche_r2',
    '_qa_node4_marche_r3','_qa_node4_marche_r35','_qa_node4_marche_r4','_qa_node4_marche_r5',
    '_qa_node4_marche_r6','_qa_node4_marche_r65','_qa_node4_marche_r7','_qa_node4_marche_r8',
    '_qa_node4_marche_r9','_qa_node4_marche_r9_backlink','_qa_node4_marche_r10']
  LOOP
    BEGIN
      EXECUTE format('SELECT public.%I()', f) INTO x;
      IF jsonb_typeof(x) = 'array' THEN
        t := jsonb_array_length(x);
        SELECT count(*) INTO fl FROM jsonb_array_elements(x) e WHERE (e->>'ok')::boolean IS NOT TRUE;
      ELSE
        t := (x->>'total')::int; fl := (x->>'failed')::int;
      END IF;
      agg := agg || jsonb_build_object('suite',f,'total',t,'failed',fl);
    EXCEPTION WHEN OTHERS THEN
      agg := agg || jsonb_build_object('suite',f,'total',0,'failed',1,'error',SQLERRM);
    END;
  END LOOP;
  DELETE FROM public._qa_s13_results WHERE part = 4202;
  INSERT INTO public._qa_s13_results(part, result) VALUES (4202, agg);
END $$;