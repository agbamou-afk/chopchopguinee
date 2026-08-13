-- =========================================================
-- NODE 0 CLOSEOUT — Course (Moto) CRS-G1 / CRS-G2 / CRS-G3
-- Server-authoritative quote + commitment + hold.
-- No flag changes. No RLS changes. No new money primitives.
-- =========================================================

-- 1) Smallest possible replay protection.
CREATE UNIQUE INDEX IF NOT EXISTS rides_client_request_id_uidx
  ON public.rides (client_id, ((metadata->>'client_request_id')))
  WHERE metadata ? 'client_request_id';

-- 2) Authoritative commitment RPC.
CREATE OR REPLACE FUNCTION public.ride_request_create(
  p_mode public.ride_mode,
  p_pickup_lat numeric,
  p_pickup_lng numeric,
  p_dest_lat numeric,
  p_dest_lng numeric,
  p_payment_mode text,
  p_client_request_id uuid,
  p_pickup_label text DEFAULT NULL,
  p_dest_label text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  -- D3: finance_policies exposes no ride reservation-buffer field, so today's
  -- 1.10 buffer is preserved as a named SERVER-SIDE constant. No new
  -- finance-policy semantics are introduced.
  C_RESERVATION_BUFFER_BPS constant integer := 11000;
  v_uid  uuid := auth.uid();
  v_pay  text;
  v_fare bigint;
  v_hold bigint := 0;
  v_hold_tx public.wallet_transactions;
  v_ride public.rides;
  v_prev public.rides;
  v_snap jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_client_request_id IS NULL THEN RAISE EXCEPTION 'CLIENT_REQUEST_ID_REQUIRED'; END IF;

  v_pay := lower(COALESCE(p_payment_mode,''));
  IF v_pay = 'choppay' THEN v_pay := 'chop_pay'; END IF;
  IF v_pay NOT IN ('cash','chop_pay') THEN RAISE EXCEPTION 'INVALID_PAYMENT_MODE'; END IF;

  IF p_pickup_lat IS NULL OR p_pickup_lng IS NULL
     OR p_dest_lat IS NULL OR p_dest_lng IS NULL THEN
    RAISE EXCEPTION 'COORDINATES_REQUIRED';
  END IF;
  IF p_pickup_lat NOT BETWEEN 7 AND 13 OR p_pickup_lng NOT BETWEEN -15.5 AND -7
     OR p_dest_lat NOT BETWEEN 7 AND 13 OR p_dest_lng NOT BETWEEN -15.5 AND -7 THEN
    RAISE EXCEPTION 'COORDINATES_OUT_OF_SERVICE_AREA';
  END IF;

  -- Replay: same client request id always returns the same ride.
  SELECT * INTO v_prev FROM public.rides
   WHERE client_id = v_uid
     AND metadata->>'client_request_id' = p_client_request_id::text
   ORDER BY created_at
   LIMIT 1;
  IF v_prev.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status','already_created',
      'ride_id', v_prev.id,
      'fare_gnf', v_prev.fare_gnf,
      'hold_amount_gnf', COALESCE((v_prev.metadata->>'hold_amount_gnf')::bigint, 0),
      'payment_mode', public._ride_payment_mode(v_prev));
  END IF;

  -- No contradictory duplicate active Course request.
  PERFORM 1 FROM public.rides
   WHERE client_id = v_uid AND status IN ('pending','in_progress') LIMIT 1;
  IF FOUND THEN RAISE EXCEPTION 'ACTIVE_RIDE_EXISTS'; END IF;

  -- CRS-G1: fare is server-derived. There is no client fare parameter.
  v_fare := public.ride_compute_quote_gnf(
              p_mode, p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng);

  v_snap := public.finance_policy_snapshot(
              public._ride_mission_type(p_mode::text), now(), v_pay, v_fare, 0, 0, 0, false);

  -- CRS-G2: reservation is server-derived and placed through the LOCKED
  -- wallet_hold primitive inside this same transaction.
  IF v_pay = 'chop_pay' THEN
    v_hold := ceil((v_fare::numeric * C_RESERVATION_BUFFER_BPS) / 10000)::bigint;
    SELECT * INTO v_hold_tx FROM public.wallet_hold(
      p_amount_gnf := v_hold,
      p_reference  := 'ride_request:' || p_client_request_id::text,
      p_description := 'Réservation course ' || p_mode::text);
    IF v_hold_tx.id IS NULL THEN RAISE EXCEPTION 'HOLD_FAILED'; END IF;
  END IF;

  INSERT INTO public.rides (
    client_id, driver_id, mode, pickup_lat, pickup_lng, dest_lat, dest_lng,
    fare_gnf, hold_tx_id, status, metadata
  ) VALUES (
    v_uid, NULL, p_mode, p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng,
    v_fare,
    CASE WHEN v_pay = 'chop_pay' THEN v_hold_tx.id ELSE NULL END,
    'pending',
    jsonb_strip_nulls(jsonb_build_object(
      'client_request_id', p_client_request_id::text,
      'payment_mode', v_pay,
      'fare_source', 'server:ride_compute_quote_gnf',
      'fare_authority', 'server',
      'request_channel', 'ride_request_create',
      'reservation_buffer_bps', CASE WHEN v_pay='chop_pay' THEN C_RESERVATION_BUFFER_BPS END,
      'hold_amount_gnf', CASE WHEN v_pay='chop_pay' THEN v_hold END,
      'pickup_label', p_pickup_label,
      'dest_label', p_dest_label,
      'finance_snapshot', v_snap))
  ) RETURNING * INTO v_ride;

  RETURN jsonb_build_object(
    'status','created',
    'ride_id', v_ride.id,
    'fare_gnf', v_fare,
    'hold_amount_gnf', v_hold,
    'payment_mode', v_pay,
    'currency','GNF',
    'fare_source','server:ride_compute_quote_gnf');
