CREATE OR REPLACE FUNCTION public.wallet_p2p_transfer(
  p_recipient_user_id uuid,
  p_amount_gnf bigint,
  p_note text DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL
)
RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  c_min_single       constant bigint := 1000;
  c_max_single       constant bigint := 500000;
  c_max_daily_total  constant bigint := 1500000;
  c_max_daily_count  constant integer := 10;

  v_sender    uuid := auth.uid();
  v_from_w    public.wallets;
  v_to_w      public.wallets;
  v_today_sum bigint;
  v_today_cnt integer;
  v_ref       text;
  v_idem      text;
  v_note      text;
  v_tx        public.wallet_transactions;
BEGIN
  IF v_sender IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  -- Slice 10 Stage 7 gate: P2P stays dormant until separately authorized.
  IF NOT public._finance_flag('chop_pay_p2p_enabled') THEN
    RAISE EXCEPTION 'STAGE_DISABLED:chop_pay_p2p_enabled';
  END IF;
  IF p_recipient_user_id IS NULL THEN
    RAISE EXCEPTION 'recipient_required';
  END IF;
  IF p_recipient_user_id = v_sender THEN
    RAISE EXCEPTION 'self_transfer_forbidden';
  END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;
  IF p_amount_gnf < c_min_single THEN
    RAISE EXCEPTION 'p2p_limit_single_min:%', c_min_single;
  END IF;
  IF p_amount_gnf > c_max_single THEN
    RAISE EXCEPTION 'p2p_limit_single_exceeded:%', c_max_single;
  END IF;

  IF public.is_user_banned(p_recipient_user_id) THEN
    RAISE EXCEPTION 'recipient_unavailable';
  END IF;

  INSERT INTO public.wallets (owner_user_id, party_type)
    VALUES (v_sender, 'client')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT * INTO v_from_w FROM public.wallets
    WHERE owner_user_id = v_sender AND party_type = 'client' LIMIT 1;
  IF v_from_w.id IS NULL THEN RAISE EXCEPTION 'sender_wallet_missing'; END IF;
  IF v_from_w.status <> 'active' THEN RAISE EXCEPTION 'sender_wallet_not_active'; END IF;

  INSERT INTO public.wallets (owner_user_id, party_type)
    VALUES (p_recipient_user_id, 'client')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT * INTO v_to_w FROM public.wallets
    WHERE owner_user_id = p_recipient_user_id AND party_type = 'client' LIMIT 1;
  IF v_to_w.id IS NULL THEN RAISE EXCEPTION 'recipient_wallet_missing'; END IF;
  IF v_to_w.status <> 'active' THEN RAISE EXCEPTION 'recipient_wallet_not_active'; END IF;

  IF (COALESCE(v_from_w.balance_gnf,0) - COALESCE(v_from_w.held_gnf,0)) < p_amount_gnf THEN
    RAISE EXCEPTION 'insufficient_funds';
  END IF;

  SELECT COALESCE(SUM(amount_gnf),0), COUNT(*)
    INTO v_today_sum, v_today_cnt
    FROM public.wallet_transactions
   WHERE from_wallet_id = v_from_w.id
     AND status = 'completed'
     AND created_at >= date_trunc('day', now())
     AND metadata->>'source_module' = 'p2p';

  IF v_today_cnt >= c_max_daily_count THEN
    RAISE EXCEPTION 'p2p_limit_daily_count_exceeded:%', c_max_daily_count;
  END IF;
  IF v_today_sum + p_amount_gnf > c_max_daily_total THEN
    RAISE EXCEPTION 'p2p_limit_daily_total_exceeded:%', c_max_daily_total;
  END IF;

  v_note := NULLIF(trim(regexp_replace(COALESCE(p_note,''), E'[\\r\\n\\t]+', ' ', 'g')), '');
  IF v_note IS NOT NULL AND length(v_note) > 140 THEN
    v_note := left(v_note, 140);
  END IF;

  v_idem := NULLIF(trim(p_idempotency_key), '');
  IF v_idem IS NULL THEN
    v_idem := encode(gen_random_bytes(12), 'hex');
  END IF;
  v_ref := 'p2p:' || v_sender::text || ':' || p_recipient_user_id::text || ':' || v_idem;

  v_tx := public.wallet_internal_transfer_v2(
    p_from_wallet_id := v_from_w.id,
    p_to_wallet_id   := v_to_w.id,
    p_amount_gnf     := p_amount_gnf,
    p_reference      := v_ref,
    p_transfer_type  := 'transfer',
    p_description    := COALESCE('Transfert CHOP' || CASE WHEN v_note IS NOT NULL THEN ' — ' || v_note ELSE '' END, 'Transfert CHOP'),
    p_source_module  := 'p2p',
    p_source_id      := v_idem,
    p_metadata       := jsonb_build_object(
      'source_module',       'p2p',
      'sender_user_id',      v_sender,
      'recipient_user_id',   p_recipient_user_id,
      'note',                v_note,
      'idempotency_key',     v_idem,
      'created_by_function', 'wallet_p2p_transfer'
    )
  );

  RETURN v_tx;
