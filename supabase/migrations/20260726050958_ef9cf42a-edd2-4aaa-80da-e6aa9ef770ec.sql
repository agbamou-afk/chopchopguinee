
-- ============================================================================
-- Orange Money Sandbox — Slice B
-- Sandbox-aware checkout + generic server finalizer for Ride, Repas, Marché.
-- ============================================================================

-- --------------------------------------------------------------------------
-- 1. Outcome map: add FINALIZE_FAIL fixture
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.om_sandbox_reference_outcome(p_reference text)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE upper(btrim(coalesce(p_reference,'')))
    WHEN 'OM-SBX-SUCCESS-001'         THEN 'success'
    WHEN 'OM-SBX-REVIEW-001'          THEN 'review'
    WHEN 'OM-SBX-REJECT-001'          THEN 'reject'
    WHEN 'OM-SBX-DUPLICATE-001'       THEN 'duplicate'
    WHEN 'OM-SBX-EXPIRED-001'         THEN 'expired'
    WHEN 'OM-SBX-REFUND-001'          THEN 'refund'
    WHEN 'OM-SBX-REFUND-REVIEW-001'   THEN 'refund_review'
    WHEN 'OM-SBX-FINALIZE-FAIL-001'   THEN 'finalize_fail'
    ELSE NULL
  END;
$$;

