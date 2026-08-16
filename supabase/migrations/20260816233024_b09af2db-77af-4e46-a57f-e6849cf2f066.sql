DELETE FROM public._qa_board_run WHERE suite IN ('_qa_node3_repas_r7_semantics','_qa_node3_repas_r7_readtruth','_qa_node3_repas_r7_ext');
DO $do$
DECLARE s text; v jsonb;
BEGIN
  FOREACH s IN ARRAY ARRAY['_qa_node3_repas_r7_semantics','_qa_node3_repas_r7_readtruth','_qa_node3_repas_r7_ext'] LOOP
    BEGIN
      EXECUTE format('SELECT to_jsonb(public.%I())', s) INTO v;
      INSERT INTO public._qa_board_run VALUES (s, v, NULL);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public._qa_board_run VALUES (s, NULL, SQLERRM);
    END;
  END LOOP;
END $do$;
SELECT suite, err, result->>'passed' passed, result->>'failed' failed FROM public._qa_board_run WHERE suite LIKE '%r7%';