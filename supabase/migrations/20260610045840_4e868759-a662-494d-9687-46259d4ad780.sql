
-- 1) New mission columns
ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS customer_handoff_code text,
  ADD COLUMN IF NOT EXISTS customer_confirmed_at timestamptz,
  ADD COLUMN IF NOT EXISTS customer_confirmed_by uuid;

-- 2) Backfill customer_handoff_code for existing marketplace missions
UPDATE public.missions
   SET customer_handoff_code = lpad((floor(random() * 1000000))::int::text, 6, '0')
 WHERE customer_handoff_code IS NULL
   AND type = 'marketplace_delivery';

-- 3) Update marketplace_create_delivery_mission to also generate the customer code
CREATE OR REPLACE FUNCTION public.marketplace_create_delivery_mission(
  _offer_id uuid,
  _dropoff_address text,
  _dropoff_lat double precision,
  _dropoff_lng double precision,
  _payload_summary text,
  _estimated_earning_gnf bigint DEFAULT 0,
  _dropoff_notes text DEFAULT NULL
) RETURNS public.missions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  _uid uuid := auth.uid();
  _offer public.marketplace_offers;
  _store public.merchant_stores;
  _mission public.missions;
  _existing_id uuid;
  _mcode text;
  _ccode text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO _offer FROM public.marketplace_offers WHERE id = _offer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'offer_not_found'; END IF;
  IF _offer.merchant_user_id IS DISTINCT FROM _uid THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF _offer.status <> 'accepted' THEN RAISE EXCEPTION 'offer_not_accepted'; END IF;

  SELECT * INTO _store FROM public.merchant_stores WHERE owner_user_id = _uid LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'store_not_found'; END IF;
  IF _store.status <> 'active' OR _store.onboarding_status <> 'approved' THEN
    RAISE EXCEPTION 'store_not_active_approved';
  END IF;
  IF _store.latitude IS NULL OR _store.longitude IS NULL THEN
    RAISE EXCEPTION 'store_missing_location';
  END IF;

  SELECT id INTO _existing_id FROM public.missions WHERE ref_market_order_id = _offer_id LIMIT 1;
  IF _existing_id IS NOT NULL THEN
    SELECT * INTO _mission FROM public.missions WHERE id = _existing_id;
    RETURN _mission;
  END IF;

  _mcode := lpad((floor(random() * 1000000))::int::text, 6, '0');
  _ccode := lpad((floor(random() * 1000000))::int::text, 6, '0');

  INSERT INTO public.missions(
    type, state,
    customer_id, merchant_id, courier_id,
    merchant_store_id, ref_market_order_id,
    pickup_address, pickup_lat, pickup_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    payload_summary,
    estimated_earning_gnf,
    merchant_handoff_code,
    customer_handoff_code
  ) VALUES (
    'marketplace_delivery'::public.mission_type,
    'assigned'::public.mission_state,
    _offer.buyer_user_id,
    _uid,
    NULL,
    _store.id,
    _offer_id,
    COALESCE(_store.address_label, _store.market_name, _store.commune, _store.district, _store.name),
    _store.latitude, _store.longitude,
    _dropoff_address, _dropoff_lat, _dropoff_lng,
    COALESCE(_payload_summary, 'Commande Marché'),
    GREATEST(COALESCE(_estimated_earning_gnf, 0), 0),
    _mcode, _ccode
  ) RETURNING * INTO _mission;

  RETURN _mission;
END;
$$;

