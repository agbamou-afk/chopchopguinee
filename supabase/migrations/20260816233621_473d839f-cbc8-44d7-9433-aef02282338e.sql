DROP TABLE IF EXISTS public._qa_shape;
DO $do$
DECLARE s text; v jsonb; t int; f int;
BEGIN
  FOREACH s IN ARRAY ARRAY['_qa_node3_repas_r5','_qa_node3_repas_r8_channel','_qa_node3_repas_r8_extra','_qa_node4_marche_r5'] LOOP
    EXECUTE format('SELECT to_jsonb(public.%I())', s) INTO v;
    IF jsonb_typeof(v) = 'array' THEN
      t := jsonb_array_length(v);
      SELECT count(*) INTO f FROM jsonb_array_elements(v) e WHERE (e->>'ok') = 'false';
    ELSE
      t := coalesce((v->>'total')::int, jsonb_array_length(coalesce(v->'results','[]'::jsonb)));
      f := coalesce((v->>'failed')::int, 0);
    END IF;
    UPDATE public._qa_board_run2 SET total = t, failed = f WHERE suite = s;
  END LOOP;
END $do$;
SELECT jsonb_build_object(
  'per_suite', (SELECT jsonb_object_agg(suite, jsonb_build_array(total, failed)) FROM public._qa_board_run2),
  'aggregate', (SELECT sum(total) FROM public._qa_board_run2),
  'failed_total', (SELECT sum(failed) FROM public._qa_board_run2)
) AS board;