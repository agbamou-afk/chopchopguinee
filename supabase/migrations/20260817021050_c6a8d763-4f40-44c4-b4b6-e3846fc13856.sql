
-- ============ NODE 4 MARCHE R7: eligibility + lifecycle engine ============

CREATE OR REPLACE FUNCTION public._marche_shopper_eligible(_uid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT _uid IS NOT NULL AND public.driver_has_capability(_uid, 'marche_shopper');
$$;

CREATE OR REPLACE FUNCTION public._marche_pm_rank(p_state text)
RETURNS int LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE p_state
    WHEN 'unassigned' THEN 0 WHEN 'assigned' THEN 1 WHEN 'at_market' THEN 2
    WHEN 'shopping' THEN 3 WHEN 'purchase_verified' THEN 4 WHEN 'delivering' THEN 5
    WHEN 'delivered' THEN 6 WHEN 'completed' THEN 7 WHEN 'cancelled' THEN 99 END;
$$;

CREATE OR REPLACE FUNCTION public._marche_pm_note(
  p_request_id uuid, p_event text, p_payload jsonb, p_actor uuid, p_role text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  INSERT INTO public.marche_procurement_mission_events(request_id, event, payload, actor_user_id, actor_role)
  VALUES (p_request_id, p_event, COALESCE(p_payload,'{}'::jsonb), p_actor, p_role);
$$;

-- Loads the mission row FOR UPDATE and asserts the caller is the assigned shopper.
CREATE OR REPLACE FUNCTION public._marche_pm_shopper_lock(p_request_id uuid, p_uid uuid)
RETURNS public.marche_procurement_missions LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public' AS $$
DECLARE m public.marche_procurement_missions;
BEGIN
  IF p_uid IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_AUTH_REQUIRED'; END IF;
  SELECT * INTO m FROM public.marche_procurement_missions WHERE request_id = p_request_id FOR UPDATE;
  IF m.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_MISSION_NOT_FOUND'; END IF;
  IF m.shopper_user_id IS DISTINCT FROM p_uid THEN RAISE EXCEPTION 'PROCUREMENT_NOT_ASSIGNED_SHOPPER'; END IF;
  IF NOT public._marche_shopper_eligible(p_uid) THEN RAISE EXCEPTION 'PROCUREMENT_SHOPPER_NOT_ELIGIBLE'; END IF;
  RETURN m;
END $$;

-- ============ canonical read ============
CREATE OR REPLACE FUNCTION public.marche_procurement_mission_get(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  m public.marche_procurement_missions; v_uid uuid := auth.uid();
  v_req public.marche_procurement_requests; v_is_shopper boolean; v_is_buyer boolean; v_admin boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_AUTH_REQUIRED'; END IF;
  SELECT * INTO m FROM public.marche_procurement_missions WHERE request_id = p_request_id;
  IF m.id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_req FROM public.marche_procurement_requests WHERE id = p_request_id;
  v_is_shopper := m.shopper_user_id IS NOT DISTINCT FROM v_uid;
  v_is_buyer := m.buyer_user_id = v_uid;
  v_admin := public._finance_privileged(v_uid) OR public.is_any_admin(v_uid);
  IF NOT (v_is_shopper OR v_is_buyer OR v_admin) THEN RAISE EXCEPTION 'PROCUREMENT_NOT_AUTHORIZED'; END IF;

  RETURN jsonb_build_object(
    'request_id', m.request_id,
    'state', m.state,
    'market_id', m.market_id,
    'destination_address', CASE WHEN v_is_buyer OR v_is_shopper OR v_admin THEN m.destination_address END,
    'shopper_user_id', CASE WHEN v_is_shopper OR v_admin THEN m.shopper_user_id END,
    'has_shopper', m.shopper_user_id IS NOT NULL,
    'buyer_user_id', CASE WHEN v_is_buyer OR v_admin THEN m.buyer_user_id END,
    'mission_id', CASE WHEN v_is_shopper OR v_admin THEN m.mission_id END,
    'authorized_ceiling_gnf', v_req.authorized_ceiling_gnf,
    'verified_spend_gnf', m.verified_spend_gnf,
    'actual_spend_gnf', v_req.actual_spend_gnf,
    'request_status', v_req.status,
    'assigned_at', m.assigned_at, 'arrived_market_at', m.arrived_market_at,
    'shopping_started_at', m.shopping_started_at,
    'purchase_submitted_at', m.purchase_submitted_at,
    'purchase_verified_at', m.purchase_verified_at,
    'delivery_started_at', m.delivery_started_at,
    'delivered_at', m.delivered_at, 'completed_at', m.completed_at,
    'evidence_count', (SELECT count(*) FROM public.marche_procurement_purchase_evidence e
                        WHERE e.request_id = p_request_id),
    'lines', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'line_no', i.line_no,
        'commodity_name_fr', i.commodity_name_fr,
        'variant_name_fr', i.variant_name_fr,
        'option_label_fr', i.option_label_fr,
        'sale_unit', i.sale_unit,
        'canonical_base_unit', i.canonical_base_unit,
        'requested_qty', i.requested_qty,
        'normalized_quantity', i.normalized_quantity,
        'state', COALESCE(lr.state,'pending'),
        'actual_qty', lr.actual_qty,
        'actual_normalized_quantity', lr.actual_normalized_quantity,
        'actual_unit_price_gnf', lr.actual_unit_price_gnf,
        'actual_line_total_gnf', lr.actual_line_total_gnf,
        'substitute_label_fr', lr.substitute_label_fr,
        'note_fr', lr.note_fr,
        'proposal_version', COALESCE(lr.proposal_version,0),
        'pending_proposal', (SELECT jsonb_build_object('version', pp.version, 'kind', pp.kind,
              'payload', pp.payload, 'proposed_at', pp.proposed_at)
            FROM public.marche_procurement_proposals pp
           WHERE pp.request_id = p_request_id AND pp.line_no = i.line_no AND pp.status = 'pending'
           ORDER BY pp.version DESC LIMIT 1)
      ) ORDER BY i.line_no), '[]'::jsonb)
      FROM public.marche_procurement_request_items i
      LEFT JOIN public.marche_procurement_line_resolutions lr
             ON lr.request_id = i.request_id AND lr.line_no = i.line_no
     WHERE i.request_id = p_request_id));
