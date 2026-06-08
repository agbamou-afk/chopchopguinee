
-- =====================================================================
-- OM RECONCILIATION TRUST FIX
-- Root cause: wallet_topup_om_credit used has_app_role / has_role,
-- which do not recognize 'super_admin' rows in admin_users. The credit
-- silently raised 'Not authorized' and was swallowed by the outer
-- EXCEPTION block, leaving events in 'received' state and topups
-- 'matched' but never credited. This migration:
--   1. Aligns wallet_topup_om_credit on can_manage_wallet().
--   2. Adds idempotency to prevent double credit per event.
--   3. Adds explicit credit_failed surfacing in om_auto_match and
--      admin_record_om_receipt (no more silent swallow).
--   4. Fixes audit_logs column names in admin_record_om_receipt.
--   5. Adds admin RPCs: admin_retry_om_credit, admin_mark_om_conflict.
-- RLS on payment_provider_events is UNCHANGED (admins only via SECURITY
-- DEFINER RPCs); no broad INSERT policy added.
-- =====================================================================

-- 1) Idempotency guards ------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS payment_provider_events_provider_tx_uidx
  ON public.payment_provider_events (provider, provider_transaction_id);

CREATE UNIQUE INDEX IF NOT EXISTS wallet_transactions_om_event_uidx
  ON public.wallet_transactions ((metadata->>'event_id'))
  WHERE type = 'topup' AND (metadata ? 'event_id');

-- 2) Fix wallet_topup_om_credit authorization + audit ------------------
CREATE OR REPLACE FUNCTION public.wallet_topup_om_credit(p_event_id uuid, p_topup_request_id uuid)
RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_event public.payment_provider_events;
  v_topup public.topup_requests;
  v_client_wallet public.wallets;
  v_master public.wallets;
  v_tx public.wallet_transactions;
  v_ref text;
