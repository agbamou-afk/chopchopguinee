DO $mig$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = '_qa_node4_marche_r3';

  IF d IS NULL THEN
    RAISE EXCEPTION 'harness missing';
  END IF;

  d := replace(d, '''%COUNTER_AWAITS_BUYER%''', '''%CONSENT_REQUIRED%''');
  EXECUTE d;
END
$mig$;