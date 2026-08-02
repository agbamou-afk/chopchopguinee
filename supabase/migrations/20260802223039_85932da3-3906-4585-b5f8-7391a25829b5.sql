-- ============================================================
-- Envoyer v1 — parcel / document delivery foundation
-- ============================================================

INSERT INTO public.feature_flags (key, enabled, description)
VALUES ('envoyer_enabled', false, 'Envoyer v1 — parcel/document delivery composer + creation RPCs')
ON CONFLICT (key) DO NOTHING;

-- Provider-neutral source module: allow 'package'
ALTER TABLE public.payment_intents DROP CONSTRAINT IF EXISTS payment_intents_source_module_chk;
ALTER TABLE public.payment_intents ADD CONSTRAINT payment_intents_source_module_chk
  CHECK (source_module IS NULL OR source_module = ANY (ARRAY['marketplace','repas','ride','mission','topup','manual','package']));

ALTER TABLE public.payment_refund_requests DROP CONSTRAINT IF EXISTS payment_refund_requests_source_module_check;
ALTER TABLE public.payment_refund_requests ADD CONSTRAINT payment_refund_requests_source_module_check
  CHECK (source_module = ANY (ARRAY['ride','repas','marketplace','package']));

-- ------------------------------------------------------------
-- 1. Authoritative quotes
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.package_delivery_quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  pickup_label text,
  pickup_lat double precision NOT NULL,
  pickup_lng double precision NOT NULL,
  destination_label text,
  destination_lat double precision NOT NULL,
  destination_lng double precision NOT NULL,
  category text NOT NULL,
  distance_meters integer,
  duration_seconds integer,
  amount_gnf bigint NOT NULL CHECK (amount_gnf > 0),
  tariff_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.package_delivery_quotes TO authenticated;
GRANT ALL ON public.package_delivery_quotes TO service_role;
ALTER TABLE public.package_delivery_quotes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pdq_owner_read" ON public.package_delivery_quotes;
CREATE POLICY "pdq_owner_read" ON public.package_delivery_quotes
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- ------------------------------------------------------------
-- 2. Package deliveries (source of truth for the parcel)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.package_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_user_id uuid NOT NULL,
  mission_id uuid UNIQUE,
  payment_intent_id uuid,
  quote_id uuid REFERENCES public.package_delivery_quotes(id),
  reference text NOT NULL,
  pickup_label text,
  pickup_lat double precision NOT NULL,
  pickup_lng double precision NOT NULL,
  destination_label text,
  destination_lat double precision NOT NULL,
  destination_lng double precision NOT NULL,
  sender_name text,
  sender_phone text,
  recipient_name text NOT NULL,
  recipient_phone text NOT NULL,
  category text NOT NULL CHECK (category = ANY (ARRAY['document','small_parcel','medium_parcel'])),
  description text,
  handling_notes text,
  quoted_amount_gnf bigint NOT NULL CHECK (quoted_amount_gnf > 0),
  distance_meters integer,
  duration_seconds integer,
  payment_status text NOT NULL DEFAULT 'pending',
  package_status text NOT NULL DEFAULT 'payment_pending',
  delivered_at timestamptz,
  recipient_confirmed_name text,
  cancelled_at timestamptz,
  cancellation_reason text,
  cancellation_fee_gnf bigint NOT NULL DEFAULT 0,
  refund_request_id uuid,
  support_issue_id uuid,
  idempotency_key text NOT NULL,
  is_sandbox boolean NOT NULL DEFAULT false,
  environment text NOT NULL DEFAULT 'production',
  test_run_id uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (sender_user_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_package_deliveries_sender ON public.package_deliveries (sender_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_package_deliveries_mission ON public.package_deliveries (mission_id);
CREATE INDEX IF NOT EXISTS idx_package_deliveries_sandbox ON public.package_deliveries (is_sandbox, environment, package_status);

GRANT SELECT ON public.package_deliveries TO authenticated;
GRANT ALL ON public.package_deliveries TO service_role;
ALTER TABLE public.package_deliveries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pd_sender_read" ON public.package_deliveries;
CREATE POLICY "pd_sender_read" ON public.package_deliveries
  FOR SELECT TO authenticated USING (auth.uid() = sender_user_id);

DROP POLICY IF EXISTS "pd_admin_read" ON public.package_deliveries;
CREATE POLICY "pd_admin_read" ON public.package_deliveries
  FOR SELECT TO authenticated USING (public.is_any_admin(auth.uid()));

-- ------------------------------------------------------------
-- 3. Verification secrets — sender-only readable
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.package_delivery_secrets (
  package_id uuid PRIMARY KEY REFERENCES public.package_deliveries(id) ON DELETE CASCADE,
  pickup_code text NOT NULL,
  delivery_code text NOT NULL,
  pickup_verified_at timestamptz,
  delivery_verified_at timestamptz,
  pickup_attempts integer NOT NULL DEFAULT 0,
  delivery_attempts integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.package_delivery_secrets TO authenticated;
GRANT ALL ON public.package_delivery_secrets TO service_role;
ALTER TABLE public.package_delivery_secrets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pds_sender_read" ON public.package_delivery_secrets;
CREATE POLICY "pds_sender_read" ON public.package_delivery_secrets
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.package_deliveries d
       WHERE d.id = package_delivery_secrets.package_id
         AND d.sender_user_id = auth.uid()
    )
  );

-- ------------------------------------------------------------
-- 4. Helpers
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._envoyer_enabled()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT enabled FROM public.feature_flags WHERE key = 'envoyer_enabled'), false);
$$;

