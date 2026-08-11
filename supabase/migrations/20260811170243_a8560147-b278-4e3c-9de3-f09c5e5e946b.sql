DO $mig$
DECLARE src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_s13_run3';

  src := replace(src,
    '    SELECT COALESCE(held_gnf,0) INTO v_held FROM public.wallets
      WHERE owner_user_id = v_cust AND party_type = ''client'';
    r := r || public._qa_s13_ok(''E4.3 customer Chop Pay hold released on cancellation'',
      v_held = 0, v_held::text);',
    '    SELECT COALESCE(sum(GREATEST(amount_gnf - captured_gnf - released_gnf,0)),0) INTO v_held
      FROM public.mission_financial_holds
     WHERE source_module = ''marche'' AND source_id = v_m2 AND kind = ''customer_payment'';
    r := r || public._qa_s13_ok(''E4.3 customer Chop Pay hold on this order fully released'',
      v_held = 0, v_held::text);');

  EXECUTE src;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_s13_run3() FROM PUBLIC, anon, authenticated;

INSERT INTO public._qa_s13_results(part, result) SELECT 3, public._qa_s13_run3();