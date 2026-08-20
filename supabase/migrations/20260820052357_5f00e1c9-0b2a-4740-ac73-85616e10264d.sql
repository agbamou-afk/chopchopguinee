DO $mig$
DECLARE s text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc WHERE proname='_qa_node4_marche_r11';
  s := replace(s,
'    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_merch), true);
    v_elig := (public.merchant_finance_overview(v_store)->>''eligible_settlement_gnf'')::bigint;',
'    UPDATE public.wallets SET balance_gnf = 6000
      WHERE owner_user_id = v_merch AND party_type = ''merchant'';
    SELECT balance_gnf INTO v_bal0 FROM public.wallets
      WHERE owner_user_id = v_merch AND party_type = ''merchant'';
    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_merch), true);
    v_elig := (public.merchant_finance_overview(v_store)->>''eligible_settlement_gnf'')::bigint;');
  IF s NOT LIKE '%balance_gnf = 6000%' THEN RAISE EXCEPTION 'R11_WALLET_PATCH_DID_NOT_APPLY'; END IF;
  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_node4_marche_r11() RETURNS jsonb LANGUAGE plpgsql AS %L', s);
END $mig$;