END $$;

-- ============ destination (customer) ============
CREATE OR REPLACE FUNCTION public.marche_procurement_set_destination(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); v_rid uuid; v_req public.marche_procurement_requests;
        m public.marche_procurement_missions; v_addr text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_AUTH_REQUIRED'; END IF;
  v_rid := (p->>'request_id')::uuid;
  v_addr := NULLIF(btrim(COALESCE(p->>'destination_address','')),'');
  IF v_addr IS NULL THEN RAISE EXCEPTION 'DELIVERY_DESTINATION_REQUIRED'; END IF;
  SELECT * INTO v_req FROM public.marche_procurement_requests WHERE id = v_rid;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_NOT_FOUND'; END IF;
  IF v_req.buyer_user_id <> v_uid THEN RAISE EXCEPTION 'PROCUREMENT_NOT_AUTHORIZED'; END IF;
  IF v_req.status <> 'authorized' THEN RAISE EXCEPTION 'PROCUREMENT_NOT_OPEN'; END IF;

  INSERT INTO public.marche_procurement_missions(request_id, buyer_user_id, state,
      destination_address, dropoff_lat, dropoff_lng)
  VALUES (v_rid, v_uid, 'unassigned', v_addr,
      NULLIF(p->>'dropoff_lat','')::numeric, NULLIF(p->>'dropoff_lng','')::numeric)
  ON CONFLICT (request_id) DO UPDATE
    SET destination_address = EXCLUDED.destination_address,
        dropoff_lat = EXCLUDED.dropoff_lat, dropoff_lng = EXCLUDED.dropoff_lng
  RETURNING * INTO m;

  IF public._marche_pm_rank(m.state) >= public._marche_pm_rank('delivering') THEN
    RAISE EXCEPTION 'PROCUREMENT_DESTINATION_LOCKED';
  END IF;
  PERFORM public._marche_pm_note(v_rid, 'destination_set',
    jsonb_build_object('destination_address', v_addr), v_uid, 'customer');
  RETURN public.marche_procurement_mission_get(v_rid);
END $$;

