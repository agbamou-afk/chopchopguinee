DO $mig$
DECLARE s text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc WHERE proname='_qa_node4_marche_r11';

  s := replace(s,
'    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_merch), true);
    v_elig := (public.merchant_finance_overview(v_store)->>''eligible_settlement_gnf'')::bigint;',
'    -- a genuinely eligible, unallocated payable so the canonical rail has real work
    INSERT INTO public.merchant_payables(payable_key, source_module, source_id, merchant_store_id,
        merchant_user_id, mission_type, subtotal_gnf, deduction_gnf, amount_gnf,
        funded_gnf, settled_gnf, state, funding_source)
      VALUES (''qa-n411-pelig-''||v_o2::text,''marche'',gen_random_uuid(), v_store, v_merch,''marketplace_delivery'',
        5000, 50, 4950, 4950, 0, ''due'', ''customer_choppay'');
    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_merch), true);
    v_elig := (public.merchant_finance_overview(v_store)->>''eligible_settlement_gnf'')::bigint;');

  s := replace(s,
'      r := r || public._qa_s13_ok(''N4R11.M3 a refused request creates no payout order'',
            (SELECT count(*) FROM public.payout_orders
              WHERE merchant_store_id = v_store AND source_kind=''merchant_settlement'') = 0, NULL);',
'      r := r || public._qa_s13_ok(''N4R11.M3 a refused request creates no payout order'',
            (SELECT count(*) FROM public.payout_orders
              WHERE merchant_store_id = v_store AND source_kind=''merchant_settlement''
                AND id <> v_po) = 0, NULL);');

  s := replace(s,
'      r := r || public._qa_s13_ok(''N4R11.M3 a replay creates no second reservation or payout order'',
            (SELECT count(*) FROM public.merchant_settlement_requests WHERE merchant_store_id=v_store) = 1
        AND (SELECT count(*) FROM public.payout_orders
              WHERE merchant_store_id=v_store AND source_kind=''merchant_settlement'') = 1, NULL);',
'      r := r || public._qa_s13_ok(''N4R11.M3 a replay creates no second reservation or payout order'',
            (SELECT count(*) FROM public.merchant_settlement_requests WHERE merchant_store_id=v_store) = 1
        AND (SELECT count(*) FROM public.payout_orders
              WHERE merchant_store_id=v_store AND source_kind=''merchant_settlement''
                AND id <> v_po) = 1, NULL);');

  s := replace(s,
'      r := r || public._qa_s13_ok(''N4R11.M6 no payout order exists to settle while nothing is eligible'',
            (SELECT count(*) FROM public.payout_orders
              WHERE merchant_store_id=v_store AND source_kind=''merchant_settlement'') = 0, NULL);',
'      r := r || public._qa_s13_ok(''N4R11.M6 no payout order exists to settle while nothing is eligible'',
            (SELECT count(*) FROM public.payout_orders
              WHERE merchant_store_id=v_store AND source_kind=''merchant_settlement''
                AND id <> v_po) = 0, NULL);');

  IF s NOT LIKE '%qa-n411-pelig-%' OR s NOT LIKE '%AND id <> v_po) = 1%' THEN
    RAISE EXCEPTION 'R11_M_PATCH_DID_NOT_APPLY';
  END IF;

  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_node4_marche_r11() RETURNS jsonb LANGUAGE plpgsql AS %L', s);
END $mig$;