CREATE OR REPLACE FUNCTION public._package_touch()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS trg_package_deliveries_touch ON public.package_deliveries;
CREATE TRIGGER trg_package_deliveries_touch BEFORE UPDATE ON public.package_deliveries
  FOR EACH ROW EXECUTE FUNCTION public._package_touch();

CREATE OR REPLACE FUNCTION public._package_new_code()
RETURNS text LANGUAGE sql VOLATILE SET search_path = public AS $$
  SELECT lpad((floor(random() * 900000) + 100000)::bigint::text, 6, '0');
$$;

-- ------------------------------------------------------------
-- 5. Authoritative quote
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.package_delivery_quote(
  p_pickup_lat double precision,
  p_pickup_lng double precision,
  p_dest_lat double precision,
  p_dest_lng double precision,
  p_category text,
  p_pickup_label text DEFAULT NULL,
  p_dest_label text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_amount bigint;
  v_km numeric;
  v_id uuid;
  v_expires timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF NOT public._envoyer_enabled() THEN RAISE EXCEPTION 'envoyer_disabled' USING ERRCODE='22023'; END IF;
  IF p_category IS NULL OR p_category NOT IN ('document','small_parcel','medium_parcel') THEN
    RAISE EXCEPTION 'unsupported_category' USING ERRCODE='22023';
  END IF;
  IF p_pickup_lat IS NULL OR p_pickup_lng IS NULL OR p_dest_lat IS NULL OR p_dest_lng IS NULL THEN
    RAISE EXCEPTION 'coordinates_required' USING ERRCODE='22023';
  END IF;
  -- Guinea bounding box sanity check
  IF p_pickup_lat NOT BETWEEN 7.0 AND 13.0 OR p_dest_lat NOT BETWEEN 7.0 AND 13.0
     OR p_pickup_lng NOT BETWEEN -15.5 AND -7.0 OR p_dest_lng NOT BETWEEN -15.5 AND -7.0 THEN
    RAISE EXCEPTION 'out_of_service_zone' USING ERRCODE='22023';
  END IF;

  v_km := public._map_distance_meters(p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng) / 1000.0;
  -- Envoyer v1 reuses the approved moto tariff. No hidden second tariff.
  v_amount := public.ride_compute_quote_gnf('moto'::public.ride_mode,
                p_pickup_lat::numeric, p_pickup_lng::numeric, p_dest_lat::numeric, p_dest_lng::numeric);
  IF v_amount IS NULL OR v_amount <= 0 THEN RAISE EXCEPTION 'server_quote_unavailable'; END IF;

  v_expires := now() + interval '15 minutes';

  INSERT INTO public.package_delivery_quotes(
    user_id, pickup_label, pickup_lat, pickup_lng, destination_label,
    destination_lat, destination_lng, category, distance_meters,
    duration_seconds, amount_gnf, tariff_snapshot, expires_at
  ) VALUES (
    v_uid, left(coalesce(p_pickup_label,''), 240), p_pickup_lat, p_pickup_lng,
    left(coalesce(p_dest_label,''), 240), p_dest_lat, p_dest_lng, p_category,
    round(v_km * 1000)::int, round(v_km / 18.0 * 3600)::int, v_amount,
    jsonb_build_object('tariff','moto','source','server:ride_compute_quote_gnf','category',p_category,'category_surcharge_gnf',0),
    v_expires
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'quote_id', v_id, 'amount_gnf', v_amount, 'currency','GNF',
    'distance_meters', round(v_km * 1000)::int,
    'duration_seconds', round(v_km / 18.0 * 3600)::int,
    'category', p_category, 'expires_at', v_expires,
    'authoritative', true, 'tariff', 'moto'
  );
END;
$$;

-- ------------------------------------------------------------
-- 6. Create + checkout (provider neutral)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.package_delivery_create_checkout(
  p_quote_id uuid,
  p_recipient_name text,
  p_recipient_phone text,
  p_description text DEFAULT NULL,
  p_instructions text DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL,
  p_sender_phone text DEFAULT NULL,
  p_provider text DEFAULT 'orange_money',
  p_sandbox boolean DEFAULT false,
  p_test_run_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_q public.package_delivery_quotes;
  v_pkg public.package_deliveries;
  v_intent public.payment_intents;
  v_profile record;
  v_recipient text;
  v_sender_phone text;
  v_key text;
  v_ref text;
  v_env text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF NOT public._envoyer_enabled() THEN RAISE EXCEPTION 'envoyer_disabled' USING ERRCODE='22023'; END IF;
  IF p_sandbox THEN PERFORM public._om_sandbox_require_active(); END IF;

  v_key := COALESCE(NULLIF(trim(p_idempotency_key), ''), p_quote_id::text);

  SELECT * INTO v_pkg FROM public.package_deliveries
   WHERE sender_user_id = v_uid AND idempotency_key = v_key;
  IF v_pkg.id IS NOT NULL THEN
    SELECT * INTO v_intent FROM public.payment_intents WHERE id = v_pkg.payment_intent_id;
    RETURN jsonb_build_object(
      'idempotent', true, 'package_id', v_pkg.id, 'reference', v_pkg.reference,
      'payment_intent_id', v_pkg.payment_intent_id, 'amount_gnf', v_pkg.quoted_amount_gnf,
      'intent_state', v_intent.state, 'provider_reference', v_intent.provider_reference,
      'is_sandbox', v_pkg.is_sandbox
    );
  END IF;

  SELECT * INTO v_q FROM public.package_delivery_quotes WHERE id = p_quote_id FOR UPDATE;
  IF v_q.id IS NULL THEN RAISE EXCEPTION 'quote_not_found' USING ERRCODE='22023'; END IF;
  IF v_q.user_id <> v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  IF v_q.expires_at <= now() THEN RAISE EXCEPTION 'quote_expired' USING ERRCODE='22023'; END IF;
  IF v_q.consumed_at IS NOT NULL THEN RAISE EXCEPTION 'quote_already_used' USING ERRCODE='22023'; END IF;

  v_recipient := public._normalize_guinea_phone(p_recipient_phone);
  IF v_recipient IS NULL THEN RAISE EXCEPTION 'invalid_recipient_phone' USING ERRCODE='22023'; END IF;
  IF p_recipient_name IS NULL OR length(trim(p_recipient_name)) < 2 THEN
    RAISE EXCEPTION 'invalid_recipient_name' USING ERRCODE='22023';
  END IF;

  SELECT full_name, phone INTO v_profile FROM public.profiles WHERE id = v_uid;
  v_sender_phone := COALESCE(public._normalize_guinea_phone(p_sender_phone),
                             public._normalize_guinea_phone(v_profile.phone));

  v_env := CASE WHEN p_sandbox THEN 'sandbox' ELSE 'production' END;
  v_ref := 'PKG-' || upper(substr(replace(gen_random_uuid()::text,'-',''), 1, 8));

  INSERT INTO public.package_deliveries(
    sender_user_id, quote_id, reference,
    pickup_label, pickup_lat, pickup_lng,
    destination_label, destination_lat, destination_lng,
    sender_name, sender_phone, recipient_name, recipient_phone,
    category, description, handling_notes,
    quoted_amount_gnf, distance_meters, duration_seconds,
    payment_status, package_status, idempotency_key,
    is_sandbox, environment, test_run_id
  ) VALUES (
    v_uid, v_q.id, v_ref,
    v_q.pickup_label, v_q.pickup_lat, v_q.pickup_lng,
    v_q.destination_label, v_q.destination_lat, v_q.destination_lng,
    v_profile.full_name, v_sender_phone, left(trim(p_recipient_name), 120), v_recipient,
    v_q.category, left(coalesce(p_description,''), 500), left(coalesce(p_instructions,''), 500),
    v_q.amount_gnf, v_q.distance_meters, v_q.duration_seconds,
    'pending', 'payment_pending', v_key,
    p_sandbox, v_env, p_test_run_id
  ) RETURNING * INTO v_pkg;

  UPDATE public.package_delivery_quotes SET consumed_at = now() WHERE id = v_q.id;

  INSERT INTO public.payment_intents(
    user_id, amount_gnf, currency, purpose, state, provider,
    internal_reference, source_module, source_id, description,
    metadata, is_sandbox, environment, test_run_id, expires_at
  ) VALUES (
    v_uid, v_q.amount_gnf, 'GNF', 'package_payment'::public.payment_purpose, 'pending',
    (CASE WHEN p_provider IN ('orange_money','mtn_money','cash','manual','internal','agent')
          THEN p_provider ELSE 'orange_money' END)::public.payment_provider,
    'pkg:' || v_pkg.id::text, 'package', v_pkg.id, 'Envoyer — livraison de colis ' || v_pkg.reference,
    jsonb_build_object(
      'module','package','package_reference', v_pkg.reference,
      'quote_id', v_q.id, 'authoritative_amount_gnf', v_q.amount_gnf,
      'sandbox', p_sandbox, 'sandbox_module', CASE WHEN p_sandbox THEN 'package' ELSE NULL END
    ),
    p_sandbox, v_env, p_test_run_id, now() + interval '30 minutes'
  ) RETURNING * INTO v_intent;

  UPDATE public.package_deliveries SET payment_intent_id = v_intent.id WHERE id = v_pkg.id;

  INSERT INTO public.payment_reconciliation_events
    (intent_id, event_type, provider, payload, actor_user_id, is_sandbox, environment, test_run_id)
  VALUES (v_intent.id, 'intent_created', v_intent.provider,
          jsonb_build_object('module','package','package_id', v_pkg.id, 'reference', v_pkg.reference),
          v_uid, p_sandbox, v_env, p_test_run_id);

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'package', 'package.checkout.created', 'package_delivery', v_pkg.id::text,
          jsonb_build_object('intent_id', v_intent.id, 'amount_gnf', v_q.amount_gnf, 'sandbox', p_sandbox));

  RETURN jsonb_build_object(
    'idempotent', false, 'package_id', v_pkg.id, 'reference', v_pkg.reference,
    'payment_intent_id', v_intent.id, 'amount_gnf', v_intent.amount_gnf,
    'intent_state', v_intent.state, 'provider', v_intent.provider,
    'is_sandbox', p_sandbox
  );
END;
$$;

-- ------------------------------------------------------------
-- 7. Payment finalizer -> real mission + codes
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.package_delivery_finalize_from_intent(p_intent_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_intent public.payment_intents;
  v_pkg public.package_deliveries;
  v_mission public.missions;
BEGIN
  SELECT * INTO v_intent FROM public.payment_intents WHERE id = p_intent_id FOR UPDATE;
  IF v_intent.id IS NULL THEN RAISE EXCEPTION 'intent_not_found'; END IF;
  IF v_intent.source_module <> 'package' OR v_intent.source_id IS NULL THEN
    RAISE EXCEPTION 'not_a_package_intent';
  END IF;

  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = v_intent.source_id FOR UPDATE;
  IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'package_not_found'; END IF;

  IF v_pkg.mission_id IS NOT NULL THEN
    RETURN jsonb_build_object('idempotent', true, 'package_id', v_pkg.id, 'mission_id', v_pkg.mission_id);
  END IF;

  IF v_intent.amount_gnf <> v_pkg.quoted_amount_gnf THEN
    RAISE EXCEPTION 'amount_mismatch';
  END IF;

  INSERT INTO public.missions(
    type, state, customer_id, courier_id,
    pickup_address, pickup_lat, pickup_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    payload_summary, estimated_earning_gnf,
    estimated_distance_m, estimated_duration_s
  ) VALUES (
    'package_delivery'::public.mission_type, 'assigned'::public.mission_state, v_pkg.sender_user_id, NULL,
    v_pkg.pickup_label, v_pkg.pickup_lat, v_pkg.pickup_lng,
    v_pkg.destination_label, v_pkg.destination_lat, v_pkg.destination_lng,
    'Colis ' || v_pkg.reference || ' · ' || v_pkg.category, v_pkg.quoted_amount_gnf,
    v_pkg.distance_meters, v_pkg.duration_seconds
  ) RETURNING * INTO v_mission;

  INSERT INTO public.package_delivery_secrets(package_id, pickup_code, delivery_code)
  VALUES (v_pkg.id, public._package_new_code(), public._package_new_code())
  ON CONFLICT (package_id) DO NOTHING;

  UPDATE public.package_deliveries
     SET mission_id = v_mission.id,
         payment_status = 'authorized',
         package_status = 'dispatching'
   WHERE id = v_pkg.id;

  UPDATE public.payment_intents
     SET state = 'confirmed', authorized_at = COALESCE(authorized_at, now()),
         related_mission_id = v_mission.id,
         metadata = metadata || jsonb_build_object('package_mission_id', v_mission.id, 'finalized_at', now()),
         updated_at = now()
   WHERE id = v_intent.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (auth.uid(), 'package', 'package.finalized', 'package_delivery', v_pkg.id::text,
          jsonb_build_object('mission_id', v_mission.id, 'intent_id', v_intent.id, 'sandbox', v_pkg.is_sandbox));

  RETURN jsonb_build_object('idempotent', false, 'package_id', v_pkg.id, 'mission_id', v_mission.id);
END;
$$;

-- ------------------------------------------------------------
-- 8. Courier-safe operational view
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.package_delivery_courier_view(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_m public.missions;
  v_pkg public.package_deliveries;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_m FROM public.missions WHERE id = p_mission_id;
  IF v_m.id IS NULL THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF v_m.courier_id IS DISTINCT FROM v_uid AND NOT public.is_any_admin(v_uid) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_pkg FROM public.package_deliveries WHERE mission_id = p_mission_id;
  IF v_pkg.id IS NULL THEN RETURN NULL; END IF;

  RETURN jsonb_build_object(
    'package_id', v_pkg.id,
    'reference', v_pkg.reference,
    'category', v_pkg.category,
    'description', v_pkg.description,
    'handling_notes', v_pkg.handling_notes,
    'pickup_label', v_pkg.pickup_label,
    'destination_label', v_pkg.destination_label,
    'sender_phone', v_pkg.sender_phone,
    'recipient_name', v_pkg.recipient_name,
    'recipient_phone', v_pkg.recipient_phone,
    'package_status', v_pkg.package_status,
    'is_sandbox', v_pkg.is_sandbox
  );
END;
$$;

-- ------------------------------------------------------------
-- 9. Pickup / delivery verification
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.package_verify_pickup(p_package_id uuid, p_code text)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_pkg public.package_deliveries;
  v_m public.missions;
  v_s public.package_delivery_secrets;
  v_code text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_package_id FOR UPDATE;
  IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'package_not_found'; END IF;
  SELECT * INTO v_m FROM public.missions WHERE id = v_pkg.mission_id FOR UPDATE;
  IF v_m.id IS NULL THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF v_m.courier_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  SELECT * INTO v_s FROM public.package_delivery_secrets WHERE package_id = p_package_id FOR UPDATE;
  IF v_s.package_id IS NULL THEN RAISE EXCEPTION 'secrets_missing'; END IF;

  IF v_s.pickup_verified_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'idempotent', true, 'mission_state', v_m.state);
  END IF;
  IF v_s.pickup_attempts >= 6 THEN RAISE EXCEPTION 'too_many_attempts' USING ERRCODE='42501'; END IF;
  IF v_m.state NOT IN ('assigned','heading_to_pickup','arrived_pickup') THEN
    RAISE EXCEPTION 'invalid_state' USING ERRCODE='22023';
  END IF;

  v_code := regexp_replace(COALESCE(p_code,''), '\D', '', 'g');
  IF v_code <> v_s.pickup_code THEN
    UPDATE public.package_delivery_secrets SET pickup_attempts = pickup_attempts + 1 WHERE package_id = p_package_id;
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
    VALUES (v_uid, 'package', 'package.pickup.code_failed', 'package_delivery', p_package_id::text,
            jsonb_build_object('attempts', v_s.pickup_attempts + 1));
    RAISE EXCEPTION 'invalid_code' USING ERRCODE='22023';
  END IF;

  UPDATE public.package_delivery_secrets
     SET pickup_verified_at = now(), pickup_attempts = pickup_attempts + 1
   WHERE package_id = p_package_id;

  UPDATE public.missions
     SET state = 'picked_up'::public.mission_state,
         pickup_confirmed_at = now(), pickup_confirmed_by = v_uid
   WHERE id = v_m.id;

  UPDATE public.package_deliveries SET package_status = 'in_transit' WHERE id = p_package_id;

  INSERT INTO public.mission_events(mission_id, event, actor_id, note)
  VALUES (v_m.id, 'picked_up', v_uid, 'package_code_verified');

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'package', 'package.pickup.verified', 'package_delivery', p_package_id::text,
          jsonb_build_object('mission_id', v_m.id));

  RETURN jsonb_build_object('ok', true, 'idempotent', false, 'mission_state', 'picked_up');
END;
$$;

CREATE OR REPLACE FUNCTION public.package_verify_delivery(
  p_package_id uuid, p_code text, p_recipient_name text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_pkg public.package_deliveries;
  v_m public.missions;
  v_s public.package_delivery_secrets;
  v_code text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_package_id FOR UPDATE;
  IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'package_not_found'; END IF;
  SELECT * INTO v_m FROM public.missions WHERE id = v_pkg.mission_id FOR UPDATE;
  IF v_m.id IS NULL THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF v_m.courier_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  SELECT * INTO v_s FROM public.package_delivery_secrets WHERE package_id = p_package_id FOR UPDATE;
  IF v_s.package_id IS NULL THEN RAISE EXCEPTION 'secrets_missing'; END IF;
  IF v_s.delivery_verified_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'idempotent', true, 'mission_state', v_m.state);
  END IF;
  IF v_s.pickup_verified_at IS NULL THEN RAISE EXCEPTION 'pickup_not_verified' USING ERRCODE='22023'; END IF;
  IF v_s.delivery_attempts >= 6 THEN RAISE EXCEPTION 'too_many_attempts' USING ERRCODE='42501'; END IF;
  IF v_m.state NOT IN ('picked_up','heading_to_dropoff','arrived_dropoff') THEN
    RAISE EXCEPTION 'invalid_state' USING ERRCODE='22023';
  END IF;

  v_code := regexp_replace(COALESCE(p_code,''), '\D', '', 'g');
  IF v_code <> v_s.delivery_code THEN
    UPDATE public.package_delivery_secrets SET delivery_attempts = delivery_attempts + 1 WHERE package_id = p_package_id;
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
    VALUES (v_uid, 'package', 'package.delivery.code_failed', 'package_delivery', p_package_id::text,
            jsonb_build_object('attempts', v_s.delivery_attempts + 1));
    RAISE EXCEPTION 'invalid_code' USING ERRCODE='22023';
  END IF;

  UPDATE public.package_delivery_secrets
     SET delivery_verified_at = now(), delivery_attempts = delivery_attempts + 1
   WHERE package_id = p_package_id;

  UPDATE public.missions
     SET state = 'delivered'::public.mission_state,
         dropoff_confirmed_at = now(), dropoff_confirmed_by = v_uid
   WHERE id = v_m.id;

  UPDATE public.package_deliveries
     SET package_status = 'delivered', delivered_at = now(),
         recipient_confirmed_name = COALESCE(left(trim(p_recipient_name),120), recipient_name),
         payment_status = CASE WHEN is_sandbox THEN payment_status ELSE 'settled' END
   WHERE id = p_package_id;

  INSERT INTO public.mission_events(mission_id, event, actor_id, note)
  VALUES (v_m.id, 'delivered', v_uid, 'package_code_verified');

  -- Trusted earning path: production only. Sandbox creates zero value.
  IF NOT v_pkg.is_sandbox THEN
    BEGIN
      PERFORM public.wallet_credit_mission_earning(v_m.id, 'package_verify_delivery');
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.mission_events(mission_id, event, actor_id, note)
      VALUES (v_m.id, 'issue', v_uid, 'courier_earning_failed: ' || SQLERRM);
    END;
  END IF;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'package', 'package.delivery.verified', 'package_delivery', p_package_id::text,
          jsonb_build_object('mission_id', v_m.id, 'sandbox', v_pkg.is_sandbox));

  RETURN jsonb_build_object('ok', true, 'idempotent', false, 'mission_state', 'delivered');
