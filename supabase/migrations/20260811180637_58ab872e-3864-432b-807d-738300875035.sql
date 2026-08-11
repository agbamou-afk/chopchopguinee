-- Storage/RLS probes require a real role switch, which Postgres forbids inside
-- SECURITY DEFINER functions. Both QA entry points therefore run as INVOKER
-- (they remain service_role-only).
DROP FUNCTION IF EXISTS public._qa_s13_rls_probe(text, uuid, text, text, text);

CREATE FUNCTION public._qa_s13_rls_probe(p_role text, p_uid uuid, p_op text,
                                         p_bucket text, p_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public'
AS $function$
DECLARE v_n bigint := -1; v_err text := 'NO_ERROR';
BEGIN
  PERFORM set_config('request.jwt.claims',
    CASE WHEN p_uid IS NULL THEN '' ELSE public._as_user_claims(p_uid) END, true);
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  BEGIN
    IF p_op = 'select' THEN
      SELECT count(*) INTO v_n FROM storage.objects o
       WHERE o.bucket_id = p_bucket AND o.name = p_name;
    ELSIF p_op = 'insert' THEN
      INSERT INTO storage.objects(bucket_id, name, owner, owner_id)
      VALUES (p_bucket, p_name, p_uid, p_uid::text);
      v_n := 1;
    ELSIF p_op = 'update' THEN
      UPDATE storage.objects SET metadata = COALESCE(metadata,'{}'::jsonb) || '{"qa":true}'::jsonb
       WHERE bucket_id = p_bucket AND name = p_name;
      GET DIAGNOSTICS v_n = ROW_COUNT;
    ELSIF p_op = 'delete' THEN
      DELETE FROM storage.objects WHERE bucket_id = p_bucket AND name = p_name;
      GET DIAGNOSTICS v_n = ROW_COUNT;
    ELSIF p_op = 'photos' THEN
      SELECT count(*) INTO v_n FROM public.package_evidence_photos WHERE storage_path = p_name;
    ELSE
      v_err := 'unknown_op';
    END IF;
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN jsonb_build_object('count', v_n, 'error', v_err);
END $function$;

REVOKE ALL ON FUNCTION public._qa_s13_rls_probe(text, uuid, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s13_rls_probe(text, uuid, text, text, text) TO service_role;

DROP FUNCTION IF EXISTS public._qa_s13_run4();

CREATE FUNCTION public._qa_s13_run4()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_drv uuid; v_god uuid; v_sfx text; v_other uuid;
  v_err text; v_n bigint; v_res jsonb; v_q jsonb; v_qid uuid; v_fee bigint;
  v_pkg uuid; v_mis uuid; v_rt public.package_runtime;
  v_pkg2 uuid; v_mis2 uuid; v_rt2 public.package_runtime; v_qid2 uuid;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_bal0 bigint; v_bal1 bigint; v_held bigint; v_mw0 bigint; v_mw bigint;
  v_pcode text; v_dcode text; v_claim uuid; v_auth bigint; v_state text;
  v_ceiling bigint; v_qidA uuid; v_j0 bigint; v_j1 bigint; v_path text;
  v_probe jsonb; v_obj text;
  v_drv3 uuid; v_drv4 uuid; v_drvA uuid; v_drvB uuid; v_drvC uuid; v_drvS uuid;
  v_pkg3 uuid; v_mis3 uuid; v_rt3 public.package_runtime; v_qid3 uuid;
  v_pkg4 uuid; v_mis4 uuid; v_qid4 uuid;
  v_pkgA uuid; v_pkgB uuid; v_pkgC uuid; v_pkgS uuid;
  v_misA uuid; v_misB uuid; v_misC uuid; v_misS uuid;
  v_rtA public.package_runtime; v_rtB public.package_runtime; v_rtC public.package_runtime;
  v_dheld0 bigint; v_dheld1 bigint; v_dbal0 bigint; v_dbal1 bigint;
  v_cheld0 bigint; v_cheld1 bigint; v_cbal0 bigint; v_cbal1 bigint;
  v_pol uuid; v_prodj0 bigint; v_prodj1 bigint; v_int uuid; v_intS uuid;
  v_relp bigint; v_relu bigint; v_hp bigint; v_hu bigint; v_can0 timestamptz;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  BEGIN
    v_cust := gen_random_uuid(); v_drv := gen_random_uuid(); v_god := gen_random_uuid();
    v_other := gen_random_uuid();
    v_sfx := substr(replace(gen_random_uuid()::text,'-',''),1,10);
    PERFORM public._qa_s13_user(v_cust,'ec'); PERFORM public._qa_s13_user(v_drv,'ed');
    PERFORM public._qa_s13_user(v_god,'eg'); PERFORM public._qa_s13_user(v_other,'eo');
    INSERT INTO public.user_roles(user_id, role) VALUES (v_god,'god_admin') ON CONFLICT DO NOTHING;
    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,id_doc_url,vehicle_photo_url)
    VALUES (v_drv,'approved','moto','x','y')
    ON CONFLICT (user_id) DO UPDATE SET status='approved';
    UPDATE public.driver_profiles
       SET capabilities = ARRAY['rides_moto','repas_delivery','marche_delivery','package_delivery']
     WHERE user_id = v_drv;
    PERFORM public._qa_s13_wallet(v_cust,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_drv,'driver',900000,0);

    v_drv3 := gen_random_uuid(); v_drv4 := gen_random_uuid();
    v_drvA := gen_random_uuid(); v_drvB := gen_random_uuid();
    v_drvC := gen_random_uuid(); v_drvS := gen_random_uuid();
    PERFORM public._qa_s13_driver(v_drv3,'ed3',900000);
    PERFORM public._qa_s13_driver(v_drv4,'ed4',900000);
    PERFORM public._qa_s13_driver(v_drvA,'eda',900000);
    PERFORM public._qa_s13_driver(v_drvB,'edb',900000);
    PERFORM public._qa_s13_driver(v_drvC,'edc',900000);
    PERFORM public._qa_s13_driver(v_drvS,'eds',900000);

    PERFORM public._qa_s13_flag('envoyer_enabled', true);
    PERFORM public._qa_s13_flag('envoyer_declared_value_enabled', true);
    PERFORM public._qa_s13_flag('envoyer_claims_enabled', true);
    PERFORM public._qa_s13_flag('chop_pay_enabled', true);
    PERFORM public._qa_s13_flag('chop_pay_checkout_enabled', true);
    PERFORM public._qa_s13_flag('driver_balance_gate_enabled', true);
    PERFORM public._qa_s13_flag('om_sandbox_enabled', true);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);

    -- ---------- F1: declared-value gates ----------
    v_q := public.package_delivery_quote(9.5370, -13.6785, 9.5560, -13.6600, 'small_parcel', 'A', 'B');
    v_qid := (v_q->>'quote_id')::uuid;
    v_fee := (v_q->>'amount_gnf')::bigint;
    r := r || public._qa_s13_ok('F1.0 Envoyer quote returns a server-priced delivery fee',
      v_qid IS NOT NULL AND v_fee > 0, v_q::text);

    BEGIN v_res := public.package_delivery_create_checkout(v_qid,'Ami Diallo','622000001',
      NULL,NULL,'k1-'||v_sfx,'622000002','orange_money',false,NULL, 500000, NULL, true,
      'Je declare la valeur de mon colis'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F1.1 shipment without an explicit tender is refused',
      v_err <> 'NO_ERROR', v_err);

    BEGIN v_res := public.package_delivery_create_checkout(v_qid,'Ami Diallo','622000001',
      NULL,NULL,'k2-'||v_sfx,'622000002','orange_money',false,NULL, NULL, 'chop_pay', true,
      'Je declare la valeur de mon colis'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F1.2 shipment without a declared value is refused',
      v_err <> 'NO_ERROR', v_err);

    BEGIN v_res := public.package_delivery_create_checkout(v_qid,'Ami Diallo','622000001',
      NULL,NULL,'k3-'||v_sfx,'622000002','orange_money',false,NULL, 500000, 'chop_pay', false,
      NULL); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F1.3 shipment without a value attestation is refused',
      v_err <> 'NO_ERROR', v_err);

    BEGIN v_res := public.package_delivery_create_checkout(v_qid,'Ami Diallo','622000001',
      NULL,NULL,'k4-'||v_sfx,'622000002','orange_money',false,NULL, 500000, 'chop_pay', true,
      'Je declare la valeur de mon colis'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F1.4 shipment without evidence photos is refused',
      v_err = 'SHIPMENT_PHOTOS_REQUIRED', v_err);

    SELECT count(*) INTO v_n FROM public.package_runtime WHERE customer_user_id = v_cust;
    r := r || public._qa_s13_ok('F1.5 refusals created no shipment runtime, hold or journal',
      v_n = 0, v_n::text);

    v_path := v_cust::text||'/'||v_qid::text||'/p1.jpg';
    PERFORM public.package_evidence_register(v_qid, v_path, 'item','image/jpeg',1024);

    BEGIN v_res := public.package_delivery_create_checkout(v_qid,'Ami Diallo','622000001',
      NULL,NULL,'k5-'||v_sfx,'622000002','orange_money',false,NULL, 999000000, 'chop_pay', true,
      'Je declare la valeur de mon colis'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F1.6 declared value above the policy ceiling is refused',
      v_err <> 'NO_ERROR', v_err);
    SELECT count(*) INTO v_n FROM public.package_runtime WHERE customer_user_id = v_cust;
    r := r || public._qa_s13_ok('F1.7 ceiling refusal created no shipment', v_n = 0, v_n::text);

    -- ===== CLOSEOUT 1: exact authoritative ceiling boundary =====
    SELECT max_declared_value_gnf INTO v_ceiling FROM public.finance_policy_at('envoyer');
    r := r || public._qa_s13_ok('F1.8 the declared-value ceiling is read from the authoritative policy',
      v_ceiling IS NOT NULL AND v_ceiling > 0, COALESCE(v_ceiling::text,'null'));

    v_q := public.package_delivery_quote(9.5370, -13.6785, 9.5510, -13.6650, 'small_parcel', 'A', 'B2');
    v_qidA := (v_q->>'quote_id')::uuid;
    PERFORM public.package_evidence_register(v_qidA, v_cust::text||'/'||v_qidA::text||'/p1.jpg',
      'item','image/jpeg',1024);
    SELECT count(*) INTO v_j0 FROM public.ledger_journals;
    BEGIN v_res := public.package_delivery_create_checkout(v_qidA,'Ami Diallo','622000001',
      NULL,NULL,'kb-'||v_sfx,'622000002','orange_money',false,NULL, v_ceiling + 1, 'chop_pay', true,
      'Je declare la valeur de mon colis'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F1.9 declared value of exactly ceiling + 1 GNF is refused',
      v_err <> 'NO_ERROR', format('ceiling=%s err=%s', v_ceiling, v_err));
    SELECT count(*) INTO v_j1 FROM public.ledger_journals;
    SELECT count(*) INTO v_n FROM public.package_runtime WHERE customer_user_id = v_cust;
    r := r || public._qa_s13_ok('F1.10 ceiling+1 refusal created no runtime, mission, hold or journal',
      v_n = 0 AND v_j1 = v_j0
      AND NOT EXISTS (SELECT 1 FROM public.missions WHERE customer_id = v_cust)
      AND NOT EXISTS (SELECT 1 FROM public.mission_financial_holds
                       WHERE source_module='package' AND party_user_id IN (v_cust, v_drv)),
      format('runtime=%s journals %s->%s', v_n, v_j0, v_j1));

    -- ---------- F2: authorized Chop Pay shipment (exactly at the ceiling) ----------
    BEGIN v_res := public.package_delivery_create_checkout(v_qid,'Ami Diallo','622000001',
      NULL,NULL,'k6-'||v_sfx,'622000002','orange_money',false,NULL, v_ceiling, 'chop_pay', true,
      'Je declare la valeur de mon colis'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb; END;
    v_pkg := (v_res->>'package_id')::uuid;
    v_int := (v_res->>'payment_intent_id')::uuid;
    r := r || public._qa_s13_ok('F2.0 fully attested shipment is authorized',
      v_err = 'NO_ERROR' AND v_pkg IS NOT NULL, format('%s %s', v_err, v_res::text));

    SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = v_pkg;
    r := r || public._qa_s13_ok('F1.11 a declared value of exactly the ceiling is accepted',
      v_rt.declared_value_gnf = v_ceiling,
      format('declared=%s ceiling=%s', v_rt.declared_value_gnf, v_ceiling));
    r := r || public._qa_s13_ok('F2.1 customer holds delivery fee + platform fee only',
      v_rt.customer_hold_gnf = v_rt.delivery_fee_gnf + v_rt.platform_fee_gnf,
      format('hold=%s fee=%s pf=%s', v_rt.customer_hold_gnf, v_rt.delivery_fee_gnf, v_rt.platform_fee_gnf));
    r := r || public._qa_s13_ok('F2.2 declared value is never charged to the customer',
      v_rt.customer_hold_gnf < v_rt.declared_value_gnf, v_rt.customer_hold_gnf::text);
    r := r || public._qa_s13_ok('F2.3 claims exposure never exceeds declared value minus collateral',
      v_rt.claims_exposure_gnf <= GREATEST(v_rt.declared_value_gnf - v_rt.collateral_gnf, 0),
      format('exp=%s dv=%s col=%s', v_rt.claims_exposure_gnf, v_rt.declared_value_gnf, v_rt.collateral_gnf));
    SELECT COALESCE(sum(GREATEST(amount_gnf-captured_gnf-released_gnf,0)),0) INTO v_n
      FROM public.mission_financial_holds
     WHERE source_module = 'package' AND source_id = v_pkg AND kind = 'customer_payment';
    r := r || public._qa_s13_ok('F2.4 customer hold is real and open on the shipment',
      v_n = v_rt.customer_hold_gnf, format('%s vs %s', v_n, v_rt.customer_hold_gnf));

    SELECT mission_id INTO v_mis FROM public.package_deliveries WHERE id = v_pkg;
    r := r || public._qa_s13_ok('F2.5 authorization dispatched a mission', v_mis IS NOT NULL, v_mis::text);

    -- ===== CLOSEOUT 2: evidence photo / storage privacy =====
    v_obj := v_path;
    INSERT INTO storage.objects(bucket_id, name, owner, owner_id, metadata)
    VALUES ('package-evidence', v_obj, v_cust, v_cust::text, '{"size":1024}'::jsonb)
    ON CONFLICT DO NOTHING;

    SELECT NOT public INTO v_err FROM storage.buckets WHERE id = 'package-evidence';
    r := r || public._qa_s13_ok('G1.1 the package-evidence bucket is private',
      COALESCE(v_err::boolean,false), v_err);

    SELECT count(*) INTO v_n FROM pg_policies
     WHERE schemaname='storage' AND tablename='objects'
       AND cmd IN ('UPDATE','DELETE','ALL')
       AND (COALESCE(qual,'') LIKE '%package-evidence%' OR COALESCE(with_check,'') LIKE '%package-evidence%');
    r := r || public._qa_s13_ok('G1.2 no policy lets any client update or delete evidence objects',
      v_n = 0, v_n::text);

    v_probe := public._qa_s13_rls_probe('authenticated', v_cust, 'select', 'package-evidence', v_obj);
    r := r || public._qa_s13_ok('G1.3 the owning sender can read their own evidence object',
      (v_probe->>'count')::bigint = 1 AND v_probe->>'error' = 'NO_ERROR', v_probe::text);

    v_probe := public._qa_s13_rls_probe('authenticated', v_other, 'select', 'package-evidence', v_obj);
    r := r || public._qa_s13_ok('G1.4 an unrelated authenticated user cannot read or list the object',
      (v_probe->>'count')::bigint = 0, v_probe::text);

    v_probe := public._qa_s13_rls_probe('anon', NULL, 'select', 'package-evidence', v_obj);
    r := r || public._qa_s13_ok('G1.5 an anonymous caller cannot read the object',
      COALESCE((v_probe->>'count')::bigint, 0) = 0, v_probe::text);

    v_probe := public._qa_s13_rls_probe('authenticated', v_other, 'update', 'package-evidence', v_obj);
    r := r || public._qa_s13_ok('G1.6 an unrelated authenticated user cannot replace the object',
      COALESCE((v_probe->>'count')::bigint, 0) = 0 OR v_probe->>'error' <> 'NO_ERROR', v_probe::text);

    v_probe := public._qa_s13_rls_probe('authenticated', v_other, 'delete', 'package-evidence', v_obj);
    r := r || public._qa_s13_ok('G1.7 an unrelated authenticated user cannot delete the object',
      COALESCE((v_probe->>'count')::bigint, 0) = 0 OR v_probe->>'error' <> 'NO_ERROR', v_probe::text);

    v_probe := public._qa_s13_rls_probe('authenticated', v_other, 'insert', 'package-evidence',
                 v_cust::text||'/'||v_qid::text||'/intruder.jpg');
    r := r || public._qa_s13_ok('G1.8 an unrelated authenticated user cannot upload into another sender folder',
      v_probe->>'error' <> 'NO_ERROR', v_probe::text);

    v_probe := public._qa_s13_rls_probe('authenticated', v_other, 'photos', 'package-evidence', v_obj);
    r := r || public._qa_s13_ok('G1.9 an unrelated authenticated user cannot read the evidence metadata row',
      COALESCE((v_probe->>'count')::bigint, 0) = 0, v_probe::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_other), true);
    BEGIN PERFORM public.package_evidence_register(v_qid, v_other::text||'/'||v_qid::text||'/x.jpg',
      'item','image/jpeg',1024); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G1.10 an unrelated user cannot register evidence against another quote',
      v_err <> 'NO_ERROR', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);

    -- ---------- F3: courier claim + collateral + custody ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN PERFORM public.mission_claim(v_mis); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT COALESCE(sum(amount_gnf),0) INTO v_held FROM public.mission_financial_holds
     WHERE source_module = 'package' AND source_id = v_pkg AND kind = 'collateral';
    r := r || public._qa_s13_ok('F3.1 courier collateral hold equals the frozen policy amount',
      v_err = 'NO_ERROR' AND v_held = v_rt.collateral_gnf,
      format('%s hold=%s frozen=%s', v_err, v_held, v_rt.collateral_gnf));

    SELECT pickup_code, delivery_code INTO v_pcode, v_dcode
      FROM public.package_delivery_secrets WHERE package_id = v_pkg;

    v_res := public.package_verify_pickup(v_pkg, '000000');
    r := r || public._qa_s13_ok('F3.2 wrong pickup code never establishes custody',
      COALESCE((v_res->>'ok')::boolean,false) = false, v_res::text);
    SELECT pickup_verified_at IS NULL INTO v_err FROM public.package_delivery_secrets WHERE package_id = v_pkg;
    r := r || public._qa_s13_ok('F3.3 shipment stays pre-custody after a failed code', v_err::boolean, v_err);

    v_res := public.package_verify_pickup(v_pkg, v_pcode);
    r := r || public._qa_s13_ok('F3.4 correct pickup code establishes custody',
      COALESCE((v_res->>'ok')::boolean,false), v_res::text);

    -- ---------- F4: cancellation locked once in custody ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN v_res := public.package_delivery_cancel(v_pkg, 'qa cancel test'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb; END;
    r := r || public._qa_s13_ok('F4.1 self-service cancellation refused once the courier has custody',
      v_err <> 'NO_ERROR' OR COALESCE(v_res->>'error','') = 'CUSTODY_ESTABLISHED_CLAIM_REQUIRED',
      format('%s %s', v_err, v_res::text));
    SELECT cancelled_at IS NULL INTO v_err FROM public.package_deliveries WHERE id = v_pkg;
    r := r || public._qa_s13_ok('F4.2 shipment remains live after the refused cancellation',
      v_err::boolean, v_err);

    -- ---------- F5: delivery + settlement ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    v_res := public.package_verify_delivery(v_pkg, '000000', 'Ami Diallo');
    r := r || public._qa_s13_ok('F5.1 wrong delivery code never completes a shipment',
      COALESCE((v_res->>'ok')::boolean,false) = false, v_res::text);

    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT balance_gnf INTO v_mw0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    v_res := public.package_verify_delivery(v_pkg, v_dcode, 'Ami Diallo');
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT balance_gnf INTO v_mw FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('F5.2 correct delivery code completes the shipment',
      COALESCE((v_res->>'ok')::boolean,false), v_res::text);
    r := r || public._qa_s13_ok('F5.3 courier is paid exactly the delivery fee',
      v_bal1 - v_bal0 = v_rt.delivery_fee_gnf, format('%s -> %s (fee %s)', v_bal0, v_bal1, v_rt.delivery_fee_gnf));
    r := r || public._qa_s13_ok('F5.4 platform fee captured to the master wallet',
      v_mw - v_mw0 = v_rt.platform_fee_gnf, format('%s -> %s (pf %s)', v_mw0, v_mw, v_rt.platform_fee_gnf));
    SELECT COALESCE(sum(GREATEST(amount_gnf-captured_gnf-released_gnf,0)),0) INTO v_n
      FROM public.mission_financial_holds WHERE source_module='package' AND source_id = v_pkg;
    r := r || public._qa_s13_ok('F5.5 no hold survives a completed shipment', v_n = 0, v_n::text);

    v_res := public.package_verify_delivery(v_pkg, v_dcode, 'Ami Diallo');
    SELECT balance_gnf INTO v_n FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s13_ok('F5.6 duplicate delivery confirmation moves 0 additional GNF',
      v_n = v_bal1, format('%s vs %s', v_n, v_bal1));

    -- ---------- F6: claims on a second shipment still in custody ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_q := public.package_delivery_quote(9.5370, -13.6785, 9.5600, -13.6500, 'small_parcel', 'A', 'C');
    v_qid2 := (v_q->>'quote_id')::uuid;
    PERFORM public.package_evidence_register(v_qid2, v_cust::text||'/'||v_qid2::text||'/p1.jpg',
      'item','image/jpeg',1024);
    v_res := public.package_delivery_create_checkout(v_qid2,'Ami Diallo','622000001',
      NULL,NULL,'k7-'||v_sfx,'622000002','orange_money',false,NULL, 400000, 'chop_pay', true,
      'Je declare la valeur de mon colis');
    v_pkg2 := (v_res->>'package_id')::uuid;
    SELECT * INTO v_rt2 FROM public.package_runtime WHERE package_id = v_pkg2;
    SELECT mission_id INTO v_mis2 FROM public.package_deliveries WHERE id = v_pkg2;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_mis2);
    SELECT pickup_code INTO v_pcode FROM public.package_delivery_secrets WHERE package_id = v_pkg2;
    PERFORM public.package_verify_pickup(v_pkg2, v_pcode);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    BEGIN v_res := public.claims_reserve_allocate('package', v_pkg2, 50000, 'evidence/x.jpg',
      'qa reserve before freeze', v_cust, v_drv, 400000, 'envoyer', false); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F6.1 no reserve can be authorised before the collateral is frozen',
      v_err <> 'NO_ERROR', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN v_res := public.package_claim_open(v_pkg2, 'colis endommage'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb; END;
    SELECT state INTO v_state FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id = v_pkg2 AND kind='collateral';
    r := r || public._qa_s13_ok('F6.2 opening a claim freezes the courier collateral',
      v_err = 'NO_ERROR' AND v_state = 'frozen', format('%s state=%s', v_err, v_state));
    SELECT claim_state INTO v_state FROM public.package_runtime WHERE package_id = v_pkg2;
    r := r || public._qa_s13_ok('F6.3 shipment runtime records the open claim', v_state = 'open', v_state);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN v_res := public.claims_reserve_allocate('package', v_pkg2, 50000, 'evidence/x.jpg',
      'qa non admin allocation', v_cust, v_drv, 400000, 'envoyer', false); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F6.4 only a God Admin can authorise a claims reserve',
      v_err <> 'NO_ERROR', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_auth := LEAST(50000, v_rt2.claims_exposure_gnf);
    v_res := public.claims_reserve_allocate('package', v_pkg2, v_auth, 'evidence/x.jpg',
      'qa investigated claim', v_cust, v_drv, 400000, 'envoyer', false);
    SELECT id INTO v_claim FROM public.claims_reserves
     WHERE source_module='package' AND source_id = v_pkg2;
    r := r || public._qa_s13_ok('F6.5 an investigated claim allocates a reserve within the frozen exposure',
      v_claim IS NOT NULL AND v_auth <= v_rt2.claims_exposure_gnf,
      format('%s authorized=%s exposure=%s', v_res::text, v_auth, v_rt2.claims_exposure_gnf));

    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    BEGIN v_res := public.claims_reserve_resolve(v_claim, v_auth + 5000000, 'qa adjudication test');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb; END;
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('F6.6 a claim can never pay more than the authorized reserve',
      v_err = 'NO_ERROR' AND COALESCE((v_res->>'paid_gnf')::bigint, -1) = v_auth,
      format('%s %s authorized=%s', v_err, v_res::text, v_auth));
    r := r || public._qa_s13_ok('F6.7 the customer is credited exactly the adjudicated amount',
      v_bal1 - v_bal0 = v_auth, format('%s -> %s (auth %s)', v_bal0, v_bal1, v_auth));

    v_res := public.claims_reserve_resolve(v_claim, v_auth, 'qa duplicate adjudication');
    SELECT balance_gnf INTO v_n FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('F6.8 re-adjudicating a resolved claim pays nothing more',
      v_n = v_bal1, format('%s vs %s', v_n, v_bal1));

    -- ===== CLOSEOUT 3: courier cancellation before custody =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_q := public.package_delivery_quote(9.5370, -13.6785, 9.5590, -13.6520, 'small_parcel', 'A', 'D');
    v_qid3 := (v_q->>'quote_id')::uuid;
    PERFORM public.package_evidence_register(v_qid3, v_cust::text||'/'||v_qid3::text||'/p1.jpg',
      'item','image/jpeg',1024);
    v_res := public.package_delivery_create_checkout(v_qid3,'Ami Diallo','622000001',
      NULL,NULL,'k8-'||v_sfx,'622000002','orange_money',false,NULL, 300000, 'chop_pay', true,
      'Je declare la valeur de mon colis');
    v_pkg3 := (v_res->>'package_id')::uuid;
    SELECT * INTO v_rt3 FROM public.package_runtime WHERE package_id = v_pkg3;
    SELECT mission_id INTO v_mis3 FROM public.package_deliveries WHERE id = v_pkg3;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv3), true);
    PERFORM public.mission_claim(v_mis3);
    SELECT held_gnf, balance_gnf INTO v_dheld0, v_dbal0
      FROM public.wallets WHERE owner_user_id=v_drv3 AND party_type='driver';
    SELECT held_gnf, balance_gnf INTO v_cheld0, v_cbal0
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_mw0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    SELECT promo_gnf, unrestricted_gnf INTO v_hp, v_hu FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg3 AND kind='collateral';
    r := r || public._qa_s13_ok('H1.0 courier collateral is really held before the release test',
      v_dheld0 = v_rt3.collateral_gnf, format('held=%s col=%s', v_dheld0, v_rt3.collateral_gnf));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN v_res := public.package_courier_cancel(v_pkg3, 'qa wrong actor'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('H1.1 only the assigned courier can release a shipment',
      v_err <> 'NO_ERROR', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv3), true);
    BEGIN v_res := public.package_courier_cancel(v_pkg3, 'panne moto avant collecte'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb; END;
    SELECT held_gnf, balance_gnf INTO v_dheld1, v_dbal1
      FROM public.wallets WHERE owner_user_id=v_drv3 AND party_type='driver';
    SELECT held_gnf, balance_gnf INTO v_cheld1, v_cbal1
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_mw FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('H1.2 a courier may cancel before custody through the canonical runtime',
      v_err = 'NO_ERROR' AND COALESCE(v_res->>'status','') = 'cancelled', format('%s %s', v_err, v_res::text));
    r := r || public._qa_s13_ok('H1.3 the courier collateral is released in full, balance untouched',
      v_dheld1 = v_dheld0 - v_rt3.collateral_gnf AND v_dbal1 = v_dbal0,
      format('held %s->%s bal %s->%s col=%s', v_dheld0, v_dheld1, v_dbal0, v_dbal1, v_rt3.collateral_gnf));
    SELECT COALESCE(sum(p.amount_gnf) FILTER (WHERE p.account='L_DRIVER_PROMO'),0),
           COALESCE(sum(p.amount_gnf) FILTER (WHERE p.account='L_DRIVER_UNRESTRICTED'),0)
      INTO v_relp, v_relu
      FROM public.ledger_journals j JOIN public.ledger_postings p ON p.journal_id=j.id
     WHERE j.source_module='package' AND j.source_id=v_pkg3 AND j.kind='release_collateral';
    r := r || public._qa_s13_ok('H1.4 released collateral returns to its original promo / unrestricted buckets',
      v_relp = -v_hp AND v_relu = -v_hu,
      format('promo %s vs %s, unrestricted %s vs %s', v_relp, v_hp, v_relu, v_hu));
    r := r || public._qa_s13_ok('H1.5 no cancellation fee is charged to the customer',
      COALESCE((v_res->'release'->>'cancellation_fee_gnf')::bigint,0) = 0
      AND (SELECT cancellation_fee_gnf FROM public.package_deliveries WHERE id=v_pkg3) = 0,
      v_res::text);
    r := r || public._qa_s13_ok('H1.6 the customer payment hold is released and declared value never charged',
      v_cheld1 = v_cheld0 - v_rt3.customer_hold_gnf AND v_cbal1 = v_cbal0,
      format('held %s->%s bal %s->%s hold=%s', v_cheld0, v_cheld1, v_cbal0, v_cbal1, v_rt3.customer_hold_gnf));
    r := r || public._qa_s13_ok('H1.7 no platform, merchant or courier earning is created by the cancellation',
      v_mw = v_mw0 AND v_dbal1 = v_dbal0
      AND NOT EXISTS (SELECT 1 FROM public.ledger_journals
                       WHERE source_module='package' AND source_id=v_pkg3
                         AND kind IN ('complete','capture_platform_fee','driver_earning')),
      format('master %s->%s', v_mw0, v_mw));

    v_can0 := (SELECT cancelled_at FROM public.package_deliveries WHERE id=v_pkg3);
    BEGIN v_res := public.package_courier_cancel(v_pkg3, 'panne moto avant collecte'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb; END;
    SELECT held_gnf, balance_gnf INTO v_dheld0, v_dbal0
      FROM public.wallets WHERE owner_user_id=v_drv3 AND party_type='driver';
    r := r || public._qa_s13_ok('H1.8 replaying the courier cancellation moves 0 additional GNF',
      v_err = 'NO_ERROR' AND COALESCE((v_res->>'idempotent')::boolean,false)
      AND v_dheld0 = v_dheld1 AND v_dbal0 = v_dbal1
      AND (SELECT cancelled_at FROM public.package_deliveries WHERE id=v_pkg3) = v_can0,
      format('%s %s', v_err, v_res::text));
    SELECT COALESCE(sum(GREATEST(amount_gnf-captured_gnf-released_gnf,0)),0) INTO v_n
      FROM public.mission_financial_holds WHERE source_module='package' AND source_id=v_pkg3;
    r := r || public._qa_s13_ok('H1.9 no stranded hold survives the courier cancellation',
      v_n = 0, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_q := public.package_delivery_quote(9.5370, -13.6785, 9.5580, -13.6540, 'small_parcel', 'A', 'E');
    v_qid4 := (v_q->>'quote_id')::uuid;
    PERFORM public.package_evidence_register(v_qid4, v_cust::text||'/'||v_qid4::text||'/p1.jpg',
      'item','image/jpeg',1024);
    v_res := public.package_delivery_create_checkout(v_qid4,'Ami Diallo','622000001',
      NULL,NULL,'k9-'||v_sfx,'622000002','orange_money',false,NULL, 300000, 'chop_pay', true,
      'Je declare la valeur de mon colis');
    v_pkg4 := (v_res->>'package_id')::uuid;
    SELECT mission_id INTO v_mis4 FROM public.package_deliveries WHERE id = v_pkg4;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv4), true);
    PERFORM public.mission_claim(v_mis4);
    SELECT pickup_code INTO v_pcode FROM public.package_delivery_secrets WHERE package_id = v_pkg4;
    PERFORM public.package_verify_pickup(v_pkg4, v_pcode);
    BEGIN v_res := public.package_courier_cancel(v_pkg4, 'qa after custody'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('H1.10 a courier holding the parcel cannot cancel, only claim',
      v_err LIKE '%CUSTODY_ESTABLISHED_CLAIM_REQUIRED%', v_err);

    -- ===== CLOSEOUT 4: compensation capped by the minimum of the three limits =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_q := public.package_delivery_quote(9.5370, -13.6785, 9.5570, -13.6560, 'small_parcel', 'A', 'F');
    v_qidA := (v_q->>'quote_id')::uuid;
    PERFORM public.package_evidence_register(v_qidA, v_cust::text||'/'||v_qidA::text||'/p1.jpg',
      'item','image/jpeg',1024);
    v_res := public.package_delivery_create_checkout(v_qidA,'Ami Diallo','622000001',
      NULL,NULL,'ia-'||v_sfx,'622000002','orange_money',false,NULL, 300000, 'chop_pay', true,
      'Je declare la valeur de mon colis');
    v_pkgA := (v_res->>'package_id')::uuid;
    SELECT * INTO v_rtA FROM public.package_runtime WHERE package_id = v_pkgA;
    SELECT mission_id INTO v_misA FROM public.package_deliveries WHERE id = v_pkgA;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drvA), true);
    PERFORM public.mission_claim(v_misA);
    SELECT pickup_code INTO v_pcode FROM public.package_delivery_secrets WHERE package_id = v_pkgA;
    PERFORM public.package_verify_pickup(v_pkgA, v_pcode);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    PERFORM public.package_claim_open(v_pkgA, 'colis perdu');

    r := r || public._qa_s13_ok('I0.1 the 75% courier collateral / remaining platform exposure model holds',
      v_rtA.collateral_gnf = (v_rtA.declared_value_gnf * 7500) / 10000
      AND v_rtA.claims_exposure_gnf = v_rtA.declared_value_gnf - v_rtA.collateral_gnf,
      format('dv=%s col=%s exp=%s', v_rtA.declared_value_gnf, v_rtA.collateral_gnf, v_rtA.claims_exposure_gnf));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    SELECT balance_gnf INTO v_cbal0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_mw0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    BEGIN v_res := public.admin_package_claim_resolve(v_pkgA,'customer_upheld',
      'qa over declared value', 'evidence/a.jpg', v_rtA.declared_value_gnf + 1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_cbal1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('I1.1 compensation above the accepted declared value is refused',
      v_err LIKE '%CLAIM_EXCEEDS_DECLARED_VALUE%', v_err);
    r := r || public._qa_s13_ok('I1.2 the refused over-compensation moved 0 GNF',
      v_cbal1 = v_cbal0, format('%s vs %s', v_cbal0, v_cbal1));

    v_res := public.admin_package_claim_resolve(v_pkgA,'customer_upheld',
      'qa declared value binding', 'evidence/a.jpg', v_rtA.declared_value_gnf);
    SELECT balance_gnf INTO v_cbal1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_mw FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('I1.3 the customer receives exactly the declared-value cap, once',
      v_cbal1 - v_cbal0 = v_rtA.declared_value_gnf
      AND COALESCE((v_res->>'from_collateral_gnf')::bigint,-1) = v_rtA.collateral_gnf
      AND COALESCE((v_res->>'from_platform_gnf')::bigint,-1) = v_rtA.claims_exposure_gnf,
      v_res::text);
    r := r || public._qa_s13_ok('I1.4 the platform funds only its own exposure share',
      v_mw0 - v_mw = v_rtA.claims_exposure_gnf, format('%s -> %s', v_mw0, v_mw));
    BEGIN v_res := public.admin_package_claim_resolve(v_pkgA,'customer_upheld',
      'qa replay adjudication', 'evidence/a.jpg', v_rtA.declared_value_gnf); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb; END;
    SELECT balance_gnf INTO v_n FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('I1.5 re-adjudication pays 0 additional GNF',
      v_n = v_cbal1, format('%s %s vs %s', v_err, v_n, v_cbal1));

    INSERT INTO public.finance_policies (mission_type, commission_bps, fixed_commission_gnf,
      min_driver_balance_gnf, collateral_mode, collateral_pct_bps, collateral_max_gnf,
      effective_from, enabled, note, transaction_fee_bps, fee_basis,
      cancel_before_dispatch_bps, cancel_after_dispatch_bps, max_declared_value_gnf,
      cancel_basis, collateral_basis, claims_exposure_max_gnf)
    VALUES ('envoyer', 0, 0, 5000, 'percentage', 7500, 375000, now(), true,
      'QA S13 P4 closeout: temporary claims-limit fixture', 100, 'delivery_fee',
      500, 1000, 500000, 'delivery_fee', 'declared_value', 20000)
    RETURNING id INTO v_pol;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_q := public.package_delivery_quote(9.5370, -13.6785, 9.5575, -13.6555, 'small_parcel', 'A', 'G');
    v_qidA := (v_q->>'quote_id')::uuid;
    PERFORM public.package_evidence_register(v_qidA, v_cust::text||'/'||v_qidA::text||'/p1.jpg',
      'item','image/jpeg',1024);
    v_res := public.package_delivery_create_checkout(v_qidA,'Ami Diallo','622000001',
      NULL,NULL,'ib-'||v_sfx,'622000002','orange_money',false,NULL, 300000, 'chop_pay', true,
      'Je declare la valeur de mon colis');
    v_pkgB := (v_res->>'package_id')::uuid;
    SELECT * INTO v_rtB FROM public.package_runtime WHERE package_id = v_pkgB;
    SELECT mission_id INTO v_misB FROM public.package_deliveries WHERE id = v_pkgB;
    r := r || public._qa_s13_ok('I2.1 the active claims limit caps the platform exposure of a shipment',
      v_rtB.claims_exposure_gnf = 20000,
      format('exp=%s dv=%s col=%s', v_rtB.claims_exposure_gnf, v_rtB.declared_value_gnf, v_rtB.collateral_gnf));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drvB), true);
    PERFORM public.mission_claim(v_misB);
    SELECT pickup_code INTO v_pcode FROM public.package_delivery_secrets WHERE package_id = v_pkgB;
    PERFORM public.package_verify_pickup(v_pkgB, v_pcode);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    PERFORM public.package_claim_open(v_pkgB, 'colis perdu');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    SELECT balance_gnf INTO v_cbal0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_mw0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    BEGIN v_res := public.admin_package_claim_resolve(v_pkgB,'customer_upheld',
      'qa above claims limit', 'evidence/b.jpg', v_rtB.declared_value_gnf); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_cbal1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('I2.2 compensation above the active claims limit is refused',
      v_err LIKE '%CLAIM_EXCEEDS_PLATFORM_EXPOSURE%' AND v_cbal1 = v_cbal0, v_err);
    v_res := public.admin_package_claim_resolve(v_pkgB,'customer_upheld',
      'qa claims limit binding', 'evidence/b.jpg', v_rtB.collateral_gnf + v_rtB.claims_exposure_gnf);
    SELECT balance_gnf INTO v_cbal1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_mw FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('I2.3 the customer receives exactly collateral + capped exposure',
      v_cbal1 - v_cbal0 = v_rtB.collateral_gnf + v_rtB.claims_exposure_gnf,
      format('%s -> %s (col=%s exp=%s)', v_cbal0, v_cbal1, v_rtB.collateral_gnf, v_rtB.claims_exposure_gnf));
    r := r || public._qa_s13_ok('I2.4 the platform never pays more than the capped exposure',
      v_mw0 - v_mw = v_rtB.claims_exposure_gnf, format('%s -> %s', v_mw0, v_mw));

    DELETE FROM public.finance_policies WHERE id = v_pol;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_q := public.package_delivery_quote(9.5370, -13.6785, 9.5585, -13.6535, 'small_parcel', 'A', 'H');
    v_qidA := (v_q->>'quote_id')::uuid;
    PERFORM public.package_evidence_register(v_qidA, v_cust::text||'/'||v_qidA::text||'/p1.jpg',
      'item','image/jpeg',1024);
    v_res := public.package_delivery_create_checkout(v_qidA,'Ami Diallo','622000001',
      NULL,NULL,'ic-'||v_sfx,'622000002','orange_money',false,NULL, 300000, 'chop_pay', true,
      'Je declare la valeur de mon colis');
    v_pkgC := (v_res->>'package_id')::uuid;
    SELECT * INTO v_rtC FROM public.package_runtime WHERE package_id = v_pkgC;
    SELECT mission_id INTO v_misC FROM public.package_deliveries WHERE id = v_pkgC;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drvC), true);
    PERFORM public.mission_claim(v_misC);
    SELECT pickup_code INTO v_pcode FROM public.package_delivery_secrets WHERE package_id = v_pkgC;
    PERFORM public.package_verify_pickup(v_pkgC, v_pcode);
    SELECT held_gnf, balance_gnf INTO v_dheld0, v_dbal0
      FROM public.wallets WHERE owner_user_id=v_drvC AND party_type='driver';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    PERFORM public.package_claim_open(v_pkgC, 'contenu abime');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    SELECT balance_gnf INTO v_cbal0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_mw0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    v_res := public.admin_package_claim_resolve(v_pkgC,'customer_upheld',
      'qa documented actual value 90000', 'evidence/c.jpg', 90000);
    SELECT balance_gnf INTO v_cbal1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_mw FROM public.wallets WHERE party_type='master' LIMIT 1;
    SELECT held_gnf, balance_gnf INTO v_dheld1, v_dbal1
      FROM public.wallets WHERE owner_user_id=v_drvC AND party_type='driver';
    r := r || public._qa_s13_ok('I3.1 a documented actual value below both caps binds the payout',
      v_cbal1 - v_cbal0 = 90000 AND COALESCE((v_res->>'from_platform_gnf')::bigint,-1) = 0,
      format('%s -> %s %s', v_cbal0, v_cbal1, v_res::text));
    r := r || public._qa_s13_ok('I3.2 the platform pays nothing when collateral covers the documented value',
      v_mw = v_mw0, format('%s -> %s', v_mw0, v_mw));
    r := r || public._qa_s13_ok('I3.3 the unused courier collateral is released back to the courier',
      v_dheld1 = v_dheld0 - v_rtC.collateral_gnf AND v_dbal1 = v_dbal0 - 90000,
      format('held %s->%s bal %s->%s col=%s', v_dheld0, v_dheld1, v_dbal0, v_dbal1, v_rtC.collateral_gnf));
    BEGIN v_res := public.admin_package_claim_resolve(v_pkgC,'customer_upheld',
      'qa replay documented value', 'evidence/c.jpg', 90000); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb; END;
    SELECT balance_gnf INTO v_n FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('I3.4 replaying the adjudication moves 0 additional GNF',
      v_n = v_cbal1, format('%s %s vs %s', v_err, v_n, v_cbal1));

    -- ===== CLOSEOUT 5: sandbox / production financial isolation =====
    SELECT count(*) INTO v_prodj0 FROM public.ledger_journals WHERE is_sandbox = false;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_q := public.package_delivery_quote(9.5370, -13.6785, 9.5595, -13.6510, 'small_parcel', 'A', 'S');
    v_qidA := (v_q->>'quote_id')::uuid;
    PERFORM public.package_evidence_register(v_qidA, v_cust::text||'/'||v_qidA::text||'/p1.jpg',
      'item','image/jpeg',1024);
    BEGIN v_res := public.package_delivery_create_checkout(v_qidA,'Ami Diallo','622000001',
      NULL,NULL,'js-'||v_sfx,'622000002','orange_money', true, gen_random_uuid(), 300000, 'chop_pay', true,
      'Je declare la valeur de mon colis'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb; END;
    v_pkgS := (v_res->>'package_id')::uuid;
    v_intS := (v_res->>'payment_intent_id')::uuid;
    r := r || public._qa_s13_ok('J1.1 a sandbox shipment can be created through the same runtime',
      v_err = 'NO_ERROR' AND v_pkgS IS NOT NULL, format('%s %s', v_err, v_res::text));

    IF v_pkgS IS NOT NULL THEN
      SELECT mission_id INTO v_misS FROM public.package_deliveries WHERE id = v_pkgS;
      PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drvS), true);
      BEGIN PERFORM public.mission_claim(v_misS); EXCEPTION WHEN OTHERS THEN NULL; END;
      r := r || public._qa_s13_ok('J1.2 every sandbox record carries the sandbox discriminator',
        (SELECT is_sandbox FROM public.package_deliveries WHERE id=v_pkgS)
        AND (SELECT is_sandbox FROM public.package_runtime WHERE package_id=v_pkgS)
        AND NOT EXISTS (SELECT 1 FROM public.mission_financial_holds
                         WHERE source_module='package' AND source_id=v_pkgS AND is_sandbox = false)
        AND NOT EXISTS (SELECT 1 FROM public.ledger_journals
                         WHERE source_module='package' AND source_id=v_pkgS AND is_sandbox = false),
        v_pkgS::text);
      SELECT count(*) INTO v_prodj1 FROM public.ledger_journals WHERE is_sandbox = false;
      r := r || public._qa_s13_ok('J1.3 the sandbox lifecycle created no production ledger journal',
        v_prodj1 = v_prodj0, format('%s -> %s', v_prodj0, v_prodj1));
      r := r || public._qa_s13_ok('J1.4 the production shipment carries no sandbox marking',
        (SELECT NOT is_sandbox FROM public.package_runtime WHERE package_id=v_pkg)
        AND NOT EXISTS (SELECT 1 FROM public.ledger_journals
                         WHERE source_module='package' AND source_id=v_pkg AND is_sandbox = true),
        v_pkg::text);
    END IF;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    BEGIN v_res := public.om_sandbox_finalize_authorized_intent(v_int); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('J1.5 the sandbox finaliser refuses a production payment intent',
      v_err LIKE '%not_a_sandbox_intent%', v_err);

    BEGIN v_res := public.confirm_payment_intent(v_intS); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('J1.6 the production confirmation path refuses a sandbox payment intent',
      v_err LIKE '%sandbox_intent%', v_err);

    -- ---------- ledger integrity ----------
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j
       JOIN public.ledger_postings p ON p.journal_id = j.id
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('F7.1 no imbalanced journal after Envoyer fixtures', v_n = 0, v_n::text);
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings;
    r := r || public._qa_s13_ok('F7.2 global ledger sum is zero', v_n = 0, v_n::text);

    RAISE EXCEPTION 'QA_S13_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S13_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS_PART4_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', '', true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z4.1 master wallet unchanged after rollback',
    v_master1 = v_master0, v_master1::text);
  r := r || public._qa_s13_ok('Z4.2 live feature flags byte-identical after fixture rollback',
    v_flags1 = v_flags0, NULL);
  SELECT count(*) INTO v_n FROM public.package_deliveries
   WHERE sender_user_id IN (SELECT id FROM auth.users WHERE email LIKE 'qa-s13-%@qa.invalid');
  r := r || public._qa_s13_ok('Z4.3 no Envoyer fixture residue survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace AND p.proname LIKE '\_qa\_s13%'
     AND (has_function_privilege('anon', p.oid, 'EXECUTE')
       OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  r := r || public._qa_s13_ok('Z4.4 no _qa_s13* helper is executable by anon or authenticated',
    v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.finance_policies WHERE note LIKE 'QA S13%';
  r := r || public._qa_s13_ok('Z4.5 no temporary finance policy fixture survives', v_n = 0, v_n::text);

  RETURN public._qa_s13_summary(4, r);
END $function$;

REVOKE ALL ON FUNCTION public._qa_s13_run4() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s13_run4() TO service_role;

SELECT public._qa_s13_run4();