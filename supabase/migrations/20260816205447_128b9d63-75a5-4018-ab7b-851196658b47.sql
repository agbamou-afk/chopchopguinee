DO $fix$
DECLARE s text; n text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r35';
  n := replace(s,
    'pg_get_triggerdef(oid) LIKE ''%BEFORE INSERT OR UPDATE OR DELETE%''',
    '(tgtype & 4) > 0 AND (tgtype & 8) > 0 AND (tgtype & 16) > 0');
  IF n = s THEN RAISE EXCEPTION 'PATCH_TARGET_NOT_FOUND'; END IF;
  EXECUTE 'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r35() RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''public'' AS '
          || quote_literal(n);
END $fix$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r35() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r35() TO service_role;

DELETE FROM public._qa_s13_results WHERE part IN (435, 436);
INSERT INTO public._qa_s13_results(part, result) SELECT 435, public._qa_node4_marche_r35();
INSERT INTO public._qa_s13_results(part, result) SELECT 436, public._qa_node4_marche_r3();