DO $do$
DECLARE v_def text;
BEGIN
  v_def := pg_get_functiondef('public._qa_s4_run()'::regprocedure);
  v_def := replace(v_def,
    'public.wallet_internal_transfer(uuid,uuid,bigint,text,text,jsonb)',
    'public.wallet_internal_transfer(uuid,text,uuid,text,bigint,text,text)');
  v_def := replace(v_def, E'    ''n/a'',\n', E'    has_function_privilege(''anon'',''public.ride_dispatch(uuid)'',''EXECUTE''),\n');
  EXECUTE v_def;
END $do$;