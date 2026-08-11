CREATE OR REPLACE FUNCTION public.om_auto_match(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_event public.payment_provider_events;
  v_topup public.topup_requests;
  v_env text;
  v_match_count int;
  v_high_value bigint := 5000000;
  v_recent_count int;
  v_event_phone text;
  v_topup_phone text;
  v_profile_phone text;
BEGIN
  SELECT * INTO v_event FROM public.payment_provider_events WHERE id = p_event_id FOR UPDATE;
  IF v_event.id IS NULL THEN RETURN jsonb_build_object('status','not_found'); END IF;

  IF v_event.processing_status IN ('credited','rejected') THEN
    RETURN jsonb_build_object('status', v_event.processing_status, 'event_id', v_event.id, 'inert', true);
  END IF;

  IF v_event.status <> 'successful' THEN
    UPDATE public.payment_provider_events
       SET processing_status = 'rejected',
           notes = coalesce(notes,'') || ' | provider_status_not_successful'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status','rejected','reason','provider_status');
  END IF;

  v_env := CASE WHEN v_event.is_sandbox THEN 'sandbox'
                ELSE COALESCE(NULLIF(btrim(v_event.environment),''),'production') END;

  IF v_event.om_code_normalized IS NULL OR length(v_event.om_code_normalized) < 4 THEN
    UPDATE public.payment_provider_events
       SET processing_status = 'needs_review',
           notes = coalesce(notes,'') || ' | missing_provider_reference'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status','needs_review','reason','missing_provider_reference');
  END IF;

  SELECT count(*) INTO v_match_count
    FROM public.topup_requests t
   WHERE t.provider = 'orange_money'
     AND COALESCE(t.environment,'production') = v_env
     AND t.status::text IN ('pending','matched','needs_review')
     AND t.customer_om_code_normalized = v_event.om_code_normalized
     AND t.expires_at > now();

  IF v_match_count = 0 THEN
    UPDATE public.payment_provider_events
       SET processing_status = 'received',
           notes = coalesce(notes,'') || ' | awaiting_customer_code'
     WHERE id = v_event.id
       AND processing_status NOT IN ('credited','rejected','needs_review');
    RETURN jsonb_build_object('status','awaiting_customer_code','environment',v_env);
  END IF;

  IF v_match_count > 1 THEN
    UPDATE public.payment_provider_events
       SET processing_status = 'needs_review',
           notes = coalesce(notes,'') || ' | multiple_candidates'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status','needs_review','reason','multiple_candidates','matches',v_match_count);
  END IF;

  SELECT * INTO v_topup FROM public.topup_requests t
   WHERE t.provider = 'orange_money'
     AND COALESCE(t.environment,'production') = v_env
     AND t.status::text IN ('pending','matched','needs_review')
     AND t.customer_om_code_normalized = v_event.om_code_normalized
     AND t.expires_at > now()
   LIMIT 1
   FOR UPDATE;

  IF v_topup.amount_gnf <> v_event.amount_gnf THEN
    UPDATE public.topup_requests
       SET status = 'needs_review'::topup_status, review_reason = 'amount_mismatch'
     WHERE id = v_topup.id;
    UPDATE public.payment_provider_events
       SET processing_status = 'needs_review',
           matched_topup_request_id = v_topup.id,
           matched_user_id = v_topup.client_user_id,
           notes = coalesce(notes,'') || ' | amount_mismatch'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status','needs_review','reason','amount_mismatch','topup_request_id',v_topup.id);
  END IF;

  -- Payer phone: MUST be present on BOTH sides and equal. Never inferred from
  -- customer data onto the provider event; absent evidence stays review-required.
  SELECT phone INTO v_profile_phone FROM public.profiles WHERE user_id = v_topup.client_user_id;
  v_event_phone := public._normalize_guinea_phone(v_event.payer_phone);
  v_topup_phone := COALESCE(public._normalize_guinea_phone(v_topup.user_phone),
                            public._normalize_guinea_phone(v_profile_phone));

  IF v_event_phone IS NULL OR v_topup_phone IS NULL THEN
    UPDATE public.topup_requests
       SET status = 'needs_review'::topup_status, review_reason = 'payer_phone_missing'
     WHERE id = v_topup.id;
    UPDATE public.payment_provider_events
       SET processing_status = 'needs_review',
           matched_topup_request_id = v_topup.id,
           matched_user_id = v_topup.client_user_id,
           notes = coalesce(notes,'') || ' | payer_phone_missing'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status','needs_review','reason','payer_phone_missing','topup_request_id',v_topup.id);
  END IF;

  IF v_event_phone <> v_topup_phone THEN
    UPDATE public.topup_requests
       SET status = 'needs_review'::topup_status, review_reason = 'payer_phone_mismatch'
     WHERE id = v_topup.id;
    UPDATE public.payment_provider_events
       SET processing_status = 'needs_review',
           matched_topup_request_id = v_topup.id,
           matched_user_id = v_topup.client_user_id,
           notes = coalesce(notes,'') || ' | payer_phone_mismatch'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status','needs_review','reason','payer_phone_mismatch','topup_request_id',v_topup.id);
  END IF;

  -- Receiving account: MUST be present on BOTH sides and equal.
  IF v_event.receiving_account_id IS NULL OR v_topup.receiving_account_id IS NULL THEN
    UPDATE public.topup_requests
       SET status = 'needs_review'::topup_status, review_reason = 'receiving_account_missing'
     WHERE id = v_topup.id;
    UPDATE public.payment_provider_events
       SET processing_status = 'needs_review',
           matched_topup_request_id = v_topup.id,
           matched_user_id = v_topup.client_user_id,
           notes = coalesce(notes,'') || ' | receiving_account_missing'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status','needs_review','reason','receiving_account_missing','topup_request_id',v_topup.id);
  END IF;

  IF v_event.receiving_account_id <> v_topup.receiving_account_id THEN
    UPDATE public.topup_requests
       SET status = 'needs_review'::topup_status, review_reason = 'receiving_account_mismatch'
     WHERE id = v_topup.id;
    UPDATE public.payment_provider_events
       SET processing_status = 'needs_review',
           matched_topup_request_id = v_topup.id,
           matched_user_id = v_topup.client_user_id,
           notes = coalesce(notes,'') || ' | receiving_account_mismatch'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status','needs_review','reason','receiving_account_mismatch','topup_request_id',v_topup.id);
  END IF;

  IF COALESCE(v_topup.target_party_type,'client') NOT IN ('client','driver') THEN
    UPDATE public.topup_requests
       SET status = 'needs_review'::topup_status, review_reason = 'target_party_invalid'
     WHERE id = v_topup.id;
    RETURN jsonb_build_object('status','needs_review','reason','target_party_invalid','topup_request_id',v_topup.id);
  END IF;

  IF v_event.amount_gnf > v_high_value THEN
    UPDATE public.topup_requests
       SET status='needs_review'::topup_status, review_reason='manual_review_high_value' WHERE id = v_topup.id;
    UPDATE public.payment_provider_events
       SET processing_status='needs_review', matched_topup_request_id=v_topup.id,
           matched_user_id=v_topup.client_user_id,
           notes = coalesce(notes,'') || ' | high_value'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status','needs_review','reason','high_value','topup_request_id',v_topup.id);
  END IF;

  SELECT count(*) INTO v_recent_count FROM public.topup_requests
   WHERE client_user_id = v_topup.client_user_id
     AND status::text = 'credited'
     AND confirmed_at > now() - interval '24 hours';
  IF v_recent_count >= 5 THEN
    UPDATE public.topup_requests
       SET status='needs_review'::topup_status, review_reason='manual_review_rate_limit' WHERE id = v_topup.id;
    UPDATE public.payment_provider_events
       SET processing_status='needs_review', matched_topup_request_id=v_topup.id,
           matched_user_id=v_topup.client_user_id,
           notes = coalesce(notes,'') || ' | rate_limit'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status','needs_review','reason','rate_limit','topup_request_id',v_topup.id);
  END IF;

  PERFORM public.wallet_topup_om_credit(v_event.id, v_topup.id);
  RETURN jsonb_build_object('status','credited','reason','exact_reference_match',
                            'topup_request_id',v_topup.id,'environment',v_env);
END;
$function$;

CREATE OR REPLACE FUNCTION public.wallet_topup_om_credit(p_event_id uuid, p_topup_request_id uuid)
 RETURNS wallet_transactions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_event public.payment_provider_events;
  v_topup public.topup_requests;
  v_target_wallet public.wallets;
  v_master public.wallets;
  v_tx public.wallet_transactions;
  v_ref text;
  v_party text;
  v_env_e text;
  v_env_t text;
  v_event_phone text;
  v_topup_phone text;
  v_profile_phone text;
  v_liab text;
BEGIN
  IF v_caller IS NOT NULL THEN
    IF NOT COALESCE(public.can_manage_wallet(v_caller), false) THEN
      RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;
  ELSIF current_user NOT IN ('postgres','service_role','supabase_admin','supabase_auth_admin') THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('om_credit:'||p_event_id::text, 0));

  SELECT * INTO v_event FROM public.payment_provider_events WHERE id = p_event_id FOR UPDATE;
  IF v_event.id IS NULL THEN RAISE EXCEPTION 'event_not_found'; END IF;

  IF v_event.processing_status = 'credited' THEN
    SELECT * INTO v_tx FROM public.wallet_transactions
      WHERE type = 'topup' AND (metadata->>'event_id') = v_event.id::text LIMIT 1;
    IF v_tx.id IS NOT NULL THEN RETURN v_tx; END IF;
    RAISE EXCEPTION 'already_credited';
  END IF;
  IF v_event.status <> 'successful' THEN RAISE EXCEPTION 'provider_status_not_successful'; END IF;

  SELECT * INTO v_topup FROM public.topup_requests WHERE id = p_topup_request_id FOR UPDATE;
  IF v_topup.id IS NULL THEN RAISE EXCEPTION 'topup_not_found'; END IF;
  IF v_topup.status::text NOT IN ('pending','matched','needs_review') THEN
    RAISE EXCEPTION 'topup_not_eligible:%', v_topup.status;
  END IF;
  IF v_topup.expires_at IS NOT NULL AND v_topup.expires_at < now() THEN
    RAISE EXCEPTION 'topup_expired';
  END IF;
  IF v_topup.transaction_id IS NOT NULL THEN RAISE EXCEPTION 'topup_already_credited'; END IF;

  v_env_e := CASE WHEN v_event.is_sandbox THEN 'sandbox'
                  ELSE COALESCE(NULLIF(btrim(v_event.environment),''),'production') END;
  v_env_t := COALESCE(NULLIF(btrim(v_topup.environment),''),'production');
  IF v_env_e <> v_env_t THEN
    RAISE EXCEPTION 'environment_mismatch:%/%', v_env_e, v_env_t;
  END IF;

  IF v_topup.amount_gnf <> v_event.amount_gnf THEN RAISE EXCEPTION 'amount_mismatch'; END IF;

  -- Exact provider reference is mandatory on BOTH sides.
  IF v_event.om_code_normalized IS NULL OR length(v_event.om_code_normalized) < 4
     OR v_topup.customer_om_code_normalized IS NULL THEN
    RAISE EXCEPTION 'provider_reference_missing';
  END IF;
  IF v_topup.customer_om_code_normalized <> v_event.om_code_normalized THEN
    RAISE EXCEPTION 'provider_reference_mismatch';
  END IF;

  -- Receiving account mandatory on BOTH sides.
  IF v_event.receiving_account_id IS NULL OR v_topup.receiving_account_id IS NULL THEN
    RAISE EXCEPTION 'receiving_account_missing';
  END IF;
  IF v_event.receiving_account_id <> v_topup.receiving_account_id THEN
    RAISE EXCEPTION 'receiving_account_mismatch';
  END IF;

  -- Payer phone mandatory on BOTH sides.
  SELECT phone INTO v_profile_phone FROM public.profiles WHERE user_id = v_topup.client_user_id;
  v_event_phone := public._normalize_guinea_phone(v_event.payer_phone);
  v_topup_phone := COALESCE(public._normalize_guinea_phone(v_topup.user_phone),
                            public._normalize_guinea_phone(v_profile_phone));
  IF v_event_phone IS NULL OR v_topup_phone IS NULL THEN
    RAISE EXCEPTION 'payer_phone_missing';
  END IF;
  IF v_event_phone <> v_topup_phone THEN RAISE EXCEPTION 'payer_phone_mismatch'; END IF;

  v_party := COALESCE(NULLIF(btrim(v_topup.target_party_type), ''), 'client');
  IF v_party NOT IN ('client','driver') THEN RAISE EXCEPTION 'invalid_target_party_type'; END IF;

  SELECT * INTO v_target_wallet FROM public.wallets
    WHERE owner_user_id = v_topup.client_user_id
      AND party_type = v_party::party_type
    FOR UPDATE;
  IF v_target_wallet.id IS NULL THEN RAISE EXCEPTION 'target_wallet_not_found:%', v_party; END IF;
  IF v_target_wallet.status <> 'active' THEN RAISE EXCEPTION 'wallet_not_active'; END IF;

  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
  IF v_master.id IS NULL THEN RAISE EXCEPTION 'master_wallet_not_found'; END IF;

  UPDATE public.wallets SET balance_gnf = balance_gnf + v_event.amount_gnf WHERE id = v_target_wallet.id;
  UPDATE public.wallets SET balance_gnf = balance_gnf - v_event.amount_gnf WHERE id = v_master.id;

  v_ref := 'CC-OM-' || upper(substring(replace(gen_random_uuid()::text,'-',''),1,10));

  INSERT INTO public.wallet_transactions (
    reference, type, status, amount_gnf,
    from_wallet_id, to_wallet_id, related_user_id, related_entity,
    description, completed_at, metadata
  ) VALUES (
    v_ref, 'topup', 'completed', v_event.amount_gnf,
    v_master.id, v_target_wallet.id, v_topup.client_user_id,
    'orange_money:' || v_event.provider_transaction_id,
    'Recharge Orange Money ' || v_topup.reference, now(),
    jsonb_build_object(
      'event_id', v_event.id,
      'topup_request_id', v_topup.id,
      'provider_transaction_id', v_event.provider_transaction_id,
      'payer_phone', v_event.payer_phone,
      'target_party_type', v_party,
      'environment', v_env_t
    )
  ) RETURNING * INTO v_tx;

  UPDATE public.topup_requests
     SET status = 'credited'::topup_status,
         confirmed_at = now(),
         transaction_id = v_tx.id,
         matched_event_id = v_event.id,
         review_reason = NULL,
         matched_provider_transaction_id = v_event.provider_transaction_id
   WHERE id = v_topup.id;

  UPDATE public.payment_provider_events
     SET processing_status = 'credited',
         matched_user_id = v_topup.client_user_id,
         matched_topup_request_id = v_topup.id,
         processed_at = now()
   WHERE id = v_event.id;

  v_liab := CASE WHEN v_party = 'driver' THEN 'L_DRIVER_UNRESTRICTED' ELSE 'L_CUSTOMER_CHOPPAY' END;
  PERFORM public._ledger_post(
    format('om_topup:%s', v_event.id),
    'om_topup', v_topup.id, 'inbound_topup_credited',
    jsonb_build_array(
      jsonb_build_object('account','A_PROVIDER_CLEARING','amount_gnf', v_event.amount_gnf,
                         'party_type', v_party, 'party_user_id', v_topup.client_user_id,
                         'memo','orange money inbound'),
      jsonb_build_object('account', v_liab, 'amount_gnf', -v_event.amount_gnf,
                         'party_type', v_party, 'party_user_id', v_topup.client_user_id,
                         'memo','top-up liability')),
    NULL, v_caller,
    jsonb_build_object('provider','orange_money','provider_transaction_id', v_event.provider_transaction_id),
    (v_env_t = 'sandbox'), NULL, v_event.provider_transaction_id);

  BEGIN
    INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, after, note)
    VALUES (
      v_caller, public.current_admin_role(v_caller),
      'wallet', 'wallet.topup.credit', 'wallet_transaction', v_tx.id::text,
      jsonb_build_object(
        'amount_gnf', v_event.amount_gnf,
        'reference', v_topup.reference,
        'event_id', v_event.id,
        'topup_request_id', v_topup.id,
        'target_party_type', v_party,
        'environment', v_env_t
      ),
      'Orange Money top-up credited'
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN v_tx;
END;
$function$;

REVOKE ALL ON FUNCTION public.wallet_topup_om_credit(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.om_auto_match(uuid) FROM PUBLIC, anon, authenticated;