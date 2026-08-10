CREATE OR REPLACE FUNCTION public._merchant_payable_reverse_internal(p_source_module text, p_source_id uuid, p_merchant_store_id uuid, p_beneficiary uuid, p_reason text, p_actor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p public.merchant_payables; v_amount bigint; v_mw public.wallets; v_dw public.wallets;
  v_driver uuid;
BEGIN
  SELECT driver_user_id INTO v_driver FROM public.cash_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id;
  IF v_driver IS NULL THEN
    RETURN jsonb_build_object('status','reconciliation_required','reversed_gnf',0,
                              'detail','no cash order runtime for source');
  END IF;
  IF p_beneficiary IS NULL OR p_beneficiary <> v_driver THEN
    RAISE EXCEPTION 'BENEFICIARY_MISMATCH'
      USING DETAIL = 'reversal beneficiary must be the cash order driver';
  END IF;

  SELECT * INTO v_p FROM public.merchant_payables
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND merchant_store_id = p_merchant_store_id FOR UPDATE;
  IF v_p.id IS NULL THEN RETURN jsonb_build_object('status','no_payable','reversed_gnf',0); END IF;
  IF v_p.state = 'reversed' THEN
    RETURN jsonb_build_object('status','already_reversed','reversed_gnf',0);
  END IF;
  IF v_p.funded_gnf = 0 THEN
    UPDATE public.merchant_payables
       SET state = 'reversed', reason = COALESCE(p_reason, reason),
           resolved_at = now(), resolved_by = p_actor, updated_at = now()
     WHERE id = v_p.id;
    RETURN jsonb_build_object('status','not_funded','reversed_gnf',0);
  END IF;
  IF v_p.funding_source <> 'driver_cash_funding' THEN
    RETURN jsonb_build_object('status','reconciliation_required','reversed_gnf',0,
                              'detail','funding source is not driver cash funding');
  END IF;
  IF v_p.settled_gnf > 0 OR v_p.state IN ('settled','settlement_held') THEN
    RETURN jsonb_build_object('status','reconciliation_required','reversed_gnf',0,
                              'detail','payable already settled externally');
  END IF;

  v_amount := v_p.funded_gnf;

  SELECT * INTO v_mw FROM public.wallets
   WHERE owner_user_id = v_p.merchant_user_id AND party_type = 'merchant' FOR UPDATE;
  IF v_mw.id IS NULL OR (v_mw.balance_gnf - v_mw.held_gnf) < v_amount THEN
    RETURN jsonb_build_object('status','reconciliation_required','reversed_gnf',0,
                              'detail','insufficient recoverable merchant liability');
  END IF;

  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = v_driver AND party_type = 'driver' FOR UPDATE;
  IF v_dw.id IS NULL THEN
    RETURN jsonb_build_object('status','reconciliation_required','reversed_gnf',0,
                              'detail','driver wallet missing');
  END IF;

  UPDATE public.wallets SET balance_gnf = balance_gnf - v_amount, updated_at = now()
   WHERE id = v_mw.id;
  UPDATE public.wallets SET balance_gnf = balance_gnf + v_amount, updated_at = now()
   WHERE id = v_dw.id;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES
    (format('payable-reverse:%s:%s:%s', p_source_module, p_source_id, p_merchant_store_id),
     'adjustment', 'completed', v_amount, v_mw.id, v_dw.id, v_p.merchant_user_id,
     p_source_module || ':' || p_source_id::text,
     'Reprise du financement marchandise (litige)',
     jsonb_build_object('reason', p_reason, 'restored_as','unrestricted',
                        'movement','merchant_payable_reversal',
                        'is_sandbox', v_p.is_sandbox), now());

  PERFORM public._ledger_post(
    format('payable-reverse:%s:%s:%s', p_source_module, p_source_id, p_merchant_store_id),
    p_source_module, p_source_id, 'merchant_payable_reversed',
    jsonb_build_array(
      jsonb_build_object('account','L_MERCHANT_PAYABLE','amount_gnf',v_amount,
                         'party_type','merchant','party_user_id',v_p.merchant_user_id,
                         'memo','reverse merchant liability'),
      jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_amount,
                         'party_type','driver','party_user_id',v_dw.owner_user_id,
                         'memo','restore merchandise principal as unrestricted')),
    v_p.mission_type, p_actor, v_p.policy_snapshot, v_p.is_sandbox);

  UPDATE public.merchant_payables
     SET funded_gnf = 0, state = 'reversed', reason = COALESCE(p_reason, reason),
         resolved_at = now(), resolved_by = p_actor, updated_at = now()
   WHERE id = v_p.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (p_actor, 'finance', 'merchant_payable_reversed', 'merchant_payables', v_p.id::text,
          jsonb_build_object('reversed_gnf', v_amount, 'merchant_user_id', v_p.merchant_user_id,
                             'driver_user_id', v_dw.owner_user_id), p_reason);

  RETURN jsonb_build_object('status','reversed','reversed_gnf',v_amount,
                            'merchant_user_id',v_p.merchant_user_id,
                            'driver_user_id',v_dw.owner_user_id);
END; $function$;

REVOKE ALL ON FUNCTION public._merchant_payable_reverse_internal(text,uuid,uuid,uuid,text,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._merchant_payable_reverse_internal(text,uuid,uuid,uuid,text,uuid) TO service_role;

INSERT INTO public._qa_s4_results (report) SELECT public._qa_s4_run();