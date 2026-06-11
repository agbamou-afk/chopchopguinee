
-- Phase 1b: hardened, idempotent merchant settlement RPC.
-- Backend-only (service_role). Customers/merchants cannot call it.

CREATE OR REPLACE FUNCTION public.wallet_pay_merchant_store(
  p_merchant_store_id uuid,
  p_amount_gnf bigint,
  p_reference text,
  p_description text DEFAULT NULL,
  p_source_module text DEFAULT NULL,
  p_source_id text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner uuid;
  v_store_name text;
  v_wid uuid;
  v_tx public.wallet_transactions;
  v_existing public.wallet_transactions;
  v_related text;
  v_meta jsonb;
BEGIN
  -- Validation
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;
  IF p_reference IS NULL OR length(btrim(p_reference)) = 0 THEN
    RAISE EXCEPTION 'reference_required';
  END IF;
  IF p_merchant_store_id IS NULL THEN
    RAISE EXCEPTION 'merchant_store_required';
  END IF;

  -- Idempotency short-circuit
  SELECT * INTO v_existing
    FROM public.wallet_transactions
    WHERE reference = p_reference
    LIMIT 1;
  IF v_existing.id IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  -- Resolve merchant store + owner
  SELECT owner_user_id, name INTO v_owner, v_store_name
    FROM public.merchant_stores
    WHERE id = p_merchant_store_id;
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'merchant_store_not_found';
  END IF;

  -- Ensure merchant wallet exists
  SELECT id INTO v_wid
    FROM public.wallets
    WHERE owner_user_id = v_owner AND party_type = 'merchant'::party_type;
  IF v_wid IS NULL THEN
    INSERT INTO public.wallets(owner_user_id, party_type)
    VALUES (v_owner, 'merchant'::party_type)
    RETURNING id INTO v_wid;
  END IF;

  -- Credit merchant wallet
  UPDATE public.wallets
    SET balance_gnf = balance_gnf + p_amount_gnf,
        updated_at = now()
    WHERE id = v_wid;

  v_related := CASE
    WHEN p_source_module IS NOT NULL AND p_source_id IS NOT NULL
      THEN p_source_module || ':' || p_source_id
    ELSE 'merchant_store:' || p_merchant_store_id::text
  END;

  v_meta := coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object(
    'merchant_store_id', p_merchant_store_id,
    'merchant_owner_user_id', v_owner,
    'merchant_store_name', v_store_name,
    'source_module', p_source_module,
    'source_id', p_source_id,
    'idempotency_reference', p_reference,
    'net_amount_gnf', p_amount_gnf,
    'created_by_function', 'wallet_pay_merchant_store'
  );

  -- Insert ledger row; race-safe via UNIQUE(reference)
  BEGIN
    INSERT INTO public.wallet_transactions(
      reference, type, status, amount_gnf,
      from_wallet_id, to_wallet_id, related_user_id,
      related_entity, description, completed_at, metadata
    ) VALUES (
      p_reference, 'payment'::txn_type, 'completed'::txn_status, p_amount_gnf,
      NULL, v_wid, v_owner,
      v_related,
      coalesce(p_description, 'Règlement marchand · ' || coalesce(v_store_name, '')),
      now(),
      v_meta
    ) RETURNING * INTO v_tx;
  EXCEPTION WHEN unique_violation THEN
    -- Concurrent caller won the race: revert our credit and return the existing tx.
    UPDATE public.wallets
      SET balance_gnf = balance_gnf - p_amount_gnf,
          updated_at = now()
      WHERE id = v_wid;
    SELECT * INTO v_tx
      FROM public.wallet_transactions
      WHERE reference = p_reference
      LIMIT 1;
  END;

  RETURN v_tx;
END $$;

-- Lock down execution: backend/service-role only.
REVOKE ALL ON FUNCTION public.wallet_pay_merchant_store(uuid,bigint,text,text,text,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.wallet_pay_merchant_store(uuid,bigint,text,text,text,text,jsonb) FROM anon;
REVOKE ALL ON FUNCTION public.wallet_pay_merchant_store(uuid,bigint,text,text,text,text,jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_pay_merchant_store(uuid,bigint,text,text,text,text,jsonb) TO service_role;

COMMENT ON FUNCTION public.wallet_pay_merchant_store(uuid,bigint,text,text,text,text,jsonb) IS
  'Phase 1b — Idempotent merchant settlement credit. Reserved for backend service_role callers. Requires unique p_reference; duplicate calls return the existing transaction without double-crediting. Not full double-entry yet: credit-only ledger row (from_wallet_id NULL) until platform settlement wallet is wired.';
