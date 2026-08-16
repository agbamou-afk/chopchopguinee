
-- ============ 1. CREATION (canonical R1/R1.5 truth) ============
CREATE OR REPLACE FUNCTION public.create_marketplace_offer(
  p_listing_id uuid, p_amount_gnf bigint, p_message text DEFAULT NULL, p_payment_method text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  caller uuid := auth.uid();
  v public.marketplace_listings;
  v_truth jsonb;
  v_offer_id uuid;
  v_meta jsonb := '{}'::jsonb;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF public.is_user_banned(caller) THEN RAISE EXCEPTION 'account blocked'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.account_freezes
    WHERE user_id = caller AND status = 'active'
      AND (expires_at IS NULL OR expires_at > now())
  ) THEN
    RAISE EXCEPTION 'account frozen';
  END IF;

  IF p_payment_method IS NOT NULL AND p_payment_method NOT IN ('cash','choppay') THEN
    RAISE EXCEPTION 'INVALID_TENDER';
  END IF;

  SELECT * INTO v FROM public.marketplace_listings WHERE id = p_listing_id;
  IF v.id IS NULL THEN RAISE EXCEPTION 'listing not found'; END IF;
  IF v.seller_id = caller THEN RAISE EXCEPTION 'cannot offer on own listing'; END IF;

  -- Canonical R1/R1.5 truth is the single source of orderability.
  v_truth := public.marche_listing_truth(p_listing_id);
  IF v_truth IS NULL OR NOT COALESCE((v_truth->>'is_orderable')::boolean, false) THEN
    RAISE EXCEPTION '%', COALESCE(v_truth->>'refusal_reason', 'LISTING_NOT_ORDERABLE');
  END IF;

  IF NOT v.allow_offers OR v.pricing_mode NOT IN ('negotiable','quote') THEN
    RAISE EXCEPTION 'offers not allowed';
  END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN RAISE EXCEPTION 'invalid amount'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.marketplace_offers
    WHERE listing_id = p_listing_id AND buyer_user_id = caller
      AND status IN ('pending','countered')
      AND (expires_at IS NULL OR expires_at > now())
  ) THEN
    RAISE EXCEPTION 'pending offer already exists';
  END IF;

  IF p_payment_method IS NOT NULL THEN
    v_meta := jsonb_build_object('payment_method', p_payment_method);
  END IF;

  INSERT INTO public.marketplace_offers (
    listing_id, merchant_store_id, buyer_user_id, merchant_user_id,
    offer_amount_gnf, buyer_message, expires_at, metadata,
    status, current_proposer_role
  ) VALUES (
    p_listing_id, v.store_id, caller, v.seller_id,
    p_amount_gnf, nullif(trim(p_message), ''), now() + interval '7 days',
    CASE WHEN p_payment_method IS NULL THEN '{}'::jsonb ELSE v_meta END,
    'pending', 'buyer'
  ) RETURNING id INTO v_offer_id;

  RETURN v_offer_id;
END $fn$;

-- ============ 2. EXPIRY TRUTH ============
CREATE OR REPLACE FUNCTION public.marche_offer_is_expired(p_offer public.marketplace_offers)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $fn$
  SELECT p_offer.status IN ('pending','countered')
     AND p_offer.expires_at IS NOT NULL
     AND p_offer.expires_at <= now();
$fn$;

CREATE OR REPLACE FUNCTION public.marche_offer_expire_due(p_limit integer DEFAULT 500)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_uid uuid := auth.uid(); v_n int := 0;
BEGIN
  IF NOT (current_user IN ('service_role','postgres','supabase_admin')
          OR (v_uid IS NOT NULL AND public.is_any_admin(v_uid))) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  WITH due AS (
    SELECT id FROM public.marketplace_offers
     WHERE status IN ('pending','countered')
       AND expires_at IS NOT NULL AND expires_at <= now()
     ORDER BY expires_at
     LIMIT GREATEST(COALESCE(p_limit,500), 1)
     FOR UPDATE SKIP LOCKED
  ), upd AS (
    UPDATE public.marketplace_offers o
       SET status = 'expired', expired_at = now(), updated_at = now()
      FROM due WHERE o.id = due.id
      RETURNING o.id
  )
  SELECT count(*) INTO v_n FROM upd;

  RETURN jsonb_build_object('ok', true, 'expired', v_n);
END $fn$;

