CREATE OR REPLACE FUNCTION public._qa_s3d_run()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r jsonb := '{}'::jsonb;
  u_d uuid := gen_random_uuid();
  v_acct uuid;
  v_topup public.topup_requests;
  v_code text;
  v_event uuid;
  v_match jsonb;
  v_dw uuid; v_cw uuid;
  v_master_before bigint; v_master_after bigint;
  v_elig jsonb;
  v_tx_count int;
  v_cust_topup public.topup_requests;
  u_c uuid := gen_random_uuid();
BEGIN
  SELECT id INTO v_acct FROM public.payment_receiving_accounts WHERE provider='orange_money' ORDER BY created_at LIMIT 1;
  IF v_acct IS NULL THEN RAISE EXCEPTION 'QA_S3D_RESULT %', jsonb_build_object('fatal','no_receiving_account'); END IF;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
  VALUES (u_d,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','qa-s3d-driver@example.invalid','x',now(),now(),now(),'{}','{}'),
         (u_c,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','qa-s3d-client@example.invalid','x',now(),now(),now(),'{}','{}');

  INSERT INTO public.profiles (user_id, full_name, phone) VALUES (u_d,'QA S3D Driver','+224600000091'),(u_c,'QA S3D Client','+224600000092')
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.driver_profiles (user_id, status, vehicle_type, approved_at)
  VALUES (u_d, 'approved', 'moto'::public.driver_vehicle_type, now());

  INSERT INTO public.wallets (owner_user_id, party_type, balance_gnf, status) VALUES
    (u_d,'driver',0,'active'),(u_d,'client',0,'active'),(u_c,'client',0,'active');
  SELECT id INTO v_dw FROM public.wallets WHERE owner_user_id=u_d AND party_type='driver';
  SELECT id INTO v_cw FROM public.wallets WHERE owner_user_id=u_d AND party_type='client';
  SELECT balance_gnf INTO v_master_before FROM public.wallets WHERE party_type='master' LIMIT 1;

  PERFORM set_config('request.jwt.claims', json_build_object('sub',u_d::text,'role','authenticated')::text, true);

  v_elig := to_jsonb(public.driver_financial_eligibility('ride', 100000));
  r := r || jsonb_build_object('E1_ineligible_at_zero', COALESCE((v_elig->>'eligible')::boolean,true) = false);

  v_topup := public.driver_wallet_topup_om_create(50000, v_acct);
  r := r || jsonb_build_object('E2_target_driver', v_topup.target_party_type = 'driver' AND v_topup.client_user_id = u_d AND v_topup.amount_gnf = 50000);

  v_code := 'QAS3D' || upper(substring(replace(gen_random_uuid()::text,'-',''),1,7));
  PERFORM public.submit_customer_om_code(v_topup.id, v_code);
  SELECT * INTO v_topup FROM public.topup_requests WHERE id = v_topup.id;

  PERFORM set_config('request.jwt.claims', NULL, true);
  INSERT INTO public.payment_provider_events (provider, event_type, provider_transaction_id, payer_phone, amount_gnf, currency, status, raw_payload, processing_status, om_code_normalized, receiving_account_id)
  VALUES ('orange_money','payment','QA-S3D-'||upper(substring(replace(gen_random_uuid()::text,'-',''),1,10)),'+224600000091',50000,'GNF','successful', jsonb_build_object('source','qa_sandbox'),'pending', v_topup.customer_om_code_normalized, v_acct)
  RETURNING id INTO v_event;

  v_match := to_jsonb(public.om_auto_match(v_event));
  r := r || jsonb_build_object('E3_auto_match_credited', (v_match->>'status') = 'credited', 'E3_match_detail', v_match);

  r := r || jsonb_build_object(
    'E4_driver_plus_50000', (SELECT balance_gnf FROM public.wallets WHERE id=v_dw) = 50000,
    'E5_client_wallet_unchanged', (SELECT balance_gnf FROM public.wallets WHERE id=v_cw) = 0);
  SELECT balance_gnf INTO v_master_after FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT count(*) INTO v_tx_count FROM public.wallet_transactions WHERE (metadata->>'event_id') = v_event::text;
  r := r || jsonb_build_object(
    'E6_master_contra_minus_50000', v_master_after = v_master_before - 50000 AND v_tx_count = 1,
    'E6_tx_is_master_to_driver', (SELECT count(*) FROM public.wallet_transactions WHERE (metadata->>'event_id')=v_event::text AND to_wallet_id=v_dw AND type='topup') = 1);

  PERFORM set_config('request.jwt.claims', json_build_object('sub',u_d::text,'role','authenticated')::text, true);
  v_elig := to_jsonb(public.driver_financial_eligibility('ride', 100000));
  r := r || jsonb_build_object(
    'E7_eligible_after_topup', COALESCE((v_elig->>'eligible')::boolean,false) = true,
    'E8_no_unblock_flag', NOT (v_elig ? 'unblocked'));

  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    PERFORM public.wallet_topup_om_credit(v_event, v_topup.id);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  SELECT count(*) INTO v_tx_count FROM public.wallet_transactions WHERE (metadata->>'event_id') = v_event::text;
  r := r || jsonb_build_object('E9_replay_zero', v_tx_count = 1 AND (SELECT balance_gnf FROM public.wallets WHERE id=v_dw) = 50000);

  PERFORM set_config('request.jwt.claims', json_build_object('sub',u_c::text,'role','authenticated')::text, true);
  BEGIN
    PERFORM public.driver_wallet_topup_om_create(10000, v_acct);
    r := r || jsonb_build_object('E10_non_driver_denied', false);
  EXCEPTION WHEN OTHERS THEN
    r := r || jsonb_build_object('E10_non_driver_denied', true);
  END;

  v_cust_topup := public.wallet_topup_om_create(20000, v_acct);
  r := r || jsonb_build_object('E11_customer_targets_client', v_cust_topup.target_party_type = 'client');

  r := r || jsonb_build_object(
    'A1_anon_om_auto_match_denied', NOT has_function_privilege('anon','public.om_auto_match(uuid)','execute'),
    'A2_auth_om_auto_match_denied', NOT has_function_privilege('authenticated','public.om_auto_match(uuid)','execute'),
    'A3_anon_credit_denied', NOT has_function_privilege('anon','public.wallet_topup_om_credit(uuid,uuid)','execute'),
    'A4_auth_credit_denied', NOT has_function_privilege('authenticated','public.wallet_topup_om_credit(uuid,uuid)','execute'),
    'A5_service_role_allowed', has_function_privilege('service_role','public.om_auto_match(uuid)','execute') AND has_function_privilege('service_role','public.wallet_topup_om_credit(uuid,uuid)','execute'),
    'A6_customer_submit_code_open', has_function_privilege('authenticated','public.submit_customer_om_code(uuid,text)','execute'),
    'A7_admin_paths_open', has_function_privilege('authenticated','public.admin_record_om_receipt(text,bigint,text,uuid,text)','execute') AND has_function_privilege('authenticated','public.admin_retry_om_credit(uuid)','execute') AND has_function_privilege('authenticated','public.admin_manual_om_credit(uuid,uuid)','execute'),
    'GUARD_ride_accept_auth_false', NOT has_function_privilege('authenticated','public.ride_accept(uuid,uuid)','execute'),
    'GUARD_internal_transfer_auth_false', NOT has_function_privilege('authenticated','public.wallet_internal_transfer(uuid,uuid,bigint,text,text,jsonb)','execute')
  );

  RAISE EXCEPTION 'QA_S3D_RESULT %', r::text;
END;
$$;

GRANT EXECUTE ON FUNCTION public._qa_s3d_run() TO PUBLIC;