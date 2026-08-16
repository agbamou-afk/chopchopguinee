TRUNCATE public._qa_board_run2;
DO $do$
DECLARE s text; v jsonb; t int; f int;
BEGIN
  FOREACH s IN ARRAY ARRAY[
    '_qa_node0_course','_qa_node1_bonbonna_full','_qa_node2_taxi_full',
    '_qa_node3_repas_r1_r4','_qa_node3_repas_pickup','_qa_node3_repas_r5_runtime',
    '_qa_node3_repas_r6_custody','_qa_node3_repas_r7_tracking_receipt','_qa_node3_repas_r7_semantics',
    '_qa_node3_repas_r7_readtruth','_qa_node3_repas_r7_ext','_qa_node3_repas_r8_discovery_truth',
    '_qa_node3_repas_r8_discovery','_qa_node3_repas_r8_channel','_qa_node3_repas_r8_extra',
    '_qa_node3_repas_r9_recovery_flows','_qa_node3_repas_r10_operations','_qa_node3_repas_r11_conakry_hardening',
    '_qa_s13_run1','_qa_s13_run2','_qa_s13_run3','_qa_s13_run4','_qa_s13_run5','_qa_s13_run6','_qa_s13_run7',
    '_qa_node4_marche_r1','_qa_node4_marche_r15','_qa_node4_marche_r2','_qa_node4_marche_r3',
    '_qa_node4_marche_r35','_qa_node4_marche_r4','_qa_node4_marche_r5','_qa_node4_marche_r6'
  ] LOOP
    BEGIN
      EXECUTE format('SELECT to_jsonb(public.%I())', s) INTO v;
      IF jsonb_typeof(v) = 'array' THEN
        t := jsonb_array_length(v);
        SELECT count(*) INTO f FROM jsonb_array_elements(v) e WHERE (e->>'ok') = 'false';
      ELSE
        t := coalesce((v->>'total')::int, jsonb_array_length(coalesce(v->'results','[]'::jsonb)));
        f := coalesce((v->>'failed')::int, 0);
      END IF;
      INSERT INTO public._qa_board_run2 VALUES (s, t, f, NULL);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public._qa_board_run2 VALUES (s, NULL, NULL, SQLERRM);
    END;
  END LOOP;
END $do$;
DO $do$
DECLARE t int; f int;
BEGIN
  CREATE TEMP TABLE _r5b AS SELECT * FROM public._qa_node3_repas_r5();
  SELECT count(*) INTO t FROM _r5b;
  EXECUTE 'SELECT count(*) FROM _r5b WHERE NOT (' ||
    (SELECT string_agg(quote_ident(column_name),' ') FROM information_schema.columns
      WHERE table_name='_r5b' AND data_type='boolean' LIMIT 1) || ')' INTO f;
  INSERT INTO public._qa_board_run2 VALUES ('_qa_node3_repas_r5', t, f, NULL);
END $do$;
SELECT jsonb_build_object(
  'per_suite', (SELECT jsonb_object_agg(suite, jsonb_build_array(total, failed)) FROM public._qa_board_run2),
  'suites', (SELECT count(*) FROM public._qa_board_run2),
  'aggregate', (SELECT sum(total) FROM public._qa_board_run2),
  'failed_total', (SELECT sum(failed) FROM public._qa_board_run2),
  'errored', (SELECT jsonb_object_agg(suite, err) FROM public._qa_board_run2 WHERE err IS NOT NULL)
) AS board;