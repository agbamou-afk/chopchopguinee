CREATE OR REPLACE FUNCTION public.wallet_internal_transfer(
  p_from_user_id uuid, p_from_party_type text, p_to_user_id uuid,
  p_to_party_type text, p_amount_gnf bigint, p_description text)
RETURNS public.wallet_transactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_from_wallet public.wallets;
  v_to_wallet public.wallets;
  v_tx public.wallet_transactions;
BEGIN
  IF p_amount_gnf <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;

  SELECT * INTO v_from_wallet FROM public.wallets
    WHERE party_type = p_from_party_type::public.party_type
      AND ((p_from_user_id IS NULL AND owner_user_id IS NULL) OR owner_user_id = p_from_user_id)
    FOR UPDATE;
  IF v_from_wallet.id IS NULL THEN RAISE EXCEPTION 'Source wallet not found'; END IF;
  IF v_from_wallet.balance_gnf - v_from_wallet.held_gnf < p_amount_gnf THEN
    RAISE EXCEPTION 'Insufficient funds';
  END IF;

  SELECT * INTO v_to_wallet FROM public.wallets
    WHERE party_type = p_to_party_type::public.party_type
      AND ((p_to_user_id IS NULL AND owner_user_id IS NULL) OR owner_user_id = p_to_user_id)
    FOR UPDATE;
  IF v_to_wallet.id IS NULL THEN RAISE EXCEPTION 'Destination wallet not found'; END IF;

  UPDATE public.wallets SET balance_gnf = balance_gnf - p_amount_gnf WHERE id = v_from_wallet.id;
  UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount_gnf WHERE id = v_to_wallet.id;

  INSERT INTO public.wallet_transactions (
    from_wallet_id, to_wallet_id, amount_gnf, type, status, description
  ) VALUES (
    v_from_wallet.id, v_to_wallet.id, p_amount_gnf, 'transfer', 'completed', p_description
  ) RETURNING * INTO v_tx;

  RETURN v_tx;
END $$;