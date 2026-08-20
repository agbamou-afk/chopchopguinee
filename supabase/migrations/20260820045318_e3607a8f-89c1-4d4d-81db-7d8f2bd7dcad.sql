DO $mig$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r11';
  v_def := replace(v_def,
    'INSERT INTO public.payout_orders(party_type, source_kind,',
    'INSERT INTO public.payout_orders(order_key, party_user_id, party_type, source_kind,');
  v_def := replace(v_def,
    'VALUES (''merchant'',''merchant_settlement'',',
    'VALUES (''qa-n411-po-''||v_o1::text, v_merch, ''merchant'',''merchant_settlement'',');
  IF v_def NOT LIKE '%qa-n411-po-%' THEN RAISE EXCEPTION 'PO_PATCH_TARGET_NOT_FOUND'; END IF;
  EXECUTE v_def;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r11() FROM PUBLIC, anon, authenticated;
