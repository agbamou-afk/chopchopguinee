CREATE OR REPLACE FUNCTION public._qa_node1_bonbonna_sweeper()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_res jsonb; v_req uuid; v_n int;
  v_ride public.rides; v_ride2 public.rides;
  v_held0 bigint; v_held1 bigint; v_err text;
  v_master0 bigint; v_master1 bigint;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;

  BEGIN
    v_cust := gen_random_uuid();
    PERFORM public._qa_s13_user(v_cust,'n1s');
    PERFORM public._qa_s13_wallet(v_cust,'client',3000000,0);

    -- ---------- AUTONOMOUS SWEEP (no customer device involved) ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    SELECT held_gnf INTO v_held0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    v_req := gen_random_uuid();
    v_res := public.ride_request_create('toktok',9.5370,-13.6785,9.5700,-13.6200,
              'chop_pay', v_req, NULL, NULL);
    SELECT * INTO v_ride FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    r := r || public._qa_s13_ok('B8.0 chop_pay booking records the payment mode for receipt truth',
          v_ride.metadata->>'payment_mode' IN ('chop_pay','choppay'),
          v_ride.metadata->>'payment_mode');

    UPDATE public.rides SET created_at = now() - interval '90 seconds' WHERE id=v_ride.id;
    -- No session at all: exactly how the scheduler runs.
    PERFORM set_config('request.jwt.claims', ''::text, true);
    v_res := public.ride_sweep_unfulfilled(500);
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    SELECT held_gnf INTO v_held1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';

    r := r || public._qa_s13_ok('B8.1 sweeper closes an abandoned search with no client device',
          v_ride2.status='cancelled'
          AND v_ride2.metadata->>'cancel_reason'='no_driver_available'
          AND v_ride2.metadata->>'cancelled_by'='system', v_ride2.status::text);
    r := r || public._qa_s13_ok('B8.2 sweeper releases the reservation in full',
          v_held1 = v_held0, (v_held1 - v_held0)::text);
    r := r || public._qa_s13_ok('B8.3 sweeper charges zero cancellation fee',
          COALESCE((v_ride2.metadata->>'cancellation_fee_gnf')::bigint,0) = 0,
          v_ride2.metadata->>'cancellation_fee_gnf');
    SELECT count(*) INTO v_n FROM public.ride_offers
      WHERE ride_id=v_ride.id AND status='pending';
    r := r || public._qa_s13_ok('B8.4 sweeper leaves no pending offer', v_n=0, v_n::text);

    SELECT held_gnf INTO v_held0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    PERFORM public.ride_sweep_unfulfilled(500);
    SELECT held_gnf INTO v_held1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('B8.5 repeated sweeps are idempotent and move zero GNF',
          v_held1 = v_held0, (v_held1 - v_held0)::text);

    -- ---------- FRESH SEARCH IS NOT SWEPT EARLY ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_req := gen_random_uuid();
    v_res := public.ride_request_create('toktok',9.5370,-13.6785,9.5700,-13.6200,
              'cash', v_req, NULL, NULL);
    SELECT * INTO v_ride FROM public.rides WHERE id=(v_res->>'ride_id')::uuid;
    r := r || public._qa_s13_ok('B8.6 cash booking records the payment mode for receipt truth',
          v_ride.metadata->>'payment_mode' = 'cash', v_ride.metadata->>'payment_mode');
    PERFORM set_config('request.jwt.claims', ''::text, true);
    PERFORM public.ride_sweep_unfulfilled(500);
    SELECT * INTO v_ride2 FROM public.rides WHERE id=v_ride.id;
    r := r || public._qa_s13_ok('B8.7 a search younger than 60s survives the sweeper',
          v_ride2.status='pending', v_ride2.status::text);

    -- ---------- AUTHORIZATION ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN PERFORM public.ride_sweep_unfulfilled(10); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B9.1 an ordinary user cannot run the sweeper',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);
    PERFORM set_config('request.jwt.claims', ''::text, true);

    RAISE EXCEPTION 'QA_NODE1_SWEEP_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE1_SWEEP_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS(sweeper) aborted before completion', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', ''::text, true);

  r := r || public._qa_s13_ok('B9.2 sweeper not executable by anon',
        NOT has_function_privilege('anon','public.ride_sweep_unfulfilled(int)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('B9.3 sweeper not executable by authenticated',
        NOT has_function_privilege('authenticated','public.ride_sweep_unfulfilled(int)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('B9.4 internal expiry primitive not executable by authenticated',
        NOT has_function_privilege('authenticated','public._ride_expire_unfulfilled_internal(uuid)','EXECUTE'), NULL);
  SELECT count(*) INTO v_n FROM cron.job
    WHERE jobname='chopchop-ride-no-driver-sweep' AND active AND schedule='* * * * *';
  r := r || public._qa_s13_ok('B9.5 no-driver sweep is scheduled every minute', v_n = 1, v_n::text);

  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || public._qa_s13_ok('Z2.1 master wallet unchanged after sweeper fixtures',
        v_master0 IS NOT DISTINCT FROM v_master1, v_master1::text);
  SELECT count(*) INTO v_n FROM public.rides r2
    JOIN auth.users u ON u.id = r2.client_id WHERE u.email LIKE 'qa-s13-n1s%';
  r := r || public._qa_s13_ok('Z2.2 no sweeper fixture residue', v_n = 0, v_n::text);

  RETURN r;
END $function$;

REVOKE ALL ON FUNCTION public._qa_node1_bonbonna_sweeper() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_node1_bonbonna_full()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_base jsonb; r jsonb;
BEGIN
  v_base := public._qa_node1_bonbonna();
  r := (v_base->'results') || public._qa_node1_bonbonna_sweeper();
  RETURN jsonb_build_object(
    'part','node1_bonbonna_full',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END $function$;

REVOKE ALL ON FUNCTION public._qa_node1_bonbonna_full() FROM PUBLIC, anon, authenticated;