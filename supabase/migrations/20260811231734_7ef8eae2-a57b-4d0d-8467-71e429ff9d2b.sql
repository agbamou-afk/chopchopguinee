-- 1. finance truth table grants
REVOKE ALL ON TABLE public.provider_fee_schedules FROM anon;
REVOKE ALL ON TABLE public.provider_fee_schedules FROM authenticated;
GRANT SELECT ON TABLE public.provider_fee_schedules TO authenticated;
GRANT ALL ON TABLE public.provider_fee_schedules TO service_role;

REVOKE ALL ON TABLE public.payment_provider_events FROM anon;
REVOKE ALL ON TABLE public.payment_provider_events FROM authenticated;
GRANT SELECT, UPDATE ON TABLE public.payment_provider_events TO authenticated;
GRANT ALL ON TABLE public.payment_provider_events TO service_role;

-- 2. internal money-moving primitives: service_role only
DO $rv$
DECLARE f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
       AND (p.proname LIKE '\_ledger\_%' OR p.proname LIKE '\_payout\_%' OR p.proname LIKE '\_merchant\_%'
            OR p.proname LIKE '\_chop\_pay\_%' OR p.proname LIKE '\_cash\_order\_%' OR p.proname LIKE '\_package\_%'
            OR p.proname LIKE '\_driver\_%' OR p.proname LIKE '\_customer\_cancellation\_%')
       AND (has_function_privilege('anon', p.oid, 'EXECUTE')
            OR has_function_privilege('authenticated', p.oid, 'EXECUTE'))
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', f.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f.sig);
  END LOOP;
END
$rv$;

-- 3. harness-only fixture fix: courier claims the Chop Pay marketplace mission before merchant capture
DO $mig$
DECLARE src text; nsrc text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE proname='_qa_s13_run7' AND pronamespace='public'::regnamespace;
  nsrc := replace(src,
    '    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_m1), true);
    SELECT COALESCE(sum(funded_gnf),0) INTO v_pay0 FROM public.merchant_payables
     WHERE source_module=''marche'' AND source_id = v_mo2;',
    '    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_d2), true);
    BEGIN PERFORM public.mission_claim(v_mmis); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT COALESCE(sum(amount_gnf),0) INTO v_held FROM public.mission_financial_holds
     WHERE source_id = v_mo2 AND kind = ''collateral'';
    r := r || public._qa_s13_ok(''R4.2b claiming the Chop Pay marketplace mission places the courier collateral hold'',
      v_err = ''NO_ERROR'' AND v_held > 0, format(''%s hold=%s'', v_err, v_held));
    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_m1), true);
    SELECT COALESCE(sum(funded_gnf),0) INTO v_pay0 FROM public.merchant_payables
     WHERE source_module=''marche'' AND source_id = v_mo2;');
  IF nsrc = src THEN RAISE EXCEPTION 'R4 patch did not apply'; END IF;
  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_s13_run7() RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''public'' AS $f$%s$f$', nsrc);
END $mig$;

DO $g$
DECLARE f record;
BEGIN
  FOR f IN SELECT oid::regprocedure AS sig FROM pg_proc
            WHERE pronamespace='public'::regnamespace AND proname LIKE '\_qa\_s13\_%'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', f.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f.sig);
  END LOOP;
END
$g$;

-- 4. full regression rerun, parts 1..7
INSERT INTO public._qa_s13_results(part, result) SELECT 1, public._qa_s13_run1();
INSERT INTO public._qa_s13_results(part, result) SELECT 2, public._qa_s13_run2();
INSERT INTO public._qa_s13_results(part, result) SELECT 3, public._qa_s13_run3();
INSERT INTO public._qa_s13_results(part, result) SELECT 4, public._qa_s13_run4();
INSERT INTO public._qa_s13_results(part, result) SELECT 5, public._qa_s13_run5();
INSERT INTO public._qa_s13_results(part, result) SELECT 6, public._qa_s13_run6();
INSERT INTO public._qa_s13_results(part, result) SELECT 7, public._qa_s13_run7();