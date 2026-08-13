CREATE OR REPLACE FUNCTION public._qa_node2_taxi_full()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_master_id constant uuid := 'b6858980-43d2-425d-b12d-b02aac3de52d';
  v_m_bal0 bigint; v_m_held0 bigint; v_m_bal1 bigint; v_m_held1 bigint;
  v_mid_bal bigint;
  v_flags0 jsonb; v_flags1 jsonb; v_auto0 int;
  v_c uuid[] := ARRAY[]::uuid[]; v_i int;
  v_drivers uuid[];
  v_taxiA uuid; v_taxiB uuid; v_moto uuid; v_bon uuid;
  v_offA uuid; v_susA uuid; v_frzA uuid;
  v_req uuid; v_req2 uuid; v_res jsonb; v_err text; v_n int; v_n2 int;
  v_ride public.rides; v_ra public.rides; v_rb public.rides; v_rc public.rides;
  v_rd public.rides; v_re public.rides; v_rf public.rides; v_r2 public.rides;
  v_offer_id uuid; v_taxiA_offer uuid;
  v_quote jsonb; v_fare bigint; v_hold bigint; v_code text;
  v_bal0 bigint; v_bal1 bigint; v_held0 bigint; v_held1 bigint;
  v_dbal0 bigint; v_dbal1 bigint; v_calc jsonb; v_snap jsonb;
  v_pay_tx uuid; v_pay_tx2 uuid;
  v_base bigint; v_perkm bigint; v_bps int; v_fixed bigint; v_expect bigint;
  v_pol uuid; v_j0 int; v_j1 int; v_wt0 int; v_wt1 int;
