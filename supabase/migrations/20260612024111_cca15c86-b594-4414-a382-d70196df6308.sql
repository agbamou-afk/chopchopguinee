
-- =========================================================================
-- Phase 9 — Service Agent Cash-In Foundation
-- Approved service agents (merchant_stores.service_agent_status='approved')
-- can credit a customer's CHOP client wallet against cash received in person.
-- v1: no agent float wallet — credit is sourced from the platform master
-- wallet, which is allowed to go negative (representing agent liability).
-- All limits enforced server-side, all flows audited, no client wallet writes.
-- =========================================================================

-- Eligibility helper
CREATE OR REPLACE FUNCTION public._is_approved_service_agent(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.merchant_stores ms
    WHERE ms.owner_user_id = _user_id
      AND ms.service_agent_status = 'approved'
      AND COALESCE(ms.status, 'active') IN ('active','approved')
  ) AND NOT public.is_user_banned(_user_id);
$$;

REVOKE ALL ON FUNCTION public._is_approved_service_agent(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._is_approved_service_agent(uuid) TO authenticated, service_role;

-- ------------------------------------------------------------------------
-- Customer lookup
-- ------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.agent_lookup_customer_wallet(p_phone text)
RETURNS TABLE (
  customer_user_id uuid,
  display_name     text,
  masked_phone     text,
  wallet_exists    boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_norm      text;
  v_cust      uuid;
  v_full      text;
  v_first     text;
  v_masked    text;
  v_wallet_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501';
  END IF;
  IF NOT public._is_approved_service_agent(v_uid) THEN
    RAISE EXCEPTION 'service_agent_not_approved';
  END IF;

  v_norm := public._normalize_guinea_phone(p_phone);
  IF v_norm IS NULL THEN
    RAISE EXCEPTION 'invalid_phone';
  END IF;

  SELECT p.id, COALESCE(p.full_name, '')
    INTO v_cust, v_full
  FROM public.profiles p
  WHERE p.phone = v_norm
  LIMIT 1;

  IF v_cust IS NULL THEN
    RAISE EXCEPTION 'customer_not_found';
  END IF;
  IF v_cust = v_uid THEN
    RAISE EXCEPTION 'self_cashin_forbidden';
  END IF;
  IF public.is_user_banned(v_cust) THEN
    RAISE EXCEPTION 'customer_unavailable';
  END IF;

  v_first := split_part(trim(v_full), ' ', 1);
  IF length(coalesce(v_first,'')) = 0 THEN v_first := 'Client CHOP'; END IF;

  v_masked := CASE
    WHEN length(v_norm) >= 6 THEN
      substr(v_norm,1,5) || ' •• •• ' || right(v_norm, 2)
    ELSE v_norm END;

  SELECT id INTO v_wallet_id FROM public.wallets
   WHERE owner_user_id = v_cust AND party_type='client' LIMIT 1;

  customer_user_id := v_cust;
  display_name     := v_first;
  masked_phone     := v_masked;
  wallet_exists    := v_wallet_id IS NOT NULL;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.agent_lookup_customer_wallet(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.agent_lookup_customer_wallet(text) TO authenticated, service_role;

-- ------------------------------------------------------------------------
-- Cash-in
-- ------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.agent_cash_in_customer_wallet(
  p_customer_user_id uuid,
  p_amount_gnf       bigint,
  p_reference_note   text DEFAULT NULL,
  p_idempotency_key  text DEFAULT NULL
)
RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  c_min_single        constant bigint  := 1000;
  c_max_single        constant bigint  := 1000000;
  c_max_daily_agent   constant bigint  := 5000000;
  c_max_daily_count   constant integer := 25;
  c_max_daily_cust    constant bigint  := 2000000;

  v_agent      uuid := auth.uid();
  v_store_id   uuid;
  v_master     uuid;
  v_cust_wal   uuid;
  v_today_sum  bigint;
  v_today_cnt  integer;
  v_cust_sum   bigint;
  v_idem       text;
  v_ref        text;
  v_existing   public.wallet_transactions;
  v_tx         public.wallet_transactions;
  v_meta       jsonb;
BEGIN
  IF v_agent IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501';
  END IF;
  IF NOT public._is_approved_service_agent(v_agent) THEN
    RAISE EXCEPTION 'service_agent_not_approved';
  END IF;
  IF p_customer_user_id IS NULL THEN
    RAISE EXCEPTION 'customer_required';
  END IF;
  IF p_customer_user_id = v_agent THEN
    RAISE EXCEPTION 'self_cashin_forbidden';
  END IF;
  IF public.is_user_banned(p_customer_user_id) THEN
    RAISE EXCEPTION 'customer_unavailable';
  END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;
  IF p_amount_gnf < c_min_single THEN
    RAISE EXCEPTION 'agent_cash_in_limit_single_min:%', c_min_single;
  END IF;
  IF p_amount_gnf > c_max_single THEN
    RAISE EXCEPTION 'agent_cash_in_limit_single_exceeded:%', c_max_single;
  END IF;

  -- Customer must exist as a real profile
  PERFORM 1 FROM public.profiles WHERE id = p_customer_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'customer_not_found';
  END IF;

  -- Agent store id (for metadata / audit)
  SELECT id INTO v_store_id FROM public.merchant_stores
    WHERE owner_user_id = v_agent
      AND service_agent_status = 'approved'
    LIMIT 1;

  -- Ensure customer client wallet
  INSERT INTO public.wallets (owner_user_id, party_type)
    VALUES (p_customer_user_id, 'client')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT id INTO v_cust_wal FROM public.wallets
    WHERE owner_user_id = p_customer_user_id AND party_type='client' LIMIT 1;
  IF v_cust_wal IS NULL THEN
    RAISE EXCEPTION 'customer_wallet_missing';
  END IF;

  -- Source: platform master wallet (liability-mode credit, no agent float yet)
  SELECT id INTO v_master FROM public.wallets WHERE party_type='master' LIMIT 1;
  IF v_master IS NULL THEN
    INSERT INTO public.wallets (owner_user_id, party_type, balance_gnf)
    VALUES (NULL, 'master', 0)
    RETURNING id INTO v_master;
  END IF;

  -- Daily caps for this agent (UTC day, completed cash-ins only)
  SELECT COALESCE(SUM(amount_gnf),0), COUNT(*)
    INTO v_today_sum, v_today_cnt
  FROM public.wallet_transactions
  WHERE status='completed'
    AND created_at >= date_trunc('day', now())
    AND reference LIKE 'agent_cash_in:' || v_agent::text || ':%';
  IF v_today_sum + p_amount_gnf > c_max_daily_agent THEN
    RAISE EXCEPTION 'agent_cash_in_daily_agent_total_exceeded:%', c_max_daily_agent;
  END IF;
  IF v_today_cnt + 1 > c_max_daily_count THEN
    RAISE EXCEPTION 'agent_cash_in_daily_count_exceeded:%', c_max_daily_count;
  END IF;

  -- Daily cap per customer across all agents
  SELECT COALESCE(SUM(amount_gnf),0)
    INTO v_cust_sum
  FROM public.wallet_transactions
  WHERE status='completed'
    AND created_at >= date_trunc('day', now())
    AND reference LIKE 'agent_cash_in:%:' || p_customer_user_id::text || ':%';
  IF v_cust_sum + p_amount_gnf > c_max_daily_cust THEN
    RAISE EXCEPTION 'agent_cash_in_daily_customer_total_exceeded:%', c_max_daily_cust;
  END IF;

  v_idem := COALESCE(NULLIF(trim(p_idempotency_key),''), gen_random_uuid()::text);
  v_ref  := 'agent_cash_in:' || v_agent::text || ':' || p_customer_user_id::text || ':' || v_idem;

  -- Idempotent short-circuit
  SELECT * INTO v_existing FROM public.wallet_transactions WHERE reference = v_ref LIMIT 1;
  IF v_existing.id IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  v_meta := jsonb_build_object(
    'source_module',         'service_agent',
    'service_agent_user_id', v_agent,
    'merchant_store_id',     v_store_id,
    'customer_user_id',      p_customer_user_id,
    'amount_gnf',            p_amount_gnf,
    'idempotency_key',       v_idem,
    'reference_note',        p_reference_note,
    'float_mode',            false,
    'created_by_function',   'agent_cash_in_customer_wallet'
  );

  v_tx := public.wallet_internal_transfer_v2(
    p_from_wallet_id := v_master,
    p_to_wallet_id   := v_cust_wal,
    p_amount_gnf     := p_amount_gnf,
    p_reference      := v_ref,
    p_transfer_type  := 'topup',
    p_description    := 'Recharge Agent CHOP',
    p_source_module  := 'service_agent',
    p_source_id      := v_agent::text || ':' || p_customer_user_id::text,
    p_metadata       := v_meta
  );

  BEGIN
    INSERT INTO public.audit_logs (
      actor_user_id, action, target_type, target_id, metadata
    ) VALUES (
      v_agent, 'service_agent.cash_in', 'wallet_transaction', v_tx.id::text, v_meta
    );
  EXCEPTION WHEN OTHERS THEN
    -- Audit failure must not break a successful credit
    NULL;
  END;

  RETURN v_tx;
END;
$$;

REVOKE ALL ON FUNCTION public.agent_cash_in_customer_wallet(uuid, bigint, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.agent_cash_in_customer_wallet(uuid, bigint, text, text)
  TO authenticated, service_role;

-- ------------------------------------------------------------------------
-- Admin preview
-- ------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_preview_service_agent_cashins(p_limit integer DEFAULT 100)
RETURNS TABLE (
  transaction_id    uuid,
  reference         text,
  amount_gnf        bigint,
  status            public.txn_status,
  created_at        timestamptz,
  agent_user_id     uuid,
  merchant_store_id uuid,
  customer_user_id  uuid,
  note              text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'admin_only' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
  SELECT t.id,
         t.reference,
         t.amount_gnf,
         t.status,
         t.created_at,
         (t.metadata->>'service_agent_user_id')::uuid,
         NULLIF(t.metadata->>'merchant_store_id','')::uuid,
         (t.metadata->>'customer_user_id')::uuid,
         t.metadata->>'reference_note'
  FROM public.wallet_transactions t
  WHERE t.reference LIKE 'agent_cash_in:%'
  ORDER BY t.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 500));
END;
$$;

REVOKE ALL ON FUNCTION public.admin_preview_service_agent_cashins(integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_preview_service_agent_cashins(integer)
  TO authenticated, service_role;
