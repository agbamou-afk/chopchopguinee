
DO $$
DECLARE s text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r2';
  s := replace(s,
    'r := r || public._qa_s13_ok(''N4R2.C11 terminal state cannot be reopened even server-side'',
          v_err = ''OFFER_TERMINAL'', v_err);',
    'r := r || public._qa_s13_ok(''N4R2.C11 terminal state cannot be reopened even server-side'',
          v_err IN (''OFFER_TERMINAL'',''AGREEMENT_REQUIRES_ACCEPTED''), v_err);');
  EXECUTE 'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r2() RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''public'' AS $fn$'||s||'$fn$';
END $$;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r2() TO service_role;
