DO $do$
DECLARE v_def text;
BEGIN
  v_def := pg_get_functiondef('public._qa_s4_run()'::regprocedure);
  v_def := replace(v_def,
    'AND entity_id IN (SELECT id FROM public.cash_order_runtime WHERE source_id IN (fo1,fo2,fo3,fo4,fo5,fo6))',
    'AND target_id IN (SELECT id::text FROM public.cash_order_runtime WHERE source_id IN (fo1,fo2,fo3,fo4,fo5,fo6))');
  EXECUTE v_def;
END $do$;