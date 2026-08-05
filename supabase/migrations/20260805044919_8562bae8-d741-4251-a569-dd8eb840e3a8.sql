-- 1. Remove the superseded 6-argument overload (ambiguous with the new one).
DROP FUNCTION IF EXISTS public.driver_mission_hold_place(text, text, uuid, bigint, uuid, boolean);

-- 2. Self-rolling-back QA harness (temporary; dropped after Slice 1 sign-off).
CREATE OR REPLACE FUNCTION public._qa_slice1_run(p_driver uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r jsonb := '{}'::jsonb;
  v jsonb;
  sid1 uuid := '22222222-2222-2222-2222-222222222222';
  sid2 uuid := '33333333-3333-3333-3333-333333333333';
BEGIN
  UPDATE public.driver_profiles
     SET status = 'approved', id_doc_url = 'http://x/id', vehicle_photo_url = 'http://x/veh'
   WHERE user_id = p_driver;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'driver_starter_credit_enabled';
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_driver, 'role', 'authenticated')::text, true);

  r := r || jsonb_build_object('qa1_grant', public.driver_starter_credit_grant());
  r := r || jsonb_build_object('qa2_replay', public.driver_starter_credit_grant());
  r := r || jsonb_build_object('qa4_summary', public.driver_balance_summary());
  BEGIN
    r := r || jsonb_build_object('qa6_cash_funding',
      public.driver_funding_allocate(p_driver, 20000, 'cash_funding'));
  EXCEPTION WHEN OTHERS THEN
    r := r || jsonb_build_object('qa6_cash_funding', 'RAISED: ' || SQLERRM);
  END;
  r := r || jsonb_build_object('qa7_commission_alloc',
    public.driver_funding_allocate(p_driver, 20000, 'commission'));

  r := r || jsonb_build_object('qa8_place',
    public.driver_mission_hold_place('ride', 'qa', sid1, 100000));
  SELECT jsonb_agg(jsonb_build_object('kind', kind, 'amt', amount_gnf,
                                      'unres', unrestricted_gnf, 'promo', promo_gnf))
    INTO v FROM public.mission_financial_holds WHERE source_module = 'qa';
  r := r || jsonb_build_object('qa8_holds', v,
                               'qa8_summary', public.driver_balance_summary());

  r := r || jsonb_build_object('qa9_release',
    public.driver_mission_hold_release('qa', sid1, NULL, 'qa'),
    'qa9_summary', public.driver_balance_summary());
  r := r || jsonb_build_object('qa11_release_replay',
    public.driver_mission_hold_release('qa', sid1, NULL, 'qa'));

  BEGIN
    r := r || jsonb_build_object('qa5_cashout',
      public.driver_cashout_create_request(5000, '+224620000001'));
  EXCEPTION WHEN OTHERS THEN
    r := r || jsonb_build_object('qa5_cashout', 'RAISED: ' || SQLERRM);
  END;

  r := r || jsonb_build_object('qa10_place2',
    public.driver_mission_hold_place('ride', 'qa2', sid2, 100000));
  r := r || jsonb_build_object('qa10_capture',
    public.driver_mission_commission_capture('qa2', sid2, 100000));
  r := r || jsonb_build_object('qa10_capture_replay',
    public.driver_mission_commission_capture('qa2', sid2, 100000));
  SELECT jsonb_build_object('granted', granted_gnf, 'consumed', consumed_gnf,
                            'reversed', reversed_gnf, 'state', state)
    INTO v FROM public.driver_promo_credits WHERE driver_user_id = p_driver;
  r := r || jsonb_build_object('qa10_promo', v,
                               'qa10_summary', public.driver_balance_summary());

  -- QA3: ineligible driver
  DELETE FROM public.driver_promo_credits WHERE driver_user_id = p_driver;
  UPDATE public.driver_profiles SET status = 'suspended' WHERE user_id = p_driver;
  r := r || jsonb_build_object('qa3_ineligible', public.driver_starter_credit_grant());

  r := r || jsonb_build_object(
    'qa17_repas', public.finance_mission_requirement('repas', 150000),
    'qa18_ride', public.finance_mission_requirement('ride', 50000),
    'qa19_envoyer_over_cap', public.finance_mission_requirement('envoyer', 900000),
    'qa20_treasury', public.admin_promotional_credit_treasury());

  RAISE EXCEPTION 'QA_RESULT %', r::text;
END;
$$;

CREATE OR REPLACE FUNCTION public._qa_slice1_selftest(p_driver uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._qa_slice1_run(p_driver);
  RETURN 'no result';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLERRM;  -- all writes above are rolled back with the subtransaction
END;
$$;

REVOKE ALL ON FUNCTION public._qa_slice1_run(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_slice1_selftest(uuid) FROM PUBLIC, anon, authenticated;