-- 4) Pickup with proof (photo + merchant code/QR)
CREATE OR REPLACE FUNCTION public.mission_confirm_pickup_with_proof(
  _mission_id uuid,
  _photo_url text,
  _merchant_code text
) RETURNS public.missions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE _uid uuid := auth.uid(); _m public.missions; _store public.merchant_stores; _ok boolean := false;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF _photo_url IS NULL OR length(trim(_photo_url)) = 0 THEN RAISE EXCEPTION 'photo_required'; END IF;
  IF _merchant_code IS NULL OR length(trim(_merchant_code)) = 0 THEN RAISE EXCEPTION 'merchant_code_required'; END IF;

  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF _m.merchant_store_id IS NOT NULL THEN
    SELECT * INTO _store FROM public.merchant_stores WHERE id = _m.merchant_store_id;
    _ok := (
      _merchant_code = COALESCE(_m.merchant_handoff_code,'')
      OR _merchant_code = COALESCE(_store.merchant_account_number,'')
      OR _merchant_code = COALESCE(_store.merchant_qr_payload,'')
    );
    IF NOT _ok THEN RAISE EXCEPTION 'invalid_merchant_code'; END IF;
  ELSE
    IF _merchant_code <> COALESCE(_m.merchant_handoff_code,'') THEN
      RAISE EXCEPTION 'invalid_merchant_code';
    END IF;
  END IF;

  UPDATE public.missions
     SET state = 'picked_up'::public.mission_state,
         pickup_confirmed_at = now(),
         pickup_confirmed_by = _uid,
         pickup_photo_url = _photo_url
   WHERE id = _mission_id
   RETURNING * INTO _m;

  INSERT INTO public.mission_events(mission_id, kind, payload)
  VALUES (_mission_id, 'pickup_confirmed', jsonb_build_object('photo_url', _photo_url));

  RETURN _m;
END;
$$;

-- 5) Dropoff with proof (photo + customer code)
CREATE OR REPLACE FUNCTION public.mission_confirm_dropoff_with_proof(
  _mission_id uuid,
  _photo_url text,
  _customer_code text
) RETURNS public.missions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE _uid uuid := auth.uid(); _m public.missions;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF _photo_url IS NULL OR length(trim(_photo_url)) = 0 THEN RAISE EXCEPTION 'photo_required'; END IF;

  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Customer code optional when no customer code was issued (e.g. legacy or non-marketplace)
  IF _m.customer_handoff_code IS NOT NULL THEN
    IF _customer_code IS NULL OR _customer_code <> _m.customer_handoff_code THEN
      RAISE EXCEPTION 'invalid_customer_code';
    END IF;
  END IF;

  UPDATE public.missions
     SET state = 'delivered'::public.mission_state,
         dropoff_confirmed_at = now(),
         dropoff_confirmed_by = _uid,
         delivery_photo_url = _photo_url
   WHERE id = _mission_id
   RETURNING * INTO _m;

  INSERT INTO public.mission_events(mission_id, kind, payload)
  VALUES (_mission_id, 'dropoff_confirmed', jsonb_build_object('photo_url', _photo_url));

  RETURN _m;
END;
$$;

-- 6) Customer confirms receipt
CREATE OR REPLACE FUNCTION public.mission_customer_confirm_delivery(
  _mission_id uuid
) RETURNS public.missions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE _uid uuid := auth.uid(); _m public.missions;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.customer_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF _m.state NOT IN ('delivered'::public.mission_state) THEN
    RAISE EXCEPTION 'not_delivered_yet';
  END IF;
  UPDATE public.missions
     SET customer_confirmed_at = now(),
         customer_confirmed_by = _uid
   WHERE id = _mission_id
   RETURNING * INTO _m;

  INSERT INTO public.mission_events(mission_id, kind, payload)
  VALUES (_mission_id, 'customer_confirmed', '{}'::jsonb);

  RETURN _m;
END;
$$;

REVOKE ALL ON FUNCTION public.mission_confirm_pickup_with_proof(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mission_confirm_dropoff_with_proof(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mission_customer_confirm_delivery(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mission_confirm_pickup_with_proof(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mission_confirm_dropoff_with_proof(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mission_customer_confirm_delivery(uuid) TO authenticated;

-- 7) Storage policies for mission-proofs bucket
-- Path convention: {mission_id}/{pickup|delivery}-{timestamp}.jpg
DROP POLICY IF EXISTS "mission_proofs_courier_insert" ON storage.objects;
CREATE POLICY "mission_proofs_courier_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'mission-proofs'
  AND EXISTS (
    SELECT 1 FROM public.missions m
    WHERE m.id::text = split_part(name, '/', 1)
      AND m.courier_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "mission_proofs_read" ON storage.objects;
CREATE POLICY "mission_proofs_read"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'mission-proofs'
  AND EXISTS (
    SELECT 1 FROM public.missions m
    WHERE m.id::text = split_part(name, '/', 1)
      AND (
        m.courier_id = auth.uid()
        OR m.customer_id = auth.uid()
        OR m.merchant_id = auth.uid()
        OR public.is_any_admin(auth.uid())
      )
  )
);
