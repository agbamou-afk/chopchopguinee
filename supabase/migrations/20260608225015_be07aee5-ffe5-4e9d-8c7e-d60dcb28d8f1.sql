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
  v_allowed boolean;
  v_tx text;
  v_event_id uuid;
  v_was_duplicate boolean := false;
  v_account public.payment_receiving_accounts%ROWTYPE;
  v_match jsonb;
  v_payload jsonb;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '28000';
  END IF;

  SELECT public.can_manage_wallet(v_caller) INTO v_allowed;
  IF NOT COALESCE(v_allowed, false) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  v_tx := upper(btrim(coalesce(p_provider_transaction_id, '')));
  IF length(v_tx) < 3 THEN
    RAISE EXCEPTION 'invalid_tx_id' USING ERRCODE = '22023';
  END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN
    RAISE EXCEPTION 'invalid_amount' USING ERRCODE = '22023';
  END IF;

  IF p_receiving_account_id IS NOT NULL THEN
    SELECT * INTO v_account FROM public.payment_receiving_accounts
     WHERE id = p_receiving_account_id;
  END IF;

  v_payload := jsonb_build_object(
    'source', 'admin_manual_entry',
    'note', p_note,
    'recorded_by', v_caller,
    'receiving_account_id', p_receiving_account_id,
    'receiving_phone', v_account.phone_e164,
    'receiving_label', v_account.label
  );

  -- Dedupe on (provider, provider_transaction_id)
  SELECT id INTO v_event_id
    FROM public.payment_provider_events
   WHERE provider = 'orange_money'
     AND provider_transaction_id = v_tx;

  IF v_event_id IS NOT NULL THEN
    v_was_duplicate := true;
  ELSE
    INSERT INTO public.payment_provider_events (
      provider, event_type, provider_transaction_id, payer_phone,
      amount_gnf, status, processing_status, raw_payload, receiving_account_id
    ) VALUES (
      'orange_money', 'payment.received', v_tx,
      NULLIF(btrim(coalesce(p_payer_phone, '')), ''),
      p_amount_gnf, 'successful', 'received', v_payload, p_receiving_account_id
    )
    RETURNING id INTO v_event_id;
  END IF;

  BEGIN
    INSERT INTO public.audit_logs (actor_user_id, action, target_type, target_id, payload)
    VALUES (v_caller, 'om.receipt.record', 'payment_provider_event', v_event_id::text,
            jsonb_build_object('tx', v_tx, 'amount_gnf', p_amount_gnf, 'duplicate', v_was_duplicate));
  EXCEPTION WHEN OTHERS THEN
    NULL; -- audit failures must not block reconciliation
  END;

  IF NOT v_was_duplicate THEN
    BEGIN
      SELECT public.om_auto_match(v_event_id) INTO v_match;
    EXCEPTION WHEN OTHERS THEN
      v_match := jsonb_build_object('status', 'error', 'message', SQLERRM);
    END;
  ELSE
    v_match := jsonb_build_object('status', 'duplicate');
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