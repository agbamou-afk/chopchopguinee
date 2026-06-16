
CREATE OR REPLACE FUNCTION public.field_submit_visit(
  p_pilot_id uuid,
  p_merchant_name text,
  p_merchant_phone text DEFAULT NULL,
  p_merchant_category text DEFAULT NULL,
  p_interest_level public.field_visit_interest DEFAULT 'cold',
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_address_text text DEFAULT NULL,
  p_landmark_note text DEFAULT NULL,
  p_entrance_note text DEFAULT NULL,
  p_pickup_note text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_zone_id uuid DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user uuid := auth.uid();
  v_visit_id uuid;
  v_place_id uuid;
  v_visit_status public.field_visit_status := 'visited';
  v_dup_count integer := 0;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF NOT public.is_assigned_to_pilot(v_user, p_pilot_id) THEN
    RAISE EXCEPTION 'not assigned to pilot';
  END IF;

  IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
    SELECT count(*) INTO v_dup_count FROM public.map_places
      WHERE active = true
        AND abs(lat - p_lat) < 0.0012
        AND abs(lng - p_lng) < 0.0012;

    INSERT INTO public.map_places (
      name, lat, lng, source, verification_status, confidence_score,
      category, landmark_note, entrance_note, pickup_note, active
    ) VALUES (
      p_merchant_name, p_lat, p_lng, 'field_visit', 'submitted', 35,
      p_merchant_category, p_landmark_note, p_entrance_note, p_pickup_note, true
    )
    RETURNING id INTO v_place_id;

    IF v_dup_count > 0 THEN v_visit_status := 'duplicate_possible';
    ELSE v_visit_status := 'submitted';
    END IF;
  END IF;

  INSERT INTO public.field_merchant_visits (
    pilot_id, assigned_user_id, map_service_zone_id, merchant_name, merchant_phone,
    merchant_category, interest_level, visit_status, lat, lng, address_text,
    landmark_note, entrance_note, pickup_note, notes, linked_map_place_id
  ) VALUES (
    p_pilot_id, v_user, p_zone_id, p_merchant_name, p_merchant_phone,
    p_merchant_category, p_interest_level, v_visit_status, p_lat, p_lng, p_address_text,
    p_landmark_note, p_entrance_note, p_pickup_note, p_notes, v_place_id
  ) RETURNING id INTO v_visit_id;

  RETURN v_visit_id;
END;
$$;
