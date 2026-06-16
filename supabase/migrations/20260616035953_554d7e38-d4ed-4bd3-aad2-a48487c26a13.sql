
CREATE OR REPLACE FUNCTION public.map_mark_place_duplicate(
  p_source_place_id uuid,
  p_target_place_id uuid,
  p_candidate_id uuid DEFAULT NULL,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  IF p_source_place_id = p_target_place_id THEN
    RAISE EXCEPTION 'source and target must differ';
  END IF;

  PERFORM 1 FROM public.map_places WHERE id = p_target_place_id FOR UPDATE;
  PERFORM 1 FROM public.map_places WHERE id = p_source_place_id FOR UPDATE;

  UPDATE public.map_places
     SET verification_status = 'duplicate',
         duplicate_of = p_target_place_id,
         active = false,
         updated_at = now()
   WHERE id = p_source_place_id;

  IF p_candidate_id IS NOT NULL THEN
    UPDATE public.map_place_duplicate_candidates
       SET status = 'confirmed_duplicate',
           reviewed_by = auth.uid(),
           reviewed_at = now(),
           merge_target_place_id = p_target_place_id,
           notes = COALESCE(p_reason, notes)
     WHERE id = p_candidate_id;
  END IF;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (auth.uid(), 'maps', 'map_mark_duplicate', 'map_place', p_source_place_id,
          jsonb_build_object(
            'target_place_id', p_target_place_id,
            'candidate_id', p_candidate_id
          ),
          p_reason);
END;
$$;

CREATE OR REPLACE FUNCTION public.map_merge_places(
  p_source_place_id uuid,
  p_target_place_id uuid,
  p_candidate_id uuid DEFAULT NULL,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_source public.map_places%ROWTYPE;
  v_target public.map_places%ROWTYPE;
  v_moved_stores integer := 0;
  v_moved_reports integer := 0;
  v_new_aliases text[];
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  IF p_source_place_id = p_target_place_id THEN
    RAISE EXCEPTION 'source and target must differ';
  END IF;

  SELECT * INTO v_source FROM public.map_places WHERE id = p_source_place_id FOR UPDATE;
  SELECT * INTO v_target FROM public.map_places WHERE id = p_target_place_id FOR UPDATE;
  IF v_source.id IS NULL OR v_target.id IS NULL THEN
    RAISE EXCEPTION 'place not found';
  END IF;

  v_new_aliases := ARRAY(
    SELECT DISTINCT x FROM unnest(
      COALESCE(v_target.aliases, '{}'::text[]) ||
      ARRAY[v_source.name] ||
      COALESCE(v_source.aliases, '{}'::text[])
    ) AS x WHERE x IS NOT NULL AND x <> '' AND lower(x) <> lower(v_target.name)
  );

  UPDATE public.map_places
     SET aliases = v_new_aliases,
         pickup_note = COALESCE(pickup_note, v_source.pickup_note),
         entrance_note = COALESCE(entrance_note, v_source.entrance_note),
         landmark_note = COALESCE(landmark_note, v_source.landmark_note),
         operational_note = COALESCE(operational_note, v_source.operational_note),
         updated_at = now()
   WHERE id = p_target_place_id;

  UPDATE public.map_places
     SET verification_status = 'duplicate',
         duplicate_of = p_target_place_id,
         active = false,
         updated_at = now()
   WHERE id = p_source_place_id;

  UPDATE public.merchant_stores
     SET map_place_id = p_target_place_id,
         updated_at = now()
   WHERE map_place_id = p_source_place_id;
  GET DIAGNOSTICS v_moved_stores = ROW_COUNT;

  UPDATE public.map_driver_reports
     SET place_id = p_target_place_id
   WHERE place_id = p_source_place_id;
  GET DIAGNOSTICS v_moved_reports = ROW_COUNT;

  IF p_candidate_id IS NOT NULL THEN
    UPDATE public.map_place_duplicate_candidates
       SET status = 'merged',
           reviewed_by = auth.uid(),
           reviewed_at = now(),
           merge_target_place_id = p_target_place_id,
           notes = COALESCE(p_reason, notes)
     WHERE id = p_candidate_id;
  END IF;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (auth.uid(), 'maps', 'map_merge_places', 'map_place', p_source_place_id,
          jsonb_build_object('source_name', v_source.name, 'target_name', v_target.name),
          jsonb_build_object(
            'target_place_id', p_target_place_id,
            'candidate_id', p_candidate_id,
            'moved_stores', v_moved_stores,
            'moved_reports', v_moved_reports
          ),
          p_reason);

  RETURN jsonb_build_object(
    'source_place_id', p_source_place_id,
    'target_place_id', p_target_place_id,
    'moved_stores', v_moved_stores,
    'moved_reports', v_moved_reports
  );
END;
$$;
