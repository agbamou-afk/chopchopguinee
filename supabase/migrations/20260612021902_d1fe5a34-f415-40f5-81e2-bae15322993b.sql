
-- =========================================================
-- Phase 7B — Marché Capture + Merchant Settlement
-- =========================================================

-- 1) Fulfillment + settlement columns on marketplace_offers
ALTER TABLE public.marketplace_offers
  ADD COLUMN IF NOT EXISTS fulfillment_status text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS fulfilled_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS completed_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS settlement_state text NOT NULL DEFAULT 'pending';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'marketplace_offers_fulfillment_status_chk') THEN
    ALTER TABLE public.marketplace_offers
      ADD CONSTRAINT marketplace_offers_fulfillment_status_chk
      CHECK (fulfillment_status IN ('pending','handed_over','delivered','completed','cancelled','needs_review'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'marketplace_offers_settlement_state_chk') THEN
    ALTER TABLE public.marketplace_offers
      ADD CONSTRAINT marketplace_offers_settlement_state_chk
      CHECK (settlement_state IN ('pending','settled','needs_review','failed'));
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS marketplace_offers_settlement_state_idx
  ON public.marketplace_offers(settlement_state, created_at DESC);

-- 2) Trusted Marché completion RPC: capture + settle in one step.
CREATE OR REPLACE FUNCTION public.marche_complete_offer(
  p_offer_id uuid,
  p_reason   text DEFAULT 'Marché offer fulfilled'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_caller    text := current_user;
  v_uid       uuid := auth.uid();
  v_offer     public.marketplace_offers%ROWTYPE;
  v_listing   public.marketplace_listings%ROWTYPE;
  v_intent    public.payment_intents%ROWTYPE;
  v_captured  public.payment_intents%ROWTYPE;
  v_store_id  uuid;
  v_amount    bigint;
  v_settle_tx public.wallet_transactions%ROWTYPE;
  v_settle_state text;
  v_reference text;
  v_is_admin  boolean := (v_uid IS NOT NULL AND public.is_any_admin(v_uid));
  v_is_trusted boolean := (v_caller IN ('service_role','postgres','supabase_admin'));
BEGIN
  SELECT * INTO v_offer FROM public.marketplace_offers WHERE id = p_offer_id FOR UPDATE;
  IF v_offer.id IS NULL THEN
    RAISE EXCEPTION 'offer_not_found' USING ERRCODE = 'P0002';
  END IF;

  -- Permission: seller (merchant_user_id), buyer, admin, or trusted role.
  IF NOT (
    v_is_trusted
    OR v_is_admin
    OR (v_uid IS NOT NULL AND (v_uid = v_offer.merchant_user_id OR v_uid = v_offer.buyer_user_id))
  ) THEN
    RAISE EXCEPTION 'forbidden_completion' USING ERRCODE = '42501';
  END IF;

  IF v_offer.status <> 'accepted' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reason', 'offer_not_accepted',
      'offer_id', v_offer.id,
      'offer_status', v_offer.status
    );
  END IF;

  SELECT * INTO v_listing FROM public.marketplace_listings WHERE id = v_offer.listing_id;
  IF v_listing.id IS NULL THEN
    RAISE EXCEPTION 'listing_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_listing.status::text IN ('cancelled','removed') THEN
    RETURN jsonb_build_object('ok', false, 'reason','listing_unavailable','offer_id', v_offer.id);
  END IF;

  -- Idempotent: already paid + settled.
  IF v_offer.payment_status = 'paid' AND v_offer.settlement_state = 'settled' THEN
    RETURN jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'offer_id', v_offer.id,
      'payment_status', v_offer.payment_status,
      'settlement_state', v_offer.settlement_state,
      'captured_tx_id', v_offer.captured_tx_id,
      'settlement_tx_id', v_offer.settlement_tx_id
    );
  END IF;

  -- Locate latest payment intent for this offer + buyer.
  SELECT * INTO v_intent
    FROM public.payment_intents
   WHERE source_module = 'marketplace'
     AND source_id = v_offer.id
     AND user_id = v_offer.buyer_user_id
   ORDER BY created_at DESC
   LIMIT 1;

  IF v_intent.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason','no_payment_intent','offer_id', v_offer.id);
  END IF;

  IF v_intent.state NOT IN ('processing','confirmed') THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reason','payment_not_authorized',
      'offer_id', v_offer.id,
      'intent_state', v_intent.state
    );
  END IF;

  -- Capture if not yet captured.
  IF v_intent.state = 'processing' THEN
    v_captured := public.choppay_capture_payment_intent(v_intent.id, COALESCE(p_reason, 'Marché offer fulfilled'));
  ELSE
    v_captured := v_intent;
  END IF;

  -- Mark offer paid + fulfilled (trigger allows service_role / postgres / admin / trusted definer).
  UPDATE public.marketplace_offers
     SET payment_status   = 'paid',
         paid_at          = COALESCE(paid_at, now()),
         captured_tx_id   = v_captured.captured_tx_id,
         fulfillment_status = CASE
           WHEN fulfillment_status IN ('pending') THEN 'completed'
           ELSE fulfillment_status
         END,
         fulfilled_at     = COALESCE(fulfilled_at, now()),
         completed_at     = COALESCE(completed_at, now()),
         updated_at       = now()
   WHERE id = v_offer.id
   RETURNING * INTO v_offer;

  -- Resolve merchant store (offer link → listing.store_id → intent metadata).
  v_store_id := COALESCE(v_offer.merchant_store_id, v_listing.store_id, v_captured.related_store_id);

  -- Net merchant amount = accepted offer amount (counter overrides original).
  v_amount := COALESCE(v_offer.counter_amount_gnf, v_offer.offer_amount_gnf);

  IF v_store_id IS NULL OR v_amount IS NULL OR v_amount <= 0 THEN
    v_settle_state := 'needs_review';
    UPDATE public.marketplace_offers
       SET settlement_state = v_settle_state, updated_at = now()
     WHERE id = v_offer.id;

    BEGIN
      INSERT INTO public.audit_logs (actor_user_id, action, resource_type, resource_id, metadata)
      VALUES (v_uid, 'marche.payment.captured_needs_review', 'marketplace_offer', v_offer.id,
        jsonb_build_object('reason',
          CASE WHEN v_store_id IS NULL THEN 'missing_merchant_store_id' ELSE 'invalid_amount' END,
          'intent_id', v_captured.id));
    EXCEPTION WHEN OTHERS THEN NULL; END;

    RETURN jsonb_build_object(
      'ok', true,
      'captured', true,
      'settled', false,
      'reason', CASE WHEN v_store_id IS NULL THEN 'missing_merchant_store_id' ELSE 'invalid_amount' END,
      'offer_id', v_offer.id,
      'captured_tx_id', v_captured.captured_tx_id,
      'payment_status', 'paid',
      'settlement_state', v_settle_state
    );
  END IF;

  -- Idempotent merchant settlement.
  v_reference := 'marche_merchant_revenue:' || v_offer.id::text;
  v_settle_tx := public.wallet_settle_merchant_revenue(
    p_source_module     := 'marketplace',
    p_source_id         := v_offer.id,
    p_merchant_store_id := v_store_id,
    p_amount_gnf        := v_amount,
    p_reference         := v_reference,
    p_description       := 'Paiement Marché reçu',
    p_metadata          := jsonb_build_object(
      'offer_id',          v_offer.id,
      'listing_id',        v_listing.id,
      'listing_title',     v_listing.title,
      'buyer_user_id',     v_offer.buyer_user_id,
      'seller_user_id',    v_offer.merchant_user_id,
      'merchant_store_id', v_store_id,
      'offer_amount_gnf',  v_offer.offer_amount_gnf,
      'net_merchant_amount_gnf', v_amount,
      'payment_intent_id', v_captured.id,
      'captured_tx_id',    v_captured.captured_tx_id,
      'fulfillment_status', v_offer.fulfillment_status,
      'created_by_function', 'marche_complete_offer'
    )
  );

  UPDATE public.marketplace_offers
     SET settlement_tx_id  = v_settle_tx.id,
         settlement_state  = 'settled',
         updated_at        = now()
   WHERE id = v_offer.id
   RETURNING * INTO v_offer;

  BEGIN
    INSERT INTO public.audit_logs (actor_user_id, action, resource_type, resource_id, metadata)
    VALUES (v_uid, 'marche.payment.capture_and_settle', 'marketplace_offer', v_offer.id,
      jsonb_build_object(
        'captured_tx_id', v_captured.captured_tx_id,
        'settlement_tx_id', v_settle_tx.id,
        'amount_gnf', v_amount,
        'merchant_store_id', v_store_id,
        'reason', p_reason
      ));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object(
    'ok', true,
    'captured', true,
    'settled', true,
    'offer_id', v_offer.id,
    'payment_status', 'paid',
    'settlement_state', 'settled',
    'captured_tx_id', v_captured.captured_tx_id,
    'settlement_tx_id', v_settle_tx.id,
    'amount_gnf', v_amount
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.marche_complete_offer(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marche_complete_offer(uuid, text) TO authenticated, service_role;

-- 3) Admin wrapper with audit log.
CREATE OR REPLACE FUNCTION public.admin_marche_capture_and_settle_offer(
  p_offer_id uuid,
  p_reason   text DEFAULT 'Admin capture'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  v_result := public.marche_complete_offer(p_offer_id, COALESCE(p_reason, 'Admin capture'));

  BEGIN
    INSERT INTO public.audit_logs (actor_user_id, action, resource_type, resource_id, metadata)
    VALUES (auth.uid(), 'marche.payment.admin_capture_and_settle', 'marketplace_offer', p_offer_id, v_result);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_marche_capture_and_settle_offer(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_marche_capture_and_settle_offer(uuid, text) TO authenticated;

-- 4) Admin preview for capture/settle queue.
CREATE OR REPLACE FUNCTION public.admin_preview_marche_payment_settlement(p_limit integer DEFAULT 100)
RETURNS TABLE(
  offer_id uuid,
  listing_id uuid,
  listing_title text,
  buyer_user_id uuid,
  seller_user_id uuid,
  merchant_store_id uuid,
  amount_gnf bigint,
  offer_status text,
  payment_status text,
  payment_intent_id uuid,
  payment_intent_state text,
  fulfillment_status text,
  settlement_state text,
  eligible_for_capture boolean,
  eligible_for_settlement boolean,
  reason text,
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
  WITH latest_intent AS (
    SELECT DISTINCT ON (pi.source_id) pi.*
    FROM public.payment_intents pi
    WHERE pi.source_module = 'marketplace'
    ORDER BY pi.source_id, pi.created_at DESC
  )
  SELECT
    o.id,
    o.listing_id,
    l.title,
    o.buyer_user_id,
    o.merchant_user_id,
    COALESCE(o.merchant_store_id, l.store_id, li.related_store_id) AS merchant_store_id,
    COALESCE(o.counter_amount_gnf, o.offer_amount_gnf) AS amount_gnf,
    o.status AS offer_status,
    o.payment_status,
    li.id AS payment_intent_id,
    li.state::text AS payment_intent_state,
    o.fulfillment_status,
    o.settlement_state,
    (o.status = 'accepted'
       AND o.payment_status IN ('authorized')
       AND li.state = 'processing') AS eligible_for_capture,
    (o.status = 'accepted'
       AND o.payment_status IN ('authorized','paid')
       AND COALESCE(o.merchant_store_id, l.store_id, li.related_store_id) IS NOT NULL
       AND o.settlement_state <> 'settled') AS eligible_for_settlement,
    CASE
      WHEN li.id IS NULL THEN 'no_payment_intent'
      WHEN o.payment_status = 'paid' AND o.settlement_state = 'settled' THEN 'already_settled'
      WHEN COALESCE(o.merchant_store_id, l.store_id, li.related_store_id) IS NULL THEN 'missing_merchant_store_id'
      WHEN o.payment_status = 'failed' THEN 'auth_failed'
      WHEN o.payment_status = 'authorized' AND li.state = 'processing' THEN 'ready_to_capture'
      WHEN o.payment_status = 'paid' AND o.settlement_state <> 'settled' THEN 'ready_to_settle'
      ELSE 'ok'
    END AS reason,
    o.created_at
  FROM public.marketplace_offers o
  LEFT JOIN latest_intent li ON li.source_id = o.id
  LEFT JOIN public.marketplace_listings l ON l.id = o.listing_id
  WHERE o.status = 'accepted' OR o.payment_status <> 'unpaid'
  ORDER BY o.created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 500));
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_preview_marche_payment_settlement(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_preview_marche_payment_settlement(integer) TO authenticated;