END;
$function$;

CREATE OR REPLACE FUNCTION public.merchant_settlement_complete(p_payable_id uuid, p_evidence_ref text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_p public.merchant_payables; v_amount bigint;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  -- Slice 10 Stage 5 gate: outbound settlement requires its own stage flag.
  IF NOT public._finance_flag('merchant_om_settlement_enabled') THEN
    RAISE EXCEPTION 'STAGE_DISABLED:merchant_om_settlement_enabled';
  END IF;
  IF p_evidence_ref IS NULL OR length(btrim(p_evidence_ref)) < 4 THEN
    RAISE EXCEPTION 'SETTLEMENT_EVIDENCE_REQUIRED';
  END IF;
  SELECT * INTO v_p FROM public.merchant_payables WHERE id = p_payable_id FOR UPDATE;
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'Payable not found'; END IF;
  IF v_p.state = 'settled' THEN RETURN jsonb_build_object('status','already_settled'); END IF;
  IF v_p.state <> 'settlement_held' THEN RAISE EXCEPTION 'SETTLEMENT_NOT_HELD'; END IF;
  v_amount := v_p.funded_gnf - v_p.settled_gnf;

  PERFORM public._finance_evidence_claim(p_evidence_ref,'merchant_settlement',v_p.id,v_amount,v_caller);

  IF v_p.merchant_user_id IS NOT NULL THEN
    UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_amount,0),
                              balance_gnf = balance_gnf - v_amount, updated_at = now()
     WHERE owner_user_id = v_p.merchant_user_id AND party_type = 'merchant';
  END IF;

  PERFORM public._ledger_post('settle-paid:' || v_p.id::text, 'merchant_settlement', v_p.id,
    'merchant_settlement_paid',
    jsonb_build_array(
      jsonb_build_object('account','L_HOLD_SETTLEMENT','amount_gnf',v_amount,
                         'party_type','merchant','merchant_store_id',v_p.merchant_store_id,'memo','settlement released'),
      jsonb_build_object('account','A_PROVIDER_CLEARING','amount_gnf',-v_amount,'memo','paid out to provider')),
    v_p.mission_type, v_caller, v_p.policy_snapshot, v_p.is_sandbox, p_evidence_ref);

  UPDATE public.merchant_payables
     SET settled_gnf = settled_gnf + v_amount, state = 'settled', evidence_ref = p_evidence_ref,
         resolved_by = v_caller, resolved_at = now(), updated_at = now()
   WHERE id = v_p.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller,'wallet','merchant_settlement_paid','merchant_payable',v_p.id::text,
          jsonb_build_object('amount_gnf',v_amount,'evidence_ref',p_evidence_ref), p_evidence_ref);

  RETURN jsonb_build_object('status','settled','amount_gnf',v_amount);
END; $$;

-- Privilege posture: anon must never reach payout / transfer rails.
REVOKE EXECUTE ON FUNCTION public.wallet_p2p_transfer(uuid,bigint,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.wallet_p2p_lookup_recipient(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.driver_cashout_create_request(bigint,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.driver_cashout_cancel_request(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.driver_cashout_mark_paid(uuid,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.driver_cashout_reject_request(uuid,text) FROM anon;
