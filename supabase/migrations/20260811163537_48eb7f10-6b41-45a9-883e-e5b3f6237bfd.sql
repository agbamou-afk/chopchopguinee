CREATE OR REPLACE FUNCTION public._qa_s13_wallet(p_owner uuid, p_party party_type, p_bal bigint, p_held bigint)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.wallets(owner_user_id, party_type, balance_gnf, held_gnf)
  VALUES (p_owner, p_party, p_bal, p_held)
  ON CONFLICT (owner_user_id, party_type)
  DO UPDATE SET balance_gnf = EXCLUDED.balance_gnf, held_gnf = EXCLUDED.held_gnf
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    UPDATE public.wallets SET balance_gnf = p_bal, held_gnf = p_held
     WHERE owner_user_id = p_owner AND party_type = p_party RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public._qa_s13_wallet(uuid,party_type,bigint,bigint) FROM PUBLIC, anon, authenticated;