-- ============ shopper queue + claim ============
CREATE OR REPLACE FUNCTION public.marche_shopper_available_baskets(p_limit int DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_AUTH_REQUIRED'; END IF;
  IF NOT public._marche_shopper_eligible(v_uid) THEN RAISE EXCEPTION 'PROCUREMENT_SHOPPER_NOT_ELIGIBLE'; END IF;
  RETURN (SELECT COALESCE(jsonb_agg(x ORDER BY x->>'authorized_at'), '[]'::jsonb) FROM (
    SELECT jsonb_build_object(
      'request_id', r.id,
      'authorized_ceiling_gnf', r.authorized_ceiling_gnf,
      'line_count', r.line_count, 'item_count', r.item_count,
      'authorized_at', r.authorized_at,
      'destination_address', m.destination_address) AS x
    FROM public.marche_procurement_requests r
    LEFT JOIN public.marche_procurement_missions m ON m.request_id = r.id
   WHERE r.status = 'authorized'
     AND (m.id IS NULL OR (m.shopper_user_id IS NULL AND m.state = 'unassigned'))
   ORDER BY r.authorized_at
   LIMIT GREATEST(1, LEAST(COALESCE(p_limit,20), 50))) s);
END $$;

CREATE OR REPLACE FUNCTION public.marche_shopper_claim(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); v_req public.marche_procurement_requests;
        m public.marche_procurement_missions; v_n int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_AUTH_REQUIRED'; END IF;
  IF NOT public._marche_shopper_eligible(v_uid) THEN RAISE EXCEPTION 'PROCUREMENT_SHOPPER_NOT_ELIGIBLE'; END IF;

  SELECT * INTO v_req FROM public.marche_procurement_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_NOT_FOUND'; END IF;
  IF v_req.status <> 'authorized' THEN RAISE EXCEPTION 'PROCUREMENT_NOT_OPEN'; END IF;

  INSERT INTO public.marche_procurement_missions(request_id, buyer_user_id, state)
  VALUES (p_request_id, v_req.buyer_user_id, 'unassigned')
  ON CONFLICT (request_id) DO NOTHING;

  SELECT * INTO m FROM public.marche_procurement_missions WHERE request_id = p_request_id FOR UPDATE;
  IF m.shopper_user_id IS NOT NULL THEN
    IF m.shopper_user_id = v_uid THEN
      RETURN public.marche_procurement_mission_get(p_request_id) || jsonb_build_object('replayed', true);
    END IF;
    RAISE EXCEPTION 'PROCUREMENT_MISSION_ALREADY_ASSIGNED';
  END IF;

  UPDATE public.marche_procurement_missions
     SET shopper_user_id = v_uid, state = 'assigned', assigned_at = now()
   WHERE request_id = p_request_id AND shopper_user_id IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN RAISE EXCEPTION 'PROCUREMENT_MISSION_ALREADY_ASSIGNED'; END IF;

  -- materialise the per-line resolution ledger from the frozen basket lines
  INSERT INTO public.marche_procurement_line_resolutions(request_id, line_no, requested_qty, canonical_base_unit)
  SELECT i.request_id, i.line_no, i.requested_qty, i.canonical_base_unit
    FROM public.marche_procurement_request_items i
   WHERE i.request_id = p_request_id
  ON CONFLICT (request_id, line_no) DO NOTHING;

  PERFORM public._marche_pm_note(p_request_id, 'shopper_assigned',
    jsonb_build_object('shopper_user_id', v_uid), v_uid, 'shopper');
  RETURN public.marche_procurement_mission_get(p_request_id);
END $$;

-- ============ lifecycle steps ============
CREATE OR REPLACE FUNCTION public.marche_shopper_arrive_market(p_request_id uuid, p_market_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); m public.marche_procurement_missions;
BEGIN
  m := public._marche_pm_shopper_lock(p_request_id, v_uid);
  IF m.state = 'at_market' THEN
    RETURN public.marche_procurement_mission_get(p_request_id) || jsonb_build_object('replayed', true);
  END IF;
  IF m.state <> 'assigned' THEN RAISE EXCEPTION 'PROCUREMENT_ILLEGAL_TRANSITION' USING DETAIL = m.state; END IF;
  UPDATE public.marche_procurement_missions
     SET state = 'at_market', arrived_market_at = now(), market_id = COALESCE(p_market_id, market_id)
   WHERE request_id = p_request_id;
  PERFORM public._marche_pm_note(p_request_id, 'arrived_market',
    jsonb_build_object('market_id', p_market_id), v_uid, 'shopper');
  RETURN public.marche_procurement_mission_get(p_request_id);
END $$;

CREATE OR REPLACE FUNCTION public.marche_shopper_start_shopping(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); m public.marche_procurement_missions;
BEGIN
  m := public._marche_pm_shopper_lock(p_request_id, v_uid);
  IF m.state = 'shopping' THEN
    RETURN public.marche_procurement_mission_get(p_request_id) || jsonb_build_object('replayed', true);
  END IF;
  IF m.state <> 'at_market' THEN RAISE EXCEPTION 'PROCUREMENT_ILLEGAL_TRANSITION' USING DETAIL = m.state; END IF;
  UPDATE public.marche_procurement_missions
     SET state = 'shopping', shopping_started_at = now() WHERE request_id = p_request_id;
  PERFORM public._marche_pm_note(p_request_id, 'shopping_started', '{}'::jsonb, v_uid, 'shopper');
  RETURN public.marche_procurement_mission_get(p_request_id);
END $$;
