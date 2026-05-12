
-- Auto-create agent wallet when agent profile is added
CREATE OR REPLACE FUNCTION public.handle_new_agent()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.wallets (owner_user_id, party_type)
  VALUES (NEW.user_id, 'agent')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.handle_new_agent() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_agent_profile_created ON public.agent_profiles;
CREATE TRIGGER trg_agent_profile_created
  AFTER INSERT ON public.agent_profiles
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_agent();

-- Backfill: ensure existing agents have wallets
INSERT INTO public.wallets (owner_user_id, party_type)
SELECT user_id, 'agent' FROM public.agent_profiles
ON CONFLICT (owner_user_id, party_type) DO NOTHING;

-- ============================================================
-- Lookup helper: phone -> user_id (agent searches by phone)
-- ============================================================
CREATE OR REPLACE FUNCTION public.find_user_by_phone(p_phone text)
RETURNS TABLE (user_id uuid, full_name text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.user_id, p.full_name
  FROM public.profiles p
  WHERE p.phone = p_phone
  LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.find_user_by_phone(text) TO authenticated;

-- ============================================================
-- Create top-up request (agent calls this)
-- ============================================================
CREATE OR REPLACE FUNCTION public.wallet_topup_create(
  p_client_user_id uuid,
  p_amount_gnf bigint
) RETURNS public.topup_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_agent_wallet public.wallets;
  v_code text;
  v_ref text;
  v_row public.topup_requests;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_amount_gnf <= 0 THEN
    RAISE EXCEPTION 'Invalid amount';
  END IF;
  IF p_client_user_id = v_caller THEN
    RAISE EXCEPTION 'Agents cannot top up themselves';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.agent_profiles
    WHERE user_id = v_caller AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Caller is not an active agent';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.wallets
    WHERE owner_user_id = p_client_user_id AND party_type = 'client'
  ) THEN
    RAISE EXCEPTION 'Client wallet not found';
  END IF;

  SELECT * INTO v_agent_wallet
  FROM public.wallets
  WHERE owner_user_id = v_caller AND party_type = 'agent';

  IF v_agent_wallet.id IS NULL THEN
    RAISE EXCEPTION 'Agent wallet not found';
  END IF;
  IF v_agent_wallet.balance_gnf < p_amount_gnf THEN
    RAISE EXCEPTION 'Insufficient agent float';
  END IF;

  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
  v_ref := 'CC-RC-' || upper(substring(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  INSERT INTO public.topup_requests (
    reference, client_user_id, agent_user_id, amount_gnf, confirmation_code
  )
  VALUES (v_ref, p_client_user_id, v_caller, p_amount_gnf, v_code)
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
GRANT EXECUTE ON FUNCTION public.wallet_topup_create(uuid, bigint) TO authenticated;

-- ============================================================
-- Confirm top-up: atomically move funds & record ledger
-- ============================================================
CREATE OR REPLACE FUNCTION public.wallet_topup_confirm(
  p_topup_id uuid,
  p_code text
) RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_topup public.topup_requests;
  v_agent_wallet public.wallets;
  v_client_wallet public.wallets;
  v_txn public.wallet_transactions;
  v_txn_ref text;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_topup
  FROM public.topup_requests
  WHERE id = p_topup_id
  FOR UPDATE;

  IF v_topup.id IS NULL THEN
    RAISE EXCEPTION 'Top-up not found';
  END IF;
  IF v_topup.agent_user_id <> v_caller THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_topup.status <> 'pending' THEN
    RAISE EXCEPTION 'Top-up is not pending';
  END IF;
  IF v_topup.expires_at < now() THEN
    UPDATE public.topup_requests SET status = 'expired' WHERE id = v_topup.id;
    RAISE EXCEPTION 'Top-up expired';
  END IF;
  IF v_topup.confirmation_code <> p_code THEN
    RAISE EXCEPTION 'Invalid confirmation code';
  END IF;

  SELECT * INTO v_agent_wallet
  FROM public.wallets
  WHERE owner_user_id = v_caller AND party_type = 'agent'
  FOR UPDATE;
  SELECT * INTO v_client_wallet
  FROM public.wallets
  WHERE owner_user_id = v_topup.client_user_id AND party_type = 'client'
  FOR UPDATE;

  IF v_agent_wallet.balance_gnf < v_topup.amount_gnf THEN
    RAISE EXCEPTION 'Insufficient agent float';
  END IF;

  UPDATE public.wallets
  SET balance_gnf = balance_gnf - v_topup.amount_gnf
  WHERE id = v_agent_wallet.id;

  UPDATE public.wallets
  SET balance_gnf = balance_gnf + v_topup.amount_gnf
  WHERE id = v_client_wallet.id;

  v_txn_ref := 'CC-TX-' || upper(substring(replace(gen_random_uuid()::text, '-', ''), 1, 10));

  INSERT INTO public.wallet_transactions (
    reference, type, status, amount_gnf,
    from_wallet_id, to_wallet_id,
    related_user_id, related_entity, description, completed_at
  ) VALUES (
    v_txn_ref, 'topup', 'completed', v_topup.amount_gnf,
    v_agent_wallet.id, v_client_wallet.id,
    v_topup.client_user_id, 'topup:' || v_topup.id,
    'Recharge agent ' || v_topup.reference, now()
  ) RETURNING * INTO v_txn;

  UPDATE public.topup_requests
  SET status = 'confirmed',
      confirmed_at = now(),
      transaction_id = v_txn.id
  WHERE id = v_topup.id;

  RETURN v_txn;
END;
$$;
GRANT EXECUTE ON FUNCTION public.wallet_topup_confirm(uuid, text) TO authenticated;

-- ============================================================
-- Cancel pending top-up
-- ============================================================
CREATE OR REPLACE FUNCTION public.wallet_topup_cancel(
  p_topup_id uuid,
  p_reason text DEFAULT NULL
) RETURNS public.topup_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_row public.topup_requests;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  UPDATE public.topup_requests
  SET status = 'cancelled', cancelled_reason = p_reason
  WHERE id = p_topup_id
    AND status = 'pending'
    AND (agent_user_id = v_caller OR client_user_id = v_caller)
  RETURNING * INTO v_row;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Cannot cancel this top-up';
  END IF;
  RETURN v_row;
END;
$$;
GRANT EXECUTE ON FUNCTION public.wallet_topup_cancel(uuid, text) TO authenticated;

-- ============================================================
-- Realtime: clients/agents need live updates on topup_requests
-- ============================================================
ALTER PUBLICATION supabase_realtime ADD TABLE public.topup_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE public.wallets;
ALTER PUBLICATION supabase_realtime ADD TABLE public.wallet_transactions;