END;
$function$;

REVOKE ALL ON FUNCTION public.ride_request_create(public.ride_mode,numeric,numeric,numeric,numeric,text,uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ride_request_create(public.ride_mode,numeric,numeric,numeric,numeric,text,uuid,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.ride_request_create(public.ride_mode,numeric,numeric,numeric,numeric,text,uuid,text,text) TO authenticated, service_role;

-- 3) Legacy path closure: ride_create keeps its signature for internal
--    compatibility but can no longer be steered by a client-supplied fare or
--    an unrelated hold, and is no longer reachable by `authenticated`.
CREATE OR REPLACE FUNCTION public.ride_create(
  p_mode public.ride_mode,
  p_pickup_lat numeric,
  p_pickup_lng numeric,
  p_dest_lat numeric,
  p_dest_lng numeric,
  p_fare_gnf bigint,
  p_hold_tx_id uuid,
  p_driver_id uuid DEFAULT NULL::uuid
)
RETURNS public.rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid  uuid := auth.uid();
  v_ride public.rides;
  v_fare bigint;
  v_pay  text;
  v_hold public.wallet_transactions;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  -- CRS-G1: the client-supplied fare is ignored; server truth wins.
  v_fare := public.ride_compute_quote_gnf(
              p_mode, p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng);

  IF p_hold_tx_id IS NOT NULL THEN
    SELECT * INTO v_hold FROM public.wallet_transactions WHERE id = p_hold_tx_id;
    IF v_hold.id IS NULL
       OR v_hold.type <> 'hold'
       OR v_hold.status <> 'pending'
       OR NOT EXISTS (SELECT 1 FROM public.wallets w
                       WHERE w.id = v_hold.from_wallet_id AND w.owner_user_id = v_uid)
       OR EXISTS (SELECT 1 FROM public.rides r WHERE r.hold_tx_id = p_hold_tx_id) THEN
      RAISE EXCEPTION 'INVALID_HOLD_REFERENCE';
    END IF;
  END IF;

  v_pay := CASE WHEN p_hold_tx_id IS NOT NULL THEN 'chop_pay' ELSE 'cash' END;

  INSERT INTO public.rides (
    client_id, driver_id, mode, pickup_lat, pickup_lng, dest_lat, dest_lng,
    fare_gnf, hold_tx_id, status, metadata
  ) VALUES (
    v_uid, p_driver_id, p_mode, p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng,
    v_fare, p_hold_tx_id, 'pending',
    jsonb_build_object(
      'payment_mode', v_pay,
      'fare_source', 'server:ride_compute_quote_gnf',
      'fare_authority', 'server',
      'request_channel', 'ride_create_legacy',
      'finance_snapshot', public.finance_policy_snapshot(
        public._ride_mission_type(p_mode::text), now(), v_pay, v_fare, 0, 0, 0, false))
  ) RETURNING * INTO v_ride;

  RETURN v_ride;
END;
$function$;

REVOKE ALL ON FUNCTION public.ride_create(public.ride_mode,numeric,numeric,numeric,numeric,bigint,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ride_create(public.ride_mode,numeric,numeric,numeric,numeric,bigint,uuid,uuid) FROM anon;
REVOKE ALL ON FUNCTION public.ride_create(public.ride_mode,numeric,numeric,numeric,numeric,bigint,uuid,uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.ride_create(public.ride_mode,numeric,numeric,numeric,numeric,bigint,uuid,uuid) TO service_role;

-- 4) Dedicated Node 0 regression harness (self-rolling-back; no residue).
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
  v_quote bigint; v_expect_hold bigint;
  v_held0 bigint; v_held1 bigint; v_bal0 bigint; v_bal1 bigint;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_n int; v_snapbps int; v_snapfix bigint; v_comm bigint;
  v_args text;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  -- static authority assertions (no fixtures required)
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

    -- ---------- CHOP PAY COMPLETION ECONOMICS ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.ride_accept(v_ride.id);
    BEGIN PERFORM public.ride_confirm_pickup(v_ride.id, '000000'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N9.1 wrong pickup code refused', v_err <> 'NO_ERROR', v_err);

    v_snapbps := COALESCE((v_ride.metadata->'finance_snapshot'->>'commission_bps')::int,0);
    v_snapfix := COALESCE((v_ride.metadata->'finance_snapshot'->>'fixed_commission_gnf')::bigint,0);
    v_comm := (v_ride.fare_gnf * v_snapbps) / 10000 + v_snapfix;
    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    PERFORM public.ride_complete(v_ride.id, NULL, NULL);
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';

    r := r || public._qa_s13_ok('N6.2 chop_pay completion captured through locked primitives',
          v_ride2.status = 'completed' AND v_ride2.payment_tx_id IS NOT NULL, v_ride2.status::text);
    r := r || public._qa_s13_ok('N7.2 completion economics derive from the frozen snapshot',
          v_bal1 - v_bal0 = v_ride.fare_gnf - v_comm,
          (v_bal1 - v_bal0)::text || ' expected ' || (v_ride.fare_gnf - v_comm)::text);
    PERFORM public.ride_complete(v_ride.id, NULL, NULL);
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s13_ok('N9.2 duplicate completion moved zero additional GNF',
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

REVOKE ALL ON FUNCTION public._qa_node0_course() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._qa_node0_course() FROM anon;
REVOKE ALL ON FUNCTION public._qa_node0_course() FROM authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node0_course() TO service_role;