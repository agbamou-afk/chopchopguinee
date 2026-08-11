CREATE OR REPLACE FUNCTION public._qa_s10_fix()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_chop_pay_customer_hold_internal'
     AND p.prosrc ILIKE '%chop_pay_checkout_enabled%';
  UPDATE public._qa_s10_results SET ok=(v_n=1), detail='_chop_pay_customer_hold_internal:'||v_n
   WHERE id='C2-stage4-chop-pay-checkout-flag';

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('ride_accept','ride_dispatch')
     AND p.prosrc ILIKE '%driver_balance_gate_enabled%';
  UPDATE public._qa_s10_results SET ok=(v_n=2), detail='ride_accept+ride_dispatch:'||v_n
   WHERE id='C4-stage1-ride-commission-gate';
END; $$;
SELECT public._qa_s10_fix();
DROP FUNCTION public._qa_s10_fix();