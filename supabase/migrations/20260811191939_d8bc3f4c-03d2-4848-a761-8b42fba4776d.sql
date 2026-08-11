DO $mig$
DECLARE s text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc
   WHERE proname = '_qa_s13_run5' AND pronamespace = 'public'::regnamespace;

  IF strpos(s, 'v_t0 := clock_timestamp();') = 0 THEN
    RAISE EXCEPTION 'baseline marker not found';
  END IF;

  s := replace(s, 'v_t0 := clock_timestamp();',
                  'v_t0 := now() - interval ''1 second'';');

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public._qa_s13_run5() RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS %L',
    s);
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_s13_run5() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._qa_s13_run5() FROM anon;
REVOKE ALL ON FUNCTION public._qa_s13_run5() FROM authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s13_run5() TO service_role;

SELECT public._qa_s13_run5();