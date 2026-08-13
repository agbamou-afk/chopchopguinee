
-- 1) Sub-minute autonomous sweep. pg_cron 1.6 supports interval schedules.
SELECT cron.schedule('chopchop-ride-no-driver-sweep', '10 seconds',
                     'SELECT public.ride_sweep_unfulfilled(500);');

-- 2) Bonbonna-specific consequential matrix.
CREATE OR REPLACE FUNCTION public._qa_node1_bonbonna_matrix()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_bon uuid; v_bon2 uuid; v_susp uuid; v_off uuid;
  v_req uuid; v_res jsonb; v_err text; v_n int;
  v_ride public.rides; v_ride2 public.rides;
  v_offer_id uuid; v_offer_id2 uuid; v_offer public.ride_offers;
  v_quote jsonb; v_fare bigint; v_hold bigint;
  v_held0 bigint; v_held1 bigint; v_bal0 bigint; v_bal1 bigint;
  v_calc jsonb; v_sched text; v_active boolean;
BEGIN
  BEGIN
    v_cust := gen_random_uuid(); v_bon := gen_random_uuid(); v_bon2 := gen_random_uuid();
    v_susp := gen_random_uuid(); v_off := gen_random_uuid();
    PERFORM public._qa_s13_user(v_cust,'n1mc');
    PERFORM public._qa_s13_user(v_bon,'n1mb');
    PERFORM public._qa_s13_user(v_bon2,'n1mb2');
    PERFORM public._qa_s13_user(v_susp,'n1ms');
    PERFORM public._qa_s13_user(v_off,'n1mo');
    PERFORM public._qa_s13_wallet(v_cust,'client',5000000,0);
    PERFORM public._qa_s13_wallet(v_bon,'driver',900000,0);
    PERFORM public._qa_s13_wallet(v_bon2,'driver',900000,0);
    PERFORM public._qa_s13_wallet(v_susp,'driver',900000,0);
    PERFORM public._qa_s13_wallet(v_off,'driver',900000,0);

    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,presence) VALUES
      (v_bon,'approved','toktok','online'),
      (v_bon2,'approved','toktok','online'),
      (v_susp,'suspended','toktok','online'),
      (v_off,'approved','toktok','offline')
    ON CONFLICT (user_id) DO UPDATE SET status=EXCLUDED.status,
      vehicle_type=EXCLUDED.vehicle_type, presence=EXCLUDED.presence;
    INSERT INTO public.driver_locations(user_id,lat,lng,status) VALUES
      (v_bon,9.5373,-13.6788,'online'),
      (v_bon2,9.5374,-13.6789,'online'),
      (v_susp,9.5375,-13.6790,'online'),
      (v_off,9.5376,-13.6791,'offline')
    ON CONFLICT (user_id) DO UPDATE SET lat=EXCLUDED.lat, lng=EXCLUDED.lng, status=EXCLUDED.status;

    -- ---------- M1 QUOTE AUTHORITY ----------
    v_quote := public.ride_get_quote('toktok',9.5370,-13.6785,9.5700,-13.6200);
    v_fare  := public.ride_compute_quote_gnf('toktok',9.5370,-13.6785,9.5700,-13.6200);
    v_hold  := public.ride_reservation_amount_gnf(v_fare);
    r := r || public._qa_s13_ok('M1.1 Bonbonna quote is server-authoritative and matches the pricing engine',
          (v_quote->>'fare_gnf')::bigint = v_fare, v_quote->>'fare_gnf');
    r := r || public._qa_s13_ok('M1.2 Bonbonna Chop Pay reservation preview equals the server reservation helper',
          (v_quote->>'chop_pay_hold_gnf')::bigint = v_hold, v_quote->>'chop_pay_hold_gnf');

    -- ---------- M2 CHOP PAY BOOKING / ELIGIBILITY ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    SELECT held_gnf INTO v_held0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    v_req := gen_random_uuid();
    v_res := public.ride_request_create('toktok',9.5370,-13.6785,9.5700,-13.6200,
              'chop_pay', v_req, 'Kaloum','Ratoma');
    SELECT * INTO v_ride FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    SELECT held_gnf INTO v_held1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('M2.1 Chop Pay Bonbonna booking places exactly the server reservation',
          v_held1 - v_held0 = v_hold, (v_held1 - v_held0)::text);
    r := r || public._qa_s13_ok('M2.2 Chop Pay Bonbonna ride carries the finance snapshot',
          (v_ride.metadata->'finance_snapshot'->>'policy_id') IS NOT NULL, NULL);

    PERFORM set_config('request.jwt.claims', '', true);
    SELECT count(*) INTO v_n FROM public.ride_offers
      WHERE ride_id=v_ride.id AND driver_id IN (v_susp, v_off);
    r := r || public._qa_s13_ok('M2.3 suspended and offline Bonbonna drivers are excluded from dispatch',
          v_n = 0, v_n::text);

    -- suspended driver cannot accept a manually inserted offer
    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at)
    VALUES (v_ride.id, v_susp, 'pending', now() + interval '5 minutes')
    RETURNING id INTO v_offer_id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_susp), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('M2.4 a suspended Bonbonna driver cannot accept',
          v_err LIKE '%DRIVER_NOT_APPROVED%', v_err);

    -- expired offer cannot be accepted
    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at)
    VALUES (v_ride.id, v_bon2, 'pending', now() - interval '1 minute')
    RETURNING id INTO v_offer_id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_bon2), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('M2.5 a stale Bonbonna offer cannot be accepted',
          v_err LIKE '%OFFER_EXPIRED%', v_err);

    -- single winner
    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at)
    VALUES (v_ride.id, v_bon2, 'pending', now() + interval '5 minutes')
    RETURNING id INTO v_offer_id2;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_bon), true);
    PERFORM public.driver_offer_accept_for_ride(v_ride.id);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_bon2), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id2); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('M2.6 an already-assigned Bonbonna ride has exactly one winner',
          v_err LIKE '%MISSION_NO_LONGER_AVAILABLE%', v_err);
    SELECT driver_id INTO v_bon2 FROM public.rides WHERE id=v_ride.id;
    r := r || public._qa_s13_ok('M2.7 the assigned Bonbonna driver is the accepting driver',
          v_bon2 = v_bon, v_bon2::text);

    -- assigned ride survives the sweeper even when old
    UPDATE public.rides SET created_at = now() - interval '10 minutes' WHERE id=v_ride.id;
    PERFORM set_config('request.jwt.claims', ''::text, true);
    PERFORM public.ride_sweep_unfulfilled(500);
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    r := r || public._qa_s13_ok('M2.8 an assigned Bonbonna ride is never swept',
          v_ride2.status <> 'cancelled', v_ride2.status::text);

    -- ---------- M3 CENTRALIZED CANCELLATION (no Bonbonna fork) ----------
    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    PERFORM public.ride_cancel(v_ride.id, 'qa post-dispatch cancel');
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    v_calc := public._cancellation_compute(v_ride.metadata->'finance_snapshot',
                'after_dispatch', v_ride.fare_gnf, 0, 0, 'customer');
    r := r || public._qa_s13_ok('M3.1 Bonbonna cancellation fee comes from the locked central calculator',
          COALESCE((v_ride2.metadata->>'cancellation_fee_gnf')::bigint,0)
            = (v_calc->>'fee_gnf')::bigint,
          COALESCE(v_ride2.metadata->>'cancellation_fee_gnf','null') || ' vs ' || (v_calc->>'fee_gnf'));

    -- ---------- M4 CASH TRUTH ----------
    UPDATE public.driver_profiles SET presence='offline' WHERE user_id IN (v_bon, v_off, v_susp);
    UPDATE public.driver_locations SET status='offline' WHERE user_id IN (v_bon, v_off, v_susp);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    v_req := gen_random_uuid();
    v_res := public.ride_request_create('toktok',9.5370,-13.6785,9.5700,-13.6200,
              'cash', v_req, 'Kaloum','Ratoma');
    SELECT * INTO v_ride FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('M4.1 a cash Bonbonna booking places no Chop Pay hold',
          v_ride.hold_tx_id IS NULL AND v_held1 = v_held0 AND v_bal1 = v_bal0,
          (v_held1 - v_held0)::text);
    r := r || public._qa_s13_ok('M4.2 cash Bonbonna receipt payment mode is persisted server truth',
          public._ride_payment_mode(v_ride) = 'cash' AND v_ride.metadata->>'payment_mode' = 'cash',
          v_ride.metadata->>'payment_mode');

    -- cash no-driver expiry moves zero GNF and creates no debt
    SELECT count(*) INTO v_n FROM public.customer_cancellation_debts WHERE user_id = v_cust;
    UPDATE public.rides SET created_at = now() - interval '90 seconds' WHERE id=v_ride.id;
    PERFORM set_config('request.jwt.claims', ''::text, true);
    PERFORM public.ride_sweep_unfulfilled(500);
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('M4.3 cash no-driver expiry cancels with a system reason',
          v_ride2.status='cancelled' AND v_ride2.metadata->>'cancel_reason'='no_driver_available',
          v_ride2.metadata->>'cancel_reason');
    r := r || public._qa_s13_ok('M4.4 cash no-driver expiry moves zero GNF',
          v_bal1 = v_bal0 AND v_held1 = v_held0, (v_bal1 - v_bal0)::text);
    r := r || public._qa_s13_ok('M4.5 cash no-driver expiry creates no cancellation debt',
          (SELECT count(*) FROM public.customer_cancellation_debts WHERE user_id = v_cust) = v_n,
          v_n::text);
    r := r || public._qa_s13_ok('M4.6 cash no-driver expiry charges zero cancellation fee',
          COALESCE((v_ride2.metadata->>'cancellation_fee_gnf')::bigint,0) = 0,
          v_ride2.metadata->>'cancellation_fee_gnf');

    -- a stale offer cannot be accepted once the ride expired
    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at)
    VALUES (v_ride.id, v_bon, 'pending', now() + interval '5 minutes')
    RETURNING id INTO v_offer_id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_bon), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('M4.7 no offer can be accepted after a Bonbonna search expired',
          v_err LIKE '%MISSION_NO_LONGER_AVAILABLE%', v_err);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    RAISE EXCEPTION 'QA_NODE1_MATRIX_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE1_MATRIX_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS(matrix) aborted before completion', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', ''::text, true);

  -- ---------- M5 SCHEDULER HONESTY / PRIVILEGE ----------
  SELECT schedule, active INTO v_sched, v_active FROM cron.job
   WHERE jobname='chopchop-ride-no-driver-sweep';
  r := r || public._qa_s13_ok('M5.1 the no-driver sweeper is scheduled and active',
        COALESCE(v_active,false), COALESCE(v_sched,'not scheduled'));
  r := r || public._qa_s13_ok('M5.2 sweep cadence is sub-minute so the 60s contract holds without a client',
        v_sched ~ 'second', COALESCE(v_sched,'null'));
  r := r || public._qa_s13_ok('M5.3 sweeper not executable by anon',
        NOT has_function_privilege('anon','public.ride_sweep_unfulfilled(integer)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('M5.4 sweeper not executable by authenticated',
        NOT has_function_privilege('authenticated','public.ride_sweep_unfulfilled(integer)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('M5.5 internal expiry helper not executable by anon',
        NOT has_function_privilege('anon','public._ride_expire_unfulfilled_internal(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('M5.6 internal expiry helper not executable by authenticated',
        NOT has_function_privilege('authenticated','public._ride_expire_unfulfilled_internal(uuid)','EXECUTE'), NULL);
  SELECT count(*) INTO v_n FROM public.rides r2
    JOIN auth.users u ON u.id = r2.client_id WHERE u.email LIKE 'qa-s13-n1m%';
  r := r || public._qa_s13_ok('M5.7 no Bonbonna matrix fixture residue', v_n = 0, v_n::text);

  RETURN r;
END $function$;

REVOKE ALL ON FUNCTION public._qa_node1_bonbonna_matrix() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_node1_bonbonna_full()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_base jsonb; r jsonb;
BEGIN
  v_base := public._qa_node1_bonbonna();
  r := (v_base->'results')
       || public._qa_node1_bonbonna_sweeper()
       || public._qa_node1_bonbonna_matrix();
  RETURN jsonb_build_object(
    'part','node1_bonbonna_full',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END $function$;
