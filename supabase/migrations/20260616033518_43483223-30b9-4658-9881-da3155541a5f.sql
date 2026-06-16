
-- Phase 2B — Merchant Location Submission
ALTER TABLE public.merchant_stores
  ADD COLUMN IF NOT EXISTS map_place_id uuid REFERENCES public.map_places(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS location_submission_status text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS location_submitted_at timestamptz,
  ADD COLUMN IF NOT EXISTS location_verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS location_verified_by uuid,
  ADD COLUMN IF NOT EXISTS location_notes text;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='merchant_stores_loc_sub_status_chk') THEN
    ALTER TABLE public.merchant_stores
      ADD CONSTRAINT merchant_stores_loc_sub_status_chk
      CHECK (location_submission_status IN ('none','submitted','needs_review','admin_verified','trusted','rejected'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_merchant_stores_map_place_id ON public.merchant_stores(map_place_id);
CREATE INDEX IF NOT EXISTS idx_merchant_stores_loc_sub_status ON public.merchant_stores(location_submission_status);

-- RPC: merchant_submit_location
CREATE OR REPLACE FUNCTION public.merchant_submit_location(
  p_store_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_address_text text DEFAULT NULL,
  p_landmark_note text DEFAULT NULL,
  p_entrance_note text DEFAULT NULL,
  p_pickup_note text DEFAULT NULL,
  p_operational_note text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_store public.merchant_stores%ROWTYPE;
  v_place_id uuid;
  v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF p_lat IS NULL OR p_lng IS NULL THEN RAISE EXCEPTION 'lat/lng required'; END IF;
  IF p_lat < -90 OR p_lat > 90 OR p_lng < -180 OR p_lng > 180 THEN
    RAISE EXCEPTION 'invalid coordinates';
  END IF;

  SELECT * INTO v_store FROM public.merchant_stores WHERE id = p_store_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'store not found'; END IF;
  IF v_store.owner_user_id <> v_uid THEN RAISE EXCEPTION 'not store owner'; END IF;

  v_name := COALESCE(NULLIF(btrim(v_store.name),''), 'Commerce');
  v_place_id := v_store.map_place_id;

  IF v_place_id IS NULL THEN
    INSERT INTO public.map_places (
      name, category, commune, neighborhood, lat, lng, source,
      verification_status, confidence_score,
      pickup_note, entrance_note, landmark_note, operational_note,
      active, created_by
    ) VALUES (
      v_name,
      COALESCE(v_store.category,'merchant'),
      v_store.commune,
      v_store.district,
      p_lat, p_lng,
      'merchant_submission',
      'submitted',
      public.map_default_confidence('submitted'),
      NULLIF(btrim(p_pickup_note),''),
      NULLIF(btrim(p_entrance_note),''),
      NULLIF(btrim(p_landmark_note),''),
      NULLIF(btrim(p_operational_note),''),
      true, v_uid
    ) RETURNING id INTO v_place_id;
  ELSE
    UPDATE public.map_places SET
      name = v_name,
      lat = p_lat, lng = p_lng,
      pickup_note = COALESCE(NULLIF(btrim(p_pickup_note),''), pickup_note),
      entrance_note = COALESCE(NULLIF(btrim(p_entrance_note),''), entrance_note),
      landmark_note = COALESCE(NULLIF(btrim(p_landmark_note),''), landmark_note),
      operational_note = COALESCE(NULLIF(btrim(p_operational_note),''), operational_note),
      -- Do not downgrade an already-trusted/admin_verified place:
      verification_status = CASE
        WHEN verification_status IN ('trusted','admin_verified') THEN verification_status
        ELSE 'submitted'::map_verification_status
      END,
      confidence_score = CASE
        WHEN verification_status IN ('trusted','admin_verified') THEN confidence_score
        ELSE public.map_default_confidence('submitted')
      END,
      active = true,
      updated_at = now()
    WHERE id = v_place_id;
  END IF;

  -- Light duplicate hint: flag for review if another nearby (<100m) place exists
  IF EXISTS (
    SELECT 1 FROM public.map_places mp
    WHERE mp.id <> v_place_id AND mp.active = true
      AND abs(mp.lat - p_lat) < 0.001 AND abs(mp.lng - p_lng) < 0.001
  ) THEN
    UPDATE public.map_places
      SET verification_status = CASE
        WHEN verification_status IN ('trusted','admin_verified') THEN verification_status
        ELSE 'needs_review'::map_verification_status
      END
    WHERE id = v_place_id;
  END IF;

  UPDATE public.merchant_stores SET
    map_place_id = v_place_id,
    latitude = p_lat,
    longitude = p_lng,
    address_label = COALESCE(NULLIF(btrim(p_address_text),''), address_label),
    landmark_note = COALESCE(NULLIF(btrim(p_landmark_note),''), landmark_note),
    location_submission_status = 'submitted',
    location_submitted_at = now(),
    location_notes = NULLIF(btrim(p_operational_note),''),
    updated_at = now()
  WHERE id = p_store_id;

  BEGIN
    INSERT INTO public.audit_logs (actor_id, action, target_type, target_id, metadata)
    VALUES (v_uid, 'merchant.location.submit', 'merchant_store', p_store_id,
            jsonb_build_object('map_place_id', v_place_id, 'lat', p_lat, 'lng', p_lng));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN v_place_id;
END;
$$;

REVOKE ALL ON FUNCTION public.merchant_submit_location(uuid,double precision,double precision,text,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.merchant_submit_location(uuid,double precision,double precision,text,text,text,text,text) TO authenticated;

-- Admin verifies merchant location — syncs map_places + merchant_stores
CREATE OR REPLACE FUNCTION public.admin_set_merchant_location_status(
  p_store_id uuid,
  p_status text,
  p_note text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_store public.merchant_stores%ROWTYPE;
  v_place_status map_verification_status;
BEGIN
  IF NOT public.has_role(v_uid, 'admin') THEN
    RAISE EXCEPTION 'admin required';
  END IF;
  IF p_status NOT IN ('submitted','needs_review','admin_verified','trusted','rejected') THEN
    RAISE EXCEPTION 'invalid status';
  END IF;

  SELECT * INTO v_store FROM public.merchant_stores WHERE id = p_store_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'store not found'; END IF;

  v_place_status := CASE p_status
    WHEN 'admin_verified' THEN 'admin_verified'::map_verification_status
    WHEN 'trusted' THEN 'trusted'::map_verification_status
    WHEN 'needs_review' THEN 'needs_review'::map_verification_status
    WHEN 'rejected' THEN 'closed'::map_verification_status
    ELSE 'submitted'::map_verification_status
  END;

  IF v_store.map_place_id IS NOT NULL THEN
    UPDATE public.map_places SET
      verification_status = v_place_status,
      confidence_score = public.map_default_confidence(v_place_status::text),
      verified_at = CASE WHEN p_status IN ('admin_verified','trusted') THEN now() ELSE verified_at END,
      verified_by = CASE WHEN p_status IN ('admin_verified','trusted') THEN v_uid ELSE verified_by END,
      active = CASE WHEN p_status='rejected' THEN false ELSE active END,
      updated_at = now()
    WHERE id = v_store.map_place_id;
  END IF;

  UPDATE public.merchant_stores SET
    location_submission_status = p_status,
    location_verified_at = CASE WHEN p_status IN ('admin_verified','trusted') THEN now() ELSE location_verified_at END,
    location_verified_by = CASE WHEN p_status IN ('admin_verified','trusted') THEN v_uid ELSE location_verified_by END,
    location_notes = COALESCE(NULLIF(btrim(p_note),''), location_notes),
    updated_at = now()
  WHERE id = p_store_id;

  BEGIN
    INSERT INTO public.audit_logs (actor_id, action, target_type, target_id, metadata)
    VALUES (v_uid, 'admin.merchant.location.' || p_status, 'merchant_store', p_store_id,
            jsonb_build_object('map_place_id', v_store.map_place_id, 'note', p_note));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_merchant_location_status(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_merchant_location_status(uuid,text,text) TO authenticated;
