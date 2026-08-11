-- ===== SLICE 13 QA HARNESS · shared infrastructure + PART 1 (stage gate isolation) =====
CREATE TABLE IF NOT EXISTS public._qa_s13_results (
  id bigserial PRIMARY KEY, part int NOT NULL, result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE public._qa_s13_results ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public._qa_s13_results FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_s13_ok(p_label text, p_ok boolean, p_detail text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT jsonb_build_array(jsonb_build_object('label',p_label,'ok',COALESCE(p_ok,false),'detail',p_detail));
$$;
REVOKE ALL ON FUNCTION public._qa_s13_ok(text,boolean,text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_s13_user(p_id uuid, p_tag text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                          created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
  VALUES ('00000000-0000-0000-0000-000000000000', p_id, 'authenticated','authenticated',
          'qa-s13-'||p_tag||'-'||substr(p_id::text,1,8)||'@qa.invalid','x', now(), now(),
          '{"provider":"email"}'::jsonb, '{}'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public._qa_s13_user(uuid,text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_s13_flag(p_key text, p_val boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.feature_flags(key, enabled) VALUES (p_key, p_val)
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled;
END $$;
REVOKE ALL ON FUNCTION public._qa_s13_flag(text,boolean) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_s13_summary(p_part int, r jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE v_pass int; v_total int;
BEGIN
  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total
    FROM jsonb_array_elements(r) x;
  INSERT INTO public._qa_s13_results(part, result) VALUES (p_part, r);
  RETURN jsonb_build_object('part',p_part,'total',v_total,'passed',v_pass,'failed',v_total-v_pass,
    'failures',(SELECT COALESCE(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(r) x
                WHERE NOT (x->>'ok')::boolean));
END $$;
REVOKE ALL ON FUNCTION public._qa_s13_summary(int,jsonb) FROM PUBLIC, anon, authenticated;

-- ---------- PART 1: every stage independently server-gated ----------
CREATE OR REPLACE FUNCTION public._qa_s13_run1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_drv uuid; v_mer uuid; v_store uuid;
  v_err text; v_res jsonb; v_master0 bigint; v_master1 bigint;
  v_flags0 jsonb; v_flags1 jsonb;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  BEGIN
    v_cust := gen_random_uuid(); v_drv := gen_random_uuid(); v_mer := gen_random_uuid();
    PERFORM public._qa_s13_user(v_cust,'cust');
    PERFORM public._qa_s13_user(v_drv,'drv');
    PERFORM public._qa_s13_user(v_mer,'mer');
    INSERT INTO public.wallets(owner_user_id, party_type, balance_gnf, held_gnf)
    VALUES (v_cust,'client',900000,0),(v_drv,'driver',900000,0);
    INSERT INTO public.driver_profiles(user_id,status,vehicle_type) VALUES (v_drv,'approved','moto');

    -- ============ 1A. all stages OFF (live posture) ============
    -- Stage 7 · P2P
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN v_res := to_jsonb(public.wallet_p2p_transfer(v_drv, 1000, 'qa', 'qa-s13-p2p-1')); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G1.1 Stage7 OFF blocks wallet_p2p_transfer at mutation point',
      v_err LIKE '%STAGE_DISABLED:chop_pay_p2p_enabled%', v_err);

    -- Stage 6 · driver payout
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN v_res := public.driver_payout_request_create(50000,'+224600000001','qa-s13-po-1'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G1.2 Stage6 OFF blocks driver_payout_request_create',
      v_err LIKE '%STAGE_DISABLED:driver_cashout_enabled%', v_err);
    BEGIN PERFORM public.driver_cashout_create_request(50000,'+224600000001','qa'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G1.3 Stage6 OFF blocks legacy driver_cashout_create_request',
      v_err LIKE '%STAGE_DISABLED:driver_cashout_enabled%', v_err);
    BEGIN PERFORM public.driver_cashout_mark_paid(gen_random_uuid(),'QA-REF','qa'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G1.4 Stage6 OFF blocks legacy driver_cashout_mark_paid',
      v_err LIKE '%STAGE_DISABLED:driver_cashout_enabled%', v_err);
    BEGIN v_res := public.driver_payout_confirm(gen_random_uuid(),'QA-REF'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G1.5 Stage6 OFF blocks driver_payout_confirm',
      v_err LIKE '%STAGE_DISABLED:driver_cashout_enabled%', v_err);

    -- Stage 5 · merchant settlement (legacy paths must stay retired)
    BEGIN v_res := public.merchant_settlement_complete(gen_random_uuid(),'QA-REF'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G1.6 legacy merchant_settlement_complete retired',
      v_err LIKE '%LEGACY_PATH_DISABLED%', v_err);
    BEGIN v_res := public.merchant_settlement_hold(gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G1.7 legacy merchant_settlement_hold retired',
      v_err LIKE '%LEGACY_PATH_DISABLED%', v_err);
    BEGIN v_res := public.merchant_settlement_fail(gen_random_uuid(),'qa'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G1.8 legacy merchant_settlement_fail retired',
      v_err LIKE '%LEGACY_PATH_DISABLED%', v_err);

    -- ============ 1B. surface-only flags must never imply a stage ============
    PERFORM public._qa_s13_flag('chop_pay_enabled', true);
    PERFORM public._qa_s13_flag('wallet_public_enabled', true);
    PERFORM public._qa_s13_flag('chop_pay_balance_enabled', true);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN v_res := to_jsonb(public.wallet_p2p_transfer(v_drv, 1000, 'qa', 'qa-s13-p2p-2')); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G2.1 surface flag chop_pay_enabled does NOT imply Stage7',
      v_err LIKE '%STAGE_DISABLED:chop_pay_p2p_enabled%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN v_res := public.driver_payout_request_create(50000,'+224600000001','qa-s13-po-2'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G2.2 surface flag chop_pay_enabled does NOT imply Stage6',
      v_err LIKE '%STAGE_DISABLED:driver_cashout_enabled%', v_err);

    -- ============ 1C. Stage 4 ON must not imply siblings 5/6/7 ============
    PERFORM public._qa_s13_flag('chop_pay_checkout_enabled', true);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN v_res := to_jsonb(public.wallet_p2p_transfer(v_drv, 1000, 'qa', 'qa-s13-p2p-3')); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G3.1 Stage4 ON does NOT imply Stage7 P2P',
      v_err LIKE '%STAGE_DISABLED:chop_pay_p2p_enabled%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN v_res := public.driver_payout_request_create(50000,'+224600000001','qa-s13-po-3'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G3.2 Stage4 ON does NOT imply Stage6 payout',
      v_err LIKE '%STAGE_DISABLED:driver_cashout_enabled%', v_err);
    BEGIN v_res := public.cash_order_accept('food_orders', gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G3.3 Stage4 ON does NOT enable Stage2 cash-order funding',
      v_err NOT LIKE 'NO_ERROR', v_err);

    -- ============ 1D. Stage 7 ON alone must not imply Stage 5/6 ============
    PERFORM public._qa_s13_flag('chop_pay_checkout_enabled', false);
    PERFORM public._qa_s13_flag('chop_pay_p2p_enabled', true);
    BEGIN v_res := public.driver_payout_request_create(50000,'+224600000001','qa-s13-po-4'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G4.1 Stage7 ON does NOT imply Stage6 payout',
      v_err LIKE '%STAGE_DISABLED:driver_cashout_enabled%', v_err);

    -- ============ 1E. Stage 6 ON alone must not imply Stage 5 or Stage 7 ============
    PERFORM public._qa_s13_flag('chop_pay_p2p_enabled', false);
    PERFORM public._qa_s13_flag('driver_cashout_enabled', true);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN v_res := to_jsonb(public.wallet_p2p_transfer(v_drv, 1000, 'qa', 'qa-s13-p2p-5')); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G5.1 Stage6 ON does NOT imply Stage7 P2P',
      v_err LIKE '%STAGE_DISABLED:chop_pay_p2p_enabled%', v_err);

    PERFORM public._qa_s13_flag('driver_cashout_enabled', false);

    RAISE EXCEPTION 'QA_S13_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S13_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS_PART1_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', '', true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z1.1 master wallet DEF-FIN-001 unchanged (-100435)',
    v_master1 = v_master0 AND v_master1 = -100435, v_master1::text);
  r := r || public._qa_s13_ok('Z1.2 live feature flags byte-identical after fixture rollback',
    v_flags1 = v_flags0, NULL);

  RETURN public._qa_s13_summary(1, r);
END $$;
REVOKE ALL ON FUNCTION public._qa_s13_run1() FROM PUBLIC, anon, authenticated;