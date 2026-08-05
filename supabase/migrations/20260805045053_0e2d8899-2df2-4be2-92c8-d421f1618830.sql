CREATE OR REPLACE FUNCTION public._qa_slice1_run(p_driver uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r jsonb := '{}'::jsonb;
  v jsonb;
  step text := 'init';
  sid1 uuid := '22222222-2222-2222-2222-222222222222';
  sid2 uuid := '33333333-3333-3333-3333-333333333333';
BEGIN
  step := 'fixtures';
  UPDATE public.driver_profiles
     SET status = 'approved', id_doc_url = 'http://x/id', vehicle_photo_url = 'http://x/veh'
   WHERE user_id = p_driver;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'driver_starter_credit_enabled';
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_driver, 'role', 'authenticated')::text, true);
  r := r || jsonb_build_object('auth_uid', auth.uid());

  step := 'qa1_grant';
  r := r || jsonb_build_object(step, public.driver_starter_credit_grant());
  step := 'qa2_replay';
  r := r || jsonb_build_object(step, public.driver_starter_credit_grant());
  step := 'qa4_summary';
  r := r || jsonb_build_object(step, public.driver_balance_summary());

  step := 'qa6_cash_funding';
  BEGIN
    r := r || jsonb_build_object(step, public.driver_funding_allocate(p_driver, 20000, 'cash_funding'));
  EXCEPTION WHEN OTHERS THEN
    r := r || jsonb_build_object(step, 'RAISED: ' || SQLERRM);
  END;
  step := 'qa7_commission_alloc';
  r := r || jsonb_build_object(step, public.driver_funding_allocate(p_driver, 20000, 'commission'));

  step := 'qa8_place';
  r := r || jsonb_build_object(step, public.driver_mission_hold_place('ride', 'qa', sid1, 100000));
  SELECT jsonb_agg(jsonb_build_object('kind', kind, 'amt', amount_gnf,
                                      'unres', unrestricted_gnf, 'promo', promo_gnf))
    INTO v FROM public.mission_financial_holds WHERE source_module = 'qa';
  r := r || jsonb_build_object('qa8_holds', v, 'qa8_summary', public.driver_balance_summary());

  step := 'qa9_release';
  r := r || jsonb_build_object(step, public.driver_mission_hold_release('qa', sid1, NULL, 'qa'),
                               'qa9_summary', public.driver_balance_summary());
  step := 'qa11_release_replay';
  r := r || jsonb_build_object(step, public.driver_mission_hold_release('qa', sid1, NULL, 'qa'));

  step := 'qa5_cashout';
  BEGIN
    r := r || jsonb_build_object(step, public.driver_cashout_create_request(5000, '+224620000001'));
  EXCEPTION WHEN OTHERS THEN
    r := r || jsonb_build_object(step, 'RAISED: ' || SQLERRM);
  END;

  step := 'qa10_place2';
  r := r || jsonb_build_object(step, public.driver_mission_hold_place('ride', 'qa2', sid2, 100000));
  step := 'qa10_capture';
  r := r || jsonb_build_object(step, public.driver_mission_commission_capture('qa2', sid2, 100000));
  step := 'qa10_capture_replay';
  r := r || jsonb_build_object(step, public.driver_mission_commission_capture('qa2', sid2, 100000));
  SELECT jsonb_build_object('granted', granted_gnf, 'consumed', consumed_gnf,
                            'reversed', reversed_gnf, 'state', state)
    INTO v FROM public.driver_promo_credits WHERE driver_user_id = p_driver;
  r := r || jsonb_build_object('qa10_promo', v, 'qa10_summary', public.driver_balance_summary());

  step := 'qa3_ineligible';
  DELETE FROM public.driver_promo_credits WHERE driver_user_id = p_driver;
  UPDATE public.driver_profiles SET status = 'suspended' WHERE user_id = p_driver;
  r := r || jsonb_build_object(step, public.driver_starter_credit_grant());

  step := 'qa_policies';
  r := r || jsonb_build_object(
    'qa17_repas', public.finance_mission_requirement('repas', 150000),
    'qa18_ride', public.finance_mission_requirement('ride', 50000),
    'qa19_envoyer_over_cap', public.finance_mission_requirement('envoyer', 900000));

  RAISE EXCEPTION 'QA_RESULT %', r::text;
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM LIKE 'QA_RESULT%' THEN RAISE; END IF;
    RAISE EXCEPTION 'QA_RESULT %', (r || jsonb_build_object('FAILED_STEP', step, 'ERROR', SQLERRM))::text;
END;
$$;