CREATE OR REPLACE FUNCTION public._qa_node0_course()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_drv uuid; v_adm uuid; v_poor uuid;
  v_req uuid; v_req2 uuid; v_req3 uuid; v_req4 uuid;
  v_res jsonb; v_res2 jsonb; v_err text;
  v_ride public.rides; v_ride2 public.rides;
  v_quote bigint; v_expect_hold bigint; v_code text;
  v_held0 bigint; v_held1 bigint; v_bal0 bigint; v_bal1 bigint;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_n int; v_snapbps int; v_snapfix bigint; v_comm bigint;
  v_args text;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  SELECT pg_get_function_identity_arguments(p.oid) INTO v_args
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ride_request_create';
  r := r || public._qa_s13_ok('N1.1 ride_request_create exposes no client fare / hold parameter',
        v_args IS NOT NULL AND v_args NOT LIKE '%fare%' AND v_args NOT LIKE '%hold%', v_args);
  r := r || public._qa_s13_ok('N8.2 legacy ride_create not executable by authenticated',
        NOT has_function_privilege('authenticated',
          'public.ride_create(public.ride_mode,numeric,numeric,numeric,numeric,bigint,uuid,uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N8.3 legacy ride_create not executable by anon',
        NOT has_function_privilege('anon',
          'public.ride_create(public.ride_mode,numeric,numeric,numeric,numeric,bigint,uuid,uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N8.4 ride_request_create not executable by anon',
        NOT has_function_privilege('anon',
          'public.ride_request_create(public.ride_mode,numeric,numeric,numeric,numeric,text,uuid,text,text)','EXECUTE'), NULL);

  BEGIN
    v_cust := gen_random_uuid(); v_drv := gen_random_uuid();
    v_adm  := gen_random_uuid(); v_poor := gen_random_uuid();
    PERFORM public._qa_s13_user(v_cust,'n0c');
    PERFORM public._qa_s13_user(v_drv,'n0d');
    PERFORM public._qa_s13_user(v_adm,'n0a');
    PERFORM public._qa_s13_user(v_poor,'n0p');
    PERFORM public._qa_s13_wallet(v_cust,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_poor,'client',100,0);
    PERFORM public._qa_s13_wallet(v_drv,'driver',900000,0);
    PERFORM public._qa_s13_admin(v_adm);
    INSERT INTO public.driver_profiles(user_id,status,vehicle_type)
      VALUES (v_drv,'approved','moto')
      ON CONFLICT (user_id) DO UPDATE SET status='approved';

    v_quote := public.ride_compute_quote_gnf('moto',9.5370,-13.6785,9.5700,-13.6200);
    v_expect_hold := ceil((v_quote::numeric * 11000) / 10000)::bigint;

    -- ---------- CHOP PAY REQUEST ----------
    SELECT held_gnf, balance_gnf INTO v_held0, v_bal0
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';

    v_req := gen_random_uuid();
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_res := public.ride_request_create('moto',9.5370,-13.6785,9.5700,-13.6200,
              'chop_pay', v_req, 'Kaloum','Ratoma');
    SELECT * INTO v_ride FROM public.rides WHERE id = (v_res->>'ride_id')::uuid;

    r := r || public._qa_s13_ok('N1.2 persisted fare equals ride_compute_quote_gnf truth',
          v_ride.fare_gnf = v_quote, v_ride.fare_gnf::text || ' vs ' || v_quote::text);
    r := r || public._qa_s13_ok('N1.3 fare provenance recorded as server-derived',
          v_ride.metadata->>'fare_source' = 'server:ride_compute_quote_gnf', v_ride.metadata->>'fare_source');
    r := r || public._qa_s13_ok('N2.1 hold equals server reservation amount (fare x 1.10)',
          COALESCE((v_ride.metadata->>'hold_amount_gnf')::bigint,0) = v_expect_hold
          AND (v_res->>'hold_amount_gnf')::bigint = v_expect_hold, v_expect_hold::text);

    SELECT held_gnf INTO v_held1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('N2.2 wallet held_gnf reflects exactly the server reservation',
          v_held1 - v_held0 = v_expect_hold, (v_held1 - v_held0)::text);
    r := r || public._qa_s13_ok('N6.1 payment mode explicit chop_pay + hold linked',
          v_ride.metadata->>'payment_mode' = 'chop_pay'
          AND v_ride.hold_tx_id IS NOT NULL
          AND public._ride_payment_mode(v_ride) = 'chop_pay', NULL);
    r := r || public._qa_s13_ok('N7.1 request-time finance snapshot frozen on the ride',
          (v_ride.metadata->'finance_snapshot'->>'policy_id') IS NOT NULL
          AND (v_ride.metadata->'finance_snapshot'->>'fare_gnf')::bigint = v_quote
          AND (v_ride.metadata->'finance_snapshot'->>'payment_mode') = 'chop_pay', NULL);

    -- ---------- REPLAY ----------
    v_res2 := public.ride_request_create('moto',9.5370,-13.6785,9.5700,-13.6200,
               'chop_pay', v_req, 'Kaloum','Ratoma');
    SELECT count(*) INTO v_n FROM public.rides WHERE client_id=v_cust
      AND metadata->>'client_request_id' = v_req::text;
    r := r || public._qa_s13_ok('N3.1 replay returns the same ride, idempotent status',
          v_res2->>'status' = 'already_created' AND v_res2->>'ride_id' = v_res->>'ride_id', v_res2->>'status');
    r := r || public._qa_s13_ok('N3.2 replay created exactly one ride', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.wallet_transactions
      WHERE reference = 'ride_request:' || v_req::text;
    r := r || public._qa_s13_ok('N3.3 replay created exactly one hold', v_n = 1, v_n::text);
    SELECT held_gnf INTO v_held1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('N3.4 replay moved zero additional GNF',
          v_held1 - v_held0 = v_expect_hold, (v_held1 - v_held0)::text);

    -- ---------- ACTIVE RIDE GUARD ----------
    v_req2 := gen_random_uuid();
    BEGIN PERFORM public.ride_request_create('moto',9.5370,-13.6785,9.5700,-13.6200,
            'chop_pay', v_req2, NULL, NULL); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N10.1 duplicate active Course request refused',
          v_err LIKE '%ACTIVE_RIDE_EXISTS%', v_err);

    -- ---------- ASSIGNMENT VIA OFFER CONTRACT ----------
    INSERT INTO public.ride_offers(ride_id, driver_id, status, expires_at)
    VALUES (v_ride.id, v_drv, 'pending', now() + interval '5 minutes');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.driver_offer_accept_for_ride(v_ride.id);
    SELECT * INTO v_ride2 FROM public.rides WHERE id = v_ride.id;
    r := r || public._qa_s13_ok('N12.1 assignment only through the offer contract',
          v_ride2.driver_id = v_drv, v_ride2.driver_id::text);

    -- driver arrival (phase only; no money movement)
    UPDATE public.rides
       SET metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
             'phase','arrived',
             'pickup_code', COALESCE(metadata->>'pickup_code','482913'))
     WHERE id = v_ride.id;
    SELECT * INTO v_ride2 FROM public.rides WHERE id = v_ride.id;
    v_code := v_ride2.metadata->>'pickup_code';

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN PERFORM public.ride_confirm_pickup(v_ride.id, '000000'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N9.1 wrong pickup code refused',
          v_err LIKE '%invalide%', v_err);
    PERFORM public.ride_confirm_pickup(v_ride.id, v_code);
    SELECT * INTO v_ride2 FROM public.rides WHERE id = v_ride.id;
    r := r || public._qa_s13_ok('N9.2 correct pickup code advances to on_trip',
          v_ride2.metadata->>'phase' = 'on_trip'
          AND v_ride2.metadata->>'pickup_confirmed_by' = 'customer', v_ride2.metadata->>'phase');

    -- ---------- CHOP PAY COMPLETION ECONOMICS ----------
    v_snapbps := COALESCE((v_ride.metadata->'finance_snapshot'->>'commission_bps')::int,0);
    v_snapfix := COALESCE((v_ride.metadata->'finance_snapshot'->>'fixed_commission_gnf')::bigint,0);
    v_comm := (v_ride.fare_gnf * v_snapbps) / 10000 + v_snapfix;
    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.ride_complete(v_ride.id, NULL, NULL);
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';

    r := r || public._qa_s13_ok('N6.2 chop_pay completion captured through locked primitives',
          v_ride2.status = 'completed' AND v_ride2.payment_tx_id IS NOT NULL, v_ride2.status::text);
    r := r || public._qa_s13_ok('N7.2 completion economics derive from the frozen snapshot',
          v_bal1 - v_bal0 = v_ride.fare_gnf - v_comm,
          (v_bal1 - v_bal0)::text || ' expected ' || (v_ride.fare_gnf - v_comm)::text);
    BEGIN PERFORM public.ride_complete(v_ride.id, NULL, NULL); EXCEPTION WHEN OTHERS THEN NULL; END;
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s13_ok('N9.3 duplicate completion moved zero additional GNF',
          v_bal1 - v_bal0 = v_ride.fare_gnf - v_comm, (v_bal1 - v_bal0)::text);

    -- ---------- CASH REQUEST ----------
    v_req3 := gen_random_uuid();
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    SELECT held_gnf INTO v_held0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    v_res := public.ride_request_create('moto',9.5370,-13.6785,9.5700,-13.6200,
              'cash', v_req3, NULL, NULL);
    SELECT * INTO v_ride FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    SELECT held_gnf INTO v_held1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('N5.1 cash ride: explicit payment_mode, no hold',
          v_ride.metadata->>'payment_mode' = 'cash'
          AND v_ride.hold_tx_id IS NULL
          AND public._ride_payment_mode(v_ride) = 'cash'
          AND (v_res->>'hold_amount_gnf')::bigint = 0, NULL);
    r := r || public._qa_s13_ok('N5.2 cash request reserved zero customer funds',
          v_held1 = v_held0, (v_held1 - v_held0)::text);
    PERFORM public.ride_cancel(v_ride.id, 'qa-node0');
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    r := r || public._qa_s13_ok('N5.3 cash cancellation routes through the cash path',
          v_ride2.status = 'cancelled', v_ride2.status::text);

    -- ---------- INSUFFICIENT FUNDS ATOMICITY ----------
    v_req4 := gen_random_uuid();
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_poor), true);
    BEGIN PERFORM public.ride_request_create('moto',9.5370,-13.6785,9.5700,-13.6200,
            'chop_pay', v_req4, NULL, NULL); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4.1 insufficient Chop Pay funds refuses the request',
          v_err LIKE '%Insufficient balance%', v_err);
    SELECT count(*) INTO v_n FROM public.rides WHERE client_id = v_poor;
    r := r || public._qa_s13_ok('N4.2 insufficient funds created zero rides', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.wallet_transactions
      WHERE reference = 'ride_request:' || v_req4::text;
    r := r || public._qa_s13_ok('N4.3 insufficient funds created zero orphan holds', v_n = 0, v_n::text);
    SELECT held_gnf INTO v_held1 FROM public.wallets WHERE owner_user_id=v_poor AND party_type='client';
    r := r || public._qa_s13_ok('N4.4 refused request left held_gnf at zero', v_held1 = 0, v_held1::text);

    -- ---------- UNAUTHENTICATED ----------
    PERFORM set_config('request.jwt.claims', ''::text, true);
    BEGIN PERFORM public.ride_request_create('moto',9.5370,-13.6785,9.5700,-13.6200,
            'chop_pay', gen_random_uuid(), NULL, NULL); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N8.1 unauthenticated request fails closed',
          v_err LIKE '%NOT_AUTHENTICATED%', v_err);

    -- ---------- LEGACY ride_create HARDENING ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_poor), true);
    SELECT * INTO v_ride FROM public.ride_create('moto',9.5370,-13.6785,9.5700,-13.6200,
            999999999::bigint, NULL, NULL);
    r := r || public._qa_s13_ok('N11.1 legacy ride_create ignores a tampered client fare',
          v_ride.fare_gnf = v_quote, v_ride.fare_gnf::text || ' vs ' || v_quote::text);
    BEGIN PERFORM public.ride_create('moto',9.5370,-13.6785,9.5700,-13.6200,
            NULL, gen_random_uuid(), NULL); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N11.2 legacy ride_create refuses an unrelated hold reference',
          v_err LIKE '%INVALID_HOLD_REFERENCE%', v_err);

    PERFORM set_config('request.jwt.claims', ''::text, true);
    RAISE EXCEPTION 'QA_NODE0_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE0_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS aborted before completion', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', ''::text, true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z0.1 master wallet unchanged after fixture rollback',
        v_master0 IS NOT DISTINCT FROM v_master1, v_master1::text);
  r := r || public._qa_s13_ok('Z0.2 feature flags unchanged after fixture rollback',
        v_flags0 = v_flags1, NULL);
  SELECT count(*) INTO v_n FROM public.rides r2
    JOIN auth.users u ON u.id = r2.client_id WHERE u.email LIKE 'qa-s13-n0%';
  r := r || public._qa_s13_ok('Z0.3 no Node 0 fixture residue', v_n = 0, v_n::text);

  RETURN jsonb_build_object(
    'part','node0_course',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END;
$function$;

INSERT INTO public._qa_s13_results(part, result)
SELECT 0, public._qa_node0_course();