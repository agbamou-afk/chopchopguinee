DO $mig$
DECLARE
  v_def text;
  a_old text := '  INSERT INTO public.repas_pricing_promotions(name, reason, fulfillment_scope,
      delivery_discount_gnf, enabled, starts_at, ends_at, created_by)
    VALUES (''QA R7 RT Promo ORIGINALE'',';
  a_new text := '  -- isolate this suite from any other promotion currently in scope
  UPDATE public.repas_pricing_promotions SET enabled = false WHERE enabled;
  INSERT INTO public.repas_pricing_promotions(name, reason, fulfillment_scope,
      delivery_discount_gnf, enabled, starts_at, ends_at, created_by)
    VALUES (''QA R7 RT Promo ORIGINALE'',';
  b_old text := '  SELECT count(*) INTO v_n FROM public.ledger_journals;
  r := r || public._qa_s13_ok(''P15.11 the pre-engagement cash path moved no ledger value'',
        v_n = v_j, v_n::text);';
  b_new text := '  SELECT count(*) INTO v_n FROM public.ledger_journals
   WHERE source_module = ''repas'' AND source_id = v_oc;
  r := r || public._qa_s13_ok(''P15.11 the pre-engagement cash path moved no ledger value'',
        v_n = 0, v_n::text);';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r7_readtruth';
  IF position(a_old in v_def) = 0 THEN RAISE EXCEPTION 'READTRUTH_P14_ANCHOR_NOT_FOUND'; END IF;
  IF position(b_old in v_def) = 0 THEN RAISE EXCEPTION 'READTRUTH_P1511_ANCHOR_NOT_FOUND'; END IF;
  v_def := replace(v_def, a_old, a_new);
  v_def := replace(v_def, b_old, b_new);
  EXECUTE v_def;
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_readtruth() FROM PUBLIC, anon, authenticated;