-- ============ 3. MERCHANT RESPONSE ============
CREATE OR REPLACE FUNCTION public.merchant_respond_marketplace_offer(
  p_offer_id uuid, p_action text, p_counter_amount_gnf bigint DEFAULT NULL, p_message text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  caller uuid := auth.uid();
  o public.marketplace_offers;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF public.is_user_banned(caller) THEN RAISE EXCEPTION 'account blocked'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.account_freezes
    WHERE user_id = caller AND status = 'active'
      AND (expires_at IS NULL OR expires_at > now())
  ) THEN RAISE EXCEPTION 'account frozen'; END IF;

  SELECT * INTO o FROM public.marketplace_offers WHERE id = p_offer_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'offer not found'; END IF;
  IF o.merchant_user_id <> caller AND NOT public.is_any_admin(caller) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF o.status NOT IN ('pending','countered') THEN
    RAISE EXCEPTION 'offer closed';
  END IF;
  IF public.marche_offer_is_expired(o) THEN
    RAISE EXCEPTION 'OFFER_EXPIRED';
  END IF;

  IF p_action = 'accept' THEN
    IF o.current_proposer_role <> 'buyer' THEN
      RAISE EXCEPTION 'COUNTER_AWAITS_BUYER';
    END IF;
    UPDATE public.marketplace_offers
      SET status = 'accepted',
          agreed_amount_gnf = o.offer_amount_gnf,
          agreed_by_user_id = o.merchant_user_id,
          agreed_at = now(),
          merchant_message = nullif(trim(p_message), ''),
          responded_at = now()
      WHERE id = p_offer_id;

  ELSIF p_action = 'reject' THEN
    UPDATE public.marketplace_offers
      SET status = 'rejected', merchant_message = nullif(trim(p_message), ''),
          responded_at = now()
      WHERE id = p_offer_id;

  ELSIF p_action = 'counter' THEN
    IF o.status = 'countered' OR o.current_proposer_role = 'merchant' THEN
      RAISE EXCEPTION 'COUNTER_AWAITS_BUYER';
    END IF;
    IF p_counter_amount_gnf IS NULL OR p_counter_amount_gnf <= 0 THEN
      RAISE EXCEPTION 'invalid counter amount';
    END IF;
    UPDATE public.marketplace_offers
      SET status = 'countered',
          counter_amount_gnf = p_counter_amount_gnf,
          current_proposer_role = 'merchant',
          merchant_message = nullif(trim(p_message), ''),
          responded_at = now()
      WHERE id = p_offer_id;
  ELSE
    RAISE EXCEPTION 'invalid action';
  END IF;
END $fn$;

-- ============ 4. BUYER RESPONSE ============
CREATE OR REPLACE FUNCTION public.buyer_respond_marketplace_offer(
  p_offer_id uuid, p_action text, p_message text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  caller uuid := auth.uid();
  o public.marketplace_offers;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF public.is_user_banned(caller) THEN RAISE EXCEPTION 'account blocked'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.account_freezes
    WHERE user_id = caller AND status = 'active'
      AND (expires_at IS NULL OR expires_at > now())
  ) THEN RAISE EXCEPTION 'account frozen'; END IF;

  SELECT * INTO o FROM public.marketplace_offers WHERE id = p_offer_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'offer not found'; END IF;
  IF o.buyer_user_id <> caller THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF o.status <> 'countered' OR o.current_proposer_role <> 'merchant' THEN
    RAISE EXCEPTION 'NO_MERCHANT_PROPOSAL';
  END IF;
  IF public.marche_offer_is_expired(o) THEN
    RAISE EXCEPTION 'OFFER_EXPIRED';
  END IF;

  IF p_action = 'accept' THEN
    IF o.counter_amount_gnf IS NULL OR o.counter_amount_gnf <= 0 THEN
      RAISE EXCEPTION 'invalid counter amount';
    END IF;
    UPDATE public.marketplace_offers
      SET status = 'accepted',
          agreed_amount_gnf = o.counter_amount_gnf,
          agreed_by_user_id = o.buyer_user_id,
          agreed_at = now(),
          buyer_message = COALESCE(nullif(trim(p_message), ''), buyer_message),
          responded_at = now()
      WHERE id = p_offer_id;
  ELSIF p_action = 'reject' THEN
    UPDATE public.marketplace_offers
      SET status = 'rejected',
          buyer_message = COALESCE(nullif(trim(p_message), ''), buyer_message),
          responded_at = now()
      WHERE id = p_offer_id;
  ELSE
    RAISE EXCEPTION 'invalid action';
  END IF;
END $fn$;

