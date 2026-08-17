
DO $do$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO d FROM pg_proc WHERE oid =
    (SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='marche_shopper_submit_purchase' LIMIT 1);
  IF d IS NULL THEN RAISE EXCEPTION 'marche_shopper_submit_purchase missing'; END IF;
  d := replace(d, 'now(), ''procurement''', 'now(), ''shopper_receipt''');
  IF d LIKE '%''procurement''%' AND d NOT LIKE '%shopper_receipt%' THEN
    RAISE EXCEPTION 'observation source_kind patch did not apply';
  END IF;
  EXECUTE d;
END $do$;

CREATE OR REPLACE FUNCTION public._qa_node4_marche_r7_obs_kind()
RETURNS text LANGUAGE sql STABLE SET search_path TO 'public' AS $$ SELECT 'shopper_receipt'::text $$;

DO $do$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO d FROM pg_proc WHERE oid =
    'public._qa_node4_marche_r7_fxcore()'::regprocedure;
  d := replace(d, 'source_kind = ''procurement''', 'source_kind = ''shopper_receipt''');
  d := replace(d, 'source_kind=''procurement''', 'source_kind=''shopper_receipt''');
  EXECUTE d;
END $do$;
