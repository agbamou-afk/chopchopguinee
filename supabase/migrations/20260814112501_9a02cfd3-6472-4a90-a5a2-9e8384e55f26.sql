-- 1) mission_set_state is another Repas bypass: guard the custody-bearing states.
CREATE OR REPLACE FUNCTION public.mission_set_state(_mission_id uuid, _state mission_state)
 RETURNS missions LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _m public.missions;
  _prev public.mission_state;
  _rt public.cash_order_runtime;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF _state NOT IN ('heading_to_pickup','arrived_pickup','picked_up','heading_to_dropoff','arrived_dropoff','delivered') THEN
    RAISE EXCEPTION 'state_not_allowed';
  END IF;
  -- R6: for Repas, possession-bearing states are owned by the custody RPCs.
  IF _state IN ('picked_up','delivered') THEN
    PERFORM public._repas_custody_guard(_m);
  END IF;
  _prev := _m.state;
  SELECT * INTO _rt FROM public.cash_order_runtime WHERE mission_id = _mission_id;

  UPDATE public.missions SET state = _state WHERE id = _mission_id RETURNING * INTO _m;

  IF _state = 'delivered'::public.mission_state
     AND _prev IS DISTINCT FROM 'delivered'::public.mission_state THEN
    IF _rt.id IS NOT NULL THEN
      PERFORM public._cash_order_complete_internal(_rt.source_module, _rt.source_id, _uid, false);
    ELSE
      BEGIN
        PERFORM public.wallet_credit_mission_earning(_mission_id, 'mission_set_state.delivered');
      EXCEPTION WHEN OTHERS THEN
        INSERT INTO public.mission_events(mission_id, kind, payload)
        VALUES (_mission_id, 'courier_earning_failed', jsonb_build_object('error', SQLERRM));
      END;
    END IF;
  END IF;
  RETURN _m;
END; $function$;

REVOKE ALL ON FUNCTION public.mission_set_state(uuid, mission_state) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mission_set_state(uuid, mission_state) TO authenticated, service_role;

-- 2) Re-point the locked R1–R4 harness at the R6 custody path (economics preserved).
DO $patch$
DECLARE v_def text; v_old text; v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r1_r4';

  v_old := '    PERFORM public.repas_merchant_transition(v_o4,''handoff'');
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o4;
    r := r || public._qa_s13_ok(''G4.3 order handed off to the courier'', v_state=''out_for_delivery'', v_state);

    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_drv2), true);
    PERFORM public.mission_confirm_pickup(v_mission4);';
  IF position(v_old in v_def) = 0 THEN RAISE EXCEPTION 'R1R4_PATCH_ANCHOR_1_MISSING'; END IF;
  v_new := '    BEGIN PERFORM public.repas_merchant_transition(v_o4,''handoff''); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok(''G4.3 R6: merchant can no longer hand off; courier custody owns it'',
          v_err LIKE ''%HANDOFF_OWNED_BY_COURIER_CUSTODY%'', v_err);

    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_drv2), true);
    PERFORM public.mission_set_state(v_mission4,''heading_to_pickup'');
    PERFORM public.mission_set_state(v_mission4,''arrived_pickup'');
    PERFORM public.repas_custody_confirm_handoff(v_mission4, ''qa/r1r4-pickup.jpg'',
      (SELECT code_plain FROM public.repas_custody_credentials
        WHERE order_id=v_o4 AND kind=''restaurant_handoff''));
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o4;
    r := r || public._qa_s13_ok(''G4.3b proven handoff moves the order out for delivery'',
          v_state=''out_for_delivery'', v_state);';
  v_def := replace(v_def, v_old, v_new);

  v_old := '    PERFORM public.mission_confirm_dropoff(v_mission4);
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime';
  IF position(v_old in v_def) = 0 THEN RAISE EXCEPTION 'R1R4_PATCH_ANCHOR_2_MISSING'; END IF;
  v_new := '    PERFORM public.mission_set_state(v_mission4,''heading_to_dropoff'');
    PERFORM public.mission_set_state(v_mission4,''arrived_dropoff'');
    PERFORM public.repas_custody_confirm_delivery(v_mission4, ''qa/r1r4-drop.jpg'',
      (SELECT code_plain FROM public.repas_custody_credentials
        WHERE order_id=v_o4 AND kind=''customer_delivery''));
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime';
  v_def := replace(v_def, v_old, v_new);

  EXECUTE v_def;
END $patch$;

-- 3) Re-point the R4.5 pickup harness at the R6 customer-code collection.
DO $patch$
DECLARE v_def text; v_old text; v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_pickup';

  v_old := '    r := r || public._qa_s13_ok(''P5.2 pickup cannot complete before the food is ready'',
          v_err LIKE ''%ILLEGAL_TRANSITION%'', v_err);';
  IF position(v_old in v_def) = 0 THEN RAISE EXCEPTION 'PICKUP_PATCH_ANCHOR_1_MISSING'; END IF;
  v_new := '    r := r || public._qa_s13_ok(''P5.2 R6: one-click merchant pickup completion is refused'',
          v_err LIKE ''%PICKUP_REQUIRES_CUSTOMER_CODE%'', v_err);';
  v_def := replace(v_def, v_old, v_new);

  v_old := '    BEGIN PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_cust2), true);
      PERFORM public.chop_pay_merchant_pickup_complete(''repas'', v_o1); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok(''P5.6 a stranger cannot confirm the pickup handover'',
          v_err LIKE ''%Not authorized%'', v_err);';
  IF position(v_old in v_def) = 0 THEN RAISE EXCEPTION 'PICKUP_PATCH_ANCHOR_2_MISSING'; END IF;
  v_new := '    BEGIN PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_cust2), true);
      PERFORM public.repas_custody_confirm_pickup_collection(v_o1,
        (SELECT code_plain FROM public.repas_custody_credentials
          WHERE order_id=v_o1 AND kind=''customer_pickup'')); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok(''P5.6 a stranger cannot confirm the pickup handover'',
          v_err LIKE ''%NOT_AUTHORIZED%'', v_err);
    BEGIN PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_merch), true);
      PERFORM public.chop_pay_merchant_pickup_complete(''repas'', v_o1); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok(''P5.6b R6: direct Slice 5 pickup completion is closed'',
          v_err LIKE ''%PICKUP_REQUIRES_CUSTOMER_CODE%'', v_err);';
  v_def := replace(v_def, v_old, v_new);

  v_old := '    v_res := public.repas_merchant_transition(v_o1,''complete'');
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime WHERE source_id=v_o1;
    r := r || public._qa_s13_ok(''P5.7 pickup completes through the Chop Pay engine'',';
  IF position(v_old in v_def) = 0 THEN RAISE EXCEPTION 'PICKUP_PATCH_ANCHOR_3_MISSING'; END IF;
  v_new := '    v_res := public.repas_custody_confirm_pickup_collection(v_o1,
      (SELECT code_plain FROM public.repas_custody_credentials
        WHERE order_id=v_o1 AND kind=''customer_pickup''));
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime WHERE source_id=v_o1;
    r := r || public._qa_s13_ok(''P5.7 pickup completes through the Chop Pay engine'',';
  v_def := replace(v_def, v_old, v_new);

  EXECUTE v_def;
END $patch$;