BEGIN
  -- Allow service_role (no auth.uid()) OR anyone authorized for wallet ops.
  IF v_caller IS NOT NULL AND NOT COALESCE(public.can_manage_wallet(v_caller), false) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_event FROM public.payment_provider_events WHERE id = p_event_id FOR UPDATE;
  IF v_event.id IS NULL THEN RAISE EXCEPTION 'event_not_found'; END IF;
  IF v_event.processing_status = 'credited' THEN
    -- Idempotent: return the existing wallet transaction if we can find it.
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

  SELECT * INTO v_client_wallet FROM public.wallets
    WHERE owner_user_id = v_topup.client_user_id AND party_type = 'client' FOR UPDATE;
  IF v_client_wallet.id IS NULL THEN RAISE EXCEPTION 'client_wallet_not_found'; END IF;
  IF v_client_wallet.status <> 'active' THEN RAISE EXCEPTION 'wallet_not_active'; END IF;

  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
  IF v_master.id IS NULL THEN RAISE EXCEPTION 'master_wallet_not_found'; END IF;

  UPDATE public.wallets SET balance_gnf = balance_gnf + v_event.amount_gnf WHERE id = v_client_wallet.id;
  UPDATE public.wallets SET balance_gnf = balance_gnf - v_event.amount_gnf WHERE id = v_master.id;

  v_ref := 'CC-OM-' || upper(substring(replace(gen_random_uuid()::text,'-',''),1,10));

  INSERT INTO public.wallet_transactions (
    reference, type, status, amount_gnf,
    from_wallet_id, to_wallet_id, related_user_id, related_entity,
    description, completed_at, metadata
  ) VALUES (
    v_ref, 'topup', 'completed', v_event.amount_gnf,
    v_master.id, v_client_wallet.id, v_topup.client_user_id,
    'orange_money:' || v_event.provider_transaction_id,
    'Recharge Orange Money ' || v_topup.reference, now(),
    jsonb_build_object(
      'event_id', v_event.id,
      'topup_request_id', v_topup.id,
      'provider_transaction_id', v_event.provider_transaction_id,
      'payer_phone', v_event.payer_phone
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
        'topup_request_id', v_topup.id
      ),
      'Orange Money top-up credited'
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN v_tx;
END;
$$;

REVOKE ALL ON FUNCTION public.wallet_topup_om_credit(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.wallet_topup_om_credit(uuid, uuid) TO authenticated, service_role;

-- 3) Fix admin_record_om_receipt: surface credit failures, fix audit ---
CREATE OR REPLACE FUNCTION public.admin_record_om_receipt(
  p_provider_transaction_id text,
  p_amount_gnf bigint,
  p_payer_phone text DEFAULT NULL,
  p_receiving_account_id uuid DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_tx text;
  v_event_id uuid;
  v_was_duplicate boolean := false;
  v_account public.payment_receiving_accounts%ROWTYPE;
  v_match jsonb;
  v_payload jsonb;
  v_err text;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'unauthenticated' USING ERRCODE='28000'; END IF;
  IF NOT COALESCE(public.can_manage_wallet(v_caller), false) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;

  v_tx := upper(btrim(coalesce(p_provider_transaction_id,'')));
  IF length(v_tx) < 3 THEN RAISE EXCEPTION 'invalid_tx_id' USING ERRCODE='22023'; END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN RAISE EXCEPTION 'invalid_amount' USING ERRCODE='22023'; END IF;

  IF p_receiving_account_id IS NOT NULL THEN
    SELECT * INTO v_account FROM public.payment_receiving_accounts WHERE id = p_receiving_account_id;
  END IF;

  v_payload := jsonb_build_object(
    'source','admin_manual_entry',
    'note', p_note,
    'recorded_by', v_caller,
    'receiving_account_id', p_receiving_account_id,
    'receiving_phone', v_account.phone_e164,
    'receiving_label', v_account.label
  );

  SELECT id INTO v_event_id FROM public.payment_provider_events
   WHERE provider='orange_money' AND provider_transaction_id = v_tx;

  IF v_event_id IS NOT NULL THEN
    v_was_duplicate := true;
  ELSE
    INSERT INTO public.payment_provider_events (
      provider, event_type, provider_transaction_id, payer_phone,
      amount_gnf, status, processing_status, raw_payload, receiving_account_id
    ) VALUES (
      'orange_money','payment.received', v_tx,
      NULLIF(btrim(coalesce(p_payer_phone,'')),''),
      p_amount_gnf, 'successful','received', v_payload, p_receiving_account_id
    ) RETURNING id INTO v_event_id;
  END IF;

  BEGIN
    INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, after, note)
    VALUES (
      v_caller, public.current_admin_role(v_caller), 'wallet',
      'om.receipt.record', 'payment_provider_event', v_event_id::text,
      jsonb_build_object('tx', v_tx, 'amount_gnf', p_amount_gnf, 'duplicate', v_was_duplicate),
      p_note
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  IF v_was_duplicate THEN
    v_match := jsonb_build_object('status','duplicate','event_id', v_event_id);
  ELSE
    BEGIN
      SELECT public.om_auto_match(v_event_id) INTO v_match;
    EXCEPTION WHEN OTHERS THEN
      v_err := SQLERRM;
      UPDATE public.payment_provider_events
         SET processing_status = 'credit_failed',
             notes = coalesce(notes,'') || ' | credit_error: ' || v_err
       WHERE id = v_event_id;
      v_match := jsonb_build_object('status','credit_failed','error', v_err);
      BEGIN
        INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, after, note)
        VALUES (v_caller, public.current_admin_role(v_caller),'wallet',
          'om.credit.failed','payment_provider_event', v_event_id::text,
          jsonb_build_object('error', v_err), p_note);
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END;
  END IF;

  RETURN jsonb_build_object(
    'event_id', v_event_id,
    'duplicate', v_was_duplicate,
    'match', v_match
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_record_om_receipt(text, bigint, text, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_record_om_receipt(text, bigint, text, uuid, text) TO authenticated;

-- 4) Admin retry credit (for credit_failed / parked rows) --------------
CREATE OR REPLACE FUNCTION public.admin_retry_om_credit(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_match jsonb;
  v_err text;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'unauthenticated' USING ERRCODE='28000'; END IF;
  IF NOT COALESCE(public.can_manage_wallet(v_caller), false) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;

  UPDATE public.payment_provider_events
     SET processing_status = 'received',
         notes = coalesce(notes,'') || ' | admin_retry'
   WHERE id = p_event_id
     AND processing_status IN ('credit_failed','needs_review','received');

  BEGIN
    SELECT public.om_auto_match(p_event_id) INTO v_match;
  EXCEPTION WHEN OTHERS THEN
    v_err := SQLERRM;
    UPDATE public.payment_provider_events
       SET processing_status = 'credit_failed',
           notes = coalesce(notes,'') || ' | retry_error: ' || v_err
     WHERE id = p_event_id;
    INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, after, note)
    VALUES (v_caller, public.current_admin_role(v_caller),'wallet','om.credit.retry.failed',
      'payment_provider_event', p_event_id::text, jsonb_build_object('error', v_err), NULL);
    RETURN jsonb_build_object('status','credit_failed','error', v_err);
  END;

  BEGIN
    INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, after, note)
    VALUES (v_caller, public.current_admin_role(v_caller),'wallet','om.credit.retry',
      'payment_provider_event', p_event_id::text, v_match, NULL);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN v_match;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_retry_om_credit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_retry_om_credit(uuid) TO authenticated;

-- 5) Admin mark conflict --------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_mark_om_conflict(p_event_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_caller uuid := auth.uid();
BEGIN
  IF v_caller IS NULL OR NOT COALESCE(public.can_manage_wallet(v_caller), false) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;
  UPDATE public.payment_provider_events
     SET processing_status = 'rejected',
         notes = coalesce(notes,'') || ' | admin_conflict: ' || coalesce(p_reason,'(no reason)'),
         processed_at = now()
   WHERE id = p_event_id;
  BEGIN
    INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, note)
    VALUES (v_caller, public.current_admin_role(v_caller),'wallet','om.conflict.mark',
      'payment_provider_event', p_event_id::text, p_reason);
  EXCEPTION WHEN OTHERS THEN NULL; END;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_mark_om_conflict(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_mark_om_conflict(uuid, text) TO authenticated;
