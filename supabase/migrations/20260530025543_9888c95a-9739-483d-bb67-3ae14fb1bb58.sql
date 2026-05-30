
-- Admin-safe cancel: requires can_manage_wallet, only cancels truly cancellable pending requests.
CREATE OR REPLACE FUNCTION public.wallet_topup_admin_cancel(p_topup_id uuid, p_reason text DEFAULT NULL)
RETURNS public.topup_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_existing public.topup_requests;
  v_row public.topup_requests;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_manage_wallet(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT * INTO v_existing FROM public.topup_requests WHERE id = p_topup_id;
  IF v_existing.id IS NULL THEN
    RAISE EXCEPTION 'Top-up introuvable';
  END IF;
  IF v_existing.status <> 'pending' THEN
    RAISE EXCEPTION 'Cette recharge ne peut pas être annulée dans son état actuel (%).', v_existing.status;
  END IF;
  IF v_existing.matched_provider_transaction_id IS NOT NULL THEN
    RAISE EXCEPTION 'Cette recharge est déjà rattachée à une transaction et ne peut pas être annulée.';
  END IF;
  IF v_existing.customer_om_code_submitted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cette recharge est en cours de vérification (code client reçu) et ne peut pas être annulée.';
  END IF;

  UPDATE public.topup_requests
  SET status = 'cancelled',
      cancelled_reason = COALESCE(p_reason, 'Annulé par admin')
  WHERE id = p_topup_id
  RETURNING * INTO v_row;

  PERFORM public.log_admin_action(
    'wallet', 'topup.cancel', 'topup_request', v_row.id::text,
    to_jsonb(v_existing), to_jsonb(v_row), p_reason
  );
  RETURN v_row;
END;
$$;

-- Admin-safe mark expired: only stale pending unmatched, no code, past expires_at or older than 24h.
CREATE OR REPLACE FUNCTION public.wallet_topup_admin_mark_expired(p_topup_id uuid, p_reason text DEFAULT NULL)
RETURNS public.topup_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_existing public.topup_requests;
  v_row public.topup_requests;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_manage_wallet(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT * INTO v_existing FROM public.topup_requests WHERE id = p_topup_id;
  IF v_existing.id IS NULL THEN
    RAISE EXCEPTION 'Top-up introuvable';
  END IF;
  IF v_existing.status <> 'pending' THEN
    RAISE EXCEPTION 'Cette recharge ne peut pas être expirée dans son état actuel (%).', v_existing.status;
  END IF;
  IF v_existing.matched_provider_transaction_id IS NOT NULL THEN
    RAISE EXCEPTION 'Cette recharge est rattachée à une transaction et ne peut pas être expirée manuellement.';
  END IF;
  IF v_existing.customer_om_code_submitted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Code client soumis — utilisez la file de réconciliation pour résoudre.';
  END IF;
  IF v_existing.expires_at > now() AND v_existing.created_at > now() - interval '24 hours' THEN
    RAISE EXCEPTION 'Cette recharge n''est pas encore stale (créée il y a moins de 24h et non expirée).';
  END IF;

  UPDATE public.topup_requests
  SET status = 'expired',
      cancelled_reason = COALESCE(p_reason, 'Marquée expirée par admin')
  WHERE id = p_topup_id
  RETURNING * INTO v_row;

  PERFORM public.log_admin_action(
    'wallet', 'topup.mark_expired', 'topup_request', v_row.id::text,
    to_jsonb(v_existing), to_jsonb(v_row), p_reason
  );
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.wallet_topup_admin_cancel(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.wallet_topup_admin_mark_expired(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.wallet_topup_admin_cancel(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_topup_admin_mark_expired(uuid, text) TO authenticated;
