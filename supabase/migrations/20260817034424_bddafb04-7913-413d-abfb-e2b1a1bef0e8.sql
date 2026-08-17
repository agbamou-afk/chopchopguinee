DELETE FROM public._qa_board_run2;
DO $$
DECLARE f text; r jsonb; t int; bad int;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    '_qa_node4_marche_r1','_qa_node4_marche_r15','_qa_node4_marche_r2','_qa_node4_marche_r3',
    '_qa_node4_marche_r35','_qa_node4_marche_r4','_qa_node4_marche_r5','_qa_node4_marche_r6',
    '_qa_node4_marche_r65','_qa_node4_marche_r7'
  ] LOOP
    BEGIN
      EXECUTE format('SELECT to_jsonb(public.%I())', f) INTO r;
      IF jsonb_typeof(r) = 'array' THEN
        SELECT count(*), count(*) FILTER (WHERE (e->>'ok') IS DISTINCT FROM 'true')
          INTO t, bad FROM jsonb_array_elements(r) e;
      ELSIF r ? 'results' THEN
        SELECT count(*), count(*) FILTER (WHERE (e->>'ok') IS DISTINCT FROM 'true')
          INTO t, bad FROM jsonb_array_elements(r->'results') e;
      ELSE
        t := (r->>'total')::int; bad := (r->>'failed')::int;
      END IF;
      INSERT INTO public._qa_board_run2(suite,total,failed,err) VALUES (f,t,bad,NULL);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public._qa_board_run2(suite,total,failed,err) VALUES (f,NULL,NULL,SQLERRM);
    END;
  END LOOP;
END $$;