CREATE OR REPLACE FUNCTION public.wallet_ensure(_party_type text DEFAULT 'client'::text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_id  uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF _party_type NOT IN ('client','driver','merchant') THEN
    RAISE EXCEPTION 'invalid_party_type';
  END IF;

  SELECT id INTO v_id
  FROM public.wallets
  WHERE owner_user_id = v_uid AND party_type = _party_type::party_type;

  IF v_id IS NULL THEN
    INSERT INTO public.wallets (owner_user_id, party_type)
    VALUES (v_uid, _party_type::party_type)
    ON CONFLICT (owner_user_id, party_type) DO NOTHING
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
      SELECT id INTO v_id FROM public.wallets
      WHERE owner_user_id = v_uid AND party_type = _party_type::party_type;
    END IF;
  END IF;

  RETURN v_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.wallet_ensure(text) TO authenticated;