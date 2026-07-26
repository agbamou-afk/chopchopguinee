
-- =========================================================
-- Slice C.1 — Authoritative server-side ride fare quote
-- =========================================================
CREATE OR REPLACE FUNCTION public.ride_compute_quote_gnf(
  p_mode public.ride_mode,
  p_pickup_lat numeric,
  p_pickup_lng numeric,
  p_dest_lat numeric,
  p_dest_lng numeric
) RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fs public.fare_settings;
  v_km numeric := 0;
  v_R numeric := 6371;
  v_dlat numeric;
  v_dlng numeric;
  v_a numeric;
  v_c numeric;
  v_fare bigint;
BEGIN
  IF p_pickup_lat IS NULL OR p_pickup_lng IS NULL THEN
    RAISE EXCEPTION 'pickup_required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_fs
    FROM public.fare_settings
   WHERE ride_type = p_mode::text
   ORDER BY updated_at DESC
   LIMIT 1;

  IF v_fs.id IS NULL THEN
    RAISE EXCEPTION 'no_fare_settings_for_mode: %', p_mode USING ERRCODE = '22023';
  END IF;

  IF p_dest_lat IS NOT NULL AND p_dest_lng IS NOT NULL THEN
    v_dlat := radians(p_dest_lat - p_pickup_lat);
    v_dlng := radians(p_dest_lng - p_pickup_lng);
    v_a := sin(v_dlat / 2) ^ 2
         + cos(radians(p_pickup_lat)) * cos(radians(p_dest_lat))
         * sin(v_dlng / 2) ^ 2;
    v_c := 2 * atan2(sqrt(v_a), sqrt(1 - v_a));
    v_km := v_R * v_c;
  END IF;

  v_fare := (v_fs.base_price + ceil(v_km * v_fs.price_per_km))::bigint;
  IF v_fare < v_fs.base_price THEN
    v_fare := v_fs.base_price;
  END IF;

  RETURN v_fare;
