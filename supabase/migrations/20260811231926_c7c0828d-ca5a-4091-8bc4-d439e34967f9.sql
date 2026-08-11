DO $mig$
DECLARE src text; nsrc text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE proname='_qa_s13_run1' AND pronamespace='public'::regnamespace;
  nsrc := replace(src,
    '    PERFORM set_config(''request.jwt.claims'', ''''::text, true);
    r := r || public._qa_s13_ok(''G1.4x legacy driver_cashout_mark_paid refuses an unauthenticated caller'',
      v_err LIKE ''%STAGE_DISABLED:driver_cashout_enabled%'', v_err);',
    '    PERFORM set_config(''request.jwt.claims'', ''''::text, true);
    BEGIN PERFORM public.driver_cashout_mark_paid(gen_random_uuid(),''QA-REF'',''qa''); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok(''G1.4x legacy driver_cashout_mark_paid refuses an unauthenticated caller'',
      v_err <> ''NO_ERROR'', v_err);');
  IF nsrc = src THEN RAISE EXCEPTION 'G1.4x patch did not apply'; END IF;
  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_s13_run1() RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''public'' AS $f$%s$f$', nsrc);
END $mig$;

REVOKE ALL ON FUNCTION public._qa_s13_run1() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s13_run1() TO service_role;

INSERT INTO public._qa_s13_results(part, result) SELECT 1, public._qa_s13_run1();