-- ============ 5. WITHDRAW ============
CREATE OR REPLACE FUNCTION public.withdraw_marketplace_offer(p_offer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  caller uuid := auth.uid();
  o public.marketplace_offers;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO o FROM public.marketplace_offers WHERE id = p_offer_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'offer not found'; END IF;
  IF o.buyer_user_id <> caller THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF o.status NOT IN ('pending','countered') THEN
    RAISE EXCEPTION 'offer closed';
  END IF;
  IF public.marche_offer_is_expired(o) THEN
    RAISE EXCEPTION 'OFFER_EXPIRED';
  END IF;
  UPDATE public.marketplace_offers
    SET status = 'withdrawn', responded_at = now()
    WHERE id = p_offer_id;
END $fn$;

-- ============ 6. SANITIZED READS ============
CREATE OR REPLACE FUNCTION public.marche_offer_get(p_offer_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE caller uuid := auth.uid(); o public.marketplace_offers; l public.marketplace_listings;
BEGIN
  IF caller IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO o FROM public.marketplace_offers WHERE id = p_offer_id;
  IF o.id IS NULL THEN RETURN NULL; END IF;
  IF o.buyer_user_id <> caller AND o.merchant_user_id <> caller AND NOT public.is_any_admin(caller) THEN
    RETURN NULL;
  END IF;
  SELECT * INTO l FROM public.marketplace_listings WHERE id = o.listing_id;
  RETURN jsonb_build_object(
    'id', o.id, 'listing_id', o.listing_id, 'listing_title', l.title,
    'merchant_store_id', o.merchant_store_id,
    'buyer_user_id', o.buyer_user_id, 'merchant_user_id', o.merchant_user_id,
    'offer_amount_gnf', o.offer_amount_gnf, 'counter_amount_gnf', o.counter_amount_gnf,
    'agreed_amount_gnf', o.agreed_amount_gnf, 'agreed_by_user_id', o.agreed_by_user_id,
    'agreed_at', o.agreed_at, 'current_proposer_role', o.current_proposer_role,
    'status', CASE WHEN public.marche_offer_is_expired(o) THEN 'expired' ELSE o.status END,
    'buyer_message', o.buyer_message, 'merchant_message', o.merchant_message,
    'expires_at', o.expires_at, 'expired_at', o.expired_at, 'responded_at', o.responded_at,
    'created_at', o.created_at, 'updated_at', o.updated_at,
    'payment_status', o.payment_status, 'payment_intent_id', o.payment_intent_id,
    'authorized_at', o.authorized_at, 'paid_at', o.paid_at,
    'fulfillment_status', o.fulfillment_status, 'fulfilled_at', o.fulfilled_at,
    'completed_at', o.completed_at, 'settlement_state', o.settlement_state,
    'payment_method', o.metadata->>'payment_method'
  );
END $fn$;

CREATE OR REPLACE FUNCTION public.marche_offers_for_buyer(p_listing_id uuid DEFAULT NULL, p_limit integer DEFAULT 100)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE caller uuid := auth.uid();
BEGIN
  IF caller IS NULL THEN RETURN; END IF;
  RETURN QUERY
    SELECT public.marche_offer_get(o.id)
      FROM public.marketplace_offers o
     WHERE o.buyer_user_id = caller
       AND (p_listing_id IS NULL OR o.listing_id = p_listing_id)
     ORDER BY o.created_at DESC
     LIMIT GREATEST(COALESCE(p_limit,100),1);
END $fn$;

CREATE OR REPLACE FUNCTION public.marche_offers_for_merchant(p_limit integer DEFAULT 100)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE caller uuid := auth.uid();
BEGIN
  IF caller IS NULL THEN RETURN; END IF;
  RETURN QUERY
    SELECT public.marche_offer_get(o.id)
      FROM public.marketplace_offers o
     WHERE o.merchant_user_id = caller
     ORDER BY o.created_at DESC
     LIMIT GREATEST(COALESCE(p_limit,100),1);
END $fn$;

CREATE OR REPLACE FUNCTION public.marche_offers_admin(p_limit integer DEFAULT 200)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE caller uuid := auth.uid();
BEGIN
  IF caller IS NULL OR NOT public.is_any_admin(caller) THEN RETURN; END IF;
  RETURN QUERY
    SELECT public.marche_offer_get(o.id)
      FROM public.marketplace_offers o
     ORDER BY o.created_at DESC
     LIMIT GREATEST(COALESCE(p_limit,200),1);
END $fn$;

-- ============ 7. AUTHORITY / GRANTS ============
REVOKE INSERT, UPDATE, DELETE ON public.marketplace_offers FROM anon, authenticated;
REVOKE ALL ON public.marketplace_offers FROM anon;
GRANT SELECT ON public.marketplace_offers TO authenticated;
GRANT ALL ON public.marketplace_offers TO service_role;

REVOKE ALL ON FUNCTION public.marche_offer_expire_due(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marche_offer_expire_due(integer) TO service_role;

REVOKE ALL ON FUNCTION public.buyer_respond_marketplace_offer(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buyer_respond_marketplace_offer(uuid, text, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.marche_offer_get(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_offer_get(uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.marche_offers_for_buyer(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_offers_for_buyer(uuid, integer) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.marche_offers_for_merchant(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_offers_for_merchant(integer) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.marche_offers_admin(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_offers_admin(integer) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.marche_offer_is_expired(public.marketplace_offers) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_offer_is_expired(public.marketplace_offers) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_marketplace_offer(uuid, bigint, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_marketplace_offer(uuid, bigint, text, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.merchant_respond_marketplace_offer(uuid, text, bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.merchant_respond_marketplace_offer(uuid, text, bigint, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.withdraw_marketplace_offer(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.withdraw_marketplace_offer(uuid) TO authenticated, service_role;
