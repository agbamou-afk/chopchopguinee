DO $mig$
DECLARE src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_s13_run3';

  src := replace(src,
    'INSERT INTO public.missions(type, customer_id, ref_market_order_id, estimated_earning_gnf, state, courier_id)
    VALUES (''marketplace_delivery'', v_cust, v_m2, 25000, ''assigned'', v_drv) RETURNING id INTO v_mmis;',
    'INSERT INTO public.missions(type, customer_id, ref_market_order_id, estimated_earning_gnf, state)
    VALUES (''marketplace_delivery'', v_cust, v_m2, 25000, ''assigned'') RETURNING id INTO v_mmis;');

  src := replace(src,
    '    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_dpromo), true);
    BEGIN v_res := public.chop_pay_merchant_accept(''marche'', v_m2); v_err := ''NO_ERROR'';',
    '    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_drv), true);
    BEGIN PERFORM public.mission_claim(v_mmis); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT COALESCE(sum(amount_gnf),0) INTO v_held FROM public.mission_financial_holds
      WHERE source_id = v_m2 AND kind = ''collateral'';
    r := r || public._qa_s13_ok(''E2.3 courier collateral hold placed at claim (75000)'',
      v_err = ''NO_ERROR'' AND v_held = 75000, format(''%s hold=%s'', v_err, v_held));

    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_dpromo), true);
    BEGIN v_res := public.chop_pay_merchant_accept(''marche'', v_m2); v_err := ''NO_ERROR'';');

  EXECUTE src;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_s13_run3() FROM PUBLIC, anon, authenticated;

INSERT INTO public._qa_s13_results(part, result) SELECT 3, public._qa_s13_run3();