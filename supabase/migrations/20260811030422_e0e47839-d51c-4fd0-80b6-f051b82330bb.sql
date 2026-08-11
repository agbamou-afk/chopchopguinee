-- =========================================================
-- SLICE 9 — ORANGE MONEY INBOUND RECONCILIATION HARDENING
-- =========================================================

-- 1. SCHEMA -------------------------------------------------
ALTER TABLE public.topup_requests
  ADD COLUMN IF NOT EXISTS environment text NOT NULL DEFAULT 'production',
  ADD COLUMN IF NOT EXISTS review_reason text,
  ADD COLUMN IF NOT EXISTS matched_event_id uuid REFERENCES public.payment_provider_events(id);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'topup_requests_environment_chk') THEN
    ALTER TABLE public.topup_requests
      ADD CONSTRAINT topup_requests_environment_chk
      CHECK (environment IN ('production','sandbox'));
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS topup_requests_credited_provider_tx_uidx
  ON public.topup_requests (provider, matched_provider_transaction_id)
  WHERE status = 'credited'::topup_status AND matched_provider_transaction_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ppe_credited_topup_uidx
  ON public.payment_provider_events (matched_topup_request_id)
  WHERE processing_status = 'credited' AND matched_topup_request_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_topup_requests_env_status
  ON public.topup_requests (environment, status, provider);

-- 2. SANITIZED STAGE HELPER ---------------------------------
CREATE OR REPLACE FUNCTION public._topup_stage(
  p_status text, p_expires_at timestamptz, p_code_at timestamptz, p_tx uuid
) RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN p_status IN ('credited','confirmed') OR p_tx IS NOT NULL THEN 'credited'
    WHEN p_status = 'failed'    THEN 'rejected'
    WHEN p_status = 'cancelled' THEN 'cancelled'
    WHEN p_status = 'expired'   THEN 'expired'
    WHEN p_status = 'needs_review' THEN 'needs_review'
    WHEN p_expires_at IS NOT NULL AND p_expires_at < now() THEN 'expired'
    WHEN p_code_at IS NOT NULL  THEN 'code_submitted_awaiting_receipt'
    ELSE 'awaiting_customer_code'
  END
$$;

-- 3. CANONICAL MATCHER --------------------------------------
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

  PROCEDURE_NOOP boolean;
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

  -- Exact provider reference identity is MANDATORY for any automatic credit.
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

  -- Exact amount
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

  -- Exact payer phone (when both sides carry one)
  SELECT phone INTO v_profile_phone FROM public.profiles WHERE user_id = v_topup.client_user_id;
  v_event_phone := public._normalize_guinea_phone(v_event.payer_phone);
  v_topup_phone := COALESCE(public._normalize_guinea_phone(v_topup.user_phone),
                            public._normalize_guinea_phone(v_profile_phone));
  IF v_event_phone IS NOT NULL AND v_topup_phone IS NOT NULL AND v_event_phone <> v_topup_phone THEN
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

  -- Exact receiving account (when both sides carry one)
  IF v_event.receiving_account_id IS NOT NULL
     AND v_topup.receiving_account_id IS NOT NULL
     AND v_event.receiving_account_id <> v_topup.receiving_account_id THEN
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

  -- Target party must be canonical
  IF COALESCE(v_topup.target_party_type,'client') NOT IN ('client','driver') THEN
    UPDATE public.topup_requests
       SET status = 'needs_review'::topup_status, review_reason = 'target_party_invalid'
     WHERE id = v_topup.id;
    RETURN jsonb_build_object('status','needs_review','reason','target_party_invalid','topup_request_id',v_topup.id);
  END IF;

  -- Fraud guards (unchanged posture)
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

