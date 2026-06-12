
-- Phase 2: hardened core inter-wallet transfer rail
CREATE OR REPLACE FUNCTION public.wallet_internal_transfer_v2(
  p_from_wallet_id uuid,
  p_to_wallet_id   uuid,
  p_amount_gnf     bigint,
  p_reference      text,
  p_transfer_type  text    DEFAULT 'transfer',
  p_description    text    DEFAULT NULL,
  p_source_module  text    DEFAULT NULL,
  p_source_id      text    DEFAULT NULL,
  p_metadata       jsonb   DEFAULT '{}'::jsonb
)
RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid        uuid := auth.uid();
  v_from       public.wallets;
  v_to         public.wallets;
  v_existing   public.wallet_transactions;
  v_tx         public.wallet_transactions;
  v_first_id   uuid;
  v_second_id  uuid;
  v_group_id   uuid;
  v_meta       jsonb;
  v_type       public.txn_type;
BEGIN
  -- Basic validation
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;
  IF p_reference IS NULL OR length(trim(p_reference)) = 0 THEN
    RAISE EXCEPTION 'reference_required';
  END IF;
  IF p_from_wallet_id IS NULL OR p_to_wallet_id IS NULL THEN
    RAISE EXCEPTION 'wallet_id_required';
  END IF;
  IF p_from_wallet_id = p_to_wallet_id THEN
    RAISE EXCEPTION 'same_wallet_transfer_forbidden';
  END IF;

  -- Cast transfer type; default to 'transfer' on bad input
  BEGIN
    v_type := COALESCE(p_transfer_type, 'transfer')::public.txn_type;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'invalid_transfer_type:%', p_transfer_type;
  END;

  -- Idempotency: if reference already used, return existing row
  SELECT * INTO v_existing FROM public.wallet_transactions
   WHERE reference = p_reference
   LIMIT 1;
  IF v_existing.id IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  -- Deterministic lock order to prevent deadlocks
  IF p_from_wallet_id < p_to_wallet_id THEN
    v_first_id := p_from_wallet_id; v_second_id := p_to_wallet_id;
  ELSE
    v_first_id := p_to_wallet_id;   v_second_id := p_from_wallet_id;
  END IF;
  PERFORM 1 FROM public.wallets WHERE id = v_first_id  FOR UPDATE;
  PERFORM 1 FROM public.wallets WHERE id = v_second_id FOR UPDATE;

  SELECT * INTO v_from FROM public.wallets WHERE id = p_from_wallet_id;
  IF v_from.id IS NULL THEN RAISE EXCEPTION 'from_wallet_not_found'; END IF;
  IF v_from.status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'from_wallet_not_active';
  END IF;

  SELECT * INTO v_to FROM public.wallets WHERE id = p_to_wallet_id;
  IF v_to.id IS NULL THEN RAISE EXCEPTION 'to_wallet_not_found'; END IF;
  IF v_to.status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'to_wallet_not_active';
  END IF;

  -- Insufficient funds (master wallet allowed to go negative for now)
  IF v_from.party_type <> 'master' THEN
    IF COALESCE(v_from.balance_gnf,0) - COALESCE(v_from.held_gnf,0) < p_amount_gnf THEN
      RAISE EXCEPTION 'insufficient_funds';
    END IF;
  END IF;

  v_group_id := gen_random_uuid();
  v_meta := COALESCE(p_metadata, '{}'::jsonb) || jsonb_build_object(
    'transfer_group_id',     v_group_id,
    'source_module',         p_source_module,
    'source_id',             p_source_id,
    'transfer_type',         p_transfer_type,
    'idempotency_reference', p_reference,
    'initiated_by_user_id',  v_uid,
    'created_by_function',   'wallet_internal_transfer_v2',
    'from_party_type',       v_from.party_type::text,
    'to_party_type',         v_to.party_type::text
  );

  -- Debit + credit atomically
  UPDATE public.wallets SET balance_gnf = balance_gnf - p_amount_gnf, updated_at = now()
   WHERE id = v_from.id;
  UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount_gnf, updated_at = now()
   WHERE id = v_to.id;

  BEGIN
    INSERT INTO public.wallet_transactions (
      reference, type, status, amount_gnf,
      from_wallet_id, to_wallet_id, related_user_id, related_entity,
      description, metadata, completed_at
    ) VALUES (
      p_reference, v_type, 'completed', p_amount_gnf,
      v_from.id, v_to.id, v_uid,
      CASE WHEN p_source_module IS NOT NULL AND p_source_id IS NOT NULL
           THEN p_source_module || ':' || p_source_id
           ELSE NULL END,
      p_description, v_meta, now()
    ) RETURNING * INTO v_tx;
  EXCEPTION WHEN unique_violation THEN
    -- Race: another caller inserted same reference. Roll back our balance
    -- changes by reversing them, then return the existing row.
    UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount_gnf, updated_at = now()
     WHERE id = v_from.id;
    UPDATE public.wallets SET balance_gnf = balance_gnf - p_amount_gnf, updated_at = now()
     WHERE id = v_to.id;
    SELECT * INTO v_existing FROM public.wallet_transactions
     WHERE reference = p_reference LIMIT 1;
    RETURN v_existing;
  END;

  RETURN v_tx;
END;
$function$;

-- Lock down execution: only trusted server contexts may call this.
REVOKE ALL ON FUNCTION public.wallet_internal_transfer_v2(
  uuid, uuid, bigint, text, text, text, text, text, jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_internal_transfer_v2(
  uuid, uuid, bigint, text, text, text, text, text, jsonb
) TO service_role;
