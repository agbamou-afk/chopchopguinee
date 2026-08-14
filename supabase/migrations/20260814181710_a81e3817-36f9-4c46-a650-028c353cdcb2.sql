DO $mig$
DECLARE
  v_def text;
  v_old text := '  -- ============ P15. PRE-ENGAGEMENT CASH IS DUE, NEVER UNKNOWN ============';
  v_new text := '  -- ============ P15. PRE-ENGAGEMENT CASH IS DUE, NEVER UNKNOWN ============
  -- Cash delivery requires customer fee = courier payout, so no promotion may apply.
  UPDATE public.repas_pricing_promotions SET enabled = false WHERE name LIKE ''QA R7 RT Promo%'';';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r7_readtruth';
  IF position(v_old in v_def) = 0 THEN RAISE EXCEPTION 'READTRUTH_P15_ANCHOR_NOT_FOUND'; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_readtruth() FROM PUBLIC, anon, authenticated;