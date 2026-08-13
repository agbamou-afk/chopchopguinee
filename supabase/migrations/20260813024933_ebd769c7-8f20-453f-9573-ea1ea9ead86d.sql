CREATE OR REPLACE FUNCTION public._qa_node1_bonbonna()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_moto uuid; v_bon uuid;
  v_req uuid; v_res jsonb; v_err text; v_n int;
  v_ride public.rides; v_ride2 public.rides;
  v_offer_id uuid; v_offer public.ride_offers;
  v_quote_m bigint; v_quote_b bigint; v_hold bigint; v_code text;
  v_held0 bigint; v_held1 bigint; v_bal0 bigint; v_bal1 bigint;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_drv uuid;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  BEGIN
    v_cust := gen_random_uuid(); v_moto := gen_random_uuid(); v_bon := gen_random_uuid();
    PERFORM public._qa_s13_user(v_cust,'n1c');
    PERFORM public._qa_s13_user(v_moto,'n1m');
    PERFORM public._qa_s13_user(v_bon,'n1b');
    PERFORM public._qa_s13_wallet(v_cust,'client',3000000,0);
    PERFORM public._qa_s13_wallet(v_moto,'driver',900000,0);
    PERFORM public._qa_s13_wallet(v_bon,'driver',900000,0);
    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,presence)
      VALUES (v_moto,'approved','moto','online')
      ON CONFLICT (user_id) DO UPDATE SET status='approved', vehicle_type='moto', presence='online';
    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,presence)
      VALUES (v_bon,'approved','toktok','online')
      ON CONFLICT (user_id) DO UPDATE SET status='approved', vehicle_type='toktok', presence='online';
    INSERT INTO public.driver_locations(user_id,lat,lng,status)
      VALUES (v_moto,9.5372,-13.6787,'online'),(v_bon,9.5373,-13.6788,'online')
      ON CONFLICT (user_id) DO UPDATE SET lat=EXCLUDED.lat, lng=EXCLUDED.lng, status='online';

    -- ---------- PRICING IDENTITY ----------
    v_quote_m := public.ride_compute_quote_gnf('moto',9.5370,-13.6785,9.5700,-13.6200);
    v_quote_b := public.ride_compute_quote_gnf('toktok',9.5370,-13.6785,9.5700,-13.6200);
    r := r || public._qa_s13_ok('B1.1 Bonbonna has its own server fare distinct from Moto',
          v_quote_b IS NOT NULL AND v_quote_b <> v_quote_m,
          v_quote_b::text || ' vs moto ' || v_quote_m::text);

    -- ---------- REQUEST ----------
    v_hold := public.ride_reservation_amount_gnf(v_quote_b);
    v_req := gen_random_uuid();
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    SELECT held_gnf INTO v_held0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    v_res := public.ride_request_create('toktok',9.5370,-13.6785,9.5700,-13.6200,
              'chop_pay', v_req, 'Kaloum','Ratoma');
    SELECT * INTO v_ride FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    r := r || public._qa_s13_ok('B1.2 Bonbonna ride persists mode=toktok with server fare',
          v_ride.mode::text='toktok' AND v_ride.fare_gnf = v_quote_b, v_ride.fare_gnf::text);
    r := r || public._qa_s13_ok('B1.3 Bonbonna request snapshots the bonbonna finance policy',
          (v_ride.metadata->'finance_snapshot'->>'policy_id') IS NOT NULL,
          v_ride.metadata->'finance_snapshot'->>'mission_type');
    SELECT held_gnf INTO v_held1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('B2.1 Bonbonna hold equals the server reservation amount',
          v_held1 - v_held0 = v_hold, (v_held1 - v_held0)::text || ' expected ' || v_hold::text);

    -- ---------- DISPATCH TARGETS THE RIGHT FLEET ----------
    PERFORM set_config('request.jwt.claims', '', true);
    SELECT id INTO v_offer_id FROM public.ride_offers WHERE ride_id = v_ride.id
     ORDER BY sent_at DESC LIMIT 1;
    IF v_offer_id IS NULL THEN v_offer_id := public.ride_dispatch(v_ride.id); END IF;
    SELECT * INTO v_offer FROM public.ride_offers WHERE id = v_offer_id;
    r := r || public._qa_s13_ok('B3.1 Bonbonna dispatch offers only a toktok driver',
          v_offer.driver_id = v_bon, COALESCE(v_offer.driver_id::text,'no offer'));
    r := r || public._qa_s13_ok('B3.2 offer carries the service mode for driver UI truth',
          v_offer.ride_mode::text = 'toktok', v_offer.ride_mode::text);
    SELECT count(*) INTO v_n FROM public.ride_offers o
      WHERE o.ride_id = v_ride.id AND o.driver_id = v_moto;
    r := r || public._qa_s13_ok('B3.3 moto driver never receives a Bonbonna offer', v_n = 0, v_n::text);

    -- ---------- ELIGIBILITY AT ACCEPTANCE ----------
    INSERT INTO public.ride_offers(ride_id,driver_id,status,expires_at)
    VALUES (v_ride.id, v_moto, 'pending', now() + interval '5 minutes')
    RETURNING id INTO v_offer_id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_moto), true);
    BEGIN PERFORM public.driver_offer_accept(v_offer_id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B4.1 moto driver cannot accept a Bonbonna ride',
          v_err LIKE '%DRIVER_VEHICLE_NOT_ELIGIBLE%', v_err);
    SELECT driver_id INTO v_drv FROM public.rides WHERE id=v_ride.id;
    r := r || public._qa_s13_ok('B4.2 refused acceptance left the ride unassigned',
          v_drv IS NULL, v_drv::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_bon), true);
    PERFORM public.driver_offer_accept_for_ride(v_ride.id);
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    r := r || public._qa_s13_ok('B4.3 toktok driver accepts the Bonbonna ride',
          v_ride2.driver_id = v_bon, v_ride2.driver_id::text);

    -- ---------- PICKUP + COMPLETION ECONOMICS ----------
    UPDATE public.rides SET metadata = COALESCE(metadata,'{}'::jsonb)
      || jsonb_build_object('phase','arrived',
           'pickup_code', COALESCE(metadata->>'pickup_code','482913'))
     WHERE id=v_ride.id;
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    v_code := v_ride2.metadata->>'pickup_code';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    PERFORM public.ride_confirm_pickup(v_ride.id, v_code);

    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_bon AND party_type='driver';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_bon), true);
    PERFORM public.ride_complete(v_ride.id, NULL, NULL);
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_bon AND party_type='driver';
    r := r || public._qa_s13_ok('B5.1 Bonbonna completion settles through locked primitives',
          v_ride2.status='completed' AND v_ride2.payment_tx_id IS NOT NULL, v_ride2.status::text);
    r := r || public._qa_s13_ok('B5.2 Bonbonna driver earning derives from the frozen snapshot',
          v_bal1 - v_bal0 = v_ride.fare_gnf
            - ((v_ride.fare_gnf * COALESCE((v_ride.metadata->'finance_snapshot'->>'commission_bps')::int,0)) / 10000
               + COALESCE((v_ride.metadata->'finance_snapshot'->>'fixed_commission_gnf')::bigint,0)),
          (v_bal1 - v_bal0)::text);

    -- ---------- NO-DRIVER EXPIRY + FULL RELEASE ----------
    UPDATE public.driver_profiles SET presence='offline' WHERE user_id IN (v_bon, v_moto);
    UPDATE public.driver_locations SET status='offline' WHERE user_id IN (v_bon, v_moto);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_req := gen_random_uuid();
    SELECT held_gnf INTO v_held0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    v_res := public.ride_request_create('toktok',9.5370,-13.6785,9.5700,-13.6200,
              'chop_pay', v_req, NULL, NULL);
    SELECT * INTO v_ride FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    v_res := public.ride_expire_unfulfilled(v_ride.id);
    r := r || public._qa_s13_ok('B6.1 expiry before 60s keeps searching',
          v_res->>'status' = 'searching', v_res::text);

    UPDATE public.rides SET created_at = now() - interval '90 seconds' WHERE id=v_ride.id;
    v_res := public.ride_expire_unfulfilled(v_ride.id);
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    SELECT held_gnf INTO v_held1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('B6.2 no-driver expiry cancels the ride with a system reason',
          v_res->>'status'='no_driver' AND v_ride2.status='cancelled'
          AND v_ride2.metadata->>'cancel_reason'='no_driver_available'
          AND v_ride2.metadata->>'cancelled_by'='system', v_ride2.metadata->>'cancel_reason');
    r := r || public._qa_s13_ok('B6.3 no-driver expiry releases the hold in full',
          v_held1 = v_held0, (v_held1 - v_held0)::text);
    r := r || public._qa_s13_ok('B6.4 no-driver expiry charges zero cancellation fee',
          COALESCE((v_ride2.metadata->>'cancellation_fee_gnf')::bigint,0) = 0,
          v_ride2.metadata->>'cancellation_fee_gnf');
    SELECT count(*) INTO v_n FROM public.ride_offers
      WHERE ride_id=v_ride.id AND status='pending';
    r := r || public._qa_s13_ok('B6.5 no pending offer survives expiry', v_n = 0, v_n::text);

    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    v_res := public.ride_expire_unfulfilled(v_ride.id);
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('B6.6 repeated expiry is idempotent and moves zero GNF',
          v_bal1 = v_bal0 AND v_held1 = v_held0, v_res::text);

    -- ---------- AUTHORIZATION ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_bon), true);
    BEGIN PERFORM public.ride_expire_unfulfilled(v_ride.id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B7.1 a non-owner cannot expire someone else''s ride',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);
    PERFORM set_config('request.jwt.claims', ''::text, true);
    BEGIN PERFORM public.ride_expire_unfulfilled(v_ride.id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B7.2 unauthenticated expiry fails closed',
          v_err LIKE '%NOT_AUTHENTICATED%', v_err);
    r := r || public._qa_s13_ok('B7.3 ride_expire_unfulfilled not executable by anon',
          NOT has_function_privilege('anon','public.ride_expire_unfulfilled(uuid)','EXECUTE'), NULL);

    RAISE EXCEPTION 'QA_NODE1_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE1_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS aborted before completion', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', ''::text, true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z1.1 master wallet unchanged after fixture rollback',
        v_master0 IS NOT DISTINCT FROM v_master1, v_master1::text);
  r := r || public._qa_s13_ok('Z1.2 feature flags unchanged after fixture rollback',
        v_flags0 = v_flags1, NULL);
  SELECT count(*) INTO v_n FROM public.rides r2
    JOIN auth.users u ON u.id = r2.client_id WHERE u.email LIKE 'qa-s13-n1%';
  r := r || public._qa_s13_ok('Z1.3 no Node 1 fixture residue', v_n = 0, v_n::text);

  RETURN jsonb_build_object(
    'part','node1_bonbonna',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END $$;

DELETE FROM public._qa_s13_results WHERE part = 101;
INSERT INTO public._qa_s13_results(part, result)
SELECT 101, public._qa_node1_bonbonna();