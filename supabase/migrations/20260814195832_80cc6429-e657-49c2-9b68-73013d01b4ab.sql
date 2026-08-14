DO $mig$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r9_recovery_flows_fxcore';
  IF position('boundary = ''customer_pickup''' in d) = 0 THEN
    RAISE EXCEPTION 'R9_HARNESS_PATCH_TARGET_MISSING';
  END IF;
  d := replace(d, 'boundary = ''customer_pickup''', 'boundary = ''merchant_to_customer_pickup''');
  EXECUTE d;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r9_recovery_flows_fxcore() FROM PUBLIC, anon, authenticated;