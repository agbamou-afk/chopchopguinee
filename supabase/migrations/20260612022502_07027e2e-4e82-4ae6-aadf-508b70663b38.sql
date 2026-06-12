
-- =========================================================
-- Phase 8 — Controlled P2P CHOP Wallet Transfers
-- =========================================================

-- 1) Phone normalization helper (idempotent)
CREATE OR REPLACE FUNCTION public._normalize_guinea_phone(p_raw text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $function$
DECLARE
  v_digits text;
BEGIN
  IF p_raw IS NULL THEN RETURN NULL; END IF;
  v_digits := regexp_replace(p_raw, '\D', '', 'g');
  IF v_digits LIKE '00224%' THEN v_digits := substr(v_digits, 6); END IF;
  IF v_digits LIKE '224%'   THEN v_digits := substr(v_digits, 4); END IF;
  IF length(v_digits) BETWEEN 8 AND 9 THEN
    RETURN '+224' || v_digits;
  END IF;
  RETURN NULL;
END;
$function$;

-- 2) Recipient lookup RPC — minimal preview only.
CREATE OR REPLACE FUNCTION public.wallet_p2p_lookup_recipient(p_phone text)
RETURNS TABLE(user_id uuid, display_name text, masked_phone text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_norm   text;
  v_local  text;
  v_masked text;
  v_uid    uuid;
  v_name   text;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_norm := public._normalize_guinea_phone(p_phone);
  IF v_norm IS NULL THEN
    RAISE EXCEPTION 'invalid_phone';
  END IF;

  SELECT p.user_id, COALESCE(NULLIF(trim(p.full_name), ''), 'Utilisateur CHOP')
    INTO v_uid, v_name
    FROM public.profiles p
   WHERE p.phone = v_norm
   LIMIT 1;

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'recipient_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_uid = v_caller THEN
    RAISE EXCEPTION 'self_transfer_forbidden';
  END IF;
  IF public.is_user_banned(v_uid) THEN
    RAISE EXCEPTION 'recipient_unavailable';
  END IF;

  -- Mask phone: +224 XX XX XX <last 2>
  v_local := substr(v_norm, 5);
  IF length(v_local) >= 4 THEN
    v_masked := '+224 ••• ••• ' || right(v_local, 2);
  ELSE
    v_masked := '+224 •••';
  END IF;

  -- Only return first name segment for privacy
  v_name := split_part(v_name, ' ', 1);

  user_id := v_uid;
  display_name := v_name;
  masked_phone := v_masked;
  RETURN NEXT;
END;
$function$;

REVOKE ALL ON FUNCTION public.wallet_p2p_lookup_recipient(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.wallet_p2p_lookup_recipient(text) TO authenticated;

-- 3) P2P transfer RPC.
CREATE OR REPLACE FUNCTION public.wallet_p2p_transfer(
  p_recipient_user_id uuid,
  p_amount_gnf bigint,
  p_note text DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL
)
RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  -- Hard-coded v1 limits (documented in phase plan).
  c_min_single       constant bigint := 1000;
  c_max_single       constant bigint := 500000;
  c_max_daily_total  constant bigint := 1500000;
  c_max_daily_count  constant integer := 10;

  v_sender    uuid := auth.uid();
  v_from_w    public.wallets;
  v_to_w      public.wallets;
  v_today_sum bigint;
  v_today_cnt integer;
  v_ref       text;
  v_idem      text;
  v_note      text;
  v_tx        public.wallet_transactions;
BEGIN
  IF v_sender IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_recipient_user_id IS NULL THEN
    RAISE EXCEPTION 'recipient_required';
  END IF;
  IF p_recipient_user_id = v_sender THEN
    RAISE EXCEPTION 'self_transfer_forbidden';
  END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;
  IF p_amount_gnf < c_min_single THEN
    RAISE EXCEPTION 'p2p_limit_single_min:%', c_min_single;
  END IF;
  IF p_amount_gnf > c_max_single THEN
    RAISE EXCEPTION 'p2p_limit_single_exceeded:%', c_max_single;
  END IF;

  IF public.is_user_banned(p_recipient_user_id) THEN
    RAISE EXCEPTION 'recipient_unavailable';
  END IF;

  -- Sender client wallet (auto-create if missing).
  INSERT INTO public.wallets (owner_user_id, party_type)
    VALUES (v_sender, 'client')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT * INTO v_from_w FROM public.wallets
    WHERE owner_user_id = v_sender AND party_type = 'client' LIMIT 1;
  IF v_from_w.id IS NULL THEN RAISE EXCEPTION 'sender_wallet_missing'; END IF;
  IF v_from_w.status <> 'active' THEN RAISE EXCEPTION 'sender_wallet_not_active'; END IF;

  -- Recipient client wallet (auto-create if missing).
  INSERT INTO public.wallets (owner_user_id, party_type)
    VALUES (p_recipient_user_id, 'client')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT * INTO v_to_w FROM public.wallets
    WHERE owner_user_id = p_recipient_user_id AND party_type = 'client' LIMIT 1;
  IF v_to_w.id IS NULL THEN RAISE EXCEPTION 'recipient_wallet_missing'; END IF;
  IF v_to_w.status <> 'active' THEN RAISE EXCEPTION 'recipient_wallet_not_active'; END IF;

  IF (COALESCE(v_from_w.balance_gnf,0) - COALESCE(v_from_w.held_gnf,0)) < p_amount_gnf THEN
    RAISE EXCEPTION 'insufficient_funds';
  END IF;

  -- Daily caps based on completed P2P transfers from this sender today (UTC).
  SELECT COALESCE(SUM(amount_gnf),0), COUNT(*)
    INTO v_today_sum, v_today_cnt
    FROM public.wallet_transactions
   WHERE from_wallet_id = v_from_w.id
     AND status = 'completed'
     AND created_at >= date_trunc('day', now())
     AND metadata->>'source_module' = 'p2p';

  IF v_today_cnt >= c_max_daily_count THEN
    RAISE EXCEPTION 'p2p_limit_daily_count_exceeded:%', c_max_daily_count;
  END IF;
  IF v_today_sum + p_amount_gnf > c_max_daily_total THEN
    RAISE EXCEPTION 'p2p_limit_daily_total_exceeded:%', c_max_daily_total;
  END IF;

  -- Note sanitization (length cap, no control chars).
  v_note := NULLIF(trim(regexp_replace(COALESCE(p_note,''), E'[\\r\\n\\t]+', ' ', 'g')), '');
  IF v_note IS NOT NULL AND length(v_note) > 140 THEN
    v_note := left(v_note, 140);
  END IF;

  -- Deterministic reference.
  v_idem := NULLIF(trim(p_idempotency_key), '');
  IF v_idem IS NULL THEN
    v_idem := encode(gen_random_bytes(12), 'hex');
  END IF;
  v_ref := 'p2p:' || v_sender::text || ':' || p_recipient_user_id::text || ':' || v_idem;

  v_tx := public.wallet_internal_transfer_v2(
    p_from_wallet_id := v_from_w.id,
    p_to_wallet_id   := v_to_w.id,
    p_amount_gnf     := p_amount_gnf,
    p_reference      := v_ref,
    p_transfer_type  := 'transfer',
    p_description    := COALESCE('Transfert CHOP' || CASE WHEN v_note IS NOT NULL THEN ' — ' || v_note ELSE '' END, 'Transfert CHOP'),
    p_source_module  := 'p2p',
    p_source_id      := v_idem,
    p_metadata       := jsonb_build_object(
      'source_module',       'p2p',
      'sender_user_id',      v_sender,
      'recipient_user_id',   p_recipient_user_id,
      'note',                v_note,
      'idempotency_key',     v_idem,
      'created_by_function', 'wallet_p2p_transfer'
    )
  );

  RETURN v_tx;
END;
$function$;

REVOKE ALL ON FUNCTION public.wallet_p2p_transfer(uuid, bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.wallet_p2p_transfer(uuid, bigint, text, text) TO authenticated;

-- 4) Admin audit preview for P2P transfers.
CREATE OR REPLACE FUNCTION public.admin_preview_p2p_transfers(p_limit integer DEFAULT 100)
RETURNS TABLE(
  reference text,
  sender_user_id uuid,
  recipient_user_id uuid,
  amount_gnf bigint,
  status text,
  note text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT
    t.reference,
    (t.metadata->>'sender_user_id')::uuid,
    (t.metadata->>'recipient_user_id')::uuid,
    t.amount_gnf,
    t.status::text,
    -- Mask note (first 60 chars) to keep audit lightweight + privacy-safe.
    left(COALESCE(t.metadata->>'note',''), 60),
    t.created_at
    FROM public.wallet_transactions t
   WHERE t.metadata->>'source_module' = 'p2p'
   ORDER BY t.created_at DESC
   LIMIT GREATEST(1, LEAST(p_limit, 500));
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_preview_p2p_transfers(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_preview_p2p_transfers(integer) TO authenticated;
