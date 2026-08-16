DO $do$
DECLARE t int; f int;
BEGIN
  CREATE TEMP TABLE _r5 AS SELECT * FROM public._qa_node3_repas_r5();
  SELECT count(*) INTO t FROM _r5;
  EXECUTE 'SELECT count(*) FROM _r5 WHERE NOT (' ||
    (SELECT string_agg(quote_ident(column_name),' ') FROM information_schema.columns
      WHERE table_name='_r5' AND data_type='boolean' LIMIT 1) || ')' INTO f;
  UPDATE public._qa_board_run2 SET total=t, failed=f WHERE suite='_qa_node3_repas_r5';
  RAISE NOTICE 'r5 total=% failed=%', t, f;
END $do$;
SELECT (SELECT sum(total) FROM public._qa_board_run2) aggregate,
       (SELECT sum(failed) FROM public._qa_board_run2) failed_total,
       (SELECT jsonb_object_agg(suite, total) FROM public._qa_board_run2 WHERE suite LIKE '%repas_r5') r5;