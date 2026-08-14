DO $mig$
DECLARE
  v_def text;
  v_old text := 'UPDATE public.repas_pricing_promotions SET enabled = false WHERE name LIKE ''QA R7 RT Promo%'';';
  v_new text := 'UPDATE public.repas_pricing_promotions SET enabled = false WHERE enabled;';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r7_readtruth';
  IF position(v_old in v_def) = 0 THEN RAISE EXCEPTION 'READTRUTH_PROMO_ANCHOR_NOT_FOUND'; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_readtruth() FROM PUBLIC, anon, authenticated;