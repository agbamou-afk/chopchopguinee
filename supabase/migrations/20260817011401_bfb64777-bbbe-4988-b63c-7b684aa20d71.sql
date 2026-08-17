TRUNCATE public._qa_r65_trace;
DO $$
DECLARE v_buy uuid := gen_random_uuid(); v_json jsonb; v_err text; v_r1 uuid; v_k uuid := gen_random_uuid();
        v_b1 jsonb; v_k3 uuid := gen_random_uuid(); v_log text := '';
BEGIN
  BEGIN
    PERFORM public._qa_s13_user(v_buy,'r65dbg');
    PERFORM public._qa_s13_wallet(v_buy,'client',5000000,0);
    v_b1 := jsonb_build_array(jsonb_build_object('commodity_code','rice','variant_code','local','option_code','kg','qty',4));
    PERFORM set_config('request.jwt.claims','',true);
    FOR i IN 1..6 LOOP
      PERFORM public.marche_procurement_observation_record(jsonb_build_object(
        'commodity_code','rice','variant_code','local','option_code','kg','unit_price_gnf',12000,'source','qa'));
    END LOOP;
    v_log := v_log || 'obs_ok;';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_json := public.marche_procurement_quote(jsonb_build_object('lines', v_b1));
    v_log := v_log || 'quote=' || COALESCE(v_json->>'estimate_status','?') || '/' || COALESCE(v_json->>'estimated_subtotal_gnf','?') || ';';
    v_json := public.marche_procurement_authorize(jsonb_build_object('lines',v_b1,'client_request_id',v_k,'authorized_ceiling_gnf',60000));
    v_r1 := (v_json->>'id')::uuid;
    v_log := v_log || 'auth_ok;';
    v_json := public.marche_procurement_increase(jsonb_build_object('request_id',v_r1,'client_request_id',v_k3,'new_ceiling_gnf',100000));
    v_log := v_log || 'inc_ok;';
    v_json := public.marche_procurement_increase(jsonb_build_object('request_id',v_r1,'client_request_id',v_k3,'new_ceiling_gnf',100000));
    v_log := v_log || 'replay=' || COALESCE(v_json->>'replayed','?') || ';';
    BEGIN PERFORM public.marche_procurement_increase(jsonb_build_object('request_id',v_r1,'client_request_id',v_k3,'new_ceiling_gnf',120000));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    v_log := v_log || 'conflict=' || v_err || ';';
    v_log := v_log || 'uid_after=' || COALESCE(auth.uid()::text,'NULL') || ';';
    RAISE EXCEPTION 'DBG_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'DBG_ROLLBACK' THEN v_log := v_log || 'ABORT:' || SQLERRM; END IF;
  END;
  INSERT INTO public._qa_r65_trace(ok,label,detail) VALUES (true,'dbg', v_log);
END $$;