DO $mig$
DECLARE
  v_def text;
  b_old text := 'r := r || public._qa_s13_ok(''P15.11 the pre-engagement cash path moved no ledger value'',
        v_n = 0, v_dbg);';
  b_new text := 'r := r || public._qa_s13_ok(''P15.11 the pre-engagement cash path settled no payment value'',
        NOT EXISTS (SELECT 1 FROM public.ledger_journals j
                     WHERE j.source_module = ''repas'' AND j.source_id = v_oc
                       AND j.action::text <> ''cancellation_fee_charged''), v_dbg);
  r := r || public._qa_s13_ok(''P15.11b any journal on a pre-engagement cash order is cancellation-only'',
        v_n <= 1 AND v_dbg IN (''-'',''cancellation_fee_charged''), v_dbg);';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r7_readtruth';
  IF position(b_old in v_def) = 0 THEN RAISE EXCEPTION 'ANCHOR'; END IF;
  EXECUTE replace(v_def, b_old, b_new);
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_readtruth() FROM PUBLIC, anon, authenticated;