-- 1. Explicit target wallet on topup_requests (legacy rows resolve as client)
ALTER TABLE public.topup_requests
  ADD COLUMN IF NOT EXISTS target_party_type text NOT NULL DEFAULT 'client';

DO $$ BEGIN
  ALTER TABLE public.topup_requests
    ADD CONSTRAINT topup_requests_target_party_type_chk
    CHECK (target_party_type IN ('client','driver'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

UPDATE public.topup_requests SET target_party_type = 'client' WHERE target_party_type IS NULL;

-- 2. Customer top-up: unchanged semantics, now explicit
CREATE OR REPLACE FUNCTION public.wallet_topup_om_create(p_amount_gnf bigint, p_receiving_account_id uuid DEFAULT NULL::uuid)
 RETURNS topup_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_wallet public.wallets;
  v_phone text;
  v_ref text;
  v_row public.topup_requests;
  v_acct public.payment_receiving_accounts;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_amount_gnf <= 0 THEN RAISE EXCEPTION 'Invalid amount'; END IF;
  IF p_amount_gnf < 1000 THEN RAISE EXCEPTION 'Minimum top-up is 1000 GNF'; END IF;
  IF p_amount_gnf > 50000000 THEN RAISE EXCEPTION 'Maximum top-up is 50,000,000 GNF'; END IF;

  IF p_receiving_account_id IS NOT NULL THEN
    SELECT * INTO v_acct FROM public.payment_receiving_accounts
      WHERE id = p_receiving_account_id AND is_active = true;
  ELSE
    SELECT * INTO v_acct FROM public.payment_receiving_accounts
      WHERE provider = 'orange_money' AND is_active = true
      ORDER BY updated_at DESC LIMIT 1;
  END IF;
  IF v_acct.id IS NULL THEN
    RAISE EXCEPTION 'No active Orange Money receiving account configured';
  END IF;

  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = v_uid AND party_type = 'client'
   LIMIT 1;
  IF v_wallet.id IS NULL THEN RAISE EXCEPTION 'Wallet not found'; END IF;
  IF v_wallet.status <> 'active' THEN RAISE EXCEPTION 'Wallet is not active'; END IF;

  SELECT phone INTO v_phone FROM public.profiles WHERE user_id = v_uid LIMIT 1;
  v_ref := public.gen_topup_reference();

  INSERT INTO public.topup_requests (
    reference, client_user_id, agent_user_id, amount_gnf,
    confirmation_code, provider, user_phone, status, expires_at,
    receiving_account_id, target_party_type
  ) VALUES (
    v_ref, v_uid, NULL, p_amount_gnf,
    '------', 'orange_money', v_phone, 'pending'::topup_status, now() + interval '24 hours',
    v_acct.id, 'client'
  ) RETURNING * INTO v_row;

  RETURN v_row;
END;
$function$;

-- 3. Driver-targeted top-up request (self only, approved driver, active driver wallet)
CREATE OR REPLACE FUNCTION public.driver_wallet_topup_om_create(p_amount_gnf bigint, p_receiving_account_id uuid DEFAULT NULL::uuid)
 RETURNS topup_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_wallet public.wallets;
  v_phone text;
  v_ref text;
  v_row public.topup_requests;
  v_acct public.payment_receiving_accounts;
  v_status text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_amount_gnf <= 0 THEN RAISE EXCEPTION 'Invalid amount'; END IF;
  IF p_amount_gnf < 1000 THEN RAISE EXCEPTION 'Minimum top-up is 1000 GNF'; END IF;
  IF p_amount_gnf > 50000000 THEN RAISE EXCEPTION 'Maximum top-up is 50,000,000 GNF'; END IF;

  SELECT dp.status::text INTO v_status FROM public.driver_profiles dp WHERE dp.user_id = v_uid;
  IF v_status IS NULL THEN RAISE EXCEPTION 'driver_profile_not_found' USING ERRCODE='42501'; END IF;
  IF v_status <> 'approved' THEN RAISE EXCEPTION 'driver_not_approved' USING ERRCODE='42501'; END IF;
  IF NOT public._driver_finance_eligible(v_uid) THEN
    RAISE EXCEPTION 'driver_restricted' USING ERRCODE='42501';
  END IF;

  IF p_receiving_account_id IS NOT NULL THEN
    SELECT * INTO v_acct FROM public.payment_receiving_accounts
      WHERE id = p_receiving_account_id AND is_active = true;
  ELSE
    SELECT * INTO v_acct FROM public.payment_receiving_accounts
      WHERE provider = 'orange_money' AND is_active = true
      ORDER BY updated_at DESC LIMIT 1;
  END IF;
  IF v_acct.id IS NULL THEN
    RAISE EXCEPTION 'No active Orange Money receiving account configured';
  END IF;

  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = v_uid AND party_type = 'driver' LIMIT 1;
  IF v_wallet.id IS NULL THEN RAISE EXCEPTION 'driver_wallet_not_found'; END IF;
  IF v_wallet.status <> 'active' THEN RAISE EXCEPTION 'driver_wallet_not_active'; END IF;

  SELECT phone INTO v_phone FROM public.profiles WHERE user_id = v_uid LIMIT 1;
  v_ref := public.gen_topup_reference();

  INSERT INTO public.topup_requests (
    reference, client_user_id, agent_user_id, amount_gnf,
    confirmation_code, provider, user_phone, status, expires_at,
    receiving_account_id, target_party_type
  ) VALUES (
    v_ref, v_uid, NULL, p_amount_gnf,
    '------', 'orange_money', v_phone, 'pending'::topup_status, now() + interval '24 hours',
    v_acct.id, 'driver'
  ) RETURNING * INTO v_row;

  RETURN v_row;
END;
$function$;

REVOKE ALL ON FUNCTION public.driver_wallet_topup_om_create(bigint, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_wallet_topup_om_create(bigint, uuid) TO authenticated, service_role;

-- 4. Credit the explicitly targeted wallet
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
BEGIN
  IF v_caller IS NOT NULL AND NOT COALESCE(public.can_manage_wallet(v_caller), false) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

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
  IF v_topup.amount_gnf <> v_event.amount_gnf THEN
    RAISE EXCEPTION 'amount_mismatch';
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
      'target_party_type', v_party
    )
  ) RETURNING * INTO v_tx;

  UPDATE public.topup_requests
     SET status = 'credited'::topup_status,
         confirmed_at = now(),
         transaction_id = v_tx.id,
         matched_provider_transaction_id = v_event.provider_transaction_id
   WHERE id = v_topup.id;

  UPDATE public.payment_provider_events
     SET processing_status = 'credited',
         matched_user_id = v_topup.client_user_id,
         matched_topup_request_id = v_topup.id,
         processed_at = now()
   WHERE id = v_event.id;

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
        'target_party_type', v_party
      ),
      'Orange Money top-up credited'
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN v_tx;
END;
$function$;