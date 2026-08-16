
CREATE OR REPLACE FUNCTION public.marche_create_offer_payment_intent(p_offer_id uuid)
RETURNS payment_intents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_caller uuid := auth.uid();
  v_offer  public.marketplace_offers;
  v_listing public.marketplace_listings;
  v_amount bigint;
  v_store_id uuid;
  v_intent public.payment_intents;
  v_new_pay text;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_offer FROM public.marketplace_offers WHERE id = p_offer_id;
  IF v_offer.id IS NULL THEN
    RAISE EXCEPTION 'offer_not_found';
  END IF;

  IF v_offer.buyer_user_id <> v_caller THEN
    RAISE EXCEPTION 'forbidden_not_buyer' USING ERRCODE = '42501';
  END IF;

  IF v_offer.status <> 'accepted' THEN
    IF public.marche_offer_is_expired(v_offer) THEN
      RAISE EXCEPTION 'offer_expired';
    END IF;
    RAISE EXCEPTION 'offer_not_accepted';
  END IF;

  IF v_offer.payment_status IN ('authorized','paid') THEN
    IF v_offer.payment_intent_id IS NOT NULL THEN
      SELECT * INTO v_intent FROM public.payment_intents WHERE id = v_offer.payment_intent_id;
      IF v_intent.id IS NOT NULL THEN RETURN v_intent; END IF;
    END IF;
    RAISE EXCEPTION 'offer_already_paid';
  END IF;

  -- R2: the binding amount is the frozen mutual agreement, nothing else.
  v_amount := v_offer.agreed_amount_gnf;
  IF v_amount IS NULL THEN
    RAISE EXCEPTION 'agreement_missing';
  END IF;
  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;

  SELECT * INTO v_listing FROM public.marketplace_listings WHERE id = v_offer.listing_id;
  IF v_listing.id IS NULL THEN
    RAISE EXCEPTION 'listing_not_found';
  END IF;
  IF v_listing.status::text IN ('sold','cancelled','removed') THEN
    RAISE EXCEPTION 'listing_unavailable';
  END IF;

  v_store_id := COALESCE(v_offer.merchant_store_id, v_listing.store_id);

  v_intent := public.choppay_create_payment_intent(
    p_source_module     := 'marketplace',
    p_source_id         := v_offer.id,
    p_amount_gnf        := v_amount,
    p_purpose           := 'marche_payment'::payment_purpose,
    p_merchant_store_id := v_store_id,
    p_payee_user_id     := v_offer.merchant_user_id,
    p_description       := 'Paiement Marché',
    p_metadata          := jsonb_build_object(
      'offer_id',         v_offer.id,
      'listing_id',       v_listing.id,
      'listing_title',    v_listing.title,
      'merchant_store_id', v_store_id,
      'seller_user_id',   v_offer.merchant_user_id,
      'buyer_user_id',    v_offer.buyer_user_id,
      'amount_gnf',       v_amount,
      'agreed_amount_gnf', v_amount,
      'agreed_by_user_id', v_offer.agreed_by_user_id
    ),
    p_use_wallet        := true
  );

  v_new_pay := CASE v_intent.state::text
    WHEN 'processing' THEN 'authorized'
    WHEN 'confirmed'  THEN 'authorized'
    WHEN 'failed'     THEN 'failed'
    WHEN 'pending'    THEN 'pending'
    ELSE v_offer.payment_status
  END;

  UPDATE public.marketplace_offers
     SET payment_intent_id = v_intent.id,
         payment_status    = v_new_pay,
         authorized_at     = CASE WHEN v_new_pay = 'authorized' THEN now() ELSE authorized_at END,
         updated_at        = now()
   WHERE id = v_offer.id;

  RETURN v_intent;
END $fn$;

CREATE OR REPLACE FUNCTION public.marche_complete_offer(p_offer_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
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

  IF v_offer.agreed_amount_gnf IS NULL OR v_offer.agreed_amount_gnf <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason','agreement_missing','offer_id', v_offer.id);
  END IF;

  SELECT * INTO v_listing FROM public.marketplace_listings WHERE id = v_offer.listing_id;
  IF v_listing.id IS NULL THEN
    RAISE EXCEPTION 'listing_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_listing.status::text IN ('cancelled','removed') THEN
    RETURN jsonb_build_object('ok', false, 'reason','listing_unavailable','offer_id', v_offer.id);
  END IF;

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

  IF v_intent.state = 'processing' THEN
    v_captured := public.choppay_capture_payment_intent(v_intent.id, COALESCE(p_reason, 'Marché offer fulfilled'));
  ELSE
    v_captured := v_intent;
  END IF;

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

  v_store_id := COALESCE(v_offer.merchant_store_id, v_listing.store_id, v_captured.related_store_id);

  -- R2: merchant settlement follows the frozen mutual agreement only.
  v_amount := v_offer.agreed_amount_gnf;

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
      'agreed_amount_gnf', v_offer.agreed_amount_gnf,
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
END $fn$;
