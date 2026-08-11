ALTER TABLE public.payment_provider_events
  DROP CONSTRAINT IF EXISTS payment_provider_events_processing_chk;
ALTER TABLE public.payment_provider_events
  ADD CONSTRAINT payment_provider_events_processing_chk
  CHECK (processing_status = ANY (ARRAY['received','matched','credited','needs_review','rejected','duplicate','credit_failed']));

CREATE OR REPLACE FUNCTION public.wallet_topup_om_credit(p_event_id uuid, p_topup_request_id uuid)
RETURNS public.wallet_transactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_caller uuid := auth.uid();
  v_internal boolean := (NULLIF(current_setting('chopchop.om_credit_internal', true), '') = p_event_id::text);
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
  -- One-shot internal marker: set by the matcher entry points immediately before
  -- delegating here. It authorises the CALL only; every piece of provider evidence
  -- below is still revalidated independently at credit time.
  PERFORM set_config('chopchop.om_credit_internal', '', true);

  IF NOT v_internal THEN
    IF v_caller IS NOT NULL THEN
      IF NOT COALESCE(public.can_manage_wallet(v_caller), false) THEN
        RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
      END IF;
    ELSIF current_user NOT IN ('postgres','service_role','supabase_admin','supabase_auth_admin') THEN
      RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;
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
$fn$;

REVOKE ALL ON FUNCTION public.wallet_topup_om_credit(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_topup_om_credit(uuid, uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.submit_customer_om_code(p_topup_request_id uuid, p_om_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_topup public.topup_requests;
  v_norm text;
  v_env text;
  v_event public.payment_provider_events;
  v_event_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  IF p_om_code IS NULL OR length(trim(p_om_code)) = 0 THEN
    RAISE EXCEPTION 'Code Orange Money requis';
  END IF;

  v_norm := public.normalize_om_code(p_om_code);
  IF v_norm IS NULL OR length(v_norm) < 4 THEN RAISE EXCEPTION 'Code Orange Money invalide'; END IF;
  IF length(v_norm) > 40 THEN RAISE EXCEPTION 'Code Orange Money trop long'; END IF;

  SELECT * INTO v_topup FROM public.topup_requests WHERE id = p_topup_request_id FOR UPDATE;
  IF v_topup.id IS NULL THEN RAISE EXCEPTION 'Demande introuvable'; END IF;
  IF v_topup.client_user_id <> v_uid THEN RAISE EXCEPTION 'Non autorisé' USING ERRCODE='42501'; END IF;
  IF v_topup.provider <> 'orange_money' THEN RAISE EXCEPTION 'Demande non Orange Money'; END IF;
  IF v_topup.status::text NOT IN ('pending','matched','needs_review') THEN
    RAISE EXCEPTION 'Cette demande n''est plus active';
  END IF;
  IF v_topup.expires_at < now() THEN RAISE EXCEPTION 'Cette demande a expiré'; END IF;

  v_env := COALESCE(NULLIF(btrim(v_topup.environment),''),'production');

  IF v_topup.customer_om_code_normalized IS NOT NULL
     AND v_topup.customer_om_code_normalized <> v_norm THEN
    RAISE EXCEPTION 'Un code différent a déjà été soumis pour cette demande';
  END IF;

  SELECT count(*) INTO v_event_count FROM public.topup_requests t
   WHERE t.customer_om_code_normalized = v_norm
     AND t.id <> v_topup.id
     AND t.status::text IN ('pending','matched','credited','needs_review');
  IF v_event_count > 0 THEN
    UPDATE public.topup_requests
       SET status='needs_review'::topup_status,
           review_reason = 'duplicate_customer_code',
           customer_om_code_normalized = v_norm,
           customer_om_code_raw = p_om_code,
           customer_om_code_submitted_at = now(),
           notes = coalesce(notes,'') || ' | duplicate_customer_code'
     WHERE id = v_topup.id;
    RETURN jsonb_build_object('status','needs_review','reason','duplicate_customer_code');
  END IF;

  UPDATE public.topup_requests
     SET customer_om_code_normalized = v_norm,
         customer_om_code_raw = p_om_code,
         customer_om_code_submitted_at = now(),
         review_reason = NULL,
         status = CASE WHEN status='pending'::topup_status THEN 'matched'::topup_status ELSE status END
   WHERE id = v_topup.id;

  -- Only consider provider receipts from the SAME environment.
  SELECT count(*) INTO v_event_count
    FROM public.payment_provider_events e
   WHERE e.om_code_normalized = v_norm
     AND e.status = 'successful'
     AND e.processing_status NOT IN ('credited','rejected')
     AND CASE WHEN e.is_sandbox THEN 'sandbox'
              ELSE COALESCE(NULLIF(btrim(e.environment),''),'production') END = v_env;

  IF v_event_count = 1 THEN
    SELECT * INTO v_event FROM public.payment_provider_events e
     WHERE e.om_code_normalized = v_norm
       AND e.status='successful'
       AND e.processing_status NOT IN ('credited','rejected')
       AND CASE WHEN e.is_sandbox THEN 'sandbox'
                ELSE COALESCE(NULLIF(btrim(e.environment),''),'production') END = v_env
     LIMIT 1;
    -- Admin-first reconciliation: the participant triggers the matcher for their own
    -- request. Mark this single event as an internal credit so the credit primitive
    -- accepts the delegated call; it still revalidates all provider evidence itself.
    PERFORM set_config('chopchop.om_credit_internal', v_event.id::text, true);
    BEGIN
      PERFORM public.om_auto_match(v_event.id);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('chopchop.om_credit_internal', '', true);
      RAISE;
    END;
    PERFORM set_config('chopchop.om_credit_internal', '', true);
    RETURN jsonb_build_object('status','attempted_match','event_id', v_event.id);
  ELSIF v_event_count > 1 THEN
    UPDATE public.topup_requests
       SET status='needs_review'::topup_status,
           review_reason='duplicate_provider_event',
           notes = coalesce(notes,'') || ' | duplicate_event_code'
     WHERE id = v_topup.id;
    RETURN jsonb_build_object('status','needs_review','reason','duplicate_provider_event');
  END IF;

  RETURN jsonb_build_object('status','awaiting_admin_receipt');
END;
$fn$;

REVOKE ALL ON FUNCTION public.submit_customer_om_code(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_customer_om_code(uuid, text) TO authenticated, service_role;