-- Admin-authorized wrapper for manual OM credit approval (replaces direct
-- authenticated access to the internal primitive).
CREATE OR REPLACE FUNCTION public.admin_manual_om_credit(p_event_id uuid, p_topup_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_tx public.wallet_transactions;
BEGIN
  IF v_caller IS NULL OR NOT COALESCE(public.can_manage_wallet(v_caller), false) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_tx FROM public.wallet_topup_om_credit(p_event_id, p_topup_request_id);

  RETURN jsonb_build_object(
    'status', 'credited',
    'transaction_id', v_tx.id,
    'reference', v_tx.reference,
    'amount_gnf', v_tx.amount_gnf
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_manual_om_credit(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_manual_om_credit(uuid, uuid) TO authenticated, service_role;

-- Harden internal inbound-OM primitives: service_role only.
REVOKE ALL ON FUNCTION public.om_auto_match(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.om_auto_match(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.wallet_topup_om_credit(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_topup_om_credit(uuid, uuid) TO service_role;