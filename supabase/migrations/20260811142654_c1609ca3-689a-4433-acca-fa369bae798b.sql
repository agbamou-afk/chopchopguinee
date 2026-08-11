-- =====================================================================
-- Slice 10 — Staged activation: independent SERVER-side stage gates.
-- Uses ONLY existing canonical flags. No umbrella flag is consulted.
-- =====================================================================

-- ---------- Stage 6: driver payout ----------
CREATE OR REPLACE FUNCTION public.driver_cashout_create_request(p_amount_gnf bigint, p_payout_phone text, p_driver_note text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_wallet public.wallets;
  v_pending_total bigint;
  v_available bigint;
  v_promo_avail bigint;
  v_id uuid;
  v_phone text := trim(coalesce(p_payout_phone,''));
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  -- Stage 6 gate (independent; never implied by any other stage).
  IF NOT public._finance_flag('driver_cashout_enabled') THEN
    RAISE EXCEPTION 'STAGE_DISABLED:driver_cashout_enabled';
  END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
  IF p_amount_gnf % 5000 <> 0 THEN RAISE EXCEPTION 'amount_must_be_multiple_of_5000'; END IF;
  IF length(v_phone) < 8 THEN RAISE EXCEPTION 'invalid_payout_phone'; END IF;

  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = v_uid AND party_type = 'driver' FOR UPDATE;
  IF v_wallet.id IS NULL THEN RAISE EXCEPTION 'driver_wallet_not_found'; END IF;

  v_promo_avail := (public.driver_promo_balance(v_uid)->>'promo_available_gnf')::bigint;
  v_available := GREATEST(0, v_wallet.balance_gnf - v_wallet.held_gnf - v_promo_avail);

  SELECT COALESCE(SUM(amount_gnf), 0) INTO v_pending_total
    FROM public.driver_cashout_requests
   WHERE driver_user_id = v_uid AND status IN ('pending','approved');

  IF (v_pending_total + p_amount_gnf) > v_available THEN
    RAISE EXCEPTION 'insufficient_available_balance';
  END IF;

  INSERT INTO public.driver_cashout_requests
    (driver_user_id, wallet_id, amount_gnf, payout_phone, driver_note)
  VALUES (v_uid, v_wallet.id, p_amount_gnf, v_phone,
          NULLIF(trim(coalesce(p_driver_note,'')),''))
  RETURNING id INTO v_id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'wallet', 'driver_cashout_requested', 'driver_cashout_request', v_id::text,
          jsonb_build_object('amount_gnf', p_amount_gnf, 'payout_phone', v_phone,
                             'promo_excluded_gnf', v_promo_avail));
  RETURN v_id;
END;
$function$;

-- Payout execution: gate + all existing invariants preserved.
CREATE OR REPLACE FUNCTION public.driver_cashout_mark_paid(p_id uuid, p_provider_reference text, p_admin_note text DEFAULT NULL::text)
 RETURNS driver_cashout_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_req public.driver_cashout_requests;
  v_wallet public.wallets;
  v_available bigint;
  v_ref text;
  v_tx_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT public.can_manage_wallet(v_uid) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;
  IF NOT public._finance_flag('driver_cashout_enabled') THEN
    RAISE EXCEPTION 'STAGE_DISABLED:driver_cashout_enabled';
  END IF;
  IF p_provider_reference IS NULL OR length(trim(p_provider_reference)) = 0 THEN
    RAISE EXCEPTION 'provider_reference_required';
  END IF;

  SELECT * INTO v_req FROM public.driver_cashout_requests WHERE id = p_id FOR UPDATE;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_req.status = 'paid' THEN RETURN v_req; END IF;
  IF v_req.status NOT IN ('pending','approved') THEN
    RAISE EXCEPTION 'not_payable';
  END IF;

  SELECT * INTO v_wallet FROM public.wallets WHERE id = v_req.wallet_id FOR UPDATE;
  IF v_wallet.id IS NULL THEN RAISE EXCEPTION 'driver_wallet_not_found'; END IF;

  v_available := GREATEST(0, v_wallet.balance_gnf - v_wallet.held_gnf);
  IF v_available < v_req.amount_gnf THEN
    RAISE EXCEPTION 'insufficient_balance_at_payout';
  END IF;

  UPDATE public.wallets
     SET balance_gnf = balance_gnf - v_req.amount_gnf
   WHERE id = v_wallet.id;

  v_ref := 'CC-CO-' || upper(substring(replace(gen_random_uuid()::text,'-',''),1,10));

  INSERT INTO public.wallet_transactions (
    reference, type, status, amount_gnf,
    from_wallet_id, to_wallet_id, related_user_id, related_entity,
    description, completed_at, metadata
  ) VALUES (
    v_ref, 'payout', 'completed', v_req.amount_gnf,
    v_wallet.id, NULL, v_req.driver_user_id,
    'driver_cashout_request:' || v_req.id::text,
    'Versement chauffeur via Orange Money', now(),
    jsonb_build_object(
      'provider_reference', p_provider_reference,
      'payout_phone', v_req.payout_phone,
      'cashout_request_id', v_req.id
    )
  ) RETURNING id INTO v_tx_id;

  UPDATE public.driver_cashout_requests
     SET status = 'paid',
         provider_reference = p_provider_reference,
         admin_note = COALESCE(NULLIF(trim(coalesce(p_admin_note,'')),''), admin_note),
         paid_by = v_uid,
         paid_at = now(),
         reviewed_by = COALESCE(reviewed_by, v_uid),
         reviewed_at = COALESCE(reviewed_at, now()),
         wallet_transaction_id = v_tx_id
   WHERE id = v_req.id
  RETURNING * INTO v_req;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'wallet', 'driver_cashout_paid', 'driver_cashout_request', v_req.id::text,
          jsonb_build_object('amount_gnf', v_req.amount_gnf,
                             'provider_reference', p_provider_reference,
                             'wallet_transaction_id', v_tx_id));

  RETURN v_req;
END;
$function$;

-- ---------- Stage 7: P2P ----------
CREATE OR REPLACE FUNCTION public.wallet_p2p_transfer(p_recipient_user_id uuid, p_amount_gnf bigint, p_note text DEFAULT NULL::text, p_idempotency_key text DEFAULT NULL::text)
 RETURNS wallet_transactions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tx public.wallet_transactions;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  -- Stage 7 gate: P2P stays dormant until separately reviewed/approved.
  IF NOT public._finance_flag('chop_pay_p2p_enabled') THEN
    RAISE EXCEPTION 'STAGE_DISABLED:chop_pay_p2p_enabled';
  END IF;
  SELECT * INTO v_tx FROM public.wallet_p2p_transfer_exec(
    p_recipient_user_id, p_amount_gnf, p_note, p_idempotency_key);
  RETURN v_tx;
END;
$function$;

-- ---------- Stage 5: merchant OM settlement (money-out point) ----------
CREATE OR REPLACE FUNCTION public.merchant_settlement_complete(p_payable_id uuid, p_evidence_ref text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public._finance_flag('merchant_om_settlement_enabled') THEN
    RAISE EXCEPTION 'STAGE_DISABLED:merchant_om_settlement_enabled';
  END IF;
  RETURN public.merchant_settlement_complete_exec(p_payable_id, p_evidence_ref);
END;
$function$;
