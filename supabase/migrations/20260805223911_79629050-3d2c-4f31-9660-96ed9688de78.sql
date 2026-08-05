CREATE OR REPLACE FUNCTION public._qa_s1c_run()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE msg text; payload jsonb;
BEGIN
  BEGIN
    PERFORM public._qa_s1c_inner();
    RETURN jsonb_build_object('error','harness did not roll back');
  EXCEPTION WHEN OTHERS THEN
    msg := SQLERRM;
  END;
  IF msg LIKE 'QA_S1C_RESULT %' THEN
    payload := substr(msg, 15)::jsonb;
  ELSE
    payload := jsonb_build_object('harness_error', msg);
  END IF;
  RETURN payload || jsonb_build_object(
    'after_rollback', jsonb_build_object(
      'wallets_total', (SELECT COALESCE(SUM(balance_gnf),0) FROM public.wallets),
      'journals', (SELECT COUNT(*) FROM public.ledger_journals),
      'postings', (SELECT COUNT(*) FROM public.ledger_postings),
      'holds', (SELECT COUNT(*) FROM public.mission_financial_holds),
      'promo_credits', (SELECT COUNT(*) FROM public.driver_promo_credits),
      'payables', (SELECT COUNT(*) FROM public.merchant_payables),
      'debts', (SELECT COUNT(*) FROM public.customer_cancellation_debts),
      'claims', (SELECT COUNT(*) FROM public.claims_reserves)
    ));
END $fn$;
REVOKE ALL ON FUNCTION public._qa_s1c_run() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s1c_run() TO service_role;