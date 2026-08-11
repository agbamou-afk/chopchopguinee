DO $mig$
DECLARE src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_s13_run3';

  src := replace(src,
    '    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_cust), true);
    BEGIN v_res := public.chop_pay_customer_cancel(''marche'', v_m2, ''qa''); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok(''E4.1 Chop Pay cancellation refused once merchandise is funded'',
      v_err <> ''NO_ERROR'', v_err);',
    '    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_cust), true);
    BEGIN v_res := public.chop_pay_customer_cancel(''marche'', v_m2, ''qa''); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := ''{}''::jsonb; END;
    r := r || public._qa_s13_ok(''E4.1 cancellation after funding reverses the merchant capture'',
      v_err = ''NO_ERROR'' AND v_res#>>''{merchant_reversal,status}'' = ''reversed'',
      format(''%s %s'', v_err, v_res::text));
    SELECT COALESCE(sum(funded_gnf),0) INTO v_n FROM public.merchant_payables
      WHERE source_module=''marche'' AND source_id = v_m2 AND state <> ''reversed'';
    r := r || public._qa_s13_ok(''E4.2 no merchant liability survives the reversal'', v_n = 0, v_n::text);
    SELECT COALESCE(held_gnf,0) INTO v_held FROM public.wallets
      WHERE owner_user_id = v_cust AND party_type = ''client'';
    r := r || public._qa_s13_ok(''E4.3 customer Chop Pay hold released on cancellation'',
      v_held = 0, v_held::text);
    SELECT COALESCE(held_gnf,0) INTO v_n FROM public.wallets
      WHERE owner_user_id = v_drv AND party_type = ''driver'';
    r := r || public._qa_s13_ok(''E4.4 courier collateral released on cancellation'', v_n = 0, v_n::text);
    BEGIN v_res := public.chop_pay_customer_cancel(''marche'', v_m2, ''qa''); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := ''{}''::jsonb; END;
    r := r || public._qa_s13_ok(''E4.5 duplicate cancellation is inert'',
      v_res->>''status'' = ''already_cancelled'', format(''%s %s'', v_err, v_res::text));');

  EXECUTE src;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_s13_run3() FROM PUBLIC, anon, authenticated;

INSERT INTO public._qa_s13_results(part, result) SELECT 3, public._qa_s13_run3();