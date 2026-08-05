CREATE OR REPLACE FUNCTION public.driver_mission_commission_capture(
  p_source_module text, p_source_id uuid, p_final_value_gnf bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_h public.mission_financial_holds;
  v_snap jsonb; v_due bigint; v_capture bigint; v_excess bigint;
  v_cp bigint := 0; v_cu bigint := 0; v_rp bigint := 0; v_ru bigint := 0;
  v_dw public.wallets; v_master public.wallets; v_tx public.wallet_transactions;
BEGIN
  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'commission'
   FOR UPDATE;
  IF v_h.id IS NULL THEN RETURN jsonb_build_object('status','no_hold','captured_gnf',0); END IF;
  IF v_h.driver_user_id <> COALESCE(v_caller, v_h.driver_user_id)
     AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_h.state <> 'held' THEN
    RETURN jsonb_build_object('status','already_resolved','captured_gnf',v_h.captured_gnf);
  END IF;

  v_snap := v_h.policy_snapshot;
  v_due := (GREATEST(COALESCE(p_final_value_gnf,0),0) * COALESCE((v_snap->>'commission_bps')::int,0)) / 10000
           + COALESCE((v_snap->>'fixed_commission_gnf')::bigint,0);
  v_capture := LEAST(v_due, v_h.amount_gnf);
  v_excess := v_h.amount_gnf - v_capture;

  v_cp := LEAST(v_h.promo_gnf, v_capture);
  v_cu := v_capture - v_cp;
  v_rp := v_h.promo_gnf - v_cp;
  v_ru := v_excess - v_rp;

  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_h.amount_gnf, 0), updated_at = now()
   WHERE id = v_dw.id;

  IF v_capture > 0 THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_capture, updated_at = now() WHERE id = v_dw.id;
    IF v_master.id IS NOT NULL THEN
      UPDATE public.wallets SET balance_gnf = balance_gnf + v_capture, updated_at = now() WHERE id = v_master.id;
    END IF;
    IF v_cp > 0 THEN PERFORM public._promo_consume(v_h.driver_user_id, v_cp); END IF;
  END IF;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES
    (format('mfh-capture:%s:%s', p_source_module, p_source_id), 'commission', 'completed',
     GREATEST(v_capture,1), v_dw.id, v_master.id, v_h.driver_user_id,
     p_source_module || ':' || p_source_id::text, 'Commission CHOPCHOP',
     jsonb_build_object('mission_type', v_h.mission_type, 'final_value_gnf', p_final_value_gnf,
                        'reserved_gnf', v_h.amount_gnf, 'captured_gnf', v_capture,
                        'released_excess_gnf', v_excess, 'promo_consumed_gnf', v_cp,
                        'unrestricted_consumed_gnf', v_cu, 'is_sandbox', v_h.is_sandbox), now())
  RETURNING * INTO v_tx;

  UPDATE public.wallet_transactions SET status = 'completed', completed_at = now()
   WHERE id = v_h.hold_tx_id AND status = 'pending';

  IF v_capture > 0 THEN
    PERFORM public._ledger_post(
      format('mfh-capture:%s:%s:commission', p_source_module, p_source_id),
      p_source_module, p_source_id, 'capture_commission',
      jsonb_build_array(
        jsonb_build_object('account','L_HOLD_COMMISSION','amount_gnf',v_capture,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','consume commission hold'),
        jsonb_build_object('account','R_COMMISSION','amount_gnf',-v_capture,'memo','commission revenue')),
      v_h.mission_type, v_caller, v_snap, v_h.is_sandbox);
  END IF;

  IF v_excess > 0 THEN
    PERFORM public._ledger_post(
      format('mfh-release:%s:%s:commission', p_source_module, p_source_id),
      p_source_module, p_source_id, 'release_commission',
      jsonb_build_array(
        jsonb_build_object('account','L_HOLD_COMMISSION','amount_gnf',v_excess,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','release excess reserve'),
        jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',-v_rp,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored to restricted credit'),
        jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_ru,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored to unrestricted')),
      v_h.mission_type, v_caller, v_snap, v_h.is_sandbox);
  END IF;

  UPDATE public.mission_financial_holds
     SET state = 'captured', captured_gnf = v_capture, released_gnf = v_excess,
         resolution_tx_id = v_tx.id, resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','captured','captured_gnf',v_capture,
                            'promo_consumed_gnf',v_cp,'unrestricted_consumed_gnf',v_cu,
                            'released_excess_gnf',v_excess);
END;
$$;

CREATE OR REPLACE FUNCTION public.driver_mission_fee_capture(
  p_source_module text, p_source_id uuid, p_final_fee_basis_gnf bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid(); v_h public.mission_financial_holds;
  v_due bigint; v_cap bigint; v_ex bigint;
  v_cp bigint; v_cu bigint; v_rp bigint; v_ru bigint;
  v_dw public.wallets; v_master public.wallets;
BEGIN
  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'platform_fee' FOR UPDATE;
  IF v_h.id IS NULL THEN RETURN jsonb_build_object('status','no_hold','captured_gnf',0); END IF;
  IF v_h.driver_user_id <> COALESCE(v_caller, v_h.driver_user_id)
     AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_h.state <> 'held' THEN RETURN jsonb_build_object('status','already_resolved','captured_gnf',v_h.captured_gnf); END IF;

  v_due := CASE WHEN p_final_fee_basis_gnf IS NULL THEN v_h.amount_gnf
           ELSE (GREATEST(p_final_fee_basis_gnf,0) *
                 COALESCE((v_h.policy_snapshot->>'transaction_fee_bps')::int,0)) / 10000 END;
  v_cap := LEAST(v_due, v_h.amount_gnf);
  v_ex := v_h.amount_gnf - v_cap;
  v_cp := LEAST(v_h.promo_gnf, v_cap); v_cu := v_cap - v_cp;
  v_rp := v_h.promo_gnf - v_cp; v_ru := v_ex - v_rp;

  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_h.amount_gnf,0), updated_at = now() WHERE id = v_dw.id;
  IF v_cap > 0 THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_cap, updated_at = now() WHERE id = v_dw.id;
    IF v_master.id IS NOT NULL THEN
      UPDATE public.wallets SET balance_gnf = balance_gnf + v_cap, updated_at = now() WHERE id = v_master.id;
    END IF;
    IF v_cp > 0 THEN PERFORM public._promo_consume(v_h.driver_user_id, v_cp); END IF;
    PERFORM public._ledger_post(
      format('mfh-capture:%s:%s:platform_fee', p_source_module, p_source_id),
      p_source_module, p_source_id, 'capture_platform_fee',
      jsonb_build_array(
        jsonb_build_object('account','L_HOLD_PLATFORM_FEE','amount_gnf',v_cap,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','fee reserve consumed'),
        jsonb_build_object('account','R_TRANSACTION_FEE','amount_gnf',-v_cap,'memo','transaction fee revenue')),
      v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox);
  END IF;
  IF v_ex > 0 THEN
    PERFORM public._ledger_post(
      format('mfh-release:%s:%s:platform_fee', p_source_module, p_source_id),
      p_source_module, p_source_id, 'release_platform_fee',
      jsonb_build_array(
        jsonb_build_object('account','L_HOLD_PLATFORM_FEE','amount_gnf',v_ex,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','excess fee reserve'),
        jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',-v_rp,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored restricted'),
        jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_ru,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored unrestricted')),
      v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox);
  END IF;

  UPDATE public.wallet_transactions SET status='completed', completed_at=now()
   WHERE id = v_h.hold_tx_id AND status='pending';
  UPDATE public.mission_financial_holds
     SET state='captured', captured_gnf = v_cap, released_gnf = v_ex,
         resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','captured','captured_gnf',v_cap,'released_gnf',v_ex);
END;
$$;