BEGIN
  SELECT balance_gnf, held_gnf INTO v_m_bal0, v_m_held0 FROM public.wallets WHERE id = v_master_id;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;
  SELECT count(*) INTO v_auto0 FROM public.driver_profiles WHERE status='approved' AND vehicle_type='auto';

  -- ============ A. IDENTITY / CONFIG TRUTH (flag still OFF) ============
  r := r || public._qa_s13_ok('A1.1 Taxi is its own ride mode in the database',
        EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
                 WHERE t.typname='ride_mode' AND e.enumlabel='auto'), NULL);
  r := r || public._qa_s13_ok('A1.2 Taxi maps to its own economics, not Moto''s',
        public._ride_mission_type('auto') = 'taxi', public._ride_mission_type('auto'));
  r := r || public._qa_s13_ok('A1.3 Taxi requires a Taxi vehicle, never a moto or a Bonbonna',
        public._ride_required_vehicle('auto') = 'auto'::public.driver_vehicle_type, NULL);
  SELECT base_price, price_per_km INTO v_base, v_perkm
    FROM public.fare_settings WHERE ride_type='auto' ORDER BY updated_at DESC LIMIT 1;
  r := r || public._qa_s13_ok('A1.4 Taxi pricing is the founder-approved 1500 base + 2000/km',
        v_base = 1500 AND v_perkm = 2000,
        COALESCE(v_base::text,'null')||'/'||COALESCE(v_perkm::text,'null'));
  SELECT id, commission_bps, COALESCE(fixed_commission_gnf,0) INTO v_pol, v_bps, v_fixed
    FROM public.finance_policy_at('taxi', now());
  r := r || public._qa_s13_ok('A1.5 Taxi has its own active commission policy at 10%',
        v_pol IS NOT NULL AND v_bps = 1000, COALESCE(v_bps::text,'none'));
  r := r || public._qa_s13_ok('A1.6 the Taxi launch switch exists and is currently OFF',
        (SELECT enabled FROM public.feature_flags WHERE key='taxi') IS FALSE, NULL);
  r := r || public._qa_s13_ok('A1.7 no approved Taxi driver exists in production yet (supply gate)',
        v_auto0 = 0, v_auto0::text);

  BEGIN
    -- ---------------- fixtures (everything below is rolled back) ----------------
    FOR v_i IN 1..12 LOOP
      v_c := v_c || gen_random_uuid();
      PERFORM public._qa_s13_user(v_c[v_i], 'n2c'||v_i::text);
      PERFORM public._qa_s13_wallet(v_c[v_i], 'client', 5000000, 0);
    END LOOP;

    -- ============ B. FLAG-OFF ZERO EFFECT ============
    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id=v_c[1] AND party_type='client';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c[1]), true);
    v_req := gen_random_uuid();
    BEGIN
      PERFORM public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
                'cash', v_req, 'Kaloum','Ratoma');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.1 a cash Taxi booking is refused with the exact launch-gate error while the switch is OFF',
          v_err = 'TAXI_NOT_ENABLED', v_err);
    v_req2 := gen_random_uuid();
    BEGIN
      PERFORM public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
                'chop_pay', v_req2, 'Kaloum','Ratoma');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.2 a Chop Pay Taxi booking is refused with the same exact launch-gate error',
          v_err = 'TAXI_NOT_ENABLED', v_err);
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT count(*) INTO v_n FROM public.rides WHERE client_id = v_c[1];
    r := r || public._qa_s13_ok('B1.3 the refused Taxi bookings create no ride at all',
          v_n = 0, v_n::text);
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_c[1] AND party_type='client';
    r := r || public._qa_s13_ok('B1.4 the refused Taxi bookings move no money and reserve nothing',
          v_bal1 = v_bal0 AND v_held1 = v_held0,
          (v_bal1-v_bal0)::text||'/'||(v_held1-v_held0)::text);
    SELECT count(*) INTO v_n FROM public.wallet_transactions
      WHERE reference IN ('ride_request:'||v_req::text, 'ride_request:'||v_req2::text);
    r := r || public._qa_s13_ok('B1.5 the refused Taxi bookings leave no reservation transaction behind',
          v_n = 0, v_n::text);

    UPDATE public.feature_flags SET enabled = true WHERE key='taxi';
    r := r || public._qa_s13_ok('B1.6 turning the Taxi switch on touches no other feature switch',
          (SELECT count(*) FROM public.feature_flags f
            WHERE f.key <> 'taxi'
              AND to_jsonb(f.enabled) IS DISTINCT FROM (v_flags0->f.key)) = 0, NULL);

    -- ---------------- supply fixtures ----------------
    v_taxiA := gen_random_uuid(); v_taxiB := gen_random_uuid();
    v_moto  := gen_random_uuid(); v_bon   := gen_random_uuid();
    v_offA  := gen_random_uuid(); v_susA  := gen_random_uuid(); v_frzA := gen_random_uuid();
    v_drivers := ARRAY[v_taxiA,v_taxiB,v_moto,v_bon,v_offA,v_susA,v_frzA];
    FOR v_i IN 1..array_length(v_drivers,1) LOOP
      PERFORM public._qa_s13_user(v_drivers[v_i], 'n2d'||v_i::text);
      PERFORM public._qa_s13_wallet(v_drivers[v_i], 'driver', 900000, 0);
    END LOOP;
    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,presence) VALUES
      (v_taxiA,'approved','auto','offline'),
      (v_taxiB,'approved','auto','offline'),
      (v_moto ,'approved','moto','offline'),
      (v_bon  ,'approved','toktok','offline'),
      (v_offA ,'approved','auto','offline'),
      (v_susA ,'suspended','auto','offline'),
      (v_frzA ,'approved','auto','offline')
    ON CONFLICT (user_id) DO UPDATE SET status=EXCLUDED.status,
      vehicle_type=EXCLUDED.vehicle_type, presence=EXCLUDED.presence;
    INSERT INTO public.driver_locations(user_id,lat,lng,status)
    SELECT d, 9.5371 + (i * 0.0001), -13.6786 - (i * 0.0001), 'offline'
      FROM unnest(v_drivers) WITH ORDINALITY AS t(d,i)
    ON CONFLICT (user_id) DO UPDATE SET lat=EXCLUDED.lat, lng=EXCLUDED.lng, status=EXCLUDED.status;
    INSERT INTO public.account_freezes(user_id, reason, freeze_type, status, frozen_by)
    VALUES (v_frzA, 'qa node2 taxi freeze', 'admin_review', 'active', v_frzA);
    r := r || public._qa_s13_ok('C0.1 the frozen Taxi driver fixture is really finance-ineligible',
          NOT public._driver_finance_eligible(v_frzA), NULL);

    -- ============ C. DISPATCH: THE ELIGIBLE TAXI DRIVER IS REACHED ============
    UPDATE public.driver_profiles SET presence='online' WHERE user_id=v_taxiA;
    UPDATE public.driver_locations SET status='online' WHERE user_id=v_taxiA;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c[2]), true);
    v_res := public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'chop_pay', gen_random_uuid(), 'Kaloum','Ratoma');
    SELECT * INTO v_ra FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT count(*) INTO v_n FROM public.ride_offers WHERE ride_id=v_ra.id AND driver_id=v_taxiA;
    r := r || public._qa_s13_ok('C1.1 an eligible online Taxi driver really receives the Taxi offer',
          v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.ride_offers WHERE ride_id=v_ra.id AND ride_mode::text <> 'auto';
    r := r || public._qa_s13_ok('C1.2 every Taxi offer is labelled as a Taxi trip',
          v_n = 0, v_n::text);
    UPDATE public.driver_profiles SET presence='offline' WHERE user_id=v_taxiA;
    UPDATE public.driver_locations SET status='offline' WHERE user_id=v_taxiA;

    -- ---- negatives: exactly one candidate is "available" per scenario ----
    -- moto only
    UPDATE public.driver_profiles SET presence='online' WHERE user_id=v_moto;
    UPDATE public.driver_locations SET status='online' WHERE user_id=v_moto;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c[3]), true);
    v_res := public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'cash', gen_random_uuid(), 'Kaloum','Ratoma');
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT count(*) INTO v_n FROM public.ride_offers WHERE ride_id=(v_res->>'ride_id')::uuid;
    r := r || public._qa_s13_ok('C2.1 a moto driver is never offered a Taxi trip, even when he is the only driver online',
          v_n = 0, v_n::text);
    UPDATE public.driver_profiles SET presence='offline' WHERE user_id=v_moto;
    UPDATE public.driver_locations SET status='offline' WHERE user_id=v_moto;

    -- bonbonna only
    UPDATE public.driver_profiles SET presence='online' WHERE user_id=v_bon;
    UPDATE public.driver_locations SET status='online' WHERE user_id=v_bon;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c[4]), true);
    v_res := public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'cash', gen_random_uuid(), 'Kaloum','Ratoma');
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT count(*) INTO v_n FROM public.ride_offers WHERE ride_id=(v_res->>'ride_id')::uuid;
    r := r || public._qa_s13_ok('C2.2 a Bonbonna driver is never offered a Taxi trip, even when he is the only driver online',
          v_n = 0, v_n::text);
    UPDATE public.driver_profiles SET presence='offline' WHERE user_id=v_bon;
    UPDATE public.driver_locations SET status='offline' WHERE user_id=v_bon;

    -- offline taxi driver only (approved, right vehicle, simply not online)
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c[5]), true);
    v_res := public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'cash', gen_random_uuid(), 'Kaloum','Ratoma');
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT count(*) INTO v_n FROM public.ride_offers WHERE ride_id=(v_res->>'ride_id')::uuid;
    r := r || public._qa_s13_ok('C2.3 an offline Taxi driver receives no Taxi offer',
          v_n = 0, v_n::text);

    -- suspended taxi driver, presence and location deliberately online
    UPDATE public.driver_profiles SET presence='online' WHERE user_id=v_susA;
    UPDATE public.driver_locations SET status='online' WHERE user_id=v_susA;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c[6]), true);
    v_res := public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'cash', gen_random_uuid(), 'Kaloum','Ratoma');
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT count(*) INTO v_n FROM public.ride_offers WHERE ride_id=(v_res->>'ride_id')::uuid;
    r := r || public._qa_s13_ok('C2.4 a suspended Taxi driver receives no Taxi offer even while he shows as online',
          v_n = 0, v_n::text);
    UPDATE public.driver_profiles SET presence='offline' WHERE user_id=v_susA;
    UPDATE public.driver_locations SET status='offline' WHERE user_id=v_susA;

    -- frozen (finance-ineligible) taxi driver, online
    UPDATE public.driver_profiles SET presence='online' WHERE user_id=v_frzA;
    UPDATE public.driver_locations SET status='online' WHERE user_id=v_frzA;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c[7]), true);
    v_res := public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'cash', gen_random_uuid(), 'Kaloum','Ratoma');
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT count(*) INTO v_n FROM public.ride_offers WHERE ride_id=(v_res->>'ride_id')::uuid;
    r := r || public._qa_s13_ok('C2.5 a frozen Taxi driver is not even offered the trip, not merely blocked at acceptance',
          v_n = 0, v_n::text);

    SELECT count(*) INTO v_n FROM public.ride_offers o
      WHERE o.driver_id IN (v_moto, v_bon, v_offA, v_susA);
    r := r || public._qa_s13_ok('C2.6 across the whole Taxi run, no ineligible driver ever received a dispatched offer',
          v_n = 0, v_n::text);

    -- ============ D. ACCEPTANCE CONTRACT (exact production errors) ============
    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at,ride_mode)
    VALUES (v_ra.id, v_moto, 'pending', now() + interval '5 minutes', 'auto')
    RETURNING id INTO v_offer_id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_moto), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D1.1 a moto driver handed a planted Taxi offer is refused on the vehicle rule',
          v_err = 'DRIVER_VEHICLE_NOT_ELIGIBLE', v_err);

    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at,ride_mode)
    VALUES (v_ra.id, v_bon, 'pending', now() + interval '5 minutes', 'auto')
    RETURNING id INTO v_offer_id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_bon), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D1.2 a Bonbonna driver handed a planted Taxi offer is refused on the same vehicle rule',
          v_err = 'DRIVER_VEHICLE_NOT_ELIGIBLE', v_err);

    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at,ride_mode)
    VALUES (v_ra.id, v_frzA, 'pending', now() + interval '5 minutes', 'auto')
    RETURNING id INTO v_offer_id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_frzA), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D1.3 a frozen Taxi driver handed a planted Taxi offer is refused as ineligible',
          v_err = 'DRIVER_NOT_ELIGIBLE', v_err);
    PERFORM set_config('request.jwt.claims', ''::text, true);
    UPDATE public.account_freezes SET status='lifted', lifted_at=now() WHERE user_id=v_frzA;
    UPDATE public.driver_profiles SET presence='offline' WHERE user_id=v_frzA;
    UPDATE public.driver_locations SET status='offline' WHERE user_id=v_frzA;

    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at,ride_mode)
    VALUES (v_ra.id, v_taxiB, 'pending', now() - interval '1 minute', 'auto')
    RETURNING id INTO v_offer_id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_taxiB), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D1.4 a stale Taxi offer can no longer be accepted',
          v_err = 'OFFER_EXPIRED', v_err);

    SELECT id INTO v_taxiA_offer FROM public.ride_offers
      WHERE ride_id=v_ra.id AND driver_id=v_taxiA AND status='pending' LIMIT 1;
    UPDATE public.ride_offers SET expires_at = now() + interval '10 minutes' WHERE id=v_taxiA_offer;
    UPDATE public.driver_profiles SET presence='online' WHERE user_id=v_taxiA;
    UPDATE public.driver_locations SET status='online' WHERE user_id=v_taxiA;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_taxiA), true);
    PERFORM public.driver_offer_accept(v_taxiA_offer);
    SELECT * INTO v_r2 FROM public.rides WHERE id=v_ra.id;
    r := r || public._qa_s13_ok('D1.5 the eligible Taxi driver really wins the trip',
          v_r2.driver_id = v_taxiA, COALESCE(v_r2.driver_id::text,'null'));
    r := r || public._qa_s13_ok('D1.6 the assigned Taxi driver really drives a Taxi',
          (SELECT vehicle_type::text FROM public.driver_profiles WHERE user_id=v_r2.driver_id)='auto', NULL);

    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at,ride_mode)
    VALUES (v_ra.id, v_taxiB, 'pending', now() + interval '5 minutes', 'auto')
    RETURNING id INTO v_offer_id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_taxiB), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D1.7 a second Taxi driver cannot take a trip that is already assigned',
          v_err = 'MISSION_NO_LONGER_AVAILABLE', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_taxiA), true);
    BEGIN PERFORM public.driver_offer_accept(v_taxiA_offer); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D1.8 the winning driver re-tapping accept is harmless and returns the same acceptance',
          v_err = 'NO_ERROR', v_err);
    SELECT count(*) INTO v_n FROM public.ride_offers WHERE ride_id=v_ra.id AND status='accepted';
    SELECT * INTO v_r2 FROM public.rides WHERE id=v_ra.id;
    r := r || public._qa_s13_ok('D1.9 re-tapping accept creates no second assignment on the Taxi trip',
          v_n = 1 AND v_r2.driver_id = v_taxiA, v_n::text);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    -- ============ E. BOOKING TRUTH ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c[8]), true);
    v_quote := public.ride_get_quote('auto',9.5370,-13.6785,9.5700,-13.6200);
    v_fare  := public.ride_compute_quote_gnf('auto',9.5370,-13.6785,9.5700,-13.6200);
    v_hold  := public.ride_reservation_amount_gnf(v_fare);
    r := r || public._qa_s13_ok('E1.1 the Taxi price shown before booking is the server price',
          (v_quote->>'fare_gnf')::bigint = v_fare, v_quote->>'fare_gnf');
    r := r || public._qa_s13_ok('E1.2 the Taxi reservation preview equals the server reservation amount',
          (v_quote->>'chop_pay_hold_gnf')::bigint = v_hold, v_quote->>'chop_pay_hold_gnf');
    r := r || public._qa_s13_ok('E1.3 a Taxi trip is priced above the same Moto trip',
          v_fare > public.ride_compute_quote_gnf('moto',9.5370,-13.6785,9.5700,-13.6200), v_fare::text);

    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id=v_c[8] AND party_type='client';
    v_res := public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'cash', gen_random_uuid(), 'Kaloum','Ratoma');
    SELECT * INTO v_rb FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_c[8] AND party_type='client';
    r := r || public._qa_s13_ok('E2.1 a cash Taxi booking reserves nothing in Chop Pay',
          v_rb.hold_tx_id IS NULL, COALESCE(v_rb.hold_tx_id::text,'null'));
    r := r || public._qa_s13_ok('E2.2 a cash Taxi booking touches neither the balance nor the reserved amount',
          v_bal1 = v_bal0 AND v_held1 = v_held0,
          (v_bal1-v_bal0)::text||'/'||(v_held1-v_held0)::text);
    r := r || public._qa_s13_ok('E2.3 a cash Taxi booking is stored as a cash Taxi trip',
          v_rb.mode::text='auto' AND public._ride_payment_mode(v_rb)='cash', v_rb.mode::text);
    r := r || public._qa_s13_ok('E2.4 the Taxi fare is the server fare, and the ride says so',
          v_rb.fare_gnf = v_fare AND v_rb.metadata->>'fare_authority' = 'server',
          v_rb.fare_gnf::text||'/'||COALESCE(v_rb.metadata->>'fare_authority','null'));
    v_snap := v_rb.metadata->'finance_snapshot';
    r := r || public._qa_s13_ok('E2.5 the Taxi trip freezes the Taxi commission policy, not another service''s',
          v_snap->>'mission_type' = 'taxi'
          AND (v_snap->>'policy_id')::uuid = v_pol
          AND (v_snap->>'commission_bps')::int = 1000,
          COALESCE(v_snap->>'mission_type','null')||'/'||COALESCE(v_snap->>'commission_bps','null'));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c[9]), true);
    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id=v_c[9] AND party_type='client';
    v_req := gen_random_uuid();
    v_res := public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'chop_pay', v_req, 'Kaloum','Ratoma');
    SELECT * INTO v_rc FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_c[9] AND party_type='client';
    r := r || public._qa_s13_ok('E3.1 a first Chop Pay Taxi booking is reported as newly created',
          v_res->>'status' = 'created', v_res->>'status');
    r := r || public._qa_s13_ok('E3.2 a Chop Pay Taxi booking reserves exactly the server reservation amount',
          v_held1 - v_held0 = v_hold AND v_bal1 = v_bal0, (v_held1-v_held0)::text);
    v_res := public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'chop_pay', v_req, 'Kaloum','Ratoma');
    r := r || public._qa_s13_ok('E3.3 replaying the same Taxi request is reported as already created',
          v_res->>'status' = 'already_created', v_res->>'status');
    r := r || public._qa_s13_ok('E3.4 the replayed Taxi request returns the very same trip',
          (v_res->>'ride_id')::uuid = v_rc.id, v_res->>'ride_id');
    SELECT held_gnf INTO v_held1 FROM public.wallets WHERE owner_user_id=v_c[9] AND party_type='client';
    SELECT count(*) INTO v_n FROM public.wallet_transactions
      WHERE reference = 'ride_request:'||v_req::text;
    r := r || public._qa_s13_ok('E3.5 the replayed Taxi request reserves no second time',
          v_held1 - v_held0 = v_hold AND v_n = 1, (v_held1-v_held0)::text||'/'||v_n::text);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    -- ============ F. NO-DRIVER OUTCOME, BOTH PAYMENT MODES ============
    UPDATE public.driver_profiles SET presence='offline' WHERE user_id = ANY(v_drivers);
    UPDATE public.driver_locations SET status='offline' WHERE user_id = ANY(v_drivers);

    -- assigned Taxi trip must survive the sweeper
    UPDATE public.rides SET created_at = now() - interval '10 minutes' WHERE id = v_ra.id;
    PERFORM public.ride_sweep_unfulfilled(500);
    SELECT * INTO v_r2 FROM public.rides WHERE id=v_ra.id;
    r := r || public._qa_s13_ok('F1.1 an assigned Taxi trip is never cancelled by the no-driver sweeper',
          v_r2.status <> 'cancelled' AND v_r2.driver_id = v_taxiA, v_r2.status::text);

    -- Chop Pay unassigned Taxi trip
    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at,ride_mode)
    VALUES (v_rc.id, v_taxiB, 'pending', now() + interval '10 minutes', 'auto')
    RETURNING id INTO v_offer_id;
    SELECT count(*) INTO v_n2 FROM public.customer_cancellation_debts WHERE customer_user_id=v_c[9];
    UPDATE public.rides SET created_at = now() - interval '90 seconds' WHERE id=v_rc.id;
    PERFORM public.ride_sweep_unfulfilled(500);
    SELECT * INTO v_r2 FROM public.rides WHERE id=v_rc.id;
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_c[9] AND party_type='client';
    r := r || public._qa_s13_ok('F2.1 an unanswered Chop Pay Taxi search is closed by the server as "no driver"',
          v_r2.status='cancelled' AND v_r2.metadata->>'cancel_reason'='no_driver_available',
          COALESCE(v_r2.metadata->>'cancel_reason', v_r2.status::text));
    r := r || public._qa_s13_ok('F2.2 an unanswered Chop Pay Taxi search returns every reserved franc',
          v_bal1 = v_bal0 AND v_held1 = v_held0, (v_bal1-v_bal0)::text||'/'||(v_held1-v_held0)::text);
    r := r || public._qa_s13_ok('F2.3 an unanswered Chop Pay Taxi search charges nothing',
          COALESCE((v_r2.metadata->>'cancellation_fee_gnf')::bigint,-1) = 0,
          COALESCE(v_r2.metadata->>'cancellation_fee_gnf','null'));
    r := r || public._qa_s13_ok('F2.4 an unanswered Chop Pay Taxi search creates no customer debt',
          (SELECT count(*) FROM public.customer_cancellation_debts WHERE customer_user_id=v_c[9]) = v_n2,
          v_n2::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_taxiB), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F2.5 an old Taxi offer cannot be accepted once the search has been closed',
          v_err = 'MISSION_NO_LONGER_AVAILABLE', v_err);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    -- cash unassigned Taxi trip
    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id=v_c[8] AND party_type='client';
    SELECT count(*) INTO v_n2 FROM public.customer_cancellation_debts WHERE customer_user_id=v_c[8];
    UPDATE public.rides SET created_at = now() - interval '90 seconds' WHERE id=v_rb.id;
    PERFORM public.ride_sweep_unfulfilled(500);
    SELECT * INTO v_r2 FROM public.rides WHERE id=v_rb.id;
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_c[8] AND party_type='client';
    r := r || public._qa_s13_ok('F3.1 an unanswered cash Taxi search is closed with the same "no driver" reason',
          v_r2.status='cancelled' AND v_r2.metadata->>'cancel_reason'='no_driver_available',
          COALESCE(v_r2.metadata->>'cancel_reason', v_r2.status::text));
    r := r || public._qa_s13_ok('F3.2 an unanswered cash Taxi search moves no money at all',
          v_bal1 = v_bal0 AND v_held1 = v_held0, (v_bal1-v_bal0)::text||'/'||(v_held1-v_held0)::text);
    r := r || public._qa_s13_ok('F3.3 an unanswered cash Taxi search charges nothing and creates no debt',
          COALESCE((v_r2.metadata->>'cancellation_fee_gnf')::bigint,-1) = 0
          AND (SELECT count(*) FROM public.customer_cancellation_debts WHERE customer_user_id=v_c[8]) = v_n2,
          COALESCE(v_r2.metadata->>'cancellation_fee_gnf','null'));

    -- ============ G. CENTRAL CANCELLATION PARITY ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c[10]), true);
    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id=v_c[10] AND party_type='client';
    v_res := public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'chop_pay', gen_random_uuid(), 'Kaloum','Ratoma');
    SELECT * INTO v_rf FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    PERFORM public.ride_cancel(v_rf.id, 'qa taxi pre-dispatch cancel');
    SELECT * INTO v_r2 FROM public.rides WHERE id=v_rf.id;
    v_calc := public._cancellation_compute(v_rf.metadata->'finance_snapshot',
                'before_dispatch', v_rf.fare_gnf, 0, 0, 'customer');
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_c[10] AND party_type='client';
    r := r || public._qa_s13_ok('G1.1 cancelling a Taxi trip before a driver is found uses the central calculator',
          COALESCE((v_r2.metadata->>'cancellation_fee_gnf')::bigint,-1) = (v_calc->>'fee_gnf')::bigint,
          COALESCE(v_r2.metadata->>'cancellation_fee_gnf','null')||' vs '||(v_calc->>'fee_gnf'));
    r := r || public._qa_s13_ok('G1.2 cancelling a Taxi trip before dispatch leaves nothing reserved',
          v_held1 = v_held0, (v_held1-v_held0)::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c[2]), true);
    SELECT held_gnf INTO v_held0 FROM public.wallets WHERE owner_user_id=v_c[2] AND party_type='client';
    PERFORM public.ride_cancel(v_ra.id, 'qa taxi post-dispatch cancel');
    SELECT * INTO v_r2 FROM public.rides WHERE id=v_ra.id;
    v_calc := public._cancellation_compute(v_ra.metadata->'finance_snapshot',
                'after_dispatch', v_ra.fare_gnf, 0, 0, 'customer');
    SELECT held_gnf INTO v_held1 FROM public.wallets WHERE owner_user_id=v_c[2] AND party_type='client';
    r := r || public._qa_s13_ok('G2.1 cancelling a Taxi trip after a driver is on the way uses the same central calculator',
          COALESCE((v_r2.metadata->>'cancellation_fee_gnf')::bigint,-1) = (v_calc->>'fee_gnf')::bigint,
          COALESCE(v_r2.metadata->>'cancellation_fee_gnf','null')||' vs '||(v_calc->>'fee_gnf'));
    r := r || public._qa_s13_ok('G2.2 a cancelled Taxi trip leaves no money reserved',
          v_held1 = 0, v_held1::text);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    -- ============ H. REAL PICKUP HANDSHAKE + CASH COMPLETION ============
    UPDATE public.driver_profiles SET presence='online' WHERE user_id=v_taxiB;
    UPDATE public.driver_locations SET status='online' WHERE user_id=v_taxiB;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c[11]), true);
    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id=v_c[11] AND party_type='client';
    v_res := public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'cash', gen_random_uuid(), 'Kaloum','Ratoma');
    SELECT * INTO v_rd FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_taxiB), true);
    PERFORM public.driver_offer_accept_for_ride(v_rd.id);
    PERFORM public.ride_set_phase(v_rd.id, 'arrived');
    SELECT * INTO v_r2 FROM public.rides WHERE id=v_rd.id;
    v_code := v_r2.metadata->>'pickup_code';
    r := r || public._qa_s13_ok('H1.1 when the Taxi driver arrives, the customer gets a real pickup code',
          COALESCE(v_code,'') <> '' AND v_r2.metadata->>'phase' = 'arrived',
          COALESCE(v_r2.metadata->>'phase','null'));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c[11]), true);
    BEGIN PERFORM public.ride_confirm_pickup(v_rd.id, 'ZZZZZZ'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT * INTO v_r2 FROM public.rides WHERE id=v_rd.id;
    r := r || public._qa_s13_ok('H1.2 a wrong pickup code is rejected',
          v_err = 'Code de prise en charge invalide', v_err);
    r := r || public._qa_s13_ok('H1.3 a wrong pickup code does not start the Taxi trip',
          v_r2.status <> 'in_progress' AND v_r2.metadata->>'phase' = 'arrived',
          v_r2.status::text||'/'||COALESCE(v_r2.metadata->>'phase','null'));
    PERFORM public.ride_confirm_pickup(v_rd.id, v_code);
    SELECT * INTO v_r2 FROM public.rides WHERE id=v_rd.id;
    r := r || public._qa_s13_ok('H1.4 the real pickup code starts the Taxi trip and records the customer confirmation',
          v_r2.status::text = 'in_progress' AND v_r2.metadata->>'phase' = 'on_trip'
          AND v_r2.metadata->>'pickup_confirmed_by' = 'customer',
          v_r2.status::text||'/'||COALESCE(v_r2.metadata->>'pickup_confirmed_by','null'));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_taxiB), true);
    PERFORM public.ride_start(v_rd.id);
    SELECT * INTO v_r2 FROM public.ride_complete(v_rd.id, NULL, NULL);
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_c[11] AND party_type='client';
    v_snap  := v_r2.metadata->'finance_snapshot';
    v_expect := (v_r2.fare_gnf * COALESCE((v_snap->>'commission_bps')::int,0)) / 10000
                + COALESCE((v_snap->>'fixed_commission_gnf')::bigint,0);
    r := r || public._qa_s13_ok('H2.1 a completed cash Taxi trip never debits the customer wallet',
          v_bal1 = v_bal0 AND v_held1 = v_held0, (v_bal1-v_bal0)::text||'/'||(v_held1-v_held0)::text);
    r := r || public._qa_s13_ok('H2.2 a completed cash Taxi trip holds and captures nothing in Chop Pay',
          v_r2.hold_tx_id IS NULL AND v_r2.payment_tx_id IS NULL,
          COALESCE(v_r2.payment_tx_id::text,'null'));
    r := r || public._qa_s13_ok('H2.3 a completed cash Taxi trip stays a cash trip',
          public._ride_payment_mode(v_r2) = 'cash', public._ride_payment_mode(v_r2));
    r := r || public._qa_s13_ok('H2.4 a completed cash Taxi trip records exactly the cash the driver collected',
          COALESCE((v_r2.metadata->>'cash_collected_gnf')::bigint,-1) = v_r2.fare_gnf,
          COALESCE(v_r2.metadata->>'cash_collected_gnf','null'));
    r := r || public._qa_s13_ok('H2.5 a completed cash Taxi trip charges exactly the Taxi commission, to the franc',
          COALESCE(v_r2.platform_fee_gnf,-1) = v_expect,
          COALESCE(v_r2.platform_fee_gnf,-1)::text||' vs '||v_expect::text);
    r := r || public._qa_s13_ok('H2.6 a completed cash Taxi trip is still recorded as a Taxi trip',
          v_r2.mode::text = 'auto', v_r2.mode::text);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    -- ============ I. REAL PICKUP HANDSHAKE + CHOP PAY, EXACTLY ONCE ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c[12]), true);
    v_res := public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'chop_pay', gen_random_uuid(), 'Kaloum','Ratoma');
    SELECT * INTO v_re FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_taxiB), true);
    PERFORM public.driver_offer_accept_for_ride(v_re.id);
    PERFORM public.ride_set_phase(v_re.id, 'arrived');
    SELECT metadata->>'pickup_code' INTO v_code FROM public.rides WHERE id=v_re.id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c[12]), true);
    PERFORM public.ride_confirm_pickup(v_re.id, v_code);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_taxiB), true);
    PERFORM public.ride_start(v_re.id);
    SELECT * INTO v_r2 FROM public.ride_complete(v_re.id, NULL, NULL);
    v_pay_tx := v_r2.payment_tx_id;
    v_snap := v_r2.metadata->'finance_snapshot';
    v_expect := (v_r2.fare_gnf * COALESCE((v_snap->>'commission_bps')::int,0)) / 10000
                + COALESCE((v_snap->>'fixed_commission_gnf')::bigint,0);
    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id=v_c[12] AND party_type='client';
    SELECT balance_gnf INTO v_dbal0 FROM public.wallets WHERE owner_user_id=v_taxiB AND party_type='driver';
    SELECT balance_gnf INTO v_mid_bal FROM public.wallets WHERE id=v_master_id;
    SELECT count(*) INTO v_j0 FROM public.ledger_journals
      WHERE source_module='ride' AND source_id=v_re.id;
    SELECT count(*) INTO v_wt0 FROM public.wallet_transactions
      WHERE reference LIKE 'ride:'||v_re.id::text||'%' OR id = v_pay_tx;
    r := r || public._qa_s13_ok('I1.1 a completed Chop Pay Taxi trip captures the reservation once and leaves nothing reserved',
          v_pay_tx IS NOT NULL AND v_held0 = 0, COALESCE(v_pay_tx::text,'null'));
    r := r || public._qa_s13_ok('I1.2 the Chop Pay Taxi commission is exactly the Taxi rate, to the franc',
          COALESCE(v_r2.platform_fee_gnf,-1) = v_expect,
          COALESCE(v_r2.platform_fee_gnf,-1)::text||' vs '||v_expect::text);
    SELECT count(*) INTO v_n FROM public.wallet_transactions
      WHERE reference = 'ride:'||v_re.id::text||':commission';
    r := r || public._qa_s13_ok('I1.3 the Chop Pay Taxi trip books its commission exactly once',
          v_n = 1, v_n::text);

    SELECT * INTO v_r2 FROM public.ride_complete(v_re.id, NULL, NULL);
    v_pay_tx2 := v_r2.payment_tx_id;
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_c[12] AND party_type='client';
    SELECT balance_gnf INTO v_dbal1 FROM public.wallets WHERE owner_user_id=v_taxiB AND party_type='driver';
    SELECT count(*) INTO v_j1 FROM public.ledger_journals
      WHERE source_module='ride' AND source_id=v_re.id;
    SELECT count(*) INTO v_wt1 FROM public.wallet_transactions
      WHERE reference LIKE 'ride:'||v_re.id::text||'%' OR id = v_pay_tx;
    r := r || public._qa_s13_ok('I2.1 replaying a Taxi completion keeps the very same payment record',
          v_pay_tx2 = v_pay_tx, COALESCE(v_pay_tx2::text,'null'));
    r := r || public._qa_s13_ok('I2.2 replaying a Taxi completion moves zero additional money for customer, driver and platform',
          v_bal1 = v_bal0 AND v_held1 = v_held0 AND v_dbal1 = v_dbal0
          AND (SELECT balance_gnf FROM public.wallets WHERE id=v_master_id) = v_mid_bal,
          (v_bal1-v_bal0)::text||'/'||(v_dbal1-v_dbal0)::text);
    SELECT count(*) INTO v_n FROM public.wallet_transactions
      WHERE reference = 'ride:'||v_re.id::text||':commission';
    r := r || public._qa_s13_ok('I2.3 replaying a Taxi completion never books a second commission',
          v_n = 1, v_n::text);
    r := r || public._qa_s13_ok('I2.4 replaying a Taxi completion creates no second money movement of any kind',
          v_wt1 = v_wt0, v_wt0::text||' -> '||v_wt1::text);
    r := r || public._qa_s13_ok('I2.5 replaying a Taxi completion creates no second accounting entry',
          v_j1 = v_j0, v_j0::text||' -> '||v_j1::text);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    RAISE EXCEPTION 'QA_NODE2_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE2_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS aborted before completion', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', ''::text, true);

  -- ============ Y. SECURITY / EXPOSURE ============
  r := r || public._qa_s13_ok('Y1.1 the Taxi booking entry point is not callable by anonymous visitors',
        NOT has_function_privilege('anon',
          'public.ride_request_create(ride_mode,numeric,numeric,numeric,numeric,text,uuid,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('Y1.2 the no-driver sweeper is not callable by app users',
        NOT has_function_privilege('anon','public.ride_sweep_unfulfilled(integer)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public.ride_sweep_unfulfilled(integer)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('Y1.3 the Taxi certification harness itself is staff-only',
        NOT has_function_privilege('anon','public._qa_node2_taxi_full()','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._qa_node2_taxi_full()','EXECUTE'), NULL);

  -- ============ Z. ROLLBACK CLEANLINESS ============
  SELECT balance_gnf, held_gnf INTO v_m_bal1, v_m_held1 FROM public.wallets WHERE id = v_master_id;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z1.1 the platform master wallet is untouched by the Taxi test run',
        v_m_bal0 IS NOT DISTINCT FROM v_m_bal1 AND v_m_held0 IS NOT DISTINCT FROM v_m_held1,
        COALESCE(v_m_bal1::text,'null')||'/'||COALESCE(v_m_held1::text,'null'));
  r := r || public._qa_s13_ok('Z1.2 the platform master wallet still matches the certified reference balance',
        v_m_bal1 = -100435 AND v_m_held1 = 0,
        COALESCE(v_m_bal1::text,'null')||'/'||COALESCE(v_m_held1::text,'null'));
  r := r || public._qa_s13_ok('Z1.3 the Taxi launch switch is back OFF after the test run',
        (SELECT enabled FROM public.feature_flags WHERE key='taxi') IS FALSE, NULL);
  r := r || public._qa_s13_ok('Z1.4 no feature switch drifted during the Taxi test run',
        v_flags0 = v_flags1, NULL);
  r := r || public._qa_s13_ok('Z1.5 the number of approved Taxi drivers in production is unchanged',
        (SELECT count(*) FROM public.driver_profiles WHERE status='approved' AND vehicle_type='auto') = v_auto0,
        v_auto0::text);

  SELECT count(*) INTO v_n FROM auth.users WHERE email LIKE 'qa-s13-n2%';
  r := r || public._qa_s13_ok('Z2.1 no Taxi test accounts remain', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.profiles p
    WHERE p.user_id IN (SELECT id FROM auth.users WHERE email LIKE 'qa-s13-n2%');
  r := r || public._qa_s13_ok('Z2.2 no Taxi test profiles remain', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.driver_profiles dp
    JOIN auth.users u ON u.id = dp.user_id WHERE u.email LIKE 'qa-s13-n2%';
  r := r || public._qa_s13_ok('Z2.3 no Taxi test drivers remain', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.driver_locations dl
    JOIN auth.users u ON u.id = dl.user_id WHERE u.email LIKE 'qa-s13-n2%';
  r := r || public._qa_s13_ok('Z2.4 no Taxi test driver positions remain', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.rides r2
    JOIN auth.users u ON u.id = r2.client_id WHERE u.email LIKE 'qa-s13-n2%';
  r := r || public._qa_s13_ok('Z2.5 no Taxi test trips remain', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.ride_offers o
    JOIN auth.users u ON u.id = o.driver_id WHERE u.email LIKE 'qa-s13-n2%';
  r := r || public._qa_s13_ok('Z2.6 no Taxi test offers remain', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.wallets w
    JOIN auth.users u ON u.id = w.owner_user_id WHERE u.email LIKE 'qa-s13-n2%';
  r := r || public._qa_s13_ok('Z2.7 no Taxi test wallets remain', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.account_freezes f
    JOIN auth.users u ON u.id = f.user_id WHERE u.email LIKE 'qa-s13-n2%';
  r := r || public._qa_s13_ok('Z2.8 no Taxi test account freezes remain', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.customer_cancellation_debts d
    JOIN auth.users u ON u.id = d.customer_user_id WHERE u.email LIKE 'qa-s13-n2%';
  r := r || public._qa_s13_ok('Z2.9 no Taxi test customer debts remain', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.wallet_transactions t
    WHERE t.related_user_id IN (SELECT id FROM auth.users WHERE email LIKE 'qa-s13-n2%')
       OR t.from_wallet_id IN (SELECT w.id FROM public.wallets w JOIN auth.users u ON u.id=w.owner_user_id
                                WHERE u.email LIKE 'qa-s13-n2%')
       OR t.to_wallet_id IN (SELECT w.id FROM public.wallets w JOIN auth.users u ON u.id=w.owner_user_id
                              WHERE u.email LIKE 'qa-s13-n2%');
  r := r || public._qa_s13_ok('Z2.10 no Taxi test money movements remain', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.ledger_journals j
    WHERE j.actor_user_id IN (SELECT id FROM auth.users WHERE email LIKE 'qa-s13-n2%');
  r := r || public._qa_s13_ok('Z2.11 no Taxi test accounting entries remain', v_n = 0, v_n::text);

  RETURN jsonb_build_object(
    'part','node2_taxi',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END $function$;

REVOKE ALL ON FUNCTION public._qa_node2_taxi_full() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node2_taxi_full() TO service_role;