END;
$$;
REVOKE ALL ON FUNCTION public.ride_compute_quote_gnf(public.ride_mode,numeric,numeric,numeric,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ride_compute_quote_gnf(public.ride_mode,numeric,numeric,numeric,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.ride_get_quote(
  p_mode public.ride_mode,
  p_pickup_lat numeric,
  p_pickup_lng numeric,
  p_dest_lat numeric DEFAULT NULL,
  p_dest_lng numeric DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fare bigint;
BEGIN
  v_fare := public.ride_compute_quote_gnf(p_mode, p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng);
  RETURN jsonb_build_object(
    'mode', p_mode::text,
    'pickup_lat', p_pickup_lat, 'pickup_lng', p_pickup_lng,
    'dest_lat', p_dest_lat, 'dest_lng', p_dest_lng,
    'fare_gnf', v_fare,
    'currency', 'GNF',
    'authoritative', true,
    'source', 'server:ride_compute_quote_gnf'
  );
END;
$$;
REVOKE ALL ON FUNCTION public.ride_get_quote(public.ride_mode,numeric,numeric,numeric,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ride_get_quote(public.ride_mode,numeric,numeric,numeric,numeric) TO authenticated;

-- =========================================================
-- Slice C.2 — Rewrite sandbox ride intent creation
--              to use server-authoritative fare
-- =========================================================
DROP FUNCTION IF EXISTS public.om_sandbox_create_ride_intent(public.ride_mode,numeric,numeric,numeric,numeric,bigint,uuid,uuid);

CREATE OR REPLACE FUNCTION public.om_sandbox_create_ride_intent(
  p_mode public.ride_mode,
  p_pickup_lat numeric,
  p_pickup_lng numeric,
  p_dest_lat numeric,
  p_dest_lng numeric,
  p_checkout_session_id uuid,
  p_test_run_id uuid DEFAULT NULL,
  p_client_display_fare_gnf bigint DEFAULT NULL
) RETURNS public.payment_intents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_existing public.payment_intents;
  v_intent public.payment_intents;
  v_ref text;
  v_server_fare bigint;
  v_mismatch boolean := false;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  PERFORM public._om_sandbox_require_active();

  IF p_checkout_session_id IS NULL THEN RAISE EXCEPTION 'checkout_session_id_required'; END IF;
  IF p_pickup_lat IS NULL OR p_pickup_lng IS NULL THEN RAISE EXCEPTION 'pickup_required'; END IF;

  -- Authoritative fare — server is the ONLY source of truth.
  v_server_fare := public.ride_compute_quote_gnf(p_mode, p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng);
  IF v_server_fare IS NULL OR v_server_fare <= 0 THEN
    RAISE EXCEPTION 'server_fare_unavailable';
  END IF;

  IF p_client_display_fare_gnf IS NOT NULL
     AND p_client_display_fare_gnf <> v_server_fare THEN
    v_mismatch := true;
  END IF;

  SELECT * INTO v_existing FROM public.payment_intents
   WHERE user_id = v_uid
     AND checkout_session_id = p_checkout_session_id
     AND is_sandbox = true
   ORDER BY created_at DESC LIMIT 1;
  IF v_existing.id IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  v_ref := 'om-sbx-ride:' || v_uid::text || ':' || p_checkout_session_id::text;

  INSERT INTO public.payment_intents(
    user_id, amount_gnf, currency, purpose, state, provider,
    internal_reference, source_module, description,
    metadata, is_sandbox, environment, test_run_id, checkout_session_id
  ) VALUES (
    v_uid, v_server_fare, 'GNF', 'wallet_topup'::public.payment_purpose, 'pending', 'orange_money',
    v_ref, 'ride', 'Sandbox ride checkout',
    jsonb_build_object(
      'sandbox', true,
      'sandbox_module', 'ride',
      'ride_quote', jsonb_build_object(
        'mode', p_mode::text,
        'pickup_lat', p_pickup_lat, 'pickup_lng', p_pickup_lng,
        'dest_lat', p_dest_lat, 'dest_lng', p_dest_lng,
        'fare_gnf', v_server_fare,
        'authoritative', true,
        'source', 'server:ride_compute_quote_gnf'
      ),
      'client_display_fare_gnf', p_client_display_fare_gnf,
      'client_display_amount_mismatch', v_mismatch
    ),
    true, 'sandbox', p_test_run_id, p_checkout_session_id
  ) RETURNING * INTO v_intent;

  RETURN v_intent;
END;
$$;
REVOKE ALL ON FUNCTION public.om_sandbox_create_ride_intent(public.ride_mode,numeric,numeric,numeric,numeric,uuid,uuid,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_create_ride_intent(public.ride_mode,numeric,numeric,numeric,numeric,uuid,uuid,bigint) TO authenticated;

-- =========================================================
-- Slice C.3 — Payment refund request model
-- =========================================================
CREATE TABLE IF NOT EXISTS public.payment_refund_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_intent_id uuid NOT NULL REFERENCES public.payment_intents(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL,
  source_module text NOT NULL CHECK (source_module IN ('ride','repas','marketplace')),
  source_id uuid NOT NULL,
  original_amount_gnf bigint NOT NULL CHECK (original_amount_gnf > 0),
  fee_gnf bigint NOT NULL DEFAULT 0 CHECK (fee_gnf >= 0),
  amount_gnf bigint NOT NULL CHECK (amount_gnf > 0),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','in_review','paid','rejected','needs_review')),
  provider text NOT NULL DEFAULT 'orange_money',
  provider_reference text,
  provider_event_id uuid REFERENCES public.payment_provider_events(id),
  reason text,
  is_sandbox boolean NOT NULL DEFAULT false,
  environment text NOT NULL DEFAULT 'production' CHECK (environment IN ('production','sandbox')),
  test_run_id uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  support_issue_id uuid REFERENCES public.support_issues(id) ON DELETE SET NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.payment_refund_requests TO authenticated;
GRANT ALL ON public.payment_refund_requests TO service_role;

ALTER TABLE public.payment_refund_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "refund_owner_read" ON public.payment_refund_requests;
CREATE POLICY "refund_owner_read" ON public.payment_refund_requests
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "refund_admin_read" ON public.payment_refund_requests;
CREATE POLICY "refund_admin_read" ON public.payment_refund_requests
  FOR SELECT TO authenticated
  USING (public.is_any_admin(auth.uid()));

CREATE INDEX IF NOT EXISTS idx_refund_intent ON public.payment_refund_requests(payment_intent_id);
CREATE INDEX IF NOT EXISTS idx_refund_user ON public.payment_refund_requests(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_refund_status ON public.payment_refund_requests(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_refund_sandbox ON public.payment_refund_requests(is_sandbox, environment, status);
CREATE INDEX IF NOT EXISTS idx_refund_source ON public.payment_refund_requests(source_module, source_id);
-- Only one active (non-rejected) refund row per intent — blocks double-refund
CREATE UNIQUE INDEX IF NOT EXISTS uidx_refund_active_per_intent
  ON public.payment_refund_requests(payment_intent_id)
  WHERE status IN ('pending','in_review','paid');
-- Provider reference cannot be reused on same intent
CREATE UNIQUE INDEX IF NOT EXISTS uidx_refund_provider_ref
  ON public.payment_refund_requests(payment_intent_id, provider_reference)
  WHERE provider_reference IS NOT NULL;

DROP TRIGGER IF EXISTS trg_refund_touch ON public.payment_refund_requests;
CREATE TRIGGER trg_refund_touch
  BEFORE UPDATE ON public.payment_refund_requests
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- =========================================================
-- Slice C.4 — Sandbox refund reference registry
-- =========================================================
CREATE OR REPLACE FUNCTION public.om_sandbox_refund_reference_outcome(p_ref text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE upper(trim(coalesce(p_ref,'')))
    WHEN 'OM-SBX-REFUND-001'         THEN 'paid'
    WHEN 'OM-SBX-REFUND-REVIEW-001'  THEN 'needs_review'
    ELSE NULL
  END;
$$;
REVOKE ALL ON FUNCTION public.om_sandbox_refund_reference_outcome(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_refund_reference_outcome(text) TO authenticated;

-- =========================================================
-- Slice C.5 — Sandbox ride cancel + refund request creator
-- =========================================================
CREATE OR REPLACE FUNCTION public.om_sandbox_cancel_ride(
  p_ride_id uuid,
  p_test_run_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides;
  v_intent public.payment_intents;
  v_existing public.payment_refund_requests;
  v_refund public.payment_refund_requests;
  v_driver_assigned boolean;
  v_fee_gnf bigint := 0;
  v_refund_gnf bigint;
  v_test_run uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  PERFORM public._om_sandbox_require_active();

  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'ride_not_found'; END IF;

  IF COALESCE((v_ride.metadata->>'sandbox')::boolean, false) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'not_a_sandbox_ride';
  END IF;

  IF NOT public.is_god_admin(v_uid) AND v_ride.client_id <> v_uid THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Locate sandbox intent that materialized this ride
  SELECT * INTO v_intent
    FROM public.payment_intents
   WHERE source_module = 'ride'
     AND source_id     = v_ride.id
     AND is_sandbox    = true
   ORDER BY created_at DESC
   LIMIT 1
   FOR UPDATE;
  IF v_intent.id IS NULL THEN RAISE EXCEPTION 'sandbox_intent_missing_for_ride'; END IF;

  v_test_run := COALESCE(p_test_run_id, v_intent.test_run_id);

  -- Idempotent: existing refund row wins
  SELECT * INTO v_existing
    FROM public.payment_refund_requests
   WHERE payment_intent_id = v_intent.id
     AND status IN ('pending','in_review','paid')
   LIMIT 1;

  IF v_existing.id IS NOT NULL THEN
    -- Also ensure ride is cancelled (idempotent)
    IF v_ride.status <> 'cancelled' THEN
      UPDATE public.rides
         SET status = 'cancelled',
             metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
               'sandbox_cancelled_at', now(),
               'sandbox_cancel_source', 'om_sandbox_cancel_ride:idem'
             ),
             updated_at = now()
       WHERE id = v_ride.id;
    END IF;
    RETURN jsonb_build_object(
      'idempotent', true,
      'refund_request_id', v_existing.id,
      'status', v_existing.status,
      'amount_gnf', v_existing.amount_gnf,
      'fee_gnf', v_existing.fee_gnf,
      'ride_id', v_ride.id,
      'intent_id', v_intent.id,
      'is_sandbox', true,
      'test_run_id', v_existing.test_run_id
    );
  END IF;

  v_driver_assigned := (v_ride.driver_id IS NOT NULL);

  IF v_driver_assigned THEN
    v_fee_gnf := GREATEST(0, ROUND(v_intent.amount_gnf * 0.10)::bigint);
  END IF;
  v_refund_gnf := GREATEST(1, v_intent.amount_gnf - v_fee_gnf);

  INSERT INTO public.payment_refund_requests(
    payment_intent_id, user_id, source_module, source_id,
    original_amount_gnf, fee_gnf, amount_gnf,
    status, provider, reason,
    is_sandbox, environment, test_run_id, metadata
  ) VALUES (
    v_intent.id, v_intent.user_id, 'ride', v_ride.id,
    v_intent.amount_gnf, v_fee_gnf, v_refund_gnf,
    'pending', 'orange_money',
    CASE WHEN v_driver_assigned
         THEN 'ride_cancel_after_assignment_10pct_fee'
         ELSE 'ride_cancel_before_assignment_full_refund'
    END,
    true, 'sandbox', v_test_run,
    jsonb_build_object(
      'sandbox', true,
      'ride_id', v_ride.id,
      'driver_assigned', v_driver_assigned,
      'fee_policy', CASE WHEN v_driver_assigned THEN '10pct_platform_fee' ELSE 'no_fee' END,
      'sandbox_fee_gnf', v_fee_gnf,
      'sandbox_refund_gnf', v_refund_gnf
    )
  ) RETURNING * INTO v_refund;

  IF v_ride.status <> 'cancelled' THEN
    UPDATE public.rides
       SET status = 'cancelled',
           metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
             'sandbox_cancelled_at', now(),
             'sandbox_driver_assigned_at_cancel', v_driver_assigned,
             'sandbox_cancellation_fee_gnf', v_fee_gnf,
             'sandbox_refund_request_id', v_refund.id
           ),
           updated_at = now()
     WHERE id = v_ride.id;
  END IF;

  INSERT INTO public.payment_provider_events(
    provider, event_type, provider_reference, payload, intent_id,
    is_sandbox, environment, test_run_id
  ) VALUES (
    'orange_money', 'sandbox.refund_requested', NULL,
    jsonb_build_object(
      'sandbox', true, 'module', 'ride',
      'refund_request_id', v_refund.id,
      'fee_gnf', v_fee_gnf, 'refund_gnf', v_refund_gnf
    ),
    v_intent.id, true, 'sandbox', v_test_run
  );

  INSERT INTO public.payment_reconciliation_events(
    intent_id, event_type, provider, provider_reference, payload, actor_user_id,
    is_sandbox, environment, test_run_id
  ) VALUES (
    v_intent.id, 'refund_created', 'orange_money', NULL,
    jsonb_build_object(
      'sandbox', true, 'module', 'ride',
      'refund_request_id', v_refund.id,
      'driver_assigned', v_driver_assigned,
      'fee_gnf', v_fee_gnf, 'refund_gnf', v_refund_gnf
    ),
    v_uid, true, 'sandbox', v_test_run
  );

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, after)
  VALUES (
    v_uid, 'payments', 'sandbox.ride.cancel',
    'ride', v_ride.id::text,
    jsonb_build_object(
      'refund_request_id', v_refund.id,
      'intent_id', v_intent.id,
      'driver_assigned', v_driver_assigned,
      'fee_gnf', v_fee_gnf,
      'refund_gnf', v_refund_gnf,
      'test_run_id', v_test_run
    )
  );

  RETURN jsonb_build_object(
    'idempotent', false,
    'refund_request_id', v_refund.id,
    'status', 'pending',
    'amount_gnf', v_refund_gnf,
    'fee_gnf', v_fee_gnf,
    'ride_id', v_ride.id,
    'intent_id', v_intent.id,
    'driver_assigned', v_driver_assigned,
    'is_sandbox', true,
    'test_run_id', v_test_run
  );
END;
$$;
REVOKE ALL ON FUNCTION public.om_sandbox_cancel_ride(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_cancel_ride(uuid,uuid) TO authenticated;

-- =========================================================
-- Slice C.6 — Sandbox Repas refund request
-- =========================================================
CREATE OR REPLACE FUNCTION public.om_sandbox_request_repas_refund(
  p_food_order_id uuid,
  p_test_run_id uuid DEFAULT NULL,
  p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.food_orders;
  v_intent public.payment_intents;
  v_existing public.payment_refund_requests;
  v_refund public.payment_refund_requests;
  v_test_run uuid;
  v_needs_review boolean := false;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  PERFORM public._om_sandbox_require_active();

  SELECT * INTO v_order FROM public.food_orders WHERE id = p_food_order_id FOR UPDATE;
  IF v_order.id IS NULL THEN RAISE EXCEPTION 'food_order_not_found'; END IF;
  IF NOT public.is_god_admin(v_uid) AND v_order.user_id <> v_uid THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_order.settlement_state <> 'sandbox' OR v_order.payment_status <> 'paid' THEN
    RAISE EXCEPTION 'order_not_refundable: payment=% settlement=%', v_order.payment_status, v_order.settlement_state;
  END IF;

  SELECT * INTO v_intent FROM public.payment_intents WHERE id = v_order.captured_intent_id FOR UPDATE;
  IF v_intent.id IS NULL OR NOT v_intent.is_sandbox THEN
    RAISE EXCEPTION 'sandbox_intent_missing_for_order';
  END IF;
  v_test_run := COALESCE(p_test_run_id, v_intent.test_run_id);

  SELECT * INTO v_existing
    FROM public.payment_refund_requests
   WHERE payment_intent_id = v_intent.id
     AND status IN ('pending','in_review','paid')
   LIMIT 1;
  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'idempotent', true,
      'refund_request_id', v_existing.id,
      'status', v_existing.status,
      'amount_gnf', v_existing.amount_gnf,
      'intent_id', v_intent.id,
      'test_run_id', v_existing.test_run_id
    );
  END IF;

  -- Ambiguous states (e.g. already delivered) → needs_review policy
  IF v_order.state IN ('out_for_delivery','completed') THEN
    v_needs_review := true;
  END IF;

  INSERT INTO public.payment_refund_requests(
    payment_intent_id, user_id, source_module, source_id,
    original_amount_gnf, fee_gnf, amount_gnf,
    status, provider, reason,
    is_sandbox, environment, test_run_id, metadata
  ) VALUES (
    v_intent.id, v_intent.user_id, 'repas', v_order.id,
    v_intent.amount_gnf, 0, v_intent.amount_gnf,
    CASE WHEN v_needs_review THEN 'needs_review' ELSE 'pending' END,
    'orange_money',
    COALESCE(p_reason,
      CASE WHEN v_needs_review
           THEN 'repas_refund_ambiguous_state_routed_needs_review'
           ELSE 'repas_customer_refund_request' END),
    true, 'sandbox', v_test_run,
    jsonb_build_object(
      'sandbox', true,
      'food_order_id', v_order.id,
      'order_state_at_request', v_order.state,
      'needs_review', v_needs_review
    )
  ) RETURNING * INTO v_refund;

  IF v_order.state NOT IN ('completed','cancelled') THEN
    UPDATE public.food_orders
       SET state = 'cancelled',
           updated_at = now()
     WHERE id = v_order.id;
  END IF;

  INSERT INTO public.payment_provider_events(
    provider, event_type, provider_reference, payload, intent_id,
    is_sandbox, environment, test_run_id
  ) VALUES (
    'orange_money', 'sandbox.refund_requested', NULL,
    jsonb_build_object('sandbox', true, 'module', 'repas', 'refund_request_id', v_refund.id),
    v_intent.id, true, 'sandbox', v_test_run
  );

  INSERT INTO public.payment_reconciliation_events(
    intent_id, event_type, provider, provider_reference, payload, actor_user_id,
    is_sandbox, environment, test_run_id
  ) VALUES (
    v_intent.id, 'refund_created', 'orange_money', NULL,
    jsonb_build_object('sandbox', true, 'module', 'repas', 'refund_request_id', v_refund.id),
    v_uid, true, 'sandbox', v_test_run
  );

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'payments', 'sandbox.repas.refund_request',
          'food_order', v_order.id::text,
          jsonb_build_object('refund_request_id', v_refund.id,
                             'needs_review', v_needs_review,
                             'test_run_id', v_test_run));

  RETURN jsonb_build_object(
    'idempotent', false,
    'refund_request_id', v_refund.id,
    'status', v_refund.status,
    'amount_gnf', v_refund.amount_gnf,
    'intent_id', v_intent.id,
    'needs_review', v_needs_review,
    'is_sandbox', true,
    'test_run_id', v_test_run
  );
END;
$$;
REVOKE ALL ON FUNCTION public.om_sandbox_request_repas_refund(uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_request_repas_refund(uuid,uuid,text) TO authenticated;

-- =========================================================
-- Slice C.7 — Sandbox Marché refund request
-- =========================================================
CREATE OR REPLACE FUNCTION public.om_sandbox_request_marche_refund(
  p_offer_id uuid,
  p_test_run_id uuid DEFAULT NULL,
  p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_offer public.marketplace_offers;
  v_intent public.payment_intents;
  v_existing public.payment_refund_requests;
  v_refund public.payment_refund_requests;
  v_test_run uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  PERFORM public._om_sandbox_require_active();

  SELECT * INTO v_offer FROM public.marketplace_offers WHERE id = p_offer_id FOR UPDATE;
  IF v_offer.id IS NULL THEN RAISE EXCEPTION 'offer_not_found'; END IF;
  IF NOT public.is_god_admin(v_uid) AND v_offer.buyer_user_id <> v_uid THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_offer.settlement_state <> 'sandbox' OR v_offer.payment_status <> 'paid' THEN
    RAISE EXCEPTION 'offer_not_refundable: payment=% settlement=%', v_offer.payment_status, v_offer.settlement_state;
  END IF;

  SELECT * INTO v_intent FROM public.payment_intents WHERE id = v_offer.payment_intent_id FOR UPDATE;
  IF v_intent.id IS NULL OR NOT v_intent.is_sandbox THEN
    RAISE EXCEPTION 'sandbox_intent_missing_for_offer';
  END IF;
  v_test_run := COALESCE(p_test_run_id, v_intent.test_run_id);

  SELECT * INTO v_existing
    FROM public.payment_refund_requests
   WHERE payment_intent_id = v_intent.id
     AND status IN ('pending','in_review','paid')
   LIMIT 1;
  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'idempotent', true,
      'refund_request_id', v_existing.id,
      'status', v_existing.status,
      'amount_gnf', v_existing.amount_gnf,
      'intent_id', v_intent.id
    );
  END IF;

  INSERT INTO public.payment_refund_requests(
    payment_intent_id, user_id, source_module, source_id,
    original_amount_gnf, fee_gnf, amount_gnf,
    status, provider, reason,
    is_sandbox, environment, test_run_id, metadata
  ) VALUES (
    v_intent.id, v_intent.user_id, 'marketplace', v_offer.id,
    v_intent.amount_gnf, 0, v_intent.amount_gnf,
    'pending', 'orange_money',
    COALESCE(p_reason,'marche_customer_refund_request'),
    true, 'sandbox', v_test_run,
    jsonb_build_object('sandbox', true, 'offer_id', v_offer.id)
  ) RETURNING * INTO v_refund;

  INSERT INTO public.payment_provider_events(
    provider, event_type, provider_reference, payload, intent_id,
    is_sandbox, environment, test_run_id
  ) VALUES (
    'orange_money', 'sandbox.refund_requested', NULL,
    jsonb_build_object('sandbox', true, 'module', 'marketplace', 'refund_request_id', v_refund.id),
    v_intent.id, true, 'sandbox', v_test_run
  );
  INSERT INTO public.payment_reconciliation_events(
    intent_id, event_type, provider, provider_reference, payload, actor_user_id,
    is_sandbox, environment, test_run_id
  ) VALUES (
    v_intent.id, 'refund_created', 'orange_money', NULL,
    jsonb_build_object('sandbox', true, 'module', 'marketplace', 'refund_request_id', v_refund.id),
    v_uid, true, 'sandbox', v_test_run
  );
  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'payments', 'sandbox.marche.refund_request',
          'marketplace_offer', v_offer.id::text,
          jsonb_build_object('refund_request_id', v_refund.id, 'test_run_id', v_test_run));

  RETURN jsonb_build_object(
    'idempotent', false,
    'refund_request_id', v_refund.id,
    'status', 'pending',
    'amount_gnf', v_refund.amount_gnf,
    'intent_id', v_intent.id,
    'is_sandbox', true,
    'test_run_id', v_test_run
  );
END;
$$;
REVOKE ALL ON FUNCTION public.om_sandbox_request_marche_refund(uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_request_marche_refund(uuid,uuid,text) TO authenticated;

-- =========================================================
-- Slice C.8 — Sandbox refund reference orchestrator
--              (submit provider reference → paid | needs_review)
-- =========================================================
CREATE OR REPLACE FUNCTION public.om_sandbox_submit_refund_reference(
  p_refund_request_id uuid,
  p_provider_reference text,
  p_test_run_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_god boolean;
  v_refund public.payment_refund_requests;
  v_intent public.payment_intents;
  v_ref text;
  v_outcome text;
  v_event public.payment_provider_events;
  v_issue_id uuid;
  v_test_run uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  PERFORM public._om_sandbox_require_active();
  v_is_god := public.is_god_admin(v_uid);

  IF p_provider_reference IS NULL OR btrim(p_provider_reference) = '' THEN
    RAISE EXCEPTION 'provider_reference_required';
  END IF;
  v_ref := upper(btrim(p_provider_reference));

  -- Reject anything that does not look like a sandbox fixture
  IF position('OM-SBX-' in v_ref) <> 1 THEN
    RAISE EXCEPTION 'live_reference_not_allowed_on_sandbox_refund_rpc';
  END IF;

  v_outcome := public.om_sandbox_refund_reference_outcome(v_ref);
  IF v_outcome IS NULL THEN
    RAISE EXCEPTION 'unknown_sandbox_refund_reference: %', v_ref;
  END IF;

  SELECT * INTO v_refund FROM public.payment_refund_requests WHERE id = p_refund_request_id FOR UPDATE;
  IF v_refund.id IS NULL THEN RAISE EXCEPTION 'refund_request_not_found'; END IF;
  IF NOT v_refund.is_sandbox THEN RAISE EXCEPTION 'not_a_sandbox_refund'; END IF;
  IF NOT v_is_god AND v_refund.user_id <> v_uid THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT * INTO v_intent FROM public.payment_intents WHERE id = v_refund.payment_intent_id FOR UPDATE;
  IF v_intent.id IS NULL THEN RAISE EXCEPTION 'intent_missing'; END IF;
  IF NOT v_intent.is_sandbox THEN
    RAISE EXCEPTION 'sandbox_reference_rejected_on_non_sandbox_intent';
  END IF;

  v_test_run := COALESCE(p_test_run_id, v_refund.test_run_id, v_intent.test_run_id);

  -- Idempotent: same reference already applied
  IF v_refund.provider_reference = v_ref AND v_refund.status IN ('paid','needs_review') THEN
    RETURN jsonb_build_object(
      'idempotent', true,
      'refund_request_id', v_refund.id,
      'status', v_refund.status,
      'amount_gnf', v_refund.amount_gnf,
      'provider_reference', v_ref,
      'intent_id', v_intent.id,
      'test_run_id', v_refund.test_run_id
    );
  END IF;

  -- Only pending refunds can be submitted
  IF v_refund.status <> 'pending' THEN
    RAISE EXCEPTION 'refund_not_in_pending_state: state=%', v_refund.status;
  END IF;

  -- Duplicate provider reference on same intent (different refund row) → double-refund protection
  IF EXISTS (
    SELECT 1 FROM public.payment_refund_requests
     WHERE payment_intent_id = v_intent.id
       AND id <> v_refund.id
       AND provider_reference = v_ref
  ) THEN
    RAISE EXCEPTION 'duplicate_provider_reference_on_intent';
  END IF;

  -- Record provider event
  INSERT INTO public.payment_provider_events(
    provider, event_type, provider_reference, payload, intent_id,
    is_sandbox, environment, test_run_id
  ) VALUES (
    'orange_money',
    CASE WHEN v_outcome = 'paid' THEN 'sandbox.refund_paid'
         ELSE 'sandbox.refund_review' END,
    v_ref,
    jsonb_build_object(
      'sandbox', true,
      'module', v_refund.source_module,
      'refund_request_id', v_refund.id,
      'amount_gnf', v_refund.amount_gnf,
      'fixture', v_ref,
      'outcome', v_outcome
    ),
    v_intent.id, true, 'sandbox', v_test_run
  ) RETURNING * INTO v_event;

  IF v_outcome = 'paid' THEN
    UPDATE public.payment_refund_requests
       SET status = 'paid',
           provider_reference = v_ref,
           provider_event_id = v_event.id,
           resolved_at = now(),
           test_run_id = v_test_run,
           metadata = metadata || jsonb_build_object(
             'sandbox_paid_at', now(),
             'sandbox_fixture', v_ref
           ),
           updated_at = now()
     WHERE id = v_refund.id
     RETURNING * INTO v_refund;

    -- Reflect refunded state on source + intent
    IF v_refund.source_module = 'repas' THEN
      UPDATE public.food_orders
         SET payment_status = 'refunded',
             updated_at = now()
       WHERE id = v_refund.source_id;
    ELSIF v_refund.source_module = 'marketplace' THEN
      UPDATE public.marketplace_offers
         SET payment_status = 'refunded',
             fulfillment_status = CASE
               WHEN fulfillment_status IN ('handed_over','delivered','completed')
                 THEN fulfillment_status
               ELSE 'cancelled'
             END,
             updated_at = now()
       WHERE id = v_refund.source_id;
    END IF;
    -- Ride source: already cancelled; nothing further

    UPDATE public.payment_intents
       SET state = 'refunded',
           metadata = metadata || jsonb_build_object(
             'sandbox_refunded_at', now(),
             'sandbox_refund_request_id', v_refund.id
           ),
           updated_at = now()
     WHERE id = v_intent.id;

    INSERT INTO public.payment_reconciliation_events(
      intent_id, event_type, provider, provider_reference, payload, actor_user_id,
      is_sandbox, environment, test_run_id
    ) VALUES (
      v_intent.id, 'refund_completed', 'orange_money', v_ref,
      jsonb_build_object(
        'sandbox', true, 'module', v_refund.source_module,
        'refund_request_id', v_refund.id, 'amount_gnf', v_refund.amount_gnf
      ),
      v_uid, true, 'sandbox', v_test_run
    );

    INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, after)
    VALUES (v_uid, 'payments', 'sandbox.refund.paid',
            'payment_refund_request', v_refund.id::text,
            jsonb_build_object(
              'module', v_refund.source_module,
              'source_id', v_refund.source_id,
              'intent_id', v_intent.id,
              'amount_gnf', v_refund.amount_gnf,
              'fixture', v_ref,
              'test_run_id', v_test_run));

  ELSE  -- needs_review
    INSERT INTO public.support_issues(
      issue_type, severity, title, description,
      reporter_user_id, related_payment_intent_id, metadata
    ) VALUES (
      'payment_failed', 'high',
      'Sandbox refund needs review (' || v_refund.source_module || ')',
      'OM-SBX-REFUND-REVIEW-001: refund flagged for manual review. No real money moved.',
      v_refund.user_id, v_intent.id,
      jsonb_build_object(
        'sandbox', true,
        'refund_request_id', v_refund.id,
        'source_module', v_refund.source_module,
        'source_id', v_refund.source_id,
        'provider_reference', v_ref,
        'amount_gnf', v_refund.amount_gnf,
        'test_run_id', v_test_run,
        'fixture', v_ref
      )
    ) RETURNING id INTO v_issue_id;

    UPDATE public.payment_refund_requests
       SET status = 'needs_review',
           provider_reference = v_ref,
           provider_event_id = v_event.id,
           support_issue_id = v_issue_id,
           test_run_id = v_test_run,
           metadata = metadata || jsonb_build_object(
             'sandbox_review_at', now(),
             'sandbox_fixture', v_ref,
             'sandbox_support_issue_id', v_issue_id
           ),
           updated_at = now()
     WHERE id = v_refund.id
     RETURNING * INTO v_refund;

    INSERT INTO public.payment_reconciliation_events(
      intent_id, event_type, provider, provider_reference, payload, actor_user_id,
      is_sandbox, environment, test_run_id
    ) VALUES (
      v_intent.id, 'refund_created', 'orange_money', v_ref,
      jsonb_build_object(
        'sandbox', true, 'module', v_refund.source_module,
        'refund_request_id', v_refund.id,
        'outcome', 'needs_review',
        'support_issue_id', v_issue_id
      ),
      v_uid, true, 'sandbox', v_test_run
    );

    INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, after)
    VALUES (v_uid, 'payments', 'sandbox.refund.needs_review',
            'payment_refund_request', v_refund.id::text,
            jsonb_build_object(
              'support_issue_id', v_issue_id,
              'intent_id', v_intent.id,
              'fixture', v_ref,
              'test_run_id', v_test_run));
  END IF;

  RETURN jsonb_build_object(
    'idempotent', false,
    'refund_request_id', v_refund.id,
    'status', v_refund.status,
    'amount_gnf', v_refund.amount_gnf,
    'provider_reference', v_ref,
    'intent_id', v_intent.id,
    'provider_event_id', v_event.id,
    'support_issue_id', v_refund.support_issue_id,
    'is_sandbox', true,
    'test_run_id', v_test_run
  );
END;
$$;
REVOKE ALL ON FUNCTION public.om_sandbox_submit_refund_reference(uuid,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_submit_refund_reference(uuid,text,uuid) TO authenticated;
