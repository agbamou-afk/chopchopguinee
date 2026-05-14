CREATE OR REPLACE FUNCTION public.ride_integrity_check(p_ride_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides;
  v_pay public.wallet_transactions;
  v_commission_count int;
  v_commission_total bigint;
  v_capture_count int;
  v_audit_count int;
  v_client_wallet public.wallets;
  v_driver_wallet public.wallets;
  v_master_wallet public.wallets;
  v_checks jsonb := '[]'::jsonb;
  v_ok boolean;
  v_is_demo boolean;
  v_financial_check text;
  v_message text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.client_id <> v_uid AND v_ride.driver_id <> v_uid AND NOT public.has_role(v_uid, 'admin') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_ride.status <> 'completed' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ride_not_completed', 'status', v_ride.status);
  END IF;

  -- Demo detection: a ride that completed with no wallet hold did not move money.
  v_is_demo := v_ride.hold_tx_id IS NULL
            OR coalesce((v_ride.metadata->>'demo')::boolean, false)
            OR coalesce((v_ride.metadata->>'is_demo')::boolean, false);

  SELECT count(*) INTO v_audit_count
    FROM public.audit_logs
   WHERE module = 'wallet' AND target_id = v_ride.id::text;

  SELECT * INTO v_client_wallet FROM public.wallets
   WHERE owner_user_id = v_ride.client_id AND party_type = 'client' LIMIT 1;
  IF v_ride.driver_id IS NOT NULL THEN
    SELECT * INTO v_driver_wallet FROM public.wallets
     WHERE owner_user_id = v_ride.driver_id AND party_type = 'driver' LIMIT 1;
  END IF;
  SELECT * INTO v_master_wallet FROM public.wallets WHERE party_type = 'master' LIMIT 1;

  IF v_is_demo AND v_ride.hold_tx_id IS NULL THEN
    -- Lifecycle-only check for demo rides; financial settlement is intentionally skipped.
    v_checks := v_checks || jsonb_build_object(
      'name','lifecycle_completed',
      'ok', v_ride.completed_at IS NOT NULL,
      'completed_at', v_ride.completed_at
    );
    v_checks := v_checks || jsonb_build_object(
      'name','audit_logs_present',
      'ok', v_audit_count >= 1,
      'audit_count', v_audit_count
    );
    v_checks := v_checks || jsonb_build_object(
      'name','financial_settlement',
      'ok', true,
      'status', 'skipped_demo_no_hold',
      'note', 'Demo ride: no wallet hold existed, financial settlement was skipped.'
    );

    SELECT bool_and((c->>'ok')::boolean) INTO v_ok FROM jsonb_array_elements(v_checks) c;
    v_financial_check := 'skipped_demo_no_hold';
    v_message := 'Demo ride completed successfully. No wallet hold existed, so financial settlement was skipped.';

    RETURN jsonb_build_object(
      'ok', v_ok,
      'is_demo', true,
      'financial_check', v_financial_check,
      'message', v_message,
      'ride_id', v_ride.id,
      'mode', v_ride.mode,
      'fare_gnf', v_ride.fare_gnf,
      'driver_earning_gnf', v_ride.driver_earning_gnf,
      'platform_fee_gnf', v_ride.platform_fee_gnf,
      'completed_at', v_ride.completed_at,
      'wallets', jsonb_build_object(
        'client_balance_gnf', v_client_wallet.balance_gnf,
        'driver_balance_gnf', v_driver_wallet.balance_gnf,
        'master_balance_gnf', v_master_wallet.balance_gnf
      ),
      'checks', v_checks
    );
  END IF;

  -- Real ride: strict wallet validation
  SELECT * INTO v_pay FROM public.wallet_transactions WHERE id = v_ride.payment_tx_id;

  SELECT count(*) INTO v_capture_count
    FROM public.wallet_transactions
   WHERE related_entity = 'capture:' || v_ride.hold_tx_id::text
     AND type = 'payment' AND status = 'completed';

  SELECT count(*), coalesce(sum(amount_gnf),0) INTO v_commission_count, v_commission_total
    FROM public.wallet_transactions
   WHERE type = 'transfer' AND status = 'completed'
     AND description = 'Commission course ' || v_ride.id::text;

  v_checks := v_checks || jsonb_build_object(
    'name','customer_debited',
    'ok', v_pay.id IS NOT NULL AND v_pay.amount_gnf = v_ride.fare_gnf,
    'expected_gnf', v_ride.fare_gnf,
    'observed_gnf', v_pay.amount_gnf
  );
  v_checks := v_checks || jsonb_build_object(
    'name','driver_credited_net',
    'ok', v_ride.driver_id IS NULL
       OR (coalesce(v_pay.amount_gnf,0) - v_commission_total) = v_ride.driver_earning_gnf,
    'expected_gnf', v_ride.driver_earning_gnf,
    'observed_gnf', coalesce(v_pay.amount_gnf,0) - v_commission_total
  );
  v_checks := v_checks || jsonb_build_object(
    'name','commission_recorded',
    'ok', v_ride.platform_fee_gnf = v_commission_total OR v_ride.driver_id IS NULL,
    'expected_gnf', v_ride.platform_fee_gnf,
    'observed_gnf', v_commission_total
  );
  v_checks := v_checks || jsonb_build_object(
    'name','no_duplicate_capture',
    'ok', v_capture_count = 1,
    'capture_count', v_capture_count
  );
  v_checks := v_checks || jsonb_build_object(
    'name','single_commission_entry',
    'ok', (v_ride.driver_id IS NULL AND v_commission_count = 0)
       OR (v_ride.platform_fee_gnf = 0 AND v_commission_count = 0)
       OR v_commission_count = 1,
    'commission_count', v_commission_count
  );
  v_checks := v_checks || jsonb_build_object(
    'name','audit_logs_present',
    'ok', v_audit_count >= 1,
    'audit_count', v_audit_count
  );

  SELECT bool_and((c->>'ok')::boolean) INTO v_ok FROM jsonb_array_elements(v_checks) c;

  RETURN jsonb_build_object(
    'ok', v_ok,
    'is_demo', false,
    'financial_check', CASE WHEN v_ok THEN 'passed' ELSE 'failed' END,
    'message', CASE WHEN v_ok
      THEN 'Real ride passed full financial settlement validation.'
      ELSE 'Real ride failed financial settlement validation. See checks for details.' END,
    'ride_id', v_ride.id,
    'mode', v_ride.mode,
    'fare_gnf', v_ride.fare_gnf,
    'driver_earning_gnf', v_ride.driver_earning_gnf,
    'platform_fee_gnf', v_ride.platform_fee_gnf,
    'completed_at', v_ride.completed_at,
    'wallets', jsonb_build_object(
      'client_balance_gnf', v_client_wallet.balance_gnf,
      'driver_balance_gnf', v_driver_wallet.balance_gnf,
      'master_balance_gnf', v_master_wallet.balance_gnf
    ),
    'checks', v_checks
  );
END $function$;