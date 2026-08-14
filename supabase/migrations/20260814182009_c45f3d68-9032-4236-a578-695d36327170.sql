DO $mig$
DECLARE
  v_def text;
  b_old text := '  SELECT count(*) INTO v_n FROM public.ledger_journals
   WHERE source_module = ''repas'' AND source_id = v_oc;
  r := r || public._qa_s13_ok(''P15.11 the pre-engagement cash path moved no ledger value'',
        v_n = 0, v_n::text);';
  b_new text := '  SELECT count(*), COALESCE(string_agg(j.kind::text||''/''||COALESCE(j.amount_gnf::text,''-''), '','' ORDER BY j.created_at),''-'')
    INTO v_n, v_dbg FROM public.ledger_journals j
   WHERE j.source_module = ''repas'' AND j.source_id = v_oc;
  r := r || public._qa_s13_ok(''P15.11 the pre-engagement cash path moved no ledger value'',
        v_n = 0, v_dbg);';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r7_readtruth';
  IF position(b_old in v_def) = 0 THEN RAISE EXCEPTION 'ANCHOR'; END IF;
  v_def := replace(v_def, b_old, b_new);
  v_def := regexp_replace(v_def, 'DECLARE', 'DECLARE v_dbg text;');
  EXECUTE v_def;
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_readtruth() FROM PUBLIC, anon, authenticated;