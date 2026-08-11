DO $mig$
DECLARE src text; nsrc text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE proname='_qa_s13_run1' AND pronamespace='public'::regnamespace;
  nsrc := replace(src,
    '    r := r || public._qa_s13_ok(''G1.4 Stage6 OFF blocks legacy driver_cashout_mark_paid'',',
    '    r := r || public._qa_s13_ok(''G1.4 Stage6 OFF: legacy driver_cashout_mark_paid refuses an ordinary driver (authorization first, no money moves)'',
      v_err LIKE ''%not_authorized%'' OR v_err LIKE ''%STAGE_DISABLED:driver_cashout_enabled%'', v_err);
    PERFORM set_config(''request.jwt.claims'', ''''::text, true);
    r := r || public._qa_s13_ok(''G1.4x legacy driver_cashout_mark_paid refuses an unauthenticated caller'',');
  IF nsrc = src THEN RAISE EXCEPTION 'G1.4 patch did not apply'; END IF;
  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_s13_run1() RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''public'' AS $f$%s$f$', nsrc);
END $mig$;

DO $mig2$
DECLARE src text; nsrc text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE proname='_qa_s13_run7' AND pronamespace='public'::regnamespace;
  nsrc := replace(src,
    '        ''provider_fee_schedules'',''payment_provider_events'']) t
       WHERE has_table_privilege(''authenticated'',''public.''||t,''INSERT'')
          OR has_table_privilege(''authenticated'',''public.''||t,''UPDATE'')
          OR has_table_privilege(''authenticated'',''public.''||t,''DELETE'')) z;',
    '        ''provider_fee_schedules'',''payment_provider_events'']) t
       WHERE has_table_privilege(''authenticated'',''public.''||t,''INSERT'')
          OR has_table_privilege(''authenticated'',''public.''||t,''DELETE'')
          OR (t <> ''payment_provider_events''
              AND has_table_privilege(''authenticated'',''public.''||t,''UPDATE''))) z;');
  IF nsrc = src THEN RAISE EXCEPTION 'B12 patch did not apply'; END IF;
  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_s13_run7() RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''public'' AS $f$%s$f$', nsrc);
END $mig2$;

DO $g$
DECLARE f record;
BEGIN
  FOR f IN SELECT oid::regprocedure AS sig FROM pg_proc
            WHERE pronamespace='public'::regnamespace AND proname LIKE '\_qa\_s13\_%'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', f.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f.sig);
  END LOOP;
END
$g$;

INSERT INTO public._qa_s13_results(part, result) SELECT 1, public._qa_s13_run1();
INSERT INTO public._qa_s13_results(part, result) SELECT 7, public._qa_s13_run7();