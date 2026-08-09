CREATE OR REPLACE FUNCTION public._qa_s3c_run()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  res jsonb := '{}'::jsonb;
  dv uuid := gen_random_uuid();
  cu uuid := gen_random_uuid();
  v_dw uuid; v_cw uuid; v_cw2 uuid; v_master uuid;
  v_acct uuid;
  v_topup public.topup_requests;
  v_ctopup public.topup_requests;
  v_event uuid; v_event2 uuid;
  v_code text := 'QA' || upper(substring(replace(gen_random_uuid()::text,'-',''),1,10));
  v_code2 text := 'QB' || upper(substring(replace(gen_random_uuid()::text,'-',''),1,10));
  e jsonb; m jsonb;
  m0 bigint; m1 bigint; d0 bigint; d1 bigint; c0 bigint; c1 bigint;
  tx1 uuid; tx2 uuid; nargs int; v_err text;
BEGIN
  PERFORM public.wallet_ensure_master();
  SELECT id INTO v_master FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT id INTO v_acct FROM public.payment_receiving_accounts WHERE provider='orange_money' AND is_active LIMIT 1;

  INSERT INTO public.driver_profiles(user_id,status,vehicle_type,presence,capabilities)
  VALUES (dv,'approved','moto','online',ARRAY['rides_moto']);
  INSERT INTO public.profiles(user_id, full_name, phone) VALUES (dv,'QA Driver','+224620000001')
    ON CONFLICT DO NOTHING;
  INSERT INTO public.wallets(owner_user_id,party_type,balance_gnf) VALUES (dv,'driver',0) RETURNING id INTO v_dw;
  INSERT INTO public.wallets(owner_user_id,party_type,balance_gnf) VALUES (dv,'client',0) RETURNING id INTO v_cw;
  INSERT INTO public.wallets(owner_user_id,party_type,balance_gnf) VALUES (cu,'client',0) RETURNING id INTO v_cw2;
  UPDATE public.feature_flags SET enabled=true WHERE key='driver_balance_gate_enabled';

  -- E1: ineligible at zero
  PERFORM set_config('request.jwt.claims','',true);
  e := public.driver_financial_eligibility('ride',100000,dv);
  res := res || jsonb_build_object(
    'E1.ineligible_at_zero', NOT (e->>'eligible')::boolean,
    'E1.required_gnf', e->>'required_gnf',
    'E1.available_gnf', e->>'available_gnf');

  -- E10: cross-user targeting impossible (self-only signature)
  SELECT pronargs INTO nargs FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='driver_wallet_topup_om_create';
  res := res || jsonb_build_object('E10.self_only_signature', nargs = 2);

  -- E2: driver-targeted top-up through the real RPC
  PERFORM set_config('request.jwt.claims', json_build_object('sub',dv::text,'role','authenticated')::text, true);
  v_topup := public.driver_wallet_topup_om_create(50000, v_acct);
  res := res || jsonb_build_object(
    'E2.request_created', v_topup.id IS NOT NULL,
    'E2.target_is_driver', v_topup.target_party_type = 'driver',
    'E2.owner_is_caller', v_topup.client_user_id = dv,
    'E2.amount', v_topup.amount_gnf);

  -- E10b: non-driver user cannot create a driver-targeted request
  PERFORM set_config('request.jwt.claims', json_build_object('sub',cu::text,'role','authenticated')::text, true);
  BEGIN
    PERFORM public.driver_wallet_topup_om_create(50000, v_acct);
    res := res || jsonb_build_object('E10.non_driver_denied', false);
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('E10.non_driver_denied', true, 'E10.err', SQLERRM);
  END;

  -- E3: real confirmation path — customer submits OM code, provider event matched
  PERFORM set_config('request.jwt.claims', json_build_object('sub',dv::text,'role','authenticated')::text, true);
  PERFORM public.submit_customer_om_code(v_topup.id, v_code);

  PERFORM set_config('request.jwt.claims','',true);
  m0 := (SELECT balance_gnf FROM public.wallets WHERE id=v_master);
  d0 := (SELECT balance_gnf FROM public.wallets WHERE id=v_dw);
  c0 := (SELECT balance_gnf FROM public.wallets WHERE id=v_cw);

  INSERT INTO public.payment_provider_events(
    provider, event_type, provider_transaction_id, payer_phone, amount_gnf,
    status, processing_status, om_code_raw, om_code_normalized, raw_payload, receiving_account_id)
  VALUES ('orange_money','payment.received','QATX'||v_code,'+224620000001',50000,
    'successful','received', v_code, public.normalize_om_code(v_code),
    jsonb_build_object('source','qa_sandbox'), v_acct)
  RETURNING id INTO v_event;

  m := public.om_auto_match(v_event);
  res := res || jsonb_build_object('E3.auto_match_status', m->>'status');

  -- E4/E5/E6
  d1 := (SELECT balance_gnf FROM public.wallets WHERE id=v_dw);
  c1 := (SELECT balance_gnf FROM public.wallets WHERE id=v_cw);
  m1 := (SELECT balance_gnf FROM public.wallets WHERE id=v_master);
  res := res || jsonb_build_object(
    'E4.driver_wallet_credited_50k', (d1 - d0) = 50000,
    'E5.client_wallet_unchanged', (c1 - c0) = 0,
    'E6.master_contra_minus_50k', (m1 - m0) = -50000,
    'E6.no_revenue_txn', NOT EXISTS (
      SELECT 1 FROM public.wallet_transactions
       WHERE (metadata->>'event_id') = v_event::text AND type <> 'topup'),
    'E6.txn_type_is_topup', EXISTS (
      SELECT 1 FROM public.wallet_transactions
       WHERE (metadata->>'event_id') = v_event::text
         AND type='topup' AND to_wallet_id=v_dw AND from_wallet_id=v_master));

  -- E7: eligibility now automatic
  e := public.driver_financial_eligibility('ride',100000,dv);
  res := res || jsonb_build_object(
    'E7.eligible_after_topup', (e->>'eligible')::boolean,
    'E7.available_gnf', e->>'available_gnf');

  -- E8: no manual unblock state anywhere in the eligibility payload
  res := res || jsonb_build_object(
    'E8.no_unblocked_flag', NOT (e ? 'unblocked') AND NOT ((e->'balance') ? 'unblocked')
      AND (e->>'available_gnf')::bigint = (SELECT balance_gnf - held_gnf FROM public.wallets WHERE id=v_dw));

  -- E9: replay is idempotent
  SELECT id INTO tx1 FROM public.wallet_transactions WHERE (metadata->>'event_id') = v_event::text LIMIT 1;
  BEGIN
    SELECT (public.wallet_topup_om_credit(v_event, v_topup.id)).id INTO tx2;
  EXCEPTION WHEN OTHERS THEN tx2 := NULL; v_err := SQLERRM; END;
  res := res || jsonb_build_object(
    'E9.replay_same_txn', tx2 IS NOT DISTINCT FROM tx1,
    'E9.replay_err', v_err,
    'E9.replay_zero_delta', (SELECT balance_gnf FROM public.wallets WHERE id=v_dw) = d1,
    'E9.single_txn_for_event', (SELECT count(*) FROM public.wallet_transactions
       WHERE (metadata->>'event_id') = v_event::text) = 1);

  -- E11: ordinary customer top-up still credits the client wallet
  PERFORM set_config('request.jwt.claims', json_build_object('sub',cu::text,'role','authenticated')::text, true);
  v_ctopup := public.wallet_topup_om_create(25000, v_acct);
  PERFORM public.submit_customer_om_code(v_ctopup.id, v_code2);
  PERFORM set_config('request.jwt.claims','',true);
  c0 := (SELECT balance_gnf FROM public.wallets WHERE id=v_cw2);
  INSERT INTO public.payment_provider_events(
    provider, event_type, provider_transaction_id, payer_phone, amount_gnf,
    status, processing_status, om_code_raw, om_code_normalized, raw_payload, receiving_account_id)
  VALUES ('orange_money','payment.received','QATX'||v_code2, NULL, 25000,
    'successful','received', v_code2, public.normalize_om_code(v_code2),
    jsonb_build_object('source','qa_sandbox'), v_acct)
  RETURNING id INTO v_event2;
  m := public.om_auto_match(v_event2);
  res := res || jsonb_build_object(
    'E11.customer_match_status', m->>'status',
    'E11.legacy_default_client', v_ctopup.target_party_type = 'client',
    'E11.client_wallet_credited', (SELECT balance_gnf FROM public.wallets WHERE id=v_cw2) - c0 = 25000,
    'E11.no_driver_wallet_for_customer', NOT EXISTS (
      SELECT 1 FROM public.wallets WHERE owner_user_id=cu AND party_type='driver'));

  -- privilege matrix (unchanged from 622067bd)
  res := res || jsonb_build_object(
    'P.wallet_internal_transfer.anon_denied', NOT has_function_privilege('anon','public.wallet_internal_transfer(uuid,text,uuid,text,bigint,text,text)','EXECUTE'),
    'P.wallet_internal_transfer.authenticated_denied', NOT has_function_privilege('authenticated','public.wallet_internal_transfer(uuid,text,uuid,text,bigint,text,text)','EXECUTE'),
    'P.wallet_internal_transfer.service_role_allowed', has_function_privilege('service_role','public.wallet_internal_transfer(uuid,text,uuid,text,bigint,text,text)','EXECUTE'),
    'P.ride_accept.authenticated_denied', NOT has_function_privilege('authenticated','public.ride_accept(uuid)','EXECUTE'),
    'P.ride_dispatch.authenticated_denied', NOT has_function_privilege('authenticated','public.ride_dispatch(uuid)','EXECUTE'),
    'P.ride_dispatch.anon_denied', NOT has_function_privilege('anon','public.ride_dispatch(uuid)','EXECUTE'),
    'P.driver_topup.anon_denied', NOT has_function_privilege('anon','public.driver_wallet_topup_om_create(bigint,uuid)','EXECUTE'),
    'P.driver_topup.authenticated_allowed', has_function_privilege('authenticated','public.driver_wallet_topup_om_create(bigint,uuid)','EXECUTE'),
    'F.flags_only_om_topup', (SELECT count(*) FROM public.feature_flags WHERE enabled AND key <> 'driver_balance_gate_enabled' AND key <> 'om_topup_enabled') = 0);

  RAISE EXCEPTION 'QA_S3C_RESULT %', res::text;
END;
$function$;