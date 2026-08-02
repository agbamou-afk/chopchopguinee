CREATE OR REPLACE FUNCTION public.om_sandbox_finalize_authorized_intent(p_payment_intent_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $fn$
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
  v_pkg jsonb;
  v_pkg_id uuid;
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

  IF v_intent.state = 'confirmed' AND v_intent.source_id IS NOT NULL AND v_module <> 'package' THEN
    RETURN jsonb_build_object(
      'idempotent', true, 'intent_id', v_intent.id, 'intent_state', v_intent.state,
      'module', v_module, 'source_id', v_intent.source_id,
      'is_sandbox', true, 'test_run_id', v_test_run
    );
  END IF;

  IF v_intent.state = 'needs_review'
     AND (v_intent.metadata->>'sandbox_finalize_failed')::boolean IS TRUE THEN
    RETURN jsonb_build_object(
      'idempotent', true, 'intent_id', v_intent.id, 'intent_state', v_intent.state,
      'module', v_module, 'source_id', NULL, 'finalize_failed', true,
      'support_issue_id', v_intent.metadata->>'sandbox_support_issue_id',
      'is_sandbox', true, 'test_run_id', v_test_run
    );
  END IF;

  IF v_module = 'package' AND v_intent.state = 'confirmed' THEN
    v_pkg := public.package_delivery_finalize_from_intent(v_intent.id);
    RETURN jsonb_build_object(
      'idempotent', true, 'intent_id', v_intent.id, 'intent_state', 'confirmed',
      'module', v_module, 'source_id', (v_pkg->>'package_id')::uuid,
      'mission_id', (v_pkg->>'mission_id')::uuid,
      'is_sandbox', true, 'test_run_id', v_test_run, 'finalize_failed', false
    );
  END IF;

  IF v_intent.state <> 'authorized' THEN
    RAISE EXCEPTION 'intent_not_authorized: state=%', v_intent.state;
  END IF;

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

  IF v_module = 'ride' THEN
    v_quote := v_intent.metadata->'ride_quote';
    IF v_quote IS NULL THEN RAISE EXCEPTION 'ride_quote_missing'; END IF;

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

  ELSIF v_module = 'package' THEN
    v_pkg := public.package_delivery_finalize_from_intent(v_intent.id);
    v_pkg_id := (v_pkg->>'package_id')::uuid;
    UPDATE public.payment_intents
       SET metadata = metadata || jsonb_build_object(
             'sandbox_source_id', v_pkg_id,
             'sandbox_mission_id', (v_pkg->>'mission_id')::uuid,
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
  VALUES (v_intent.id, 'provider_confirmed', 'orange_money', v_intent.provider_reference,
          jsonb_build_object('sandbox', true, 'module', v_module, 'stage', 'finalized'),
          v_uid, true, 'sandbox', v_test_run);

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'payments', 'sandbox.finalize.success',
          'payment_intent', v_intent.id::text,
          jsonb_build_object('module', v_module,
            'source_id', COALESCE(v_ride.id, v_order.id, v_offer.id, v_pkg_id),
            'test_run_id', v_test_run));

  RETURN jsonb_build_object(
    'idempotent', false,
    'intent_id', v_intent.id,
    'intent_state', 'confirmed',
    'module', v_module,
    'source_id', COALESCE(v_ride.id, v_order.id, v_offer.id, v_pkg_id),
    'mission_id', (v_pkg->>'mission_id')::uuid,
    'is_sandbox', true,
    'test_run_id', v_test_run,
    'finalize_failed', false
  );
END;
$fn$;