CREATE OR REPLACE FUNCTION public._qa_node1_bonbonna_matrix()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_bon uuid; v_bon2 uuid; v_susp uuid; v_off uuid; v_winner uuid; v_fin uuid;
  v_req uuid; v_res jsonb; v_err text; v_n int;
  v_ride public.rides; v_ride2 public.rides;
  v_offer_id uuid; v_offer_id2 uuid;
  v_quote jsonb; v_fare bigint; v_hold bigint;
  v_held0 bigint; v_held1 bigint; v_bal0 bigint; v_bal1 bigint;
  v_calc jsonb; v_sched text; v_active boolean;
  v_pay_tx uuid; v_pay_tx2 uuid; v_dbal0 bigint; v_dbal1 bigint;
BEGIN
  BEGIN
    v_cust := gen_random_uuid(); v_bon := gen_random_uuid(); v_bon2 := gen_random_uuid();
    v_susp := gen_random_uuid(); v_off := gen_random_uuid(); v_fin := gen_random_uuid();
    PERFORM public._qa_s13_user(v_cust,'n1mc');
    PERFORM public._qa_s13_user(v_bon,'n1mb');
    PERFORM public._qa_s13_user(v_bon2,'n1mb2');
    PERFORM public._qa_s13_user(v_susp,'n1ms');
    PERFORM public._qa_s13_user(v_off,'n1mo');
    PERFORM public._qa_s13_user(v_fin,'n1mf');
    PERFORM public._qa_s13_wallet(v_cust,'client',5000000,0);
    PERFORM public._qa_s13_wallet(v_bon,'driver',900000,0);
    PERFORM public._qa_s13_wallet(v_bon2,'driver',900000,0);
    PERFORM public._qa_s13_wallet(v_susp,'driver',900000,0);
    PERFORM public._qa_s13_wallet(v_off,'driver',900000,0);
    PERFORM public._qa_s13_wallet(v_fin,'driver',900000,0);

    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,presence) VALUES
      (v_bon,'approved','toktok','online'),
      (v_bon2,'approved','toktok','online'),
      (v_susp,'suspended','toktok','online'),
      (v_off,'approved','toktok','offline'),
      (v_fin,'approved','toktok','offline')
    ON CONFLICT (user_id) DO UPDATE SET status=EXCLUDED.status,
      vehicle_type=EXCLUDED.vehicle_type, presence=EXCLUDED.presence;
    INSERT INTO public.driver_locations(user_id,lat,lng,status) VALUES
      (v_bon,9.5373,-13.6788,'online'),
      (v_bon2,9.5374,-13.6789,'online'),
      (v_susp,9.5375,-13.6790,'online'),
      (v_off,9.5376,-13.6791,'offline'),
      (v_fin,9.5377,-13.6792,'offline')
    ON CONFLICT (user_id) DO UPDATE SET lat=EXCLUDED.lat, lng=EXCLUDED.lng, status=EXCLUDED.status;

    -- ---------- M1 QUOTE AUTHORITY (inside a real customer session) ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_quote := public.ride_get_quote('toktok',9.5370,-13.6785,9.5700,-13.6200);
    v_fare  := public.ride_compute_quote_gnf('toktok',9.5370,-13.6785,9.5700,-13.6200);
    v_hold  := public.ride_reservation_amount_gnf(v_fare);
    r := r || public._qa_s13_ok('M1.1 Bonbonna quote is server-authoritative and matches the pricing engine',
          (v_quote->>'fare_gnf')::bigint = v_fare, v_quote->>'fare_gnf');
    r := r || public._qa_s13_ok('M1.2 Bonbonna Chop Pay reservation preview equals the server reservation helper',
          (v_quote->>'chop_pay_hold_gnf')::bigint = v_hold, v_quote->>'chop_pay_hold_gnf');

    -- ---------- M2 CHOP PAY BOOKING / ELIGIBILITY ----------
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

    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at)
    VALUES (v_ride.id, v_susp, 'pending', now() + interval '5 minutes')
    RETURNING id INTO v_offer_id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_susp), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('M2.4 a suspended Bonbonna driver cannot accept',
          v_err LIKE '%DRIVER_NOT_APPROVED%', v_err);

    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at)
    VALUES (v_ride.id, v_bon2, 'pending', now() - interval '1 minute')
    RETURNING id INTO v_offer_id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_bon2), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('M2.5 a stale Bonbonna offer cannot be accepted',
          v_err LIKE '%OFFER_EXPIRED%', v_err);

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
    SELECT driver_id INTO v_winner FROM public.rides WHERE id=v_ride.id;
    r := r || public._qa_s13_ok('M2.7 the assigned Bonbonna driver is the accepting driver',
          v_winner = v_bon, v_winner::text);

    UPDATE public.rides SET created_at = now() - interval '10 minutes' WHERE id=v_ride.id;
    PERFORM set_config('request.jwt.claims', ''::text, true);
    PERFORM public.ride_sweep_unfulfilled(500);
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    r := r || public._qa_s13_ok('M2.8 an assigned Bonbonna ride is never swept',
          v_ride2.status <> 'cancelled', v_ride2.status::text);

    -- ---------- M3 CENTRALIZED CANCELLATION (no Bonbonna fork) ----------
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
    UPDATE public.driver_profiles SET presence='offline' WHERE user_id IN (v_bon, v_bon2, v_off, v_susp);
    UPDATE public.driver_locations SET status='offline' WHERE user_id IN (v_bon, v_bon2, v_off, v_susp);
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

    SELECT count(*) INTO v_n FROM public.customer_cancellation_debts WHERE customer_user_id = v_cust;
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
          (SELECT count(*) FROM public.customer_cancellation_debts WHERE customer_user_id = v_cust) = v_n,
          v_n::text);
    r := r || public._qa_s13_ok('M4.6 cash no-driver expiry charges zero cancellation fee',
          COALESCE((v_ride2.metadata->>'cancellation_fee_gnf')::bigint,0) = 0,
          v_ride2.metadata->>'cancellation_fee_gnf');

    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at)
    VALUES (v_ride.id, v_bon, 'pending', now() + interval '5 minutes')
    RETURNING id INTO v_offer_id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_bon), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('M4.7 no offer can be accepted after a Bonbonna search expired',
          v_err LIKE '%MISSION_NO_LONGER_AVAILABLE%', v_err);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    -- ---------- M6 FINANCE-INELIGIBLE DRIVER (approved but frozen) ----------
    UPDATE public.driver_profiles SET presence='online' WHERE user_id = v_fin;
    UPDATE public.driver_locations SET status='online' WHERE user_id = v_fin;
    INSERT INTO public.account_freezes(user_id, reason, freeze_type, status, frozen_by)
    VALUES (v_fin, 'qa node1 matrix freeze', 'admin_review', 'active', v_fin);
    r := r || public._qa_s13_ok('M6.0 the frozen Bonbonna driver is finance-ineligible',
          NOT public._driver_finance_eligible(v_fin), NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_req := gen_random_uuid();
    v_res := public.ride_request_create('toktok',9.5370,-13.6785,9.5700,-13.6200,
              'cash', v_req, 'Kaloum','Ratoma');
    SELECT * INTO v_ride FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT count(*) INTO v_n FROM public.ride_offers WHERE ride_id=v_ride.id AND driver_id=v_fin;
    r := r || public._qa_s13_ok('M6.1 a finance-ineligible Bonbonna driver never receives an offer',
          v_n = 0, v_n::text);
    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at)
    VALUES (v_ride.id, v_fin, 'pending', now() + interval '5 minutes')
    RETURNING id INTO v_offer_id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_fin), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('M6.2 a finance-ineligible Bonbonna driver cannot accept even a planted offer',
          v_err LIKE '%DRIVER_NOT_ELIGIBLE%', v_err);
    PERFORM set_config('request.jwt.claims', ''::text, true);
    UPDATE public.account_freezes SET status='lifted', lifted_at=now() WHERE user_id=v_fin;
    UPDATE public.driver_profiles SET presence='offline' WHERE user_id = v_fin;
    UPDATE public.driver_locations SET status='offline' WHERE user_id = v_fin;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    PERFORM public.ride_cancel(v_ride.id, 'qa cleanup');
    PERFORM set_config('request.jwt.claims', ''::text, true);

    -- ---------- M7 PRE-DISPATCH CANCELLATION PARITY (Chop Pay) ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    v_req := gen_random_uuid();
    v_res := public.ride_request_create('toktok',9.5370,-13.6785,9.5700,-13.6200,
              'chop_pay', v_req, 'Kaloum','Ratoma');
    SELECT * INTO v_ride FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    r := r || public._qa_s13_ok('M7.0 the pre-dispatch Bonbonna fixture really has no driver',
          v_ride.driver_id IS NULL, COALESCE(v_ride.driver_id::text,'null'));
    PERFORM public.ride_cancel(v_ride.id, 'qa pre-dispatch cancel');
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    v_calc := public._cancellation_compute(v_ride.metadata->'finance_snapshot',
                'before_dispatch', v_ride.fare_gnf, 0, 0, 'customer');
    r := r || public._qa_s13_ok('M7.1 pre-dispatch Bonbonna cancellation uses the same central calculator',
          COALESCE((v_ride2.metadata->>'cancellation_fee_gnf')::bigint,0) = (v_calc->>'fee_gnf')::bigint,
          COALESCE(v_ride2.metadata->>'cancellation_fee_gnf','null') || ' vs ' || (v_calc->>'fee_gnf'));
    SELECT held_gnf INTO v_held1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('M7.2 pre-dispatch Bonbonna cancellation leaves no residual reservation',
          v_held1 = v_held0, (v_held1 - v_held0)::text);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    -- ---------- M8 CASH COMPLETION TRUTH ----------
    UPDATE public.driver_profiles SET presence='online' WHERE user_id = v_bon;
    UPDATE public.driver_locations SET status='online' WHERE user_id = v_bon;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    v_req := gen_random_uuid();
    v_res := public.ride_request_create('toktok',9.5370,-13.6785,9.5700,-13.6200,
              'cash', v_req, 'Kaloum','Ratoma');
    SELECT * INTO v_ride FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_bon), true);
    PERFORM public.driver_offer_accept_for_ride(v_ride.id);
    UPDATE public.rides SET metadata = COALESCE(metadata,'{}'::jsonb)
      || jsonb_build_object('phase','on_trip','pickup_confirmed_by','customer')
     WHERE id = v_ride.id;
    PERFORM public.ride_start(v_ride.id);
    SELECT * INTO v_ride2 FROM public.ride_complete(v_ride.id, NULL, NULL);
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('M8.1 a completed cash Bonbonna trip never debits the customer wallet',
          v_bal1 = v_bal0 AND v_held1 = v_held0, (v_bal1 - v_bal0)::text);
    r := r || public._qa_s13_ok('M8.2 a completed cash Bonbonna trip records no Chop Pay payment transaction',
          v_ride2.payment_tx_id IS NULL, COALESCE(v_ride2.payment_tx_id::text,'null'));
    r := r || public._qa_s13_ok('M8.3 a completed cash Bonbonna trip records the cash collected by the driver',
          COALESCE((v_ride2.metadata->>'cash_collected_gnf')::bigint,-1) = v_ride2.fare_gnf,
          COALESCE(v_ride2.metadata->>'cash_collected_gnf','null'));
    r := r || public._qa_s13_ok('M8.4 a completed cash Bonbonna trip still books platform commission',
          COALESCE(v_ride2.platform_fee_gnf,0) > 0, COALESCE(v_ride2.platform_fee_gnf,0)::text);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    -- ---------- M9 CHOP PAY CAPTURE IS EXACTLY ONCE ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_req := gen_random_uuid();
    v_res := public.ride_request_create('toktok',9.5370,-13.6785,9.5700,-13.6200,
              'chop_pay', v_req, 'Kaloum','Ratoma');
    SELECT * INTO v_ride FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_bon), true);
    PERFORM public.driver_offer_accept_for_ride(v_ride.id);
    UPDATE public.rides SET metadata = COALESCE(metadata,'{}'::jsonb)
      || jsonb_build_object('phase','on_trip','pickup_confirmed_by','customer')
     WHERE id = v_ride.id;
    PERFORM public.ride_start(v_ride.id);
    SELECT * INTO v_ride2 FROM public.ride_complete(v_ride.id, NULL, NULL);
    v_pay_tx := v_ride2.payment_tx_id;
    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_dbal0 FROM public.wallets WHERE owner_user_id=v_bon AND party_type='driver';
    r := r || public._qa_s13_ok('M9.1 a completed Chop Pay Bonbonna trip captures the reservation once',
          v_pay_tx IS NOT NULL AND v_held0 = 0, COALESCE(v_pay_tx::text,'null'));
    SELECT * INTO v_ride2 FROM public.ride_complete(v_ride.id, NULL, NULL);
    v_pay_tx2 := v_ride2.payment_tx_id;
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_dbal1 FROM public.wallets WHERE owner_user_id=v_bon AND party_type='driver';
    r := r || public._qa_s13_ok('M9.2 replaying completion keeps the same Chop Pay payment transaction',
          v_pay_tx2 = v_pay_tx, COALESCE(v_pay_tx2::text,'null'));
    r := r || public._qa_s13_ok('M9.3 replaying completion moves zero additional GNF',
          v_bal1 = v_bal0 AND v_held1 = v_held0 AND v_dbal1 = v_dbal0,
          (v_bal1 - v_bal0)::text || '/' || (v_dbal1 - v_dbal0)::text);
    SELECT count(*) INTO v_n FROM public.wallet_transactions
      WHERE reference = 'ride:' || v_ride.id::text || ':commission';
    r := r || public._qa_s13_ok('M9.4 replaying completion books commission at most once',
          v_n <= 1, v_n::text);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    RAISE EXCEPTION 'QA_NODE1_MATRIX_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE1_MATRIX_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS(matrix) aborted before completion', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', ''::text, true);

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