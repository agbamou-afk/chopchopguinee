DO $mig$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public._qa_node3_repas_r1_r4()'::regprocedure);
  IF position($o0$  v_col bigint; v_open bigint; v_pay public.merchant_payables;$o0$ in d) = 0 THEN RAISE EXCEPTION 'QA_FIXTURE_ANCHOR_MISSING _qa_node3_repas_r1_r4() #0'; END IF;
  d := replace(d, $o0$  v_col bigint; v_open bigint; v_pay public.merchant_payables;$o0$, $n0$  v_col bigint; v_open bigint; v_pay public.merchant_payables;
  v_code text; v_proof text;$n0$);
  IF position($o1$    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    PERFORM public.mission_set_state(v_mission4,'heading_to_pickup');
    PERFORM public.mission_set_state(v_mission4,'arrived_pickup');
    PERFORM public.repas_custody_confirm_handoff(v_mission4, 'qa/r1r4-pickup.jpg',
      (SELECT code_plain FROM public.repas_custody_credentials
        WHERE order_id=v_o4 AND kind='restaurant_handoff'));$o1$ in d) = 0 THEN RAISE EXCEPTION 'QA_FIXTURE_ANCHOR_MISSING _qa_node3_repas_r1_r4() #1'; END IF;
  d := replace(d, $o1$    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    PERFORM public.mission_set_state(v_mission4,'heading_to_pickup');
    PERFORM public.mission_set_state(v_mission4,'arrived_pickup');
    PERFORM public.repas_custody_confirm_handoff(v_mission4, 'qa/r1r4-pickup.jpg',
      (SELECT code_plain FROM public.repas_custody_credentials
        WHERE order_id=v_o4 AND kind='restaurant_handoff'));$o1$, $n1$    -- R6: the merchant is the holder of its own handoff code; it is never read from a table.
    v_code := public.repas_custody_code_view(v_o4,'restaurant_handoff')->>'code';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    PERFORM public.mission_set_state(v_mission4,'heading_to_pickup');
    PERFORM public.mission_set_state(v_mission4,'arrived_pickup');
    v_proof := public._qa_r6_proof(v_mission4,'pickup',v_drv2,'r1r4');
    PERFORM public.repas_custody_confirm_handoff(v_mission4, v_proof, v_code);$n1$);
  IF position($o2$    PERFORM public.mission_set_state(v_mission4,'heading_to_dropoff');
    PERFORM public.mission_set_state(v_mission4,'arrived_dropoff');
    PERFORM public.repas_custody_confirm_delivery(v_mission4, 'qa/r1r4-drop.jpg',
      (SELECT code_plain FROM public.repas_custody_credentials
        WHERE order_id=v_o4 AND kind='customer_delivery'));$o2$ in d) = 0 THEN RAISE EXCEPTION 'QA_FIXTURE_ANCHOR_MISSING _qa_node3_repas_r1_r4() #2'; END IF;
  d := replace(d, $o2$    PERFORM public.mission_set_state(v_mission4,'heading_to_dropoff');
    PERFORM public.mission_set_state(v_mission4,'arrived_dropoff');
    PERFORM public.repas_custody_confirm_delivery(v_mission4, 'qa/r1r4-drop.jpg',
      (SELECT code_plain FROM public.repas_custody_credentials
        WHERE order_id=v_o4 AND kind='customer_delivery'));$o2$, $n2$    PERFORM public.mission_set_state(v_mission4,'heading_to_dropoff');
    PERFORM public.mission_set_state(v_mission4,'arrived_dropoff');
    -- R6: the customer is the holder of the delivery code; the courier must be given it.
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust3), true);
    v_code := public.repas_custody_code_view(v_o4,'customer_delivery')->>'code';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    v_proof := public._qa_r6_proof(v_mission4,'delivery',v_drv2,'r1r4');
    PERFORM public.repas_custody_confirm_delivery(v_mission4, v_proof, v_code);$n2$);
  IF position('code_plain' in d) > 0 THEN RAISE EXCEPTION 'PLAINTEXT_RESIDUE _qa_node3_repas_r1_r4()'; END IF;
  EXECUTE d;
END $mig$;

