-- 1) Remove owner-driver authority from mission settlement primitives.
DO $mig$
DECLARE r record; src text; newsrc text;
BEGIN
  FOR r IN
    SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('driver_mission_hold_release',
                        'driver_mission_commission_capture',
                        'driver_mission_fee_capture')
  LOOP
    src := pg_get_functiondef(r.oid);
    newsrc := replace(src,
      'v_h.driver_user_id <> COALESCE(v_caller, v_h.driver_user_id)',
      '(v_caller IS NOT NULL)');
    IF newsrc = src THEN
      RAISE EXCEPTION 'Owner-driver guard pattern not found in %', r.oid::regprocedure;
    END IF;
    EXECUTE newsrc;
  END LOOP;
END $mig$;

-- 2) Least-privilege EXECUTE grants on Slice 1 finance primitives.
DO $g$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig, p.proname
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND (p.proname LIKE 'driver_mission%'
        OR p.proname LIKE 'chop_pay_customer_capture%'
        OR p.proname LIKE 'chop_pay_customer_refund%'
        OR p.proname LIKE 'merchant_payable%'
        OR p.proname LIKE 'merchant_settlement%'
        OR p.proname LIKE 'customer_cancellation_debt%'
        OR p.proname LIKE 'claims_reserve%'
        OR p.proname LIKE 'driver_payout_hold%'
        OR p.proname LIKE 'driver_collateral_resolve'
        OR p.proname LIKE 'driver_starter_credit_grant'
        OR p.proname LIKE 'driver_funding_allocate'
        OR p.proname LIKE 'driver_promo_balance'
        OR p.proname LIKE '_ledger_post'
        OR p.proname LIKE '_ledger_reverse'
        OR p.proname LIKE '_promo_%'
        OR p.proname LIKE '_finance_evidence_%')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;
END $g$;

-- 3) Explicitly keep the safe, read-only / self-service surface for app users.
GRANT EXECUTE ON FUNCTION public.driver_balance_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_financial_eligibility(text, bigint, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finance_mission_requirement(text, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finance_mission_requirement_v2(text, bigint, bigint, bigint, bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chop_pay_customer_hold_place(text, uuid, bigint, text, uuid, boolean, jsonb) TO authenticated;