-- --------------------------------------------------------------------------
-- 2. Submit RPC: treat FINALIZE_FAIL like success at the payment layer but
--    stamp a metadata marker so the finalizer produces a controlled failure.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.om_payment_submit_sandbox_reference(
  p_payment_intent_id uuid,
  p_provider_reference text,
  p_payer_phone text DEFAULT NULL,
  p_test_run_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_uid          uuid := auth.uid();
  v_is_god       boolean;
  v_intent       public.payment_intents;
  v_ref          text;
  v_outcome      text;
  v_new_state    payment_state;
  v_event        public.payment_provider_events;
  v_event_status text;
  v_env_ok       boolean;
  v_sbx_ok       boolean;
  v_tx_id        text;
  v_recon_type   text;
  v_force_ff     boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501';
  END IF;
  v_is_god := public.is_god_admin(v_uid);

  SELECT COALESCE((SELECT enabled FROM public.feature_flags WHERE key='om_environment'),   false) INTO v_env_ok;
  SELECT COALESCE((SELECT enabled FROM public.feature_flags WHERE key='om_sandbox_enabled'),false) INTO v_sbx_ok;
  IF NOT (v_env_ok AND v_sbx_ok) THEN
    RAISE EXCEPTION 'sandbox_disabled' USING ERRCODE='42501';
  END IF;

  v_ref := upper(btrim(coalesce(p_provider_reference,'')));
  IF v_ref = '' THEN RAISE EXCEPTION 'reference_required'; END IF;
  IF v_ref NOT LIKE 'OM-SBX-%' THEN
    RAISE EXCEPTION 'live_reference_rejected_on_sandbox_rpc';
  END IF;

  v_outcome := public.om_sandbox_reference_outcome(v_ref);
  IF v_outcome IS NULL THEN RAISE EXCEPTION 'unknown_sandbox_reference'; END IF;

  SELECT * INTO v_intent FROM public.payment_intents WHERE id = p_payment_intent_id FOR UPDATE;
  IF v_intent.id IS NULL THEN RAISE EXCEPTION 'intent_not_found'; END IF;
  IF NOT v_is_god AND v_intent.user_id <> v_uid THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF NOT v_intent.is_sandbox THEN RAISE EXCEPTION 'not_a_sandbox_intent'; END IF;

  -- Idempotent replay of exact reference on terminal-ish state.
  IF v_intent.provider_reference IS NOT NULL
     AND upper(btrim(v_intent.provider_reference)) = v_ref
     AND v_intent.state IN ('authorized','confirmed','failed','expired','needs_review','cancelled','refunded','reversed') THEN
    RETURN jsonb_build_object(
      'idempotent', true, 'intent_id', v_intent.id, 'intent_state', v_intent.state,
      'outcome', v_outcome, 'is_sandbox', true, 'test_run_id', v_intent.test_run_id
    );
  END IF;

  IF v_outcome = 'duplicate' THEN
    v_tx_id := 'OM-SBX-DUPLICATE-FIXED';
  ELSE
    v_tx_id := v_ref || '::' || v_intent.id::text;
  END IF;

  IF v_intent.state NOT IN ('pending','processing') THEN
    RAISE EXCEPTION 'intent_not_transitionable: state=%', v_intent.state;
  END IF;

  v_new_state    := v_intent.state;
  v_event_status := 'received';
  v_recon_type   := 'provider_pending';

  IF v_outcome = 'success' THEN
    v_new_state := 'authorized'; v_event_status := 'matched'; v_recon_type := 'provider_confirmed';
  ELSIF v_outcome = 'finalize_fail' THEN
    -- Payment side authorizes; finalizer will refuse and revert.
    v_new_state := 'authorized'; v_event_status := 'matched'; v_recon_type := 'provider_confirmed';
    v_force_ff := true;
  ELSIF v_outcome = 'review' THEN
    v_new_state := 'needs_review'; v_event_status := 'needs_review'; v_recon_type := 'provider_pending';
  ELSIF v_outcome = 'reject' THEN
    v_new_state := 'failed'; v_event_status := 'rejected'; v_recon_type := 'provider_failed';
  ELSIF v_outcome = 'expired' THEN
    v_new_state := 'expired'; v_event_status := 'rejected'; v_recon_type := 'provider_failed';
  ELSIF v_outcome = 'duplicate' THEN
    v_new_state := 'needs_review'; v_event_status := 'duplicate'; v_recon_type := 'provider_pending';
  ELSIF v_outcome IN ('refund','refund_review') THEN
    v_new_state := 'needs_review'; v_event_status := 'needs_review';
    v_recon_type := CASE WHEN v_outcome='refund' THEN 'refund_created' ELSE 'provider_pending' END;
  END IF;

  BEGIN
    INSERT INTO public.payment_provider_events (
      provider, event_type, provider_transaction_id,
      payer_phone, amount_gnf, currency, status,
      raw_payload, processing_status,
      is_sandbox, environment, test_run_id
    ) VALUES (
      'orange_money', 'sandbox.payment.simulated', v_tx_id,
      NULLIF(btrim(coalesce(p_payer_phone,'')), ''),
      v_intent.amount_gnf, v_intent.currency,
      CASE v_outcome
        WHEN 'success' THEN 'successful'
        WHEN 'finalize_fail' THEN 'successful'
        WHEN 'reject'  THEN 'failed'
        WHEN 'expired' THEN 'expired'
        ELSE 'pending'
      END,
      jsonb_build_object(
        'sandbox', true, 'reference', v_ref, 'outcome', v_outcome,
        'intent_id', v_intent.id,
        'test_run_id', COALESCE(p_test_run_id, v_intent.test_run_id)
      ),
      v_event_status, true, 'sandbox',
      COALESCE(p_test_run_id, v_intent.test_run_id)
    ) RETURNING * INTO v_event;
  EXCEPTION WHEN unique_violation THEN
    SELECT * INTO v_event FROM public.payment_provider_events
     WHERE provider='orange_money' AND provider_transaction_id = v_tx_id;
    INSERT INTO public.payment_reconciliation_events
      (intent_id, event_type, provider, provider_reference, payload, actor_user_id,
       is_sandbox, environment, test_run_id)
    VALUES (v_intent.id, 'provider_pending', 'orange_money', v_ref,
            jsonb_build_object('sandbox', true, 'duplicate_of_event', v_event.id, 'outcome', 'duplicate'),
            v_uid, true, 'sandbox', COALESCE(p_test_run_id, v_intent.test_run_id));
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
    VALUES (v_uid, 'payments', 'sandbox.payment.duplicate_rejected',
            'payment_intent', v_intent.id::text,
            jsonb_build_object('reference', v_ref, 'existing_event_id', v_event.id));
    RETURN jsonb_build_object(
      'idempotent', true, 'duplicate', true,
      'intent_id', v_intent.id, 'intent_state', v_intent.state,
      'outcome', 'duplicate', 'is_sandbox', true
    );
  END;

  UPDATE public.payment_intents pi
     SET state              = v_new_state,
         provider_reference = v_ref,
         provider_event_id  = v_event.id,
         payer_phone        = COALESCE(pi.payer_phone, NULLIF(btrim(coalesce(p_payer_phone,'')),'')),
         test_run_id        = COALESCE(pi.test_run_id, p_test_run_id),
         authorized_at      = CASE WHEN v_new_state='authorized' THEN now() ELSE pi.authorized_at END,
         rejected_at        = CASE WHEN v_new_state='failed'     THEN now() ELSE pi.rejected_at END,
         rejection_reason   = CASE WHEN v_new_state='failed'     THEN v_outcome ELSE pi.rejection_reason END,
         metadata           = pi.metadata || jsonb_build_object(
           'sandbox', true,
           'sandbox_outcome', v_outcome,
           'sandbox_reference', v_ref,
           'sandbox_event_id', v_event.id,
           'sandbox_force_finalize_fail', v_force_ff
         ),
         updated_at         = now()
   WHERE id = v_intent.id
   RETURNING * INTO v_intent;

  INSERT INTO public.payment_reconciliation_events
    (intent_id, event_type, provider, provider_reference, payload, actor_user_id,
     is_sandbox, environment, test_run_id)
  VALUES (v_intent.id, v_recon_type::payment_recon_event, 'orange_money', v_ref,
          jsonb_build_object('sandbox', true, 'outcome', v_outcome, 'event_id', v_event.id),
          v_uid, true, 'sandbox', COALESCE(p_test_run_id, v_intent.test_run_id));

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'payments',
          'sandbox.payment.' || CASE
            WHEN v_new_state='authorized'    THEN 'authorized'
            WHEN v_new_state='failed'        THEN 'rejected'
            WHEN v_new_state='expired'       THEN 'expired'
            WHEN v_new_state='needs_review'  THEN 'needs_review'
            ELSE 'transitioned' END,
          'payment_intent', v_intent.id::text,
          jsonb_build_object('reference', v_ref, 'outcome', v_outcome, 'event_id', v_event.id,
            'new_state', v_new_state, 'test_run_id', v_intent.test_run_id,
            'force_finalize_fail', v_force_ff));

  RETURN jsonb_build_object(
    'idempotent', false,
    'intent_id', v_intent.id,
    'intent_state', v_intent.state,
    'outcome', v_outcome,
    'event_id', v_event.id,
    'is_sandbox', true,
    'test_run_id', v_intent.test_run_id,
    'source_finalization', CASE
      WHEN v_new_state = 'authorized' THEN 'ready_call_om_sandbox_finalize_authorized_intent'
      ELSE 'not_applicable' END,
    'needs_review', v_new_state = 'needs_review',
    'force_finalize_fail', v_force_ff
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.om_payment_submit_sandbox_reference(uuid,text,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_payment_submit_sandbox_reference(uuid,text,text,uuid) TO authenticated;

-- --------------------------------------------------------------------------
-- 3. Skip real dispatch for sandbox rides.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rides_after_insert_dispatch()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(NEW.metadata->>'sandbox','false') = 'true' THEN
    RETURN NEW;
  END IF;
  IF NEW.status = 'pending' AND NEW.driver_id IS NULL THEN
    PERFORM public.ride_dispatch(NEW.id);
  END IF;
  RETURN NEW;
END $$;

-- --------------------------------------------------------------------------
-- 4. Sandbox activation gate helper.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._om_sandbox_require_active()
RETURNS void LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE v_env boolean; v_sbx boolean;
BEGIN
  SELECT COALESCE((SELECT enabled FROM public.feature_flags WHERE key='om_environment'),   false) INTO v_env;
  SELECT COALESCE((SELECT enabled FROM public.feature_flags WHERE key='om_sandbox_enabled'),false) INTO v_sbx;
  IF NOT (v_env AND v_sbx) THEN
    RAISE EXCEPTION 'sandbox_disabled' USING ERRCODE='42501';
  END IF;
END $$;

-- --------------------------------------------------------------------------
-- 5. Sandbox intent creation — RIDE (quote-based).
--    Idempotent per (user_id, checkout_session_id).
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.om_sandbox_create_ride_intent(
  p_mode ride_mode,
  p_pickup_lat numeric,
  p_pickup_lng numeric,
  p_dest_lat numeric,
  p_dest_lng numeric,
  p_fare_gnf bigint,
  p_checkout_session_id uuid,
  p_test_run_id uuid DEFAULT NULL
) RETURNS public.payment_intents
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_existing public.payment_intents;
  v_intent public.payment_intents;
  v_ref text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  PERFORM public._om_sandbox_require_active();

  IF p_checkout_session_id IS NULL THEN RAISE EXCEPTION 'checkout_session_id_required'; END IF;
  IF p_fare_gnf IS NULL OR p_fare_gnf <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
  IF p_pickup_lat IS NULL OR p_pickup_lng IS NULL THEN RAISE EXCEPTION 'pickup_required'; END IF;

  SELECT * INTO v_existing FROM public.payment_intents
   WHERE user_id = v_uid
     AND checkout_session_id = p_checkout_session_id
     AND is_sandbox = true
   ORDER BY created_at DESC LIMIT 1;
  IF v_existing.id IS NOT NULL THEN RETURN v_existing; END IF;

  v_ref := 'om-sbx-ride:' || v_uid::text || ':' || p_checkout_session_id::text;

  INSERT INTO public.payment_intents(
    user_id, amount_gnf, currency, purpose, state, provider,
    internal_reference, source_module, description,
    metadata, is_sandbox, environment, test_run_id, checkout_session_id
  ) VALUES (
    v_uid, p_fare_gnf, 'GNF', 'wallet_topup'::payment_purpose, 'pending', 'orange_money',
    v_ref, 'ride', 'Sandbox ride checkout',
    jsonb_build_object(
      'sandbox', true,
      'sandbox_module', 'ride',
      'ride_quote', jsonb_build_object(
        'mode', p_mode::text,
        'pickup_lat', p_pickup_lat, 'pickup_lng', p_pickup_lng,
        'dest_lat',   p_dest_lat,   'dest_lng',   p_dest_lng,
        'fare_gnf', p_fare_gnf
      )
    ),
    true, 'sandbox', p_test_run_id, p_checkout_session_id
  ) RETURNING * INTO v_intent;

  RETURN v_intent;
END $$;

REVOKE ALL ON FUNCTION public.om_sandbox_create_ride_intent(ride_mode,numeric,numeric,numeric,numeric,bigint,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_create_ride_intent(ride_mode,numeric,numeric,numeric,numeric,bigint,uuid,uuid) TO authenticated;

-- --------------------------------------------------------------------------
-- 6. Sandbox intent creation — REPAS (existing food_order).
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.om_sandbox_create_repas_intent(
  p_food_order_id uuid,
  p_test_run_id uuid DEFAULT NULL
) RETURNS public.payment_intents
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.food_orders;
  v_existing public.payment_intents;
  v_intent public.payment_intents;
  v_amount bigint;
  v_ref text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  PERFORM public._om_sandbox_require_active();

  SELECT * INTO v_order FROM public.food_orders WHERE id = p_food_order_id FOR UPDATE;
  IF v_order.id IS NULL THEN RAISE EXCEPTION 'food_order_not_found'; END IF;
  IF v_order.user_id <> v_uid THEN RAISE EXCEPTION 'forbidden'; END IF;

  v_amount := v_order.subtotal_gnf;
  IF v_amount IS NULL OR v_amount <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;

  SELECT * INTO v_existing FROM public.payment_intents
   WHERE source_module='repas' AND source_id = v_order.id AND user_id = v_uid AND is_sandbox = true
   ORDER BY created_at DESC LIMIT 1;
  IF v_existing.id IS NOT NULL THEN RETURN v_existing; END IF;

  v_ref := 'om-sbx-repas:' || v_order.id::text;

  INSERT INTO public.payment_intents(
    user_id, amount_gnf, currency, purpose, state, provider,
    internal_reference, source_module, source_id, description,
    metadata, is_sandbox, environment, test_run_id
  ) VALUES (
    v_uid, v_amount, 'GNF', 'repas_payment'::payment_purpose, 'pending', 'orange_money',
    v_ref, 'repas', v_order.id, 'Sandbox Repas order',
    jsonb_build_object('sandbox', true, 'sandbox_module', 'repas',
                       'food_order_id', v_order.id, 'restaurant_id', v_order.restaurant_id),
    true, 'sandbox', p_test_run_id
  ) RETURNING * INTO v_intent;

  RETURN v_intent;
END $$;

REVOKE ALL ON FUNCTION public.om_sandbox_create_repas_intent(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_create_repas_intent(uuid,uuid) TO authenticated;

-- --------------------------------------------------------------------------
-- 7. Sandbox intent creation — MARCHÉ (accepted offer).
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.om_sandbox_create_marche_intent(
  p_offer_id uuid,
  p_test_run_id uuid DEFAULT NULL
) RETURNS public.payment_intents
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_offer public.marketplace_offers;
  v_existing public.payment_intents;
  v_intent public.payment_intents;
  v_amount bigint;
  v_ref text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  PERFORM public._om_sandbox_require_active();

  SELECT * INTO v_offer FROM public.marketplace_offers WHERE id = p_offer_id FOR UPDATE;
  IF v_offer.id IS NULL THEN RAISE EXCEPTION 'offer_not_found'; END IF;
  IF v_offer.buyer_user_id <> v_uid THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF v_offer.status <> 'accepted' THEN RAISE EXCEPTION 'offer_not_accepted'; END IF;

  v_amount := COALESCE(v_offer.counter_amount_gnf, v_offer.offer_amount_gnf);
  IF v_amount IS NULL OR v_amount <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;

  SELECT * INTO v_existing FROM public.payment_intents
   WHERE source_module='marketplace' AND source_id = v_offer.id AND user_id = v_uid AND is_sandbox = true
   ORDER BY created_at DESC LIMIT 1;
  IF v_existing.id IS NOT NULL THEN RETURN v_existing; END IF;

  v_ref := 'om-sbx-marche:' || v_offer.id::text;

  INSERT INTO public.payment_intents(
    user_id, amount_gnf, currency, purpose, state, provider,
    internal_reference, source_module, source_id, related_store_id,
    payee_user_id, description, metadata,
    is_sandbox, environment, test_run_id
  ) VALUES (
    v_uid, v_amount, 'GNF', 'marche_payment'::payment_purpose, 'pending', 'orange_money',
    v_ref, 'marketplace', v_offer.id, v_offer.merchant_store_id,
    v_offer.merchant_user_id, 'Sandbox Marché offer',
    jsonb_build_object('sandbox', true, 'sandbox_module', 'marketplace',
                       'offer_id', v_offer.id, 'listing_id', v_offer.listing_id),
    true, 'sandbox', p_test_run_id
  ) RETURNING * INTO v_intent;

  RETURN v_intent;
END $$;

REVOKE ALL ON FUNCTION public.om_sandbox_create_marche_intent(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_create_marche_intent(uuid,uuid) TO authenticated;

-- --------------------------------------------------------------------------
-- 8. Generic finalizer.
--    Requires sandbox+authorized intent. Idempotent. Never touches wallet_*.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.om_sandbox_finalize_authorized_intent(
  p_payment_intent_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_is_god boolean;
  v_intent public.payment_intents;
  v_module text;
  v_quote jsonb;
  v_ride public.rides;
  v_ride_existing public.rides;
  v_order public.food_orders;
  v_offer public.marketplace_offers;
  v_ff boolean;
  v_issue_id uuid;
  v_test_run uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  PERFORM public._om_sandbox_require_active();
  v_is_god := public.is_god_admin(v_uid);

  SELECT * INTO v_intent FROM public.payment_intents WHERE id = p_payment_intent_id FOR UPDATE;
  IF v_intent.id IS NULL THEN RAISE EXCEPTION 'intent_not_found'; END IF;
  IF NOT v_intent.is_sandbox THEN RAISE EXCEPTION 'not_a_sandbox_intent'; END IF;
  IF NOT v_is_god AND v_intent.user_id <> v_uid THEN RAISE EXCEPTION 'forbidden'; END IF;

  v_test_run := v_intent.test_run_id;
  v_module   := v_intent.source_module;
  v_ff       := COALESCE((v_intent.metadata->>'sandbox_force_finalize_fail')::boolean, false);

  -- Idempotent: already confirmed with source linkage -> return existing.
  IF v_intent.state = 'confirmed' AND v_intent.source_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'idempotent', true, 'intent_id', v_intent.id, 'intent_state', v_intent.state,
      'module', v_module, 'source_id', v_intent.source_id,
      'is_sandbox', true, 'test_run_id', v_test_run
    );
  END IF;

  -- Idempotent: needs_review from a prior finalize_fail -> return that state.
  IF v_intent.state = 'needs_review'
     AND (v_intent.metadata->>'sandbox_finalize_failed')::boolean IS TRUE THEN
    RETURN jsonb_build_object(
      'idempotent', true, 'intent_id', v_intent.id, 'intent_state', v_intent.state,
      'module', v_module, 'source_id', NULL, 'finalize_failed', true,
      'support_issue_id', v_intent.metadata->>'sandbox_support_issue_id',
      'is_sandbox', true, 'test_run_id', v_test_run
    );
  END IF;

  IF v_intent.state <> 'authorized' THEN
    RAISE EXCEPTION 'intent_not_authorized: state=%', v_intent.state;
  END IF;

  -- Controlled finalization failure branch.
  IF v_ff THEN
    INSERT INTO public.support_issues(
      issue_type, severity, title, description,
      reporter_user_id, related_payment_intent_id, metadata
    ) VALUES (
      'payment_failed', 'high',
      'Sandbox finalization failure ('|| coalesce(v_module,'?') ||')',
      'OM-SBX-FINALIZE-FAIL-001 fixture: intent authorized but source finalization was intentionally aborted.',
      v_intent.user_id, v_intent.id,
      jsonb_build_object(
        'sandbox', true, 'test_run_id', v_test_run,
        'intent_id', v_intent.id, 'source_module', v_module,
        'checkout_session_id', v_intent.checkout_session_id,
        'fixture', 'OM-SBX-FINALIZE-FAIL-001'
      )
    ) RETURNING id INTO v_issue_id;

    UPDATE public.payment_intents
       SET state = 'needs_review',
           metadata = metadata || jsonb_build_object(
             'sandbox_finalize_failed', true,
             'sandbox_support_issue_id', v_issue_id,
             'sandbox_finalize_failed_at', now()
           ),
           updated_at = now()
     WHERE id = v_intent.id;

    INSERT INTO public.payment_reconciliation_events
      (intent_id, event_type, provider, provider_reference, payload, actor_user_id,
       is_sandbox, environment, test_run_id)
    VALUES (v_intent.id, 'provider_pending', 'orange_money', v_intent.provider_reference,
            jsonb_build_object('sandbox', true, 'finalize_failed', true, 'support_issue_id', v_issue_id),
            v_uid, true, 'sandbox', v_test_run);

    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
    VALUES (v_uid, 'payments', 'sandbox.finalize.failed',
            'payment_intent', v_intent.id::text,
            jsonb_build_object('module', v_module, 'support_issue_id', v_issue_id,
              'fixture','OM-SBX-FINALIZE-FAIL-001','test_run_id', v_test_run));

    RETURN jsonb_build_object(
      'idempotent', false, 'intent_id', v_intent.id, 'intent_state', 'needs_review',
      'module', v_module, 'source_id', NULL,
      'finalize_failed', true, 'support_issue_id', v_issue_id,
      'is_sandbox', true, 'test_run_id', v_test_run
    );
  END IF;

  -- ================== module-specific finalization ==================
  IF v_module = 'ride' THEN
    v_quote := v_intent.metadata->'ride_quote';
    IF v_quote IS NULL THEN RAISE EXCEPTION 'ride_quote_missing'; END IF;

    -- Idempotency: if a ride already tagged with this intent exists.
    SELECT * INTO v_ride_existing FROM public.rides
     WHERE client_id = v_intent.user_id
       AND (metadata->>'sandbox_intent_id') = v_intent.id::text
     LIMIT 1;

    IF v_ride_existing.id IS NOT NULL THEN
      v_ride := v_ride_existing;
    ELSE
      INSERT INTO public.rides(
        client_id, driver_id, mode,
        pickup_lat, pickup_lng, dest_lat, dest_lng,
        fare_gnf, hold_tx_id, status, metadata
      ) VALUES (
        v_intent.user_id, NULL, (v_quote->>'mode')::ride_mode,
        (v_quote->>'pickup_lat')::numeric, (v_quote->>'pickup_lng')::numeric,
        NULLIF(v_quote->>'dest_lat','')::numeric, NULLIF(v_quote->>'dest_lng','')::numeric,
        v_intent.amount_gnf, NULL, 'pending',
        jsonb_build_object(
          'sandbox', true,
          'sandbox_intent_id', v_intent.id,
          'sandbox_reference', v_intent.provider_reference,
          'test_run_id', v_test_run
        )
      ) RETURNING * INTO v_ride;
    END IF;

    UPDATE public.payment_intents
       SET state = 'confirmed',
           source_id = v_ride.id,
           metadata = metadata || jsonb_build_object(
             'sandbox_source_id', v_ride.id,
             'sandbox_finalized_at', now()
           ),
           updated_at = now()
     WHERE id = v_intent.id;

  ELSIF v_module = 'repas' THEN
    IF v_intent.source_id IS NULL THEN RAISE EXCEPTION 'source_id_missing'; END IF;
    SELECT * INTO v_order FROM public.food_orders WHERE id = v_intent.source_id FOR UPDATE;
    IF v_order.id IS NULL THEN RAISE EXCEPTION 'food_order_not_found'; END IF;

    IF v_order.payment_status <> 'paid' OR v_order.settlement_state <> 'sandbox' THEN
      UPDATE public.food_orders
         SET payment_status     = 'paid',
             paid_at            = COALESCE(paid_at, now()),
             captured_intent_id = v_intent.id,
             settlement_state   = 'sandbox',
             state              = CASE WHEN state='placed' THEN 'confirmed'::food_order_state ELSE state END,
             updated_at         = now()
       WHERE id = v_order.id
       RETURNING * INTO v_order;
    END IF;

    UPDATE public.payment_intents
       SET state = 'confirmed',
           metadata = metadata || jsonb_build_object(
             'sandbox_source_id', v_order.id,
             'sandbox_finalized_at', now()
           ),
           updated_at = now()
     WHERE id = v_intent.id;

  ELSIF v_module = 'marketplace' THEN
    IF v_intent.source_id IS NULL THEN RAISE EXCEPTION 'source_id_missing'; END IF;
    SELECT * INTO v_offer FROM public.marketplace_offers WHERE id = v_intent.source_id FOR UPDATE;
    IF v_offer.id IS NULL THEN RAISE EXCEPTION 'offer_not_found'; END IF;

    IF v_offer.payment_status <> 'paid' OR v_offer.settlement_state <> 'sandbox' THEN
      UPDATE public.marketplace_offers
         SET payment_intent_id = v_intent.id,
             payment_status    = 'paid',
             authorized_at     = COALESCE(authorized_at, v_intent.authorized_at, now()),
             paid_at            = COALESCE(paid_at, now()),
             settlement_state   = 'sandbox',
             fulfillment_status = CASE WHEN fulfillment_status='pending' THEN 'completed' ELSE fulfillment_status END,
             fulfilled_at       = COALESCE(fulfilled_at, now()),
             completed_at       = COALESCE(completed_at, now()),
             updated_at         = now()
       WHERE id = v_offer.id
       RETURNING * INTO v_offer;
    END IF;

    UPDATE public.payment_intents
       SET state = 'confirmed',
           metadata = metadata || jsonb_build_object(
             'sandbox_source_id', v_offer.id,
             'sandbox_finalized_at', now()
           ),
           updated_at = now()
     WHERE id = v_intent.id;

  ELSE
    RAISE EXCEPTION 'unsupported_sandbox_module: %', v_module;
  END IF;

  INSERT INTO public.payment_reconciliation_events
    (intent_id, event_type, provider, provider_reference, payload, actor_user_id,
     is_sandbox, environment, test_run_id)
  VALUES (v_intent.id, 'provider_captured', 'orange_money', v_intent.provider_reference,
          jsonb_build_object('sandbox', true, 'module', v_module),
          v_uid, true, 'sandbox', v_test_run);

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'payments', 'sandbox.finalize.success',
          'payment_intent', v_intent.id::text,
          jsonb_build_object('module', v_module,
            'source_id', COALESCE(v_ride.id, v_order.id, v_offer.id),
            'test_run_id', v_test_run));

  RETURN jsonb_build_object(
    'idempotent', false,
    'intent_id', v_intent.id,
    'intent_state', 'confirmed',
    'module', v_module,
    'source_id', COALESCE(v_ride.id, v_order.id, v_offer.id),
    'is_sandbox', true,
    'test_run_id', v_test_run,
    'finalize_failed', false
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.om_sandbox_finalize_authorized_intent(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_finalize_authorized_intent(uuid) TO authenticated;