END;
$$;

-- ------------------------------------------------------------
-- 10. Cancellation / dispute
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.package_delivery_cancel(p_package_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_pkg public.package_deliveries;
  v_m public.missions;
  v_s public.package_delivery_secrets;
  v_fee bigint := 0;
  v_refund bigint;
  v_req uuid;
  v_issue uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_package_id FOR UPDATE;
  IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'package_not_found'; END IF;
  IF v_pkg.sender_user_id <> v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  IF v_pkg.cancelled_at IS NOT NULL THEN
    RETURN jsonb_build_object('idempotent', true, 'status', v_pkg.package_status,
                              'refund_request_id', v_pkg.refund_request_id, 'fee_gnf', v_pkg.cancellation_fee_gnf);
  END IF;

  SELECT * INTO v_m FROM public.missions WHERE id = v_pkg.mission_id FOR UPDATE;
  SELECT * INTO v_s FROM public.package_delivery_secrets WHERE package_id = p_package_id;

  IF v_s.pickup_verified_at IS NOT NULL OR v_pkg.package_status IN ('in_transit','delivered') THEN
    INSERT INTO public.support_issues(
      issue_type, severity, title, description, reporter_user_id,
      related_mission_id, related_payment_intent_id, related_customer_id, metadata
    ) VALUES (
      'package_dispute', 'high', 'Colis déjà récupéré — demande d''annulation ' || v_pkg.reference,
      COALESCE(p_reason, 'Annulation demandée après récupération du colis.'), v_uid,
      v_pkg.mission_id, v_pkg.payment_intent_id, v_uid,
      jsonb_build_object('package_id', v_pkg.id, 'reference', v_pkg.reference, 'sandbox', v_pkg.is_sandbox)
    ) RETURNING id INTO v_issue;

    UPDATE public.package_deliveries SET support_issue_id = v_issue WHERE id = p_package_id;

    RETURN jsonb_build_object('idempotent', false, 'self_service', false,
                              'support_issue_id', v_issue, 'status', v_pkg.package_status);
  END IF;

  IF v_m.id IS NOT NULL AND v_m.courier_id IS NOT NULL THEN
    v_fee := floor(v_pkg.quoted_amount_gnf * 0.10)::bigint;
  END IF;
  v_refund := v_pkg.quoted_amount_gnf - v_fee;

  IF v_m.id IS NOT NULL THEN
    UPDATE public.missions SET state = 'failed'::public.mission_state,
           issue_reason = COALESCE(p_reason, 'client_cancelled') WHERE id = v_m.id;
  END IF;

  UPDATE public.package_deliveries
     SET package_status = 'cancelled', cancelled_at = now(),
         cancellation_reason = left(COALESCE(p_reason,'client_cancelled'), 300),
         cancellation_fee_gnf = v_fee
   WHERE id = p_package_id;

  IF v_pkg.payment_intent_id IS NOT NULL
     AND v_pkg.payment_status IN ('authorized','settled')
     AND v_refund > 0 THEN
    INSERT INTO public.payment_refund_requests(
      payment_intent_id, user_id, source_module, source_id,
      original_amount_gnf, fee_gnf, amount_gnf, reason,
      is_sandbox, environment, test_run_id, metadata
    ) VALUES (
      v_pkg.payment_intent_id, v_uid, 'package', v_pkg.id,
      v_pkg.quoted_amount_gnf, v_fee, v_refund,
      COALESCE(p_reason, 'client_cancelled'), v_pkg.is_sandbox, v_pkg.environment, v_pkg.test_run_id,
      jsonb_build_object('package_reference', v_pkg.reference)
    )
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_req;

    UPDATE public.package_deliveries SET refund_request_id = v_req WHERE id = p_package_id AND v_req IS NOT NULL;
  END IF;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'package', 'package.cancelled', 'package_delivery', p_package_id::text,
          jsonb_build_object('fee_gnf', v_fee, 'refund_gnf', v_refund, 'refund_request_id', v_req));

  RETURN jsonb_build_object('idempotent', false, 'self_service', true,
                            'fee_gnf', v_fee, 'refund_gnf', v_refund, 'refund_request_id', v_req);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.package_delivery_quote(double precision,double precision,double precision,double precision,text,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.package_delivery_create_checkout(uuid,text,text,text,text,text,text,text,boolean,uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.package_verify_pickup(uuid,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.package_verify_delivery(uuid,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.package_delivery_cancel(uuid,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.package_delivery_courier_view(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.package_delivery_finalize_from_intent(uuid) FROM anon, authenticated;