-- 4. CREDIT FUNCTION ----------------------------------------
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
  -- Authorisation: privileged staff OR trusted server role. No anonymous shortcut.
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

  -- Environment isolation
  v_env_e := CASE WHEN v_event.is_sandbox THEN 'sandbox'
                  ELSE COALESCE(NULLIF(btrim(v_event.environment),''),'production') END;
  v_env_t := COALESCE(NULLIF(btrim(v_topup.environment),''),'production');
  IF v_env_e <> v_env_t THEN
    RAISE EXCEPTION 'environment_mismatch:%/%', v_env_e, v_env_t;
  END IF;

  -- Exact facts (defence in depth — matcher already checked)
  IF v_topup.amount_gnf <> v_event.amount_gnf THEN RAISE EXCEPTION 'amount_mismatch'; END IF;

  IF v_topup.customer_om_code_normalized IS NOT NULL
     AND v_event.om_code_normalized IS NOT NULL
     AND v_topup.customer_om_code_normalized <> v_event.om_code_normalized THEN
    RAISE EXCEPTION 'provider_reference_mismatch';
  END IF;

  IF v_event.receiving_account_id IS NOT NULL
     AND v_topup.receiving_account_id IS NOT NULL
     AND v_event.receiving_account_id <> v_topup.receiving_account_id THEN
    RAISE EXCEPTION 'receiving_account_mismatch';
  END IF;

  SELECT phone INTO v_profile_phone FROM public.profiles WHERE user_id = v_topup.client_user_id;
  v_event_phone := public._normalize_guinea_phone(v_event.payer_phone);
  v_topup_phone := COALESCE(public._normalize_guinea_phone(v_topup.user_phone),
                            public._normalize_guinea_phone(v_profile_phone));
  IF v_event_phone IS NOT NULL AND v_topup_phone IS NOT NULL AND v_event_phone <> v_topup_phone THEN
    RAISE EXCEPTION 'payer_phone_mismatch';
  END IF;

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

  -- Inbound top-up = liability increase, never platform revenue.
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

-- 5. CUSTOMER CODE SUBMISSION -------------------------------
CREATE OR REPLACE FUNCTION public.submit_customer_om_code(p_topup_request_id uuid, p_om_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
    PERFORM public.om_auto_match(v_event.id);
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
$function$;

-- 6. REQUESTER STATUS SURFACES ------------------------------
DROP FUNCTION IF EXISTS public.get_my_topup_om_status(uuid);
CREATE FUNCTION public.get_my_topup_om_status(p_topup_id uuid)
RETURNS TABLE(
  id uuid, reference text, amount_gnf bigint, status text, stage text,
  review_reason text, target_party_type text, provider text,
  expires_at timestamptz, customer_om_code_submitted_at timestamptz,
  receiving_label text, receiving_phone text, receiving_instructions text
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT t.id, t.reference, t.amount_gnf, t.status::text,
         public._topup_stage(t.status::text, t.expires_at, t.customer_om_code_submitted_at, t.transaction_id),
         t.review_reason, COALESCE(t.target_party_type,'client'), t.provider,
         t.expires_at, t.customer_om_code_submitted_at,
         a.label, a.phone_e164, a.public_instructions
    FROM public.topup_requests t
    LEFT JOIN public.payment_receiving_accounts a ON a.id = t.receiving_account_id
   WHERE t.id = p_topup_id
     AND t.client_user_id = auth.uid();
$function$;

DROP FUNCTION IF EXISTS public.list_my_topup_requests(integer);
CREATE FUNCTION public.list_my_topup_requests(p_limit integer DEFAULT 20)
RETURNS TABLE(
  id uuid, reference text, amount_gnf bigint, status text, stage text,
  review_reason text, provider text, created_at timestamptz, updated_at timestamptz,
  expires_at timestamptz, confirmed_at timestamptz, cancelled_reason text,
  customer_code_submitted_at timestamptz, receiving_label text, receiving_phone text
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT t.id, t.reference, t.amount_gnf, t.status::text,
         public._topup_stage(t.status::text, t.expires_at, t.customer_om_code_submitted_at, t.transaction_id),
         t.review_reason, t.provider,
         t.created_at, t.updated_at, t.expires_at, t.confirmed_at,
         t.cancelled_reason, t.customer_om_code_submitted_at,
         a.label, a.phone_e164
    FROM public.topup_requests t
    LEFT JOIN public.payment_receiving_accounts a ON a.id = t.receiving_account_id
   WHERE t.client_user_id = auth.uid()
     AND COALESCE(t.target_party_type,'client') = 'client'
   ORDER BY t.created_at DESC
   LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 100));
$function$;

DROP FUNCTION IF EXISTS public.driver_topup_history(integer);
CREATE FUNCTION public.driver_topup_history(p_limit integer DEFAULT 20)
RETURNS TABLE(
  id uuid, reference text, amount_gnf bigint, status text, stage text,
  review_reason text, provider text, created_at timestamptz, confirmed_at timestamptz,
  cancelled_reason text, credited_transaction_id uuid, credited boolean,
  receiving_label text, receiving_phone text
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT t.id, t.reference, t.amount_gnf, t.status::text,
         public._topup_stage(t.status::text, t.expires_at, t.customer_om_code_submitted_at, t.transaction_id),
         t.review_reason, t.provider,
         t.created_at, t.confirmed_at, t.cancelled_reason,
         t.transaction_id,
         (t.transaction_id IS NOT NULL AND t.status IN ('confirmed','credited')),
         a.label, a.phone_e164
    FROM public.topup_requests t
    LEFT JOIN public.payment_receiving_accounts a ON a.id = t.receiving_account_id
   WHERE t.client_user_id = auth.uid()
     AND t.target_party_type = 'driver'
   ORDER BY t.created_at DESC
   LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 100));
