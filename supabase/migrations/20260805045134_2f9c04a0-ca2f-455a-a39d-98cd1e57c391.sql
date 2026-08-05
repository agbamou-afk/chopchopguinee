CREATE OR REPLACE FUNCTION public._qa_slice1_run(p_driver uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r jsonb := '{}'::jsonb;
  s1 jsonb; s2 jsonb; rel jsonb;
  sid1 uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  UPDATE public.driver_profiles
     SET status = 'approved', id_doc_url = 'http://x/id', vehicle_photo_url = 'http://x/veh'
   WHERE user_id = p_driver;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'driver_starter_credit_enabled';
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_driver, 'role', 'authenticated')::text, true);

  PERFORM public.driver_starter_credit_grant();
  PERFORM public.driver_mission_hold_place('ride', 'qa', sid1, 100000);
  s1 := public.driver_balance_summary();
  rel := public.driver_mission_hold_release('qa', sid1, NULL, 'qa');
  s2 := public.driver_balance_summary();
  SELECT jsonb_agg(jsonb_build_object('kind', kind, 'state', state, 'amt', amount_gnf))
    INTO r FROM public.mission_financial_holds WHERE source_module = 'qa';

  RAISE EXCEPTION 'QA_RESULT %', jsonb_build_object(
    'before', s1, 'release', rel, 'after', s2, 'holds', r,
    'wallet', (SELECT jsonb_build_object('bal', balance_gnf, 'held', held_gnf)
                 FROM public.wallets WHERE owner_user_id = p_driver AND party_type = 'driver')
  )::text;
END;
$$;