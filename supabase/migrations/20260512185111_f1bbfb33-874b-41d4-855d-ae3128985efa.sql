-- Admin RPC: create agent profile from a phone number
CREATE OR REPLACE FUNCTION public.admin_create_agent(
  p_phone text,
  p_business_name text,
  p_location text DEFAULT NULL,
  p_daily_limit_gnf bigint DEFAULT 5000000,
  p_commission_rate numeric DEFAULT 0.01
) RETURNS public.agent_profiles
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_user_id uuid;
  v_row public.agent_profiles;
BEGIN
  IF v_caller IS NULL OR NOT public.has_role(v_caller, 'admin') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF coalesce(trim(p_business_name), '') = '' THEN
    RAISE EXCEPTION 'Business name required';
  END IF;

  SELECT user_id INTO v_user_id FROM public.profiles WHERE phone = p_phone LIMIT 1;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No user found with this phone';
  END IF;

  IF EXISTS (SELECT 1 FROM public.agent_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'User is already an agent';
  END IF;

  INSERT INTO public.agent_profiles (user_id, business_name, location, daily_limit_gnf, commission_rate, status)
  VALUES (v_user_id, p_business_name, p_location, p_daily_limit_gnf, p_commission_rate, 'active')
  RETURNING * INTO v_row;

  RETURN v_row;
END $$;

-- Admin RPC: adjust an agent's prepaid float (positive credit, negative debit)
-- Mirrors the change in the agent wallet and records a ledger entry from/to master wallet.
CREATE OR REPLACE FUNCTION public.admin_adjust_agent_float(
  p_agent_user_id uuid,
  p_delta_gnf bigint,
  p_reason text DEFAULT NULL
) RETURNS public.wallet_transactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_agent_wallet public.wallets;
  v_master public.wallets;
  v_txn public.wallet_transactions;
  v_ref text;
  v_amount bigint;
  v_type txn_type;
  v_from uuid;
  v_to uuid;
BEGIN
  IF v_caller IS NULL OR NOT public.has_role(v_caller, 'admin') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF p_delta_gnf = 0 THEN
    RAISE EXCEPTION 'Delta must be non-zero';
  END IF;

  SELECT * INTO v_agent_wallet FROM public.wallets
   WHERE owner_user_id = p_agent_user_id AND party_type = 'agent' FOR UPDATE;
  IF v_agent_wallet.id IS NULL THEN
    RAISE EXCEPTION 'Agent wallet not found';
  END IF;

  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
  IF v_master.id IS NULL THEN
    RAISE EXCEPTION 'Master wallet not found';
  END IF;

  v_amount := abs(p_delta_gnf);

  IF p_delta_gnf > 0 THEN
    -- credit agent (load float)
    UPDATE public.wallets SET balance_gnf = balance_gnf + v_amount WHERE id = v_agent_wallet.id;
    UPDATE public.agent_profiles SET prepaid_float_gnf = prepaid_float_gnf + v_amount WHERE user_id = p_agent_user_id;
    v_type := 'adjustment';
    v_from := v_master.id;
    v_to := v_agent_wallet.id;
  ELSE
    IF v_agent_wallet.balance_gnf < v_amount THEN
      RAISE EXCEPTION 'Insufficient agent float';
    END IF;
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_amount WHERE id = v_agent_wallet.id;
    UPDATE public.agent_profiles SET prepaid_float_gnf = greatest(prepaid_float_gnf - v_amount, 0) WHERE user_id = p_agent_user_id;
    v_type := 'adjustment';
    v_from := v_agent_wallet.id;
    v_to := v_master.id;
  END IF;

  v_ref := 'CC-AD-' || upper(substring(replace(gen_random_uuid()::text, '-', ''), 1, 10));

  INSERT INTO public.wallet_transactions (
    reference, type, status, amount_gnf,
    from_wallet_id, to_wallet_id, related_user_id, related_entity,
    description, completed_at, metadata
  ) VALUES (
    v_ref, v_type, 'completed', v_amount,
    v_from, v_to, p_agent_user_id, 'admin_float_adjustment',
    coalesce(p_reason, 'Admin float adjustment'), now(),
    jsonb_build_object('admin_user_id', v_caller, 'delta_gnf', p_delta_gnf)
  ) RETURNING * INTO v_txn;

  RETURN v_txn;
END $$;