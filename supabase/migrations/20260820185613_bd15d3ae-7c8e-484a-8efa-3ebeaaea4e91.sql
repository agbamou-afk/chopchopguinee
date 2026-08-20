REVOKE ALL ON public.marche_ops_cases FROM anon, authenticated;
REVOKE ALL ON public.marche_ops_events FROM anon, authenticated;
REVOKE ALL ON public.marche_ops_controls FROM anon, authenticated;
REVOKE ALL ON public.marche_ops_reputation_moderations FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.marche_ops_case_detail(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.marche_ops_queue(text,text,text,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.marche_ops_case_open(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.marche_ops_command(uuid,text,uuid,text,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.marche_ops_signal(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marche_ops_case_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_ops_queue(text,text,text,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_ops_case_open(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_ops_command(uuid,text,uuid,text,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_ops_signal(jsonb) TO authenticated;

DO $mig$
DECLARE s text; s0 text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO s FROM pg_proc
   WHERE proname = '_qa_node4_marche_r12' AND pronamespace = 'public'::regnamespace;
  s0 := s;
  s := replace(s,
    'INSERT INTO public.marche_procurement_missions(request_id, buyer_user_id, shopper_user_id, state)' || E'\n' ||
    '      VALUES (gen_random_uuid(), v_buy, v_shop, ''shopping'') RETURNING id INTO v_mission;',
    'DECLARE v_req0 uuid; BEGIN' || E'\n' ||
    '      INSERT INTO public.marche_procurement_requests(buyer_user_id, authorized_ceiling_gnf,' || E'\n' ||
    '        estimate_status, estimate_basis, estimated_subtotal_gnf, estimate_confidence,' || E'\n' ||
    '        estimate_sample_count, line_count, item_count, client_request_id, request_fingerprint)' || E'\n' ||
    '      VALUES (v_buy, 100000, ''available'', ''observed_procurement'', 50000, ''medium'', 3, 1, 1,' || E'\n' ||
    '              gen_random_uuid(), ''qa-n412-fp'') RETURNING id INTO v_req0;' || E'\n' ||
    '      INSERT INTO public.marche_procurement_missions(request_id, buyer_user_id, shopper_user_id, state)' || E'\n' ||
    '        VALUES (v_req0, v_buy, v_shop, ''shopping'') RETURNING id INTO v_mission;' || E'\n' ||
    '    END;');
  IF s = s0 THEN RAISE EXCEPTION 'QA_R12_PATCH_FAILED'; END IF;
  EXECUTE s;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r12() FROM PUBLIC, anon, authenticated;