DO $mig$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public._qa_node3_repas_pickup()'::regprocedure);
  IF position($o0$  v_c0 bigint; v_c1 bigint; v_held bigint; v_unbalanced int;$o0$ in d) = 0 THEN RAISE EXCEPTION 'QA_FIXTURE_ANCHOR_MISSING _qa_node3_repas_pickup() #0'; END IF;
  d := replace(d, $o0$  v_c0 bigint; v_c1 bigint; v_held bigint; v_unbalanced int;$o0$, $n0$  v_c0 bigint; v_c1 bigint; v_held bigint; v_unbalanced int;
  v_code text;$n0$);
  IF position($o1$    BEGIN PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
      PERFORM public.repas_custody_confirm_pickup_collection(v_o1,
        (SELECT code_plain FROM public.repas_custody_credentials
          WHERE order_id=v_o1 AND kind='customer_pickup')); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;$o1$ in d) = 0 THEN RAISE EXCEPTION 'QA_FIXTURE_ANCHOR_MISSING _qa_node3_repas_pickup() #1'; END IF;
  d := replace(d, $o1$    BEGIN PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
      PERFORM public.repas_custody_confirm_pickup_collection(v_o1,
        (SELECT code_plain FROM public.repas_custody_credentials
          WHERE order_id=v_o1 AND kind='customer_pickup')); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;$o1$, $n1$    -- R6: only the customer holds the pickup code; it is read holder-scoped, never from a table.
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_code := public.repas_custody_code_view(v_o1,'customer_pickup')->>'code';
    BEGIN PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
      PERFORM public.repas_custody_confirm_pickup_collection(v_o1, v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;$n1$);
  IF position($o2$    v_res := public.repas_custody_confirm_pickup_collection(v_o1,
      (SELECT code_plain FROM public.repas_custody_credentials
        WHERE order_id=v_o1 AND kind='customer_pickup'));$o2$ in d) = 0 THEN RAISE EXCEPTION 'QA_FIXTURE_ANCHOR_MISSING _qa_node3_repas_pickup() #2'; END IF;
  d := replace(d, $o2$    v_res := public.repas_custody_confirm_pickup_collection(v_o1,
      (SELECT code_plain FROM public.repas_custody_credentials
        WHERE order_id=v_o1 AND kind='customer_pickup'));$o2$, $n2$    v_res := public.repas_custody_confirm_pickup_collection(v_o1, v_code);$n2$);
  IF position('code_plain' in d) > 0 THEN RAISE EXCEPTION 'PLAINTEXT_RESIDUE _qa_node3_repas_pickup()'; END IF;
  EXECUTE d;
END $mig$;

DO $mig$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public._qa_node3_repas_r5_runtime()'::regprocedure);
  IF position($o0$  v_orders_before int; v_open bigint;$o0$ in d) = 0 THEN RAISE EXCEPTION 'QA_FIXTURE_ANCHOR_MISSING _qa_node3_repas_r5_runtime() #0'; END IF;
  d := replace(d, $o0$  v_orders_before int; v_open bigint;$o0$, $n0$  v_orders_before int; v_open bigint;
  v_code text; v_proof text;$n0$);
  IF position($o1$    PERFORM public.repas_merchant_transition(v_o4,'ready');
    PERFORM public.repas_merchant_transition(v_o4,'handoff');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_confirm_pickup(v_m4);
    PERFORM public.mission_confirm_dropoff(v_m4);$o1$ in d) = 0 THEN RAISE EXCEPTION 'QA_FIXTURE_ANCHOR_MISSING _qa_node3_repas_r5_runtime() #1'; END IF;
  d := replace(d, $o1$    PERFORM public.repas_merchant_transition(v_o4,'ready');
    PERFORM public.repas_merchant_transition(v_o4,'handoff');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_confirm_pickup(v_m4);
    PERFORM public.mission_confirm_dropoff(v_m4);$o1$, $n1$    PERFORM public.repas_merchant_transition(v_o4,'ready');
    -- R6 custody transport (economics unchanged): merchant-holder code + real courier proof.
    v_code := public.repas_custody_code_view(v_o4,'restaurant_handoff')->>'code';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_set_state(v_m4,'heading_to_pickup');
    PERFORM public.mission_set_state(v_m4,'arrived_pickup');
    v_proof := public._qa_r6_proof(v_m4,'pickup',v_drv,'r5rt');
    PERFORM public.repas_custody_confirm_handoff(v_m4, v_proof, v_code);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_code := public.repas_custody_code_view(v_o4,'customer_delivery')->>'code';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_set_state(v_m4,'heading_to_dropoff');
    PERFORM public.mission_set_state(v_m4,'arrived_dropoff');
    v_proof := public._qa_r6_proof(v_m4,'delivery',v_drv,'r5rt');
    PERFORM public.repas_custody_confirm_delivery(v_m4, v_proof, v_code);$n1$);
  IF position('code_plain' in d) > 0 THEN RAISE EXCEPTION 'PLAINTEXT_RESIDUE _qa_node3_repas_r5_runtime()'; END IF;
  EXECUTE d;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r1_r4(), public._qa_node3_repas_pickup(), public._qa_node3_repas_r5_runtime() FROM PUBLIC, anon, authenticated;