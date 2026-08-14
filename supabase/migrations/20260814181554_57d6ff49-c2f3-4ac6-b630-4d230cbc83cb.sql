DO $mig$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r7_readtruth';
  IF v_def IS NULL THEN RAISE EXCEPTION 'READTRUTH_MISSING'; END IF;
  v_def := replace(v_def, ', ''both'',', ', ''delivery'',');
  EXECUTE v_def;
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_readtruth() FROM PUBLIC, anon, authenticated;