
-- 1. Trust-layer columns on missions
ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS merchant_store_id uuid REFERENCES public.merchant_stores(id),
  ADD COLUMN IF NOT EXISTS pickup_photo_url text,
  ADD COLUMN IF NOT EXISTS delivery_photo_url text,
  ADD COLUMN IF NOT EXISTS merchant_handoff_code text;

CREATE INDEX IF NOT EXISTS missions_merchant_store_id_idx
  ON public.missions(merchant_store_id);

-- 2. Bridge RPC
CREATE OR REPLACE FUNCTION public.marketplace_create_delivery_mission(
  _offer_id              uuid,
  _dropoff_address       text,
  _dropoff_lat           double precision,
  _dropoff_lng           double precision,
  _payload_summary       text,
  _estimated_earning_gnf bigint DEFAULT 0,
  _dropoff_notes         text   DEFAULT NULL
)
RETURNS public.missions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid   uuid := auth.uid();
  _offer public.marketplace_offers;
  _store public.merchant_stores;
  _mission public.missions;
  _code  text;
  _existing_id uuid;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO _offer FROM public.marketplace_offers WHERE id = _offer_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'offer_not_found'; END IF;

  IF _offer.merchant_user_id IS DISTINCT FROM _uid THEN
    RAISE EXCEPTION 'not_merchant_on_offer';
  END IF;
  IF _offer.status <> 'accepted' THEN
    RAISE EXCEPTION 'offer_not_accepted';
  END IF;
  IF _offer.merchant_store_id IS NULL THEN
    RAISE EXCEPTION 'offer_missing_store';
  END IF;

  SELECT * INTO _store FROM public.merchant_stores WHERE id = _offer.merchant_store_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'store_not_found'; END IF;
  IF _store.status <> 'active' OR _store.onboarding_status <> 'approved' THEN
    RAISE EXCEPTION 'store_not_active_approved';
  END IF;
  IF _store.latitude IS NULL OR _store.longitude IS NULL THEN
    RAISE EXCEPTION 'store_missing_location';
  END IF;

  -- Idempotency: do not create a second mission for the same offer
  SELECT id INTO _existing_id
    FROM public.missions
   WHERE ref_market_order_id = _offer_id
   LIMIT 1;
  IF _existing_id IS NOT NULL THEN
    SELECT * INTO _mission FROM public.missions WHERE id = _existing_id;
    RETURN _mission;
  END IF;

  -- 6-digit numeric handoff code, server-generated
  _code := lpad((floor(random() * 1000000))::int::text, 6, '0');

  INSERT INTO public.missions(
    type, state,
    customer_id, merchant_id, courier_id,
    merchant_store_id, ref_market_order_id,
    pickup_address, pickup_lat, pickup_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    payload_summary,
    estimated_earning_gnf,
    merchant_handoff_code
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
    _code
  )
  RETURNING * INTO _mission;

  RETURN _mission;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.marketplace_create_delivery_mission(uuid,text,double precision,double precision,text,bigint,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.marketplace_create_delivery_mission(uuid,text,double precision,double precision,text,bigint,text) TO authenticated;
