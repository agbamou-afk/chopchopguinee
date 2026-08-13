DO $$
DECLARE r jsonb; v_batch text := 'node0-final-gate-' || to_char(now(),'YYYYMMDDHH24MISS'); v_parity jsonb;
BEGIN
  SELECT jsonb_agg(to_jsonb(t)) INTO r FROM public._qa_node0_course() t;
  INSERT INTO public._qa_s13_results(part, result)
  VALUES (100, jsonb_build_object('batch', v_batch, 'suite','node0_course','result', r));

  -- ride_get_quote is fail-closed on a NULL caller; emulate a service-role caller.
  PERFORM set_config('request.jwt.claim.role','service_role', true);

  SELECT jsonb_build_object(
    'batch', v_batch,
    'suite', 'node0_preview_parity',
    'quote', q,
    'helper_hold', public.ride_reservation_amount_gnf((q->>'fare_gnf')::bigint),
    'parity_ok', (q->>'chop_pay_hold_gnf')::bigint
                 = public.ride_reservation_amount_gnf((q->>'fare_gnf')::bigint),
    'bps_ok', (q->>'reservation_buffer_bps')::int = 11000,
    'quote_anon_denied', NOT has_function_privilege('anon',
        'public.ride_get_quote(ride_mode,numeric,numeric,numeric,numeric)','EXECUTE'),
    'quote_authenticated_allowed', has_function_privilege('authenticated',
        'public.ride_get_quote(ride_mode,numeric,numeric,numeric,numeric)','EXECUTE')
  ) INTO v_parity
  FROM public.ride_get_quote('moto'::ride_mode, 9.5350, -13.6800, 9.5710, -13.6120) q;
  INSERT INTO public._qa_s13_results(part, result) VALUES (101, v_parity);

  INSERT INTO public._qa_s13_results(part, result) VALUES (1, jsonb_build_object('batch',v_batch) || to_jsonb(public._qa_s13_run1()));
  INSERT INTO public._qa_s13_results(part, result) VALUES (2, jsonb_build_object('batch',v_batch) || to_jsonb(public._qa_s13_run2()));
  INSERT INTO public._qa_s13_results(part, result) VALUES (3, jsonb_build_object('batch',v_batch) || to_jsonb(public._qa_s13_run3()));
  INSERT INTO public._qa_s13_results(part, result) VALUES (4, jsonb_build_object('batch',v_batch) || to_jsonb(public._qa_s13_run4()));
  INSERT INTO public._qa_s13_results(part, result) VALUES (5, jsonb_build_object('batch',v_batch) || to_jsonb(public._qa_s13_run5()));
  INSERT INTO public._qa_s13_results(part, result) VALUES (6, jsonb_build_object('batch',v_batch) || to_jsonb(public._qa_s13_run6()));
  INSERT INTO public._qa_s13_results(part, result) VALUES (7, jsonb_build_object('batch',v_batch) || to_jsonb(public._qa_s13_run7()));
END $$;