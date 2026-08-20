DO $mig$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r11';

  v_def := replace(v_def,
$old$  r := r || public._qa_s13_ok('N4R11.A8 finance tables stay RPC-only for clients',
        NOT has_table_privilege('authenticated','public.merchant_payables','SELECT')
    AND NOT has_table_privilege('authenticated','public.payout_settlement_allocations','SELECT')
    AND NOT has_table_privilege('anon','public.merchant_payables','SELECT'), NULL);$old$,
$new$  r := r || public._qa_node4_marche_r11_a8();$new$);

  IF v_def NOT LIKE '%_qa_node4_marche_r11_a8()%' THEN
    RAISE EXCEPTION 'A8_PATCH_TARGET_NOT_FOUND';
  END IF;

  EXECUTE v_def;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r11() FROM PUBLIC, anon, authenticated;
