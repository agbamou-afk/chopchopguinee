
-- ===== single settlement engine: extract core, keep privileged wrapper =====
CREATE OR REPLACE FUNCTION public._marche_procurement_settle_core(
  p_request_id uuid, p_actual_spend_gnf bigint, p_evidence_ref text, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_req public.marche_procurement_requests;
  v_a record; v_remaining bigint; v_take bigint; v_cap bigint := 0; v_rel bigint := 0; v_j jsonb;
BEGIN
  IF p_actual_spend_gnf IS NULL OR p_actual_spend_gnf < 0 THEN
    RAISE EXCEPTION 'PROCUREMENT_ACTUAL_SPEND_INVALID';
  END IF;
  SELECT * INTO v_req FROM public.marche_procurement_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_NOT_FOUND'; END IF;
  IF v_req.status = 'settled' THEN
    RETURN jsonb_build_object('status','already_settled','request_id',p_request_id,
      'actual_spend_gnf', v_req.actual_spend_gnf, 'captured_gnf', 0, 'released_gnf', 0);
  END IF;
  IF v_req.status = 'cancelled' THEN RAISE EXCEPTION 'PROCUREMENT_ALREADY_CANCELLED'; END IF;

  IF p_actual_spend_gnf > v_req.authorized_ceiling_gnf THEN
    RETURN jsonb_build_object('status','approval_required',
      'code','PROCUREMENT_AUTHORIZATION_REQUIRED',
      'request_id', p_request_id,
      'authorized_ceiling_gnf', v_req.authorized_ceiling_gnf,
      'requested_spend_gnf', p_actual_spend_gnf,
      'required_ceiling_gnf', p_actual_spend_gnf,
      'captured_gnf', 0, 'released_gnf', 0);
  END IF;

  v_remaining := p_actual_spend_gnf;
  FOR v_a IN SELECT id, amount_gnf FROM public.marche_procurement_authorizations
              WHERE request_id = p_request_id ORDER BY seq LOOP
    v_take := LEAST(v_remaining, v_a.amount_gnf);
    IF v_take > 0 THEN
      v_j := public._marche_procurement_capture_internal(v_a.id, v_take, p_actor);
      v_cap := v_cap + COALESCE((v_j->>'captured_gnf')::bigint, 0);
      v_remaining := v_remaining - v_take;
    END IF;
    v_j := public._marche_procurement_release_internal(v_a.id, 'procurement_unused_authorization', p_actor);
    v_rel := v_rel + COALESCE((v_j->>'released_gnf')::bigint, 0);
  END LOOP;

  UPDATE public.marche_procurement_requests
     SET status = 'settled', actual_spend_gnf = p_actual_spend_gnf, settled_at = now(),
         captured_total_gnf = captured_total_gnf + v_cap,
         released_total_gnf = released_total_gnf + v_rel
   WHERE id = p_request_id;
  INSERT INTO public.marche_procurement_events(request_id, event, payload, actor_user_id)
  VALUES (p_request_id, 'settled',
          jsonb_build_object('actual_spend_gnf', p_actual_spend_gnf, 'captured_gnf', v_cap,
                             'released_gnf', v_rel, 'evidence_ref', p_evidence_ref), p_actor);

  RETURN jsonb_build_object('status','settled','request_id',p_request_id,
    'actual_spend_gnf', p_actual_spend_gnf, 'captured_gnf', v_cap, 'released_gnf', v_rel,
    'authorized_ceiling_gnf', v_req.authorized_ceiling_gnf);
END $$;

CREATE OR REPLACE FUNCTION public.marche_procurement_settle_internal(
  p_request_id uuid, p_actual_spend_gnf bigint, p_evidence_ref text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF NOT public._finance_privileged(v_uid) THEN RAISE EXCEPTION 'PROCUREMENT_SETTLEMENT_FORBIDDEN'; END IF;
  RETURN public._marche_procurement_settle_core(p_request_id, p_actual_spend_gnf, p_evidence_ref, v_uid);
END $$;

-- ===== per-line procurement resolution (shopper) =====
CREATE OR REPLACE FUNCTION public.marche_shopper_resolve_line(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid(); m public.marche_procurement_missions;
  v_rid uuid; v_line int; v_kind text; v_item public.marche_procurement_request_items;
  lr public.marche_procurement_line_resolutions; v_pending public.marche_procurement_proposals;
  v_qty numeric; v_price bigint; v_total bigint; v_norm numeric; v_ver int; v_sub text;
BEGIN
  v_rid := (p->>'request_id')::uuid;
  v_line := (p->>'line_no')::int;
  v_kind := p->>'kind';
  m := public._marche_pm_shopper_lock(v_rid, v_uid);
  IF m.state <> 'shopping' THEN RAISE EXCEPTION 'PROCUREMENT_ILLEGAL_TRANSITION' USING DETAIL = m.state; END IF;

  SELECT * INTO v_item FROM public.marche_procurement_request_items
   WHERE request_id = v_rid AND line_no = v_line;
  IF v_item.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_LINE_NOT_FOUND'; END IF;

  SELECT * INTO lr FROM public.marche_procurement_line_resolutions
   WHERE request_id = v_rid AND line_no = v_line FOR UPDATE;
  IF lr.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_LINE_NOT_FOUND'; END IF;

  SELECT * INTO v_pending FROM public.marche_procurement_proposals
   WHERE request_id = v_rid AND line_no = v_line AND status = 'pending'
   ORDER BY version DESC LIMIT 1;

  IF v_kind = 'propose_substitution' OR v_kind = 'propose_quantity' THEN
    IF v_pending.id IS NOT NULL THEN
      UPDATE public.marche_procurement_proposals SET status = 'superseded'
       WHERE id = v_pending.id;
    END IF;
    SELECT COALESCE(max(version),0) + 1 INTO v_ver
      FROM public.marche_procurement_proposals WHERE request_id = v_rid AND line_no = v_line;
    IF v_kind = 'propose_substitution' THEN
      v_sub := NULLIF(btrim(COALESCE(p->>'substitute_label_fr','')),'');
      IF v_sub IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_SUBSTITUTION_LABEL_REQUIRED'; END IF;
      INSERT INTO public.marche_procurement_proposals(request_id, line_no, version, kind, payload, proposed_by)
      VALUES (v_rid, v_line, v_ver, 'substitution',
        jsonb_build_object('substitute_label_fr', v_sub,
                           'note_fr', NULLIF(p->>'note_fr',''),
                           'unit_price_gnf', NULLIF(p->>'actual_unit_price_gnf','')::bigint), v_uid);
      UPDATE public.marche_procurement_line_resolutions
         SET state = 'substitution_proposed', proposal_version = v_ver
       WHERE id = lr.id;
    ELSE
      v_qty := NULLIF(p->>'actual_qty','')::numeric;
      IF v_qty IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'PROCUREMENT_QTY_INVALID'; END IF;
      INSERT INTO public.marche_procurement_proposals(request_id, line_no, version, kind, payload, proposed_by)
      VALUES (v_rid, v_line, v_ver, 'quantity_adjust',
        jsonb_build_object('actual_qty', v_qty, 'requested_qty', v_item.requested_qty,
                           'note_fr', NULLIF(p->>'note_fr','')), v_uid);
      UPDATE public.marche_procurement_line_resolutions
         SET state = 'quantity_proposed', proposal_version = v_ver
       WHERE id = lr.id;
    END IF;
    PERFORM public._marche_pm_note(v_rid, 'proposal_created',
      jsonb_build_object('line_no', v_line, 'version', v_ver, 'kind', v_kind), v_uid, 'shopper');
    RETURN public.marche_procurement_mission_get(v_rid);
  END IF;

  IF v_kind = 'unavailable' THEN
    IF v_pending.id IS NOT NULL THEN
      UPDATE public.marche_procurement_proposals SET status='superseded' WHERE id = v_pending.id;
    END IF;
    UPDATE public.marche_procurement_line_resolutions
       SET state='unavailable', actual_qty = 0, actual_line_total_gnf = 0,
           actual_unit_price_gnf = NULL, actual_normalized_quantity = 0,
           note_fr = NULLIF(p->>'note_fr',''), resolved_by = v_uid, resolved_at = now()
     WHERE id = lr.id;
    PERFORM public._marche_pm_note(v_rid, 'line_unavailable',
      jsonb_build_object('line_no', v_line), v_uid, 'shopper');
    RETURN public.marche_procurement_mission_get(v_rid);
  END IF;

  IF v_kind <> 'acquired' THEN RAISE EXCEPTION 'PROCUREMENT_RESOLUTION_KIND_INVALID'; END IF;

  IF v_pending.id IS NOT NULL THEN RAISE EXCEPTION 'PROCUREMENT_APPROVAL_PENDING'; END IF;

  v_qty := COALESCE(NULLIF(p->>'actual_qty','')::numeric, v_item.requested_qty);
  v_price := NULLIF(p->>'actual_unit_price_gnf','')::bigint;
  IF v_qty <= 0 THEN RAISE EXCEPTION 'PROCUREMENT_QTY_INVALID'; END IF;
  IF v_price IS NULL OR v_price <= 0 THEN RAISE EXCEPTION 'PROCUREMENT_ACTUAL_PRICE_REQUIRED'; END IF;

  -- any deviation from the frozen basket line needs an APPROVED proposal of the right shape
  IF v_qty <> v_item.requested_qty THEN
    IF NOT EXISTS (SELECT 1 FROM public.marche_procurement_proposals
                    WHERE request_id = v_rid AND line_no = v_line AND status='approved'
                      AND kind='quantity_adjust' AND (payload->>'actual_qty')::numeric = v_qty) THEN
      RAISE EXCEPTION 'PROCUREMENT_APPROVAL_REQUIRED' USING DETAIL = 'quantity_adjust';
    END IF;
  END IF;

  v_sub := NULLIF(btrim(COALESCE(p->>'substitute_label_fr','')),'');
  IF v_sub IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.marche_procurement_proposals
                    WHERE request_id = v_rid AND line_no = v_line AND status='approved'
                      AND kind='substitution' AND payload->>'substitute_label_fr' = v_sub) THEN
      RAISE EXCEPTION 'PROCUREMENT_APPROVAL_REQUIRED' USING DETAIL = 'substitution';
    END IF;
  END IF;

  v_total := floor(v_qty * v_price)::bigint;
  v_norm := COALESCE(NULLIF(p->>'actual_normalized_quantity','')::numeric,
                     CASE WHEN v_item.canonical_quantity IS NOT NULL
                          THEN v_qty * v_item.canonical_quantity END);

  UPDATE public.marche_procurement_line_resolutions
     SET state='acquired', actual_qty = v_qty, actual_unit_price_gnf = v_price,
         actual_line_total_gnf = v_total, actual_normalized_quantity = v_norm,
         canonical_base_unit = v_item.canonical_base_unit,
         substitute_label_fr = v_sub, note_fr = NULLIF(p->>'note_fr',''),
         resolved_by = v_uid, resolved_at = now()
   WHERE id = lr.id;

  PERFORM public._marche_pm_note(v_rid, 'line_acquired',
    jsonb_build_object('line_no', v_line, 'actual_qty', v_qty,
      'actual_unit_price_gnf', v_price, 'actual_line_total_gnf', v_total,
      'substitute_label_fr', v_sub), v_uid, 'shopper');
  RETURN public.marche_procurement_mission_get(v_rid);
END $$;

-- ===== customer decision on a proposal =====
CREATE OR REPLACE FUNCTION public.marche_customer_decide_proposal(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid(); v_rid uuid; v_line int; v_ver int; v_dec text;
  m public.marche_procurement_missions; pr public.marche_procurement_proposals;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_AUTH_REQUIRED'; END IF;
  v_rid := (p->>'request_id')::uuid; v_line := (p->>'line_no')::int;
  v_ver := (p->>'version')::int; v_dec := p->>'decision';
  IF v_dec NOT IN ('approve','reject') THEN RAISE EXCEPTION 'PROCUREMENT_DECISION_INVALID'; END IF;

  SELECT * INTO m FROM public.marche_procurement_missions WHERE request_id = v_rid FOR UPDATE;
  IF m.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_MISSION_NOT_FOUND'; END IF;
  IF m.buyer_user_id <> v_uid THEN RAISE EXCEPTION 'PROCUREMENT_NOT_AUTHORIZED'; END IF;

  SELECT * INTO pr FROM public.marche_procurement_proposals
   WHERE request_id = v_rid AND line_no = v_line AND version = v_ver FOR UPDATE;
  IF pr.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_PROPOSAL_NOT_FOUND'; END IF;
  IF pr.status = 'superseded' THEN RAISE EXCEPTION 'PROCUREMENT_PROPOSAL_STALE'; END IF;
  IF pr.status <> 'pending' THEN
    IF (pr.status = 'approved' AND v_dec = 'approve') OR (pr.status = 'rejected' AND v_dec = 'reject') THEN
      RETURN public.marche_procurement_mission_get(v_rid) || jsonb_build_object('replayed', true);
    END IF;
    RAISE EXCEPTION 'PROCUREMENT_PROPOSAL_ALREADY_DECIDED';
  END IF;
  IF EXISTS (SELECT 1 FROM public.marche_procurement_proposals
              WHERE request_id = v_rid AND line_no = v_line AND version > v_ver) THEN
    RAISE EXCEPTION 'PROCUREMENT_PROPOSAL_STALE';
  END IF;

  UPDATE public.marche_procurement_proposals
     SET status = CASE WHEN v_dec='approve' THEN 'approved' ELSE 'rejected' END,
         decided_by = v_uid, decided_at = now()
   WHERE id = pr.id;

  UPDATE public.marche_procurement_line_resolutions
     SET state = 'pending'
   WHERE request_id = v_rid AND line_no = v_line AND state IN ('substitution_proposed','quantity_proposed');

  IF v_dec = 'reject' AND pr.kind = 'substitution' THEN
    UPDATE public.marche_procurement_line_resolutions
       SET state='unavailable', actual_qty = 0, actual_line_total_gnf = 0,
           actual_normalized_quantity = 0, resolved_by = v_uid, resolved_at = now()
     WHERE request_id = v_rid AND line_no = v_line;
  END IF;

  PERFORM public._marche_pm_note(v_rid, 'proposal_'||v_dec||'d',
    jsonb_build_object('line_no', v_line, 'version', v_ver, 'kind', pr.kind), v_uid, 'customer');
  RETURN public.marche_procurement_mission_get(v_rid);
END $$;

-- ===== purchase evidence =====
CREATE OR REPLACE FUNCTION public.marche_shopper_attach_evidence(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); m public.marche_procurement_missions; v_rid uuid; v_path text;
BEGIN
  v_rid := (p->>'request_id')::uuid;
  v_path := NULLIF(btrim(COALESCE(p->>'storage_path','')),'');
  m := public._marche_pm_shopper_lock(v_rid, v_uid);
  IF m.state NOT IN ('at_market','shopping') THEN
    RAISE EXCEPTION 'PROCUREMENT_ILLEGAL_TRANSITION' USING DETAIL = m.state;
  END IF;
  IF v_path IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_EVIDENCE_PATH_REQUIRED'; END IF;
  IF v_path NOT LIKE v_rid::text || '/%' THEN RAISE EXCEPTION 'PROCUREMENT_EVIDENCE_PATH_INVALID'; END IF;

  INSERT INTO public.marche_procurement_purchase_evidence(request_id, line_no, storage_path, uploaded_by)
  VALUES (v_rid, NULLIF(p->>'line_no','')::int, v_path, v_uid)
  ON CONFLICT (request_id, storage_path) DO NOTHING;
  PERFORM public._marche_pm_note(v_rid, 'evidence_attached',
    jsonb_build_object('storage_path', v_path), v_uid, 'shopper');
  RETURN public.marche_procurement_mission_get(v_rid);
END $$;

-- ===== purchase submission + server verification =====
CREATE OR REPLACE FUNCTION public.marche_shopper_submit_purchase(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid(); v_rid uuid; m public.marche_procurement_missions;
  v_req public.marche_procurement_requests; v_total bigint; v_unresolved int; v_pending int; v_ev int;
BEGIN
  v_rid := (p->>'request_id')::uuid;
  m := public._marche_pm_shopper_lock(v_rid, v_uid);
  IF m.state IN ('purchase_verified','delivering','delivered','completed') THEN
    RETURN public.marche_procurement_mission_get(v_rid) || jsonb_build_object('replayed', true);
  END IF;
  IF m.state <> 'shopping' THEN RAISE EXCEPTION 'PROCUREMENT_ILLEGAL_TRANSITION' USING DETAIL = m.state; END IF;

  SELECT count(*) INTO v_unresolved FROM public.marche_procurement_line_resolutions
   WHERE request_id = v_rid AND state NOT IN ('acquired','unavailable');
  IF v_unresolved > 0 THEN RAISE EXCEPTION 'PROCUREMENT_LINES_UNRESOLVED' USING DETAIL = v_unresolved::text; END IF;

  SELECT count(*) INTO v_pending FROM public.marche_procurement_proposals
   WHERE request_id = v_rid AND status = 'pending';
  IF v_pending > 0 THEN RAISE EXCEPTION 'PROCUREMENT_APPROVAL_PENDING'; END IF;

  SELECT count(*) INTO v_ev FROM public.marche_procurement_purchase_evidence WHERE request_id = v_rid;
  IF v_ev = 0 THEN RAISE EXCEPTION 'PROCUREMENT_EVIDENCE_REQUIRED'; END IF;

  SELECT COALESCE(sum(actual_line_total_gnf),0) INTO v_total
    FROM public.marche_procurement_line_resolutions WHERE request_id = v_rid AND state='acquired';

  SELECT * INTO v_req FROM public.marche_procurement_requests WHERE id = v_rid FOR UPDATE;
  IF v_total > v_req.authorized_ceiling_gnf THEN
    PERFORM public._marche_pm_note(v_rid, 'purchase_over_ceiling',
      jsonb_build_object('requested_spend_gnf', v_total,
                         'authorized_ceiling_gnf', v_req.authorized_ceiling_gnf), v_uid, 'shopper');
    RETURN jsonb_build_object('status','authorization_required',
      'code','PROCUREMENT_AUTHORIZATION_REQUIRED',
      'request_id', v_rid, 'requested_spend_gnf', v_total,
      'authorized_ceiling_gnf', v_req.authorized_ceiling_gnf,
      'required_ceiling_gnf', v_total);
  END IF;

  UPDATE public.marche_procurement_missions
     SET state='purchase_verified', purchase_submitted_at = now(),
         purchase_verified_at = now(), verified_spend_gnf = v_total
   WHERE request_id = v_rid;

  -- R8 substrate: truthful observations from a real, verified purchase
  INSERT INTO public.marche_procurement_price_observations
    (purchase_option_id, variant_id, commodity_id, market_id, observed_unit_price_gnf,
     observed_at, source_kind, source_ref, recorded_by)
  SELECT i.purchase_option_id, i.variant_id, i.commodity_id, m.market_id,
         lr.actual_unit_price_gnf, now(), 'procurement',
         v_rid::text || ':' || lr.line_no::text, v_uid
    FROM public.marche_procurement_line_resolutions lr
    JOIN public.marche_procurement_request_items i
      ON i.request_id = lr.request_id AND i.line_no = lr.line_no
   WHERE lr.request_id = v_rid AND lr.state = 'acquired'
     AND lr.substitute_label_fr IS NULL AND lr.actual_unit_price_gnf > 0;

  PERFORM public._marche_pm_note(v_rid, 'purchase_verified',
    jsonb_build_object('verified_spend_gnf', v_total), v_uid, 'shopper');
  RETURN public.marche_procurement_mission_get(v_rid);
END $$;

-- ===== delivery (reuses the certified mission rail) =====
CREATE OR REPLACE FUNCTION public.marche_shopper_start_delivery(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); m public.marche_procurement_missions; v_mid uuid;
        v_req public.marche_procurement_requests;
BEGIN
  m := public._marche_pm_shopper_lock(p_request_id, v_uid);
  IF m.state = 'delivering' THEN
    RETURN public.marche_procurement_mission_get(p_request_id) || jsonb_build_object('replayed', true);
  END IF;
  IF m.state <> 'purchase_verified' THEN
    RAISE EXCEPTION 'PROCUREMENT_PURCHASE_VERIFICATION_REQUIRED' USING DETAIL = m.state;
  END IF;
  IF NULLIF(btrim(COALESCE(m.destination_address,'')),'') IS NULL THEN
    RAISE EXCEPTION 'DELIVERY_DESTINATION_REQUIRED';
  END IF;
  SELECT * INTO v_req FROM public.marche_procurement_requests WHERE id = p_request_id;

  IF m.mission_id IS NULL THEN
    INSERT INTO public.missions(type, state, customer_id, courier_id,
      pickup_address, dropoff_address, dropoff_lat, dropoff_lng,
      payload_summary, estimated_earning_gnf)
    VALUES ('marketplace_delivery', 'picked_up', m.buyer_user_id, v_uid,
      COALESCE((SELECT name FROM public.physical_markets WHERE id = m.market_id), 'Marché'),
      m.destination_address, m.dropoff_lat, m.dropoff_lng,
      format('Marché ChopChop · %s ligne(s) · achat vérifié', v_req.line_count), 0)
    RETURNING id INTO v_mid;
  ELSE
    v_mid := m.mission_id;
  END IF;

  UPDATE public.marche_procurement_missions
     SET state='delivering', delivery_started_at = now(), mission_id = v_mid
   WHERE request_id = p_request_id;
  PERFORM public._marche_pm_note(p_request_id, 'delivery_started',
    jsonb_build_object('mission_id', v_mid), v_uid, 'shopper');
  RETURN public.marche_procurement_mission_get(p_request_id);
END $$;

CREATE OR REPLACE FUNCTION public.marche_shopper_complete_delivery(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); m public.marche_procurement_missions;
        v_req public.marche_procurement_requests; v_settle jsonb;
BEGIN
  m := public._marche_pm_shopper_lock(p_request_id, v_uid);
  IF m.state = 'completed' THEN
    RETURN public.marche_procurement_mission_get(p_request_id) || jsonb_build_object('replayed', true);
  END IF;
  IF m.state <> 'delivering' THEN RAISE EXCEPTION 'PROCUREMENT_ILLEGAL_TRANSITION' USING DETAIL = m.state; END IF;
  IF m.purchase_verified_at IS NULL OR m.verified_spend_gnf IS NULL THEN
    RAISE EXCEPTION 'PROCUREMENT_PURCHASE_VERIFICATION_REQUIRED';
  END IF;

  SELECT * INTO v_req FROM public.marche_procurement_requests WHERE id = p_request_id;
  IF m.verified_spend_gnf > v_req.authorized_ceiling_gnf THEN
    RAISE EXCEPTION 'PROCUREMENT_AUTHORIZATION_REQUIRED';
  END IF;

  v_settle := public._marche_procurement_settle_core(
    p_request_id, m.verified_spend_gnf, 'marche_shopper_mission', v_uid);
  IF COALESCE(v_settle->>'status','') NOT IN ('settled','already_settled') THEN
    RAISE EXCEPTION 'PROCUREMENT_SETTLEMENT_BLOCKED' USING DETAIL = COALESCE(v_settle->>'code','unknown');
  END IF;

  IF m.mission_id IS NOT NULL THEN
    UPDATE public.missions SET state = 'delivered', dropoff_confirmed_at = now(),
           dropoff_confirmed_by = v_uid
     WHERE id = m.mission_id AND state <> 'delivered';
  END IF;

  UPDATE public.marche_procurement_missions
     SET state='completed', delivered_at = COALESCE(delivered_at, now()), completed_at = now()
   WHERE request_id = p_request_id;
  PERFORM public._marche_pm_note(p_request_id, 'completed',
    jsonb_build_object('captured_gnf', v_settle->>'captured_gnf',
                       'released_gnf', v_settle->>'released_gnf'), v_uid, 'shopper');
  RETURN public.marche_procurement_mission_get(p_request_id) || jsonb_build_object('settlement', v_settle);
END $$;

-- ===== grants: narrow, RPC-only =====
REVOKE ALL ON FUNCTION public._marche_shopper_eligible(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_pm_rank(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_pm_note(uuid, text, jsonb, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_pm_shopper_lock(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_procurement_settle_core(uuid, bigint, text, uuid) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.marche_procurement_mission_get(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_procurement_set_destination(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_shopper_available_baskets(int) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_shopper_claim(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_shopper_arrive_market(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_shopper_start_shopping(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_shopper_resolve_line(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_customer_decide_proposal(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_shopper_attach_evidence(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_shopper_submit_purchase(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_shopper_start_delivery(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_shopper_complete_delivery(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.marche_procurement_mission_get(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_procurement_set_destination(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_shopper_available_baskets(int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_shopper_claim(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_shopper_arrive_market(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_shopper_start_shopping(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_shopper_resolve_line(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_customer_decide_proposal(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_shopper_attach_evidence(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_shopper_submit_purchase(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_shopper_start_delivery(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_shopper_complete_delivery(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._marche_shopper_eligible(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._marche_pm_rank(text) TO service_role;
GRANT EXECUTE ON FUNCTION public._marche_pm_note(uuid, text, jsonb, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public._marche_pm_shopper_lock(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._marche_procurement_settle_core(uuid, bigint, text, uuid) TO service_role;
