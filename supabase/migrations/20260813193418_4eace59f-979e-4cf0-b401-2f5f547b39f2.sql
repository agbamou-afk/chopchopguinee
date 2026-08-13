CREATE OR REPLACE FUNCTION public._qa_node2_taxi_full()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_cust uuid; v_taxi uuid; v_taxi2 uuid; v_moto uuid; v_bon uuid; v_fin uuid;
  v_req uuid; v_res jsonb; v_err text; v_n int;
  v_ride public.rides; v_ride2 public.rides;
  v_offer_id uuid;
  v_quote jsonb; v_fare bigint; v_hold bigint;
  v_bal0 bigint; v_bal1 bigint; v_held0 bigint; v_held1 bigint;
  v_calc jsonb; v_pay_tx uuid; v_pay_tx2 uuid; v_dbal0 bigint; v_dbal1 bigint;
  v_base bigint; v_perkm bigint; v_bps int;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  -- ============ A. IDENTITY / CONFIG TRUTH (no fixtures, flag still OFF) ============
  r := r || public._qa_s13_ok('A1.1 Taxi is its own ride mode in the database enum',
        EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
                 WHERE t.typname='ride_mode' AND e.enumlabel='auto'), NULL);
  r := r || public._qa_s13_ok('A1.2 Taxi maps to its own economics, not Moto''s',
        public._ride_mission_type('auto') = 'taxi', public._ride_mission_type('auto'));
  r := r || public._qa_s13_ok('A1.3 Taxi requires a Taxi vehicle, never a moto or a Bonbonna',
        public._ride_required_vehicle('auto') = 'auto'::public.driver_vehicle_type, NULL);
  SELECT base_price, price_per_km INTO v_base, v_perkm
    FROM public.fare_settings WHERE ride_type='auto' ORDER BY updated_at DESC LIMIT 1;
  r := r || public._qa_s13_ok('A1.4 Taxi pricing is the founder-approved 1500 base + 2000/km',
        v_base = 1500 AND v_perkm = 2000, COALESCE(v_base::text,'null')||'/'||COALESCE(v_perkm::text,'null'));
  SELECT commission_bps INTO v_bps FROM public.finance_policies
   WHERE mission_type='taxi' AND enabled AND effective_from <= now()
   ORDER BY effective_from DESC LIMIT 1;
  r := r || public._qa_s13_ok('A1.5 Taxi has its own active commission policy',
        v_bps = 1000, COALESCE(v_bps::text,'none'));
  r := r || public._qa_s13_ok('A1.6 the Taxi launch switch exists and is currently OFF',
        (SELECT enabled FROM public.feature_flags WHERE key='taxi') IS FALSE, NULL);

  -- ============ B. FAIL-CLOSED WHILE THE FLAG IS OFF ============
  BEGIN
    v_cust := gen_random_uuid();
    PERFORM public._qa_s13_user(v_cust,'n2c');
    PERFORM public._qa_s13_wallet(v_cust,'client',5000000,0);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_req := gen_random_uuid();
    BEGIN
      PERFORM public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
                'cash', v_req, 'Kaloum','Ratoma');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.1 a Taxi booking is refused while the launch switch is OFF',
          v_err LIKE '%TAXI_NOT_ENABLED%', v_err);
    SELECT count(*) INTO v_n FROM public.rides WHERE client_id = v_cust;
    r := r || public._qa_s13_ok('B1.2 the refused Taxi booking creates no ride at all',
          v_n = 0, v_n::text);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    -- ============ FIXTURES (flag ON only inside this rolled-back block) ============
    UPDATE public.feature_flags SET enabled = true WHERE key='taxi';
    r := r || public._qa_s13_ok('B1.3 the Taxi switch can be turned on without touching any other flag',
          (SELECT count(*) FROM public.feature_flags f
            WHERE f.key <> 'taxi'
              AND to_jsonb(f.enabled) IS DISTINCT FROM (v_flags0->f.key)) = 0, NULL);

    v_taxi := gen_random_uuid(); v_taxi2 := gen_random_uuid();
    v_moto := gen_random_uuid(); v_bon := gen_random_uuid(); v_fin := gen_random_uuid();
    PERFORM public._qa_s13_user(v_taxi,'n2t');
    PERFORM public._qa_s13_user(v_taxi2,'n2t2');
    PERFORM public._qa_s13_user(v_moto,'n2m');
    PERFORM public._qa_s13_user(v_bon,'n2b');
    PERFORM public._qa_s13_user(v_fin,'n2f');
    PERFORM public._qa_s13_wallet(v_taxi,'driver',900000,0);
    PERFORM public._qa_s13_wallet(v_taxi2,'driver',900000,0);
    PERFORM public._qa_s13_wallet(v_moto,'driver',900000,0);
    PERFORM public._qa_s13_wallet(v_bon,'driver',900000,0);
    PERFORM public._qa_s13_wallet(v_fin,'driver',900000,0);
    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,presence) VALUES
      (v_taxi,'approved','auto','online'),
      (v_taxi2,'approved','auto','online'),
      (v_moto,'approved','moto','online'),
      (v_bon,'approved','toktok','online'),
      (v_fin,'approved','auto','online')
    ON CONFLICT (user_id) DO UPDATE SET status=EXCLUDED.status,
      vehicle_type=EXCLUDED.vehicle_type, presence=EXCLUDED.presence;
    INSERT INTO public.driver_locations(user_id,lat,lng,status) VALUES
      (v_taxi,9.5373,-13.6788,'online'),
      (v_taxi2,9.5374,-13.6789,'online'),
      (v_moto,9.5375,-13.6790,'online'),
      (v_bon,9.5376,-13.6791,'online'),
      (v_fin,9.5377,-13.6792,'online')
    ON CONFLICT (user_id) DO UPDATE SET lat=EXCLUDED.lat, lng=EXCLUDED.lng, status=EXCLUDED.status;

    -- ============ C. BOOKING TRUTH ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_quote := public.ride_get_quote('auto',9.5370,-13.6785,9.5700,-13.6200);
    v_fare  := public.ride_compute_quote_gnf('auto',9.5370,-13.6785,9.5700,-13.6200);
    v_hold  := public.ride_reservation_amount_gnf(v_fare);
    r := r || public._qa_s13_ok('C1.1 the Taxi quote shown to the customer is server-authoritative',
          (v_quote->>'fare_gnf')::bigint = v_fare, v_quote->>'fare_gnf');
    r := r || public._qa_s13_ok('C1.2 the Taxi reservation preview equals the server reservation helper',
          (v_quote->>'chop_pay_hold_gnf')::bigint = v_hold, v_quote->>'chop_pay_hold_gnf');
    r := r || public._qa_s13_ok('C1.3 a Taxi fare is priced above the equivalent Moto fare',
          v_fare > public.ride_compute_quote_gnf('moto',9.5370,-13.6785,9.5700,-13.6200),
          v_fare::text);

    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    v_req := gen_random_uuid();
    v_res := public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'chop_pay', v_req, 'Kaloum','Ratoma');
    SELECT * INTO v_ride FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('C1.4 a Taxi booking is stored as a Taxi ride, never as a Moto ride',
          v_ride.mode::text = 'auto', v_ride.mode::text);
    r := r || public._qa_s13_ok('C1.5 a Chop Pay Taxi booking reserves exactly the server reservation',
          v_held1 - v_held0 = v_hold, (v_held1 - v_held0)::text);
    r := r || public._qa_s13_ok('C1.6 the Taxi ride locks Taxi economics, not ride or Bonbonna economics',
          v_ride.metadata->'finance_snapshot'->>'mission_type' = 'taxi',
          v_ride.metadata->'finance_snapshot'->>'mission_type');
    r := r || public._qa_s13_ok('C1.7 replaying the same Taxi request creates no duplicate ride',
          (public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'chop_pay', v_req, 'Kaloum','Ratoma')->>'ride_id')::uuid = v_ride.id, NULL);
    SELECT held_gnf INTO v_held1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('C1.8 the replayed Taxi request reserves no additional money',
          v_held1 - v_held0 = v_hold, (v_held1 - v_held0)::text);

    -- ============ D. DISPATCH ISOLATION ============
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT count(*) INTO v_n FROM public.ride_offers
      WHERE ride_id=v_ride.id AND driver_id IN (v_moto, v_bon);
    r := r || public._qa_s13_ok('D1.1 a Taxi request is never offered to moto or Bonbonna drivers',
          v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.ride_offers WHERE ride_id=v_ride.id;
    r := r || public._qa_s13_ok('D1.2 a Taxi request reaches at least one real Taxi driver',
          v_n > 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.ride_offers
      WHERE ride_id=v_ride.id AND ride_mode::text <> 'auto';
    r := r || public._qa_s13_ok('D1.3 every Taxi offer carries the Taxi mode, so no driver sees a wrong product',
          v_n = 0, v_n::text);

    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at,ride_mode)
    VALUES (v_ride.id, v_moto, 'pending', now() + interval '5 minutes', 'auto')
    RETURNING id INTO v_offer_id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_moto), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D1.4 a moto driver cannot accept a Taxi trip even with a planted offer',
          v_err <> 'NO_ERROR', v_err);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    INSERT INTO public.account_freezes(user_id, reason, freeze_type, status, frozen_by)
    VALUES (v_fin, 'qa node2 taxi freeze', 'admin_review', 'active', v_fin);
    r := r || public._qa_s13_ok('D1.5 a frozen Taxi driver is finance-ineligible',
          NOT public._driver_finance_eligible(v_fin), NULL);
    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at,ride_mode)
    VALUES (v_ride.id, v_fin, 'pending', now() + interval '5 minutes', 'auto')
    RETURNING id INTO v_offer_id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_fin), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D1.6 a finance-ineligible Taxi driver cannot accept a Taxi trip',
          v_err LIKE '%DRIVER_NOT_ELIGIBLE%', v_err);
    PERFORM set_config('request.jwt.claims', ''::text, true);
    UPDATE public.account_freezes SET status='lifted', lifted_at=now() WHERE user_id=v_fin;
    UPDATE public.driver_profiles SET presence='offline' WHERE user_id=v_fin;
    UPDATE public.driver_locations SET status='offline' WHERE user_id=v_fin;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_taxi), true);
    PERFORM public.driver_offer_accept_for_ride(v_ride.id);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_taxi2), true);
    BEGIN PERFORM public.driver_offer_accept_for_ride(v_ride.id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D1.7 a Taxi trip has exactly one winning driver',
          v_err <> 'NO_ERROR', v_err);
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    r := r || public._qa_s13_ok('D1.8 the assigned Taxi driver really drives a Taxi',
          (SELECT vehicle_type::text FROM public.driver_profiles WHERE user_id=v_ride2.driver_id)='auto',
          v_ride2.driver_id::text);

    -- ============ E. CANCELLATION ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    PERFORM public.ride_cancel(v_ride.id, 'qa taxi post-dispatch cancel');
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    v_calc := public._cancellation_compute(v_ride.metadata->'finance_snapshot',
                'after_dispatch', v_ride.fare_gnf, 0, 0, 'customer');
    r := r || public._qa_s13_ok('E1.1 a Taxi cancellation fee comes from the same central calculator',
          COALESCE((v_ride2.metadata->>'cancellation_fee_gnf')::bigint,0) = (v_calc->>'fee_gnf')::bigint,
          COALESCE(v_ride2.metadata->>'cancellation_fee_gnf','null')||' vs '||(v_calc->>'fee_gnf'));
    SELECT held_gnf INTO v_held1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('E1.2 a cancelled Taxi trip leaves no money reserved',
          v_held1 = v_held0, (v_held1 - v_held0)::text);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    -- ============ F. NO-DRIVER EXPIRY ============
    UPDATE public.driver_profiles SET presence='offline' WHERE user_id IN (v_taxi,v_taxi2);
    UPDATE public.driver_locations SET status='offline' WHERE user_id IN (v_taxi,v_taxi2);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT count(*) INTO v_n FROM public.customer_cancellation_debts WHERE customer_user_id=v_cust;
    v_req := gen_random_uuid();
    v_res := public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'chop_pay', v_req, 'Kaloum','Ratoma');
    SELECT * INTO v_ride FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    PERFORM set_config('request.jwt.claims', ''::text, true);
    UPDATE public.rides SET created_at = now() - interval '90 seconds' WHERE id=v_ride.id;
    PERFORM public.ride_sweep_unfulfilled(500);
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('F1.1 an unanswered Taxi search is closed automatically by the server',
          v_ride2.status='cancelled' AND v_ride2.metadata->>'cancel_reason'='no_driver_available',
          COALESCE(v_ride2.metadata->>'cancel_reason', v_ride2.status::text));
    r := r || public._qa_s13_ok('F1.2 an unanswered Taxi search returns every reserved franc',
          v_bal1 = v_bal0 AND v_held1 = v_held0, (v_bal1-v_bal0)::text||'/'||(v_held1-v_held0)::text);
    r := r || public._qa_s13_ok('F1.3 an unanswered Taxi search charges the customer nothing',
          COALESCE((v_ride2.metadata->>'cancellation_fee_gnf')::bigint,0) = 0,
          COALESCE(v_ride2.metadata->>'cancellation_fee_gnf','null'));
    r := r || public._qa_s13_ok('F1.4 an unanswered Taxi search creates no customer debt',
          (SELECT count(*) FROM public.customer_cancellation_debts WHERE customer_user_id=v_cust) = v_n,
          v_n::text);

    -- ============ G. COMPLETION TRUTH (cash) ============
    UPDATE public.driver_profiles SET presence='online' WHERE user_id=v_taxi;
    UPDATE public.driver_locations SET status='online' WHERE user_id=v_taxi;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    v_req := gen_random_uuid();
    v_res := public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'cash', v_req, 'Kaloum','Ratoma');
    SELECT * INTO v_ride FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    r := r || public._qa_s13_ok('G1.1 a cash Taxi booking reserves nothing in Chop Pay',
          v_ride.hold_tx_id IS NULL, COALESCE(v_ride.hold_tx_id::text,'null'));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_taxi), true);
    PERFORM public.driver_offer_accept_for_ride(v_ride.id);
    UPDATE public.rides SET metadata = COALESCE(metadata,'{}'::jsonb)
      || jsonb_build_object('phase','on_trip','pickup_confirmed_by','customer')
     WHERE id = v_ride.id;
    PERFORM public.ride_start(v_ride.id);
    SELECT * INTO v_ride2 FROM public.ride_complete(v_ride.id, NULL, NULL);
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('G1.2 a completed cash Taxi trip never debits the customer wallet',
          v_bal1 = v_bal0 AND v_held1 = v_held0, (v_bal1-v_bal0)::text);
    r := r || public._qa_s13_ok('G1.3 a completed cash Taxi trip records the cash the driver collected',
          COALESCE((v_ride2.metadata->>'cash_collected_gnf')::bigint,-1) = v_ride2.fare_gnf,
          COALESCE(v_ride2.metadata->>'cash_collected_gnf','null'));
    r := r || public._qa_s13_ok('G1.4 a completed cash Taxi trip charges the Taxi commission rate',
          abs(COALESCE(v_ride2.platform_fee_gnf,0) - (v_ride2.fare_gnf * v_bps) / 10000) <= 1,
          COALESCE(v_ride2.platform_fee_gnf,0)::text);
    r := r || public._qa_s13_ok('G1.5 a completed cash Taxi trip is still recorded as a Taxi trip',
          v_ride2.mode::text='auto' AND public._ride_payment_mode(v_ride2)='cash',
          v_ride2.mode::text);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    -- ============ H. COMPLETION TRUTH (Chop Pay, exactly once) ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_req := gen_random_uuid();
    v_res := public.ride_request_create('auto',9.5370,-13.6785,9.5700,-13.6200,
              'chop_pay', v_req, 'Kaloum','Ratoma');
    SELECT * INTO v_ride FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_taxi), true);
    PERFORM public.driver_offer_accept_for_ride(v_ride.id);
    UPDATE public.rides SET metadata = COALESCE(metadata,'{}'::jsonb)
      || jsonb_build_object('phase','on_trip','pickup_confirmed_by','customer')
     WHERE id = v_ride.id;
    PERFORM public.ride_start(v_ride.id);
    SELECT * INTO v_ride2 FROM public.ride_complete(v_ride.id, NULL, NULL);
    v_pay_tx := v_ride2.payment_tx_id;
    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_dbal0 FROM public.wallets WHERE owner_user_id=v_taxi AND party_type='driver';
    r := r || public._qa_s13_ok('H1.1 a completed Chop Pay Taxi trip captures the reservation once',
          v_pay_tx IS NOT NULL AND v_held0 = 0, COALESCE(v_pay_tx::text,'null'));
    SELECT * INTO v_ride2 FROM public.ride_complete(v_ride.id, NULL, NULL);
    v_pay_tx2 := v_ride2.payment_tx_id;
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_dbal1 FROM public.wallets WHERE owner_user_id=v_taxi AND party_type='driver';
    r := r || public._qa_s13_ok('H1.2 replaying a Taxi completion keeps the same payment record',
          v_pay_tx2 = v_pay_tx, COALESCE(v_pay_tx2::text,'null'));
    r := r || public._qa_s13_ok('H1.3 replaying a Taxi completion moves zero additional money',
          v_bal1 = v_bal0 AND v_held1 = v_held0 AND v_dbal1 = v_dbal0,
          (v_bal1-v_bal0)::text||'/'||(v_dbal1-v_dbal0)::text);
    SELECT count(*) INTO v_n FROM public.wallet_transactions
      WHERE reference = 'ride:' || v_ride.id::text || ':commission';
    r := r || public._qa_s13_ok('H1.4 a Taxi trip books commission at most once',
          v_n <= 1, v_n::text);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    RAISE EXCEPTION 'QA_NODE2_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE2_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS aborted before completion', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', ''::text, true);

  -- ============ I. SECURITY / EXPOSURE ============
  r := r || public._qa_s13_ok('I1.1 the Taxi booking entry point is not callable by anonymous visitors',
        NOT has_function_privilege('anon',
          'public.ride_request_create(ride_mode,numeric,numeric,numeric,numeric,text,uuid,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('I1.2 the no-driver sweeper is not callable by app users',
        NOT has_function_privilege('anon','public.ride_sweep_unfulfilled(integer)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public.ride_sweep_unfulfilled(integer)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('I1.3 the Taxi certification harness itself is staff-only',
        NOT has_function_privilege('anon','public._qa_node2_taxi_full()','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._qa_node2_taxi_full()','EXECUTE'), NULL);

  -- ============ Z. ROLLBACK CLEANLINESS ============
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z1.1 the platform master wallet is unchanged after the Taxi test run',
        v_master0 IS NOT DISTINCT FROM v_master1, v_master1::text);
  r := r || public._qa_s13_ok('Z1.2 the Taxi launch switch is back OFF after the test run',
        (SELECT enabled FROM public.feature_flags WHERE key='taxi') IS FALSE, NULL);
  r := r || public._qa_s13_ok('Z1.3 no feature flag was left changed by the Taxi test run',
        v_flags0 = v_flags1, NULL);
  SELECT count(*) INTO v_n FROM public.rides r2
    JOIN auth.users u ON u.id = r2.client_id WHERE u.email LIKE 'qa-s13-n2%';
  r := r || public._qa_s13_ok('Z1.4 no Taxi test data is left behind in production',
        v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.driver_profiles dp
    JOIN auth.users u ON u.id = dp.user_id WHERE u.email LIKE 'qa-s13-n2%';
  r := r || public._qa_s13_ok('Z1.5 no Taxi test drivers are left behind in production',
        v_n = 0, v_n::text);

  RETURN jsonb_build_object(
    'part','node2_taxi',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END $function$;

REVOKE ALL ON FUNCTION public._qa_node2_taxi_full() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._qa_node2_taxi_full() FROM anon;
REVOKE ALL ON FUNCTION public._qa_node2_taxi_full() FROM authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node2_taxi_full() TO service_role;