$function$;

-- 7. FINANCE CANDIDATE LIST (role-gated, environment-scoped) -
DROP FUNCTION IF EXISTS public.om_pending_topups_for_event(uuid);
CREATE FUNCTION public.om_pending_topups_for_event(p_event_id uuid)
RETURNS TABLE(
  topup_id uuid, reference text, client_user_id uuid, client_phone text, client_name text,
  amount_gnf bigint, target_party_type text, environment text,
  created_at timestamptz, expires_at timestamptz, status text,
  amount_match boolean, phone_match boolean, code_match boolean, account_match boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
BEGIN
  IF v_caller IS NULL OR NOT COALESCE(public.can_manage_wallet(v_caller), false) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;

  RETURN QUERY
  SELECT t.id, t.reference, t.client_user_id, p.phone, p.full_name,
         t.amount_gnf, COALESCE(t.target_party_type,'client'),
         COALESCE(NULLIF(btrim(t.environment),''),'production'),
         t.created_at, t.expires_at, t.status::text,
         (t.amount_gnf = e.amount_gnf),
         (public._normalize_guinea_phone(COALESCE(t.user_phone, p.phone))
            IS NOT DISTINCT FROM public._normalize_guinea_phone(e.payer_phone)),
         (t.customer_om_code_normalized IS NOT NULL
            AND t.customer_om_code_normalized = e.om_code_normalized),
         (t.receiving_account_id IS NOT DISTINCT FROM e.receiving_account_id)
    FROM public.payment_provider_events e
    CROSS JOIN public.topup_requests t
    LEFT JOIN public.profiles p ON p.user_id = t.client_user_id
   WHERE e.id = p_event_id
     AND t.provider = 'orange_money'
     AND t.status::text IN ('pending','matched','needs_review')
     AND COALESCE(NULLIF(btrim(t.environment),''),'production')
         = CASE WHEN e.is_sandbox THEN 'sandbox'
                ELSE COALESCE(NULLIF(btrim(e.environment),''),'production') END
   ORDER BY (t.customer_om_code_normalized = e.om_code_normalized) DESC NULLS LAST,
            (t.amount_gnf = e.amount_gnf) DESC,
            t.created_at DESC
   LIMIT 20;
END;
$function$;

-- 8. PRIVILEGES ---------------------------------------------
REVOKE ALL ON FUNCTION public.om_auto_match(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.wallet_topup_om_credit(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.om_auto_match(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.wallet_topup_om_credit(uuid, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.submit_customer_om_code(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_topup_om_status(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_my_topup_requests(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.driver_topup_history(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.om_pending_topups_for_event(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.wallet_topup_om_create(bigint, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_record_om_receipt(text, bigint, text, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_retry_om_credit(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_mark_om_conflict(uuid, text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.submit_customer_om_code(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_topup_om_status(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_my_topup_requests(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.driver_topup_history(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.om_pending_topups_for_event(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._topup_stage(text, timestamptz, timestamptz, uuid) TO authenticated, service_role;
