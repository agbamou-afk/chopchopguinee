
-- 1) Add merchant_revenue txn_type if missing.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
    WHERE t.typname='txn_type' AND e.enumlabel='merchant_revenue'
  ) THEN
    ALTER TYPE public.txn_type ADD VALUE 'merchant_revenue';
  END IF;
END $$;

-- 2) Settlement RPC. Server-side only; uses the hardened transfer rail.
CREATE OR REPLACE FUNCTION public.wallet_settle_merchant_revenue(
  p_source_module      text,
  p_source_id          uuid,
  p_merchant_store_id  uuid,
  p_amount_gnf         bigint,
  p_reference          text,
  p_description        text  DEFAULT NULL,
  p_metadata           jsonb DEFAULT '{}'::jsonb
)
RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_store           public.merchant_stores;
  v_owner           uuid;
  v_merchant_wallet uuid;
  v_master_wallet   uuid;
  v_existing        public.wallet_transactions;
  v_tx              public.wallet_transactions;
  v_meta            jsonb;
BEGIN
  IF p_reference IS NULL OR length(trim(p_reference)) = 0 THEN
    RAISE EXCEPTION 'reference_required';
  END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;
  IF p_source_module IS NULL OR length(trim(p_source_module)) = 0 THEN
    RAISE EXCEPTION 'source_module_required';
  END IF;
  IF p_source_id IS NULL THEN
    RAISE EXCEPTION 'source_id_required';
  END IF;
  IF p_merchant_store_id IS NULL THEN
    RAISE EXCEPTION 'merchant_store_required';
  END IF;

  -- Idempotency pre-check.
  SELECT * INTO v_existing FROM public.wallet_transactions
    WHERE reference = p_reference LIMIT 1;
  IF v_existing.id IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  SELECT * INTO v_store FROM public.merchant_stores WHERE id = p_merchant_store_id;
  IF v_store.id IS NULL THEN RAISE EXCEPTION 'merchant_store_not_found'; END IF;
  v_owner := v_store.owner_user_id;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'merchant_store_misconfigured'; END IF;

  -- Ensure merchant wallet exists.
  INSERT INTO public.wallets (owner_user_id, party_type)
    VALUES (v_owner, 'merchant')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT id INTO v_merchant_wallet FROM public.wallets
    WHERE owner_user_id = v_owner AND party_type = 'merchant' LIMIT 1;
  IF v_merchant_wallet IS NULL THEN
    RAISE EXCEPTION 'merchant_wallet_missing';
  END IF;

  SELECT id INTO v_master_wallet FROM public.wallets
    WHERE party_type = 'master' AND owner_user_id IS NULL LIMIT 1;
  IF v_master_wallet IS NULL THEN
    RAISE EXCEPTION 'master_wallet_missing';
  END IF;

  v_meta := COALESCE(p_metadata, '{}'::jsonb) || jsonb_build_object(
    'merchant_store_id',     p_merchant_store_id,
    'merchant_owner_user_id',v_owner,
    'source_module',         p_source_module,
    'source_id',             p_source_id,
    'idempotency_reference', p_reference,
    'created_by_function',   'wallet_settle_merchant_revenue'
  );

  v_tx := public.wallet_internal_transfer_v2(
    p_from_wallet_id => v_master_wallet,
    p_to_wallet_id   => v_merchant_wallet,
    p_amount_gnf     => p_amount_gnf,
    p_reference      => p_reference,
    p_transfer_type  => 'merchant_revenue',
    p_description    => COALESCE(p_description, 'Règlement vente · ' || v_store.name),
    p_source_module  => p_source_module,
    p_source_id      => p_source_id::text,
    p_metadata       => v_meta
  );

  RETURN v_tx;
END;
$function$;

REVOKE ALL ON FUNCTION public.wallet_settle_merchant_revenue(
  text, uuid, uuid, bigint, text, text, jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_settle_merchant_revenue(
  text, uuid, uuid, bigint, text, text, jsonb
) TO service_role;

-- 3) Admin consistency helper. Lists merchant_revenue rows by module so
-- admins can audit / reconcile. (No paid trigger exists yet for Marché /
-- Repas, so until then this is the audit hook for future captured sales.)
CREATE OR REPLACE FUNCTION public.admin_preview_missing_merchant_revenue(
  p_source_module text DEFAULT NULL
)
RETURNS TABLE(
  tx_id uuid,
  reference text,
  source_module text,
  source_id text,
  merchant_store_id uuid,
  merchant_owner_user_id uuid,
  amount_gnf bigint,
  status text,
  created_at timestamptz,
  metadata jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR NOT (
    public.has_role(v_uid, 'god_admin'::public.app_role)
    OR public.has_role(v_uid, 'finance_admin'::public.app_role)
    OR public.has_role(v_uid, 'admin'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'forbidden: admin role required';
  END IF;

  RETURN QUERY
  SELECT wt.id,
         wt.reference,
         (wt.metadata->>'source_module'),
         (wt.metadata->>'source_id'),
         NULLIF(wt.metadata->>'merchant_store_id','')::uuid,
         NULLIF(wt.metadata->>'merchant_owner_user_id','')::uuid,
         wt.amount_gnf,
         wt.status::text,
         wt.created_at,
         wt.metadata
  FROM public.wallet_transactions wt
  WHERE wt.type = 'merchant_revenue'
    AND (p_source_module IS NULL OR wt.metadata->>'source_module' = p_source_module)
  ORDER BY wt.created_at DESC
  LIMIT 500;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_preview_missing_merchant_revenue(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_preview_missing_merchant_revenue(text)
  TO authenticated, service_role;
