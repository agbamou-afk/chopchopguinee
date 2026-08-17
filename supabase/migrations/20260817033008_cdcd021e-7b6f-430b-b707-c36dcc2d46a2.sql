DO $$
DECLARE f text; res jsonb; arr jsonb; tot int; fl int;
BEGIN
  DELETE FROM public._qa_board_run2;
  FOREACH f IN ARRAY ARRAY[
    '_qa_s13_run4','_qa_s13_run5','_qa_s13_run6','_qa_s13_run7',
    '_qa_node4_marche_r1','_qa_node4_marche_r15','_qa_node4_marche_r2','_qa_node4_marche_r3',
    '_qa_node4_marche_r4','_qa_node4_marche_r6','_qa_node4_marche_r65','_qa_node4_marche_r7'
  ] LOOP
    BEGIN
      EXECUTE format('SELECT public.%I()', f) INTO res;
      IF jsonb_typeof(res) = 'array' THEN arr := res;
      ELSIF jsonb_typeof(res->'results') = 'array' THEN arr := res->'results';
      ELSE arr := NULL; END IF;
      IF arr IS NULL THEN
        tot := COALESCE((res->>'total')::int, 0);
        fl  := COALESCE((res->>'failed')::int, 0);
      ELSE
        SELECT count(*), count(*) FILTER (WHERE (e->>'ok') IS DISTINCT FROM 'true')
          INTO tot, fl FROM jsonb_array_elements(arr) e;
      END IF;
      INSERT INTO public._qa_board_run2(suite,total,failed,err)
      VALUES (f, tot, fl, CASE WHEN fl>0 THEN left(res::text, 2000) ELSE NULL END);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public._qa_board_run2(suite,total,failed,err) VALUES (f, 0, -1, SQLERRM);
    END;
  END LOOP;
END $$;