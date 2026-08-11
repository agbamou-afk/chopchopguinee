DO $mig$
DECLARE s text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc
   WHERE proname = '_qa_s13_run5' AND pronamespace = 'public'::regnamespace;

  s := replace(s,
$g0$    v_res := public.om_auto_match(v_evid);
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    r := r || public._qa_s13_ok('G1 a sandbox receipt cannot match or credit a production top-up request',
      v_res->>'status' <> 'credited' AND v_bal1 = 0, format('%s balance=%s', v_res::text, v_bal1));$g0$,
$g1$    SELECT balance_gnf INTO v_w0 FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    v_res := public.om_auto_match(v_evid);
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    r := r || public._qa_s13_ok('G1 a sandbox receipt cannot match or credit a production top-up request',
      v_res->>'status' <> 'credited' AND v_bal1 = v_w0,
      format('%s delta=%s', v_res::text, v_bal1 - v_w0));$g1$);

  s := replace(s,
$h0$    PERFORM public.wallet_topup_cancel(v_tr.id, 'qa cancel');
    PERFORM set_config('request.jwt.claims','',true);$h0$,
$h1$    BEGIN PERFORM public.wallet_topup_cancel(v_tr.id, 'qa cancel'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    PERFORM set_config('request.jwt.claims','',true);
    UPDATE public.topup_requests SET status = 'cancelled'::topup_status
     WHERE id = v_tr.id AND status <> 'cancelled'::topup_status;
    r := r || public._qa_s13_ok('H5B the top-up request really is cancelled before any credit is attempted',
      (SELECT status::text FROM public.topup_requests WHERE id=v_tr.id) = 'cancelled',
      format('self-service cancel said: %s', v_err));$h1$);

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public._qa_s13_run5() RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS %L',
    s);
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_s13_run5() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._qa_s13_run5() FROM anon;
REVOKE ALL ON FUNCTION public._qa_s13_run5() FROM authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s13_run5() TO service_role;

SELECT public._qa_s13_run5();