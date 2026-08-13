DO $mig$
DECLARE
  v_src text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = '_qa_node2_taxi_full';
  IF v_src IS NULL THEN RAISE EXCEPTION 'NODE2_HARNESS_MISSING'; END IF;

  v_old := $old$    r := r || public._qa_s13_ok('F2.5 an old Taxi offer cannot be accepted once the search has been closed',
          v_err = 'MISSION_NO_LONGER_AVAILABLE', v_err);$old$;

  v_new := $new$    r := r || public._qa_s13_ok('F2.5 an old Taxi offer cannot be accepted once the search has been closed',
          v_err = 'OFFER_NO_LONGER_PENDING', v_err);
    r := r || public._qa_s13_ok('F2.6 closing the search really retires the pending Taxi offer',
          (SELECT status::text FROM public.ride_offers WHERE id=v_offer_id) = 'expired',
          (SELECT status::text FROM public.ride_offers WHERE id=v_offer_id));
    PERFORM set_config('request.jwt.claims', ''::text, true);
    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at,ride_mode)
    VALUES (v_rc.id, v_taxiB, 'pending', now() + interval '10 minutes', 'auto')
    RETURNING id INTO v_offer_id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_taxiB), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F2.7 a Taxi offer planted after the search closed cannot revive the trip',
          v_err = 'MISSION_NO_LONGER_AVAILABLE', v_err);
    SELECT * INTO v_r2 FROM public.rides WHERE id=v_rc.id;
    r := r || public._qa_s13_ok('F2.8 the closed Taxi trip never gains a driver afterwards',
          v_r2.driver_id IS NULL AND v_r2.status='cancelled', COALESCE(v_r2.driver_id::text,'null'));$new$;

  IF position(v_old in v_src) = 0 THEN RAISE EXCEPTION 'NODE2_HARNESS_FRAGMENT_NOT_FOUND'; END IF;
  EXECUTE replace(v_src, v_old, v_new);
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_node2_taxi_full() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node2_taxi_full() TO service_role;