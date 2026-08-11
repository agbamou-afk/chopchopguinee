-- Correct the positional call into the canonical claims-reserve primitive.
CREATE OR REPLACE FUNCTION public.admin_package_claim_resolve(
  p_package_id uuid, p_outcome text, p_reason text, p_evidence_ref text,
  p_pay_customer_gnf bigint DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_caller uuid := auth.uid(); v_rt public.package_runtime; v_pkg public.package_deliveries;
  v_pay bigint; v_from_driver bigint; v_from_platform bigint;
  v_cap jsonb; v_alloc jsonb; v_res jsonb; v_rel jsonb; v_cust jsonb; v_settle jsonb;
  v_open_col bigint; v_master public.wallets; v_claim uuid;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501',
      DETAIL = 'Only a God Admin can resolve an Envoyer claim';
  END IF;
  IF p_outcome NOT IN ('customer_upheld','driver_exonerated','reconciliation_required') THEN
    RAISE EXCEPTION 'INVALID_OUTCOME';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  IF p_evidence_ref IS NULL OR length(btrim(p_evidence_ref)) < 4 THEN RAISE EXCEPTION 'CLAIM_EVIDENCE_REQUIRED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('package:'||p_package_id::text, 0));
  SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = p_package_id FOR UPDATE;
  IF v_rt.id IS NULL THEN RAISE EXCEPTION 'PACKAGE_NOT_AUTHORIZED'; END IF;
  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_package_id FOR UPDATE;
  IF v_rt.claim_state <> 'open' THEN
    RETURN jsonb_build_object('status','already_resolved','claim_state',v_rt.claim_state);
  END IF;

  IF p_outcome = 'reconciliation_required' THEN
    UPDATE public.package_runtime
       SET claim_state = 'reconciliation_required', state = 'reconciliation_required', resolved_at = now()
     WHERE id = v_rt.id;
    UPDATE public.package_deliveries SET claim_state = 'reconciliation_required' WHERE id = p_package_id;
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
    VALUES (v_caller,'package','package.claim.reconciliation_required','package_delivery',
            p_package_id::text, jsonb_build_object('evidence_ref',p_evidence_ref), p_reason);
    RETURN jsonb_build_object('status','reconciliation_required','money_moved',false);
  END IF;

  IF p_outcome = 'customer_upheld' THEN
    v_pay := GREATEST(COALESCE(p_pay_customer_gnf,0),0);
    IF v_pay <= 0 THEN RAISE EXCEPTION 'CLAIM_PAYMENT_REQUIRED'; END IF;
    IF v_pay > v_rt.declared_value_gnf THEN RAISE EXCEPTION 'CLAIM_EXCEEDS_DECLARED_VALUE'; END IF;

    SELECT GREATEST(amount_gnf - captured_gnf - released_gnf, 0) INTO v_open_col
      FROM public.mission_financial_holds
     WHERE source_module = 'package' AND source_id = p_package_id AND kind = 'collateral';
    v_open_col := COALESCE(v_open_col, 0);

    v_from_driver := LEAST(v_pay, v_open_col);
    v_from_platform := v_pay - v_from_driver;
    IF v_from_platform > v_rt.claims_exposure_gnf THEN
      RAISE EXCEPTION 'CLAIM_EXCEEDS_PLATFORM_EXPOSURE'
        USING DETAIL = format('exposure=%s requested=%s', v_rt.claims_exposure_gnf, v_from_platform);
    END IF;

    IF v_from_platform > 0 THEN
      v_alloc := public.claims_reserve_allocate(
        p_source_module      => 'package',
        p_source_id          => p_package_id,
        p_authorized_gnf     => v_from_platform,
        p_evidence_ref       => p_evidence_ref,
        p_reason             => btrim(p_reason),
        p_customer           => v_rt.customer_user_id,
        p_driver             => v_rt.driver_user_id,
        p_declared_value_gnf => v_rt.declared_value_gnf,
        p_mission_type       => 'envoyer',
        p_is_sandbox         => v_rt.is_sandbox);
      SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
      IF v_master.id IS NULL THEN RAISE EXCEPTION 'MASTER_WALLET_MISSING'; END IF;
      UPDATE public.wallets SET balance_gnf = balance_gnf - v_from_platform, updated_at = now()
       WHERE id = v_master.id;
      SELECT id INTO v_claim FROM public.claims_reserves
       WHERE source_module='package' AND source_id=p_package_id;
      v_res := public.claims_reserve_resolve(v_claim, v_from_platform, btrim(p_reason));
    END IF;

    IF v_from_driver > 0 THEN
      v_cap := public._package_collateral_capture_internal(
        p_package_id, v_from_driver, btrim(p_reason), p_evidence_ref, v_caller);
    END IF;

    v_rel := public._driver_mission_hold_release_internal(
      'package', p_package_id, NULL, 'envoyer_claim_upheld', v_caller);

    UPDATE public.mission_financial_holds SET state = 'held'
     WHERE source_module='package' AND source_id=p_package_id AND kind='customer_payment' AND state='frozen';
    IF v_rt.tender = 'chop_pay' THEN
      v_cust := public._package_choppay_release_internal(p_package_id, 'envoyer_claim_upheld', v_caller);
    END IF;

    UPDATE public.package_runtime
       SET claim_state = 'upheld', state = 'resolved', resolved_at = now(), claim_paid_gnf = v_pay
     WHERE id = v_rt.id;
    UPDATE public.package_deliveries SET claim_state = 'resolved' WHERE id = p_package_id;

    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
    VALUES (v_caller,'package','package.claim.customer_upheld','package_delivery', p_package_id::text,
            jsonb_build_object('paid_gnf',v_pay,'from_collateral_gnf',v_from_driver,
                               'from_platform_gnf',v_from_platform,'evidence_ref',p_evidence_ref), p_reason);

    RETURN jsonb_build_object('status','customer_upheld','paid_gnf',v_pay,
      'from_collateral_gnf',v_from_driver,'from_platform_gnf',v_from_platform,
      'collateral_release',v_rel,'customer_release',v_cust,'capture',v_cap,
      'reserve_allocate',v_alloc,'reserve_resolve',v_res);
  END IF;

  UPDATE public.mission_financial_holds SET state = 'held'
   WHERE source_module='package' AND source_id=p_package_id AND state='frozen' AND captured_gnf = 0;
  UPDATE public.mission_financial_holds SET state = 'partially_captured'
   WHERE source_module='package' AND source_id=p_package_id AND state='frozen' AND captured_gnf > 0;

  IF v_pkg.package_status = 'delivered' THEN
    UPDATE public.package_runtime SET claim_state = 'none', state = 'picked_up' WHERE id = v_rt.id;
    v_settle := public._package_complete_internal(p_package_id, v_caller);
  ELSE
    UPDATE public.package_runtime SET claim_state = 'none', state = 'accepted' WHERE id = v_rt.id;
    v_settle := public._package_cancel_release_internal(p_package_id, 'envoyer_claim_denied', v_caller);
  END IF;

  UPDATE public.package_runtime SET claim_state = 'denied', resolved_at = now() WHERE id = v_rt.id;
  UPDATE public.package_deliveries SET claim_state = 'resolved' WHERE id = p_package_id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller,'package','package.claim.driver_exonerated','package_delivery', p_package_id::text,
          jsonb_build_object('evidence_ref',p_evidence_ref,'settlement',v_settle), p_reason);

  RETURN jsonb_build_object('status','driver_exonerated','paid_gnf',0,'settlement',v_settle);
END; $$;

REVOKE ALL ON FUNCTION public.admin_package_claim_resolve(uuid,text,text,text,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_package_claim_resolve(uuid,text,text,text,bigint) TO authenticated, service_role;

-- ============================================================
-- Slice 6 QA harness (self-rolling-back)
-- ============================================================
CREATE TABLE IF NOT EXISTS public._qa_s6_results (
  id bigserial PRIMARY KEY, part int, report jsonb, created_at timestamptz DEFAULT now());
ALTER TABLE public._qa_s6_results ENABLE ROW LEVEL SECURITY;
GRANT ALL ON public._qa_s6_results TO service_role;

CREATE OR REPLACE FUNCTION public._qa_s6_setup(p_send uuid, p_drv uuid, p_god uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  INSERT INTO public.admin_users(user_id, admin_role, status) VALUES (p_god,'god_admin','active');
  INSERT INTO public.driver_profiles(user_id, status, vehicle_type, capabilities)
  VALUES (p_drv,'approved','moto',ARRAY['package_delivery']);
  INSERT INTO public.wallets(owner_user_id, party_type, balance_gnf)
  VALUES (p_drv,'driver',5000000),(p_send,'client',5000000);
  UPDATE public.feature_flags SET enabled = true
   WHERE key IN ('envoyer_enabled','envoyer_declared_value_enabled',
                 'chop_pay_checkout_enabled','envoyer_claims_enabled');
END; $$;

CREATE OR REPLACE FUNCTION public._qa_s6_quote(p_user uuid, p_amount bigint DEFAULT 100000)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.package_delivery_quotes(
    user_id, pickup_label, pickup_lat, pickup_lng, destination_label, destination_lat,
    destination_lng, category, distance_meters, duration_seconds, amount_gnf, expires_at)
  VALUES (p_user,'QA pickup',9.5,-13.7,'QA dest',9.6,-13.6,'small_parcel',5000,900,
          p_amount, now() + interval '10 minutes')
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

REVOKE ALL ON FUNCTION public._qa_s6_setup(uuid,uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_s6_quote(uuid,bigint) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_s6_run1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  r jsonb := '[]'::jsonb; v_pass int; v_total int;
  v_send uuid; v_drv uuid; v_god uuid;
  v_q uuid; v_j jsonb; v_pkg uuid; v_rt public.package_runtime;
  v_n bigint; v_err text; v_master0 bigint; v_master1 bigint; v_ceiling bigint;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  BEGIN
    v_send := gen_random_uuid(); v_drv := gen_random_uuid(); v_god := gen_random_uuid();
    PERFORM public._qa_s6_setup(v_send, v_drv, v_god);

    -- A. declared value 500000 => collateral 375000, exposure 125000, fee 1% of delivery fee
    v_q := public._qa_s6_quote(v_send, 100000);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_send), true);
    PERFORM public.package_evidence_register(v_q, format('%s/%s/front.jpg', v_send, v_q), 'item');
    v_j := public.package_delivery_create_checkout(
      v_q,'QA Destinataire','+224620000001','QA colis','QA instructions',
      'qa-s6-a-'||substr(v_q::text,1,8), '+224620000002','orange_money',false,NULL,
      500000,'cash',true,'Je certifie que la valeur declaree est exacte.');
    v_pkg := (v_j->>'package_id')::uuid;
    SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = v_pkg;
    r := r || public._qa_s5_ok('A1 declared 500000 => collateral exactly 375000',
      v_rt.collateral_gnf = 375000, v_rt.collateral_gnf::text);
    r := r || public._qa_s5_ok('A2 claims exposure exactly 125000',
      v_rt.claims_exposure_gnf = 125000, v_rt.claims_exposure_gnf::text);
    r := r || public._qa_s5_ok('A3 platform fee = 1% of the DELIVERY FEE (1000), not declared value',
      v_rt.platform_fee_gnf = 1000, v_rt.platform_fee_gnf::text);
    r := r || public._qa_s5_ok('A4 commission is zero for Envoyer',
      COALESCE((v_rt.policy_snapshot->>'commission_bps')::int,-1) = 0,
      v_rt.policy_snapshot->>'commission_bps');
    r := r || public._qa_s5_ok('A5 cash due = delivery fee + platform fee (101000)',
      v_rt.cash_due_gnf = 101000 AND v_rt.customer_hold_gnf = 0, v_rt.cash_due_gnf::text);
    r := r || public._qa_s5_ok('A6 attestation frozen, timestamped and attributable to the sender',
      EXISTS (SELECT 1 FROM public.package_deliveries WHERE id=v_pkg
               AND value_attested_by = v_send AND value_attested_at IS NOT NULL
               AND value_attestation_version = 'envoyer.value_attestation.v1'));
    r := r || public._qa_s5_ok('A7 mission dispatched and available (courier NULL)',
      EXISTS (SELECT 1 FROM public.missions m JOIN public.package_deliveries p ON p.mission_id=m.id
               WHERE p.id=v_pkg AND m.state='assigned' AND m.courier_id IS NULL));
    r := r || public._qa_s5_ok('A8 no financial hold exists before a courier accepts',
      NOT EXISTS (SELECT 1 FROM public.mission_financial_holds
                   WHERE source_module='package' AND source_id=v_pkg));

    -- B. 500001 denied atomically
    v_q := public._qa_s6_quote(v_send, 100000);
    PERFORM public.package_evidence_register(v_q, format('%s/%s/front.jpg', v_send, v_q), 'item');
    BEGIN
      v_j := public.package_delivery_create_checkout(
        v_q,'QA Destinataire','+224620000001',NULL,NULL,'qa-s6-b-'||substr(v_q::text,1,8),
        NULL,'orange_money',false,NULL,500001,'cash',true,'Je certifie la valeur declaree.');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('B1 declared 500001 denied', v_err LIKE '%DECLARED_VALUE_ABOVE_CEILING%', v_err);
    SELECT count(*) INTO v_n FROM public.package_deliveries WHERE quote_id = v_q;
    r := r || public._qa_s5_ok('B2 no shipment row persisted for the refused declaration', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.package_runtime;
    r := r || public._qa_s5_ok('B3 exactly one runtime exists (only the accepted shipment)', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_module='package';
    r := r || public._qa_s5_ok('B4 no hold residue from the refused declaration', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.ledger_journals WHERE source_module='package';
    r := r || public._qa_s5_ok('B5 no journal residue from the refused declaration', v_n = 0, v_n::text);
    r := r || public._qa_s5_ok('B6 declared 500000 is allowed (ceiling inclusive)',
      (SELECT declared_value_gnf FROM public.package_runtime LIMIT 1) = 500000);

    -- C. missing photos denied
    v_q := public._qa_s6_quote(v_send, 100000);
    BEGIN
      v_j := public.package_delivery_create_checkout(
        v_q,'QA Destinataire','+224620000001',NULL,NULL,'qa-s6-c-'||substr(v_q::text,1,8),
        NULL,'orange_money',false,NULL,300000,'cash',true,'Je certifie la valeur declaree.');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('C1 missing private photos denied', v_err LIKE '%SHIPMENT_PHOTOS_REQUIRED%', v_err);
    SELECT count(*) INTO v_n FROM public.package_deliveries WHERE quote_id = v_q;
    r := r || public._qa_s5_ok('C2 no shipment persisted without photos', v_n = 0, v_n::text);

    -- D. attestation required
    v_q := public._qa_s6_quote(v_send, 100000);
    PERFORM public.package_evidence_register(v_q, format('%s/%s/front.jpg', v_send, v_q), 'item');
    BEGIN
      v_j := public.package_delivery_create_checkout(
        v_q,'QA Destinataire','+224620000001',NULL,NULL,'qa-s6-d-'||substr(v_q::text,1,8),
        NULL,'orange_money',false,NULL,300000,'cash',false,'Je certifie la valeur declaree.');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('D1 false attestation denied', v_err LIKE '%VALUE_ATTESTATION_REQUIRED%', v_err);
    BEGIN
      v_j := public.package_delivery_create_checkout(
        v_q,'QA Destinataire','+224620000001',NULL,NULL,'qa-s6-d2-'||substr(v_q::text,1,8),
        NULL,'orange_money',false,NULL,300000,'cash',true,NULL);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('D2 missing attestation statement denied',
      v_err LIKE '%VALUE_ATTESTATION_REQUIRED%', v_err);
    BEGIN
      v_j := public.package_delivery_create_checkout(
        v_q,'QA Destinataire','+224620000001',NULL,NULL,'qa-s6-d3-'||substr(v_q::text,1,8),
        NULL,'orange_money',false,NULL,300000,NULL,true,'Je certifie la valeur declaree.');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('D3 no implicit tender (explicit cash / chop_pay required)',
      v_err LIKE '%ENVOYER_TENDER_REQUIRED%', v_err);
    BEGIN
      v_j := public.package_delivery_create_checkout(
        v_q,'QA Destinataire','+224620000001',NULL,NULL,'qa-s6-d4-'||substr(v_q::text,1,8),
        NULL,'orange_money',false,NULL,0,'cash',true,'Je certifie la valeur declaree.');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('D4 declared value must be a positive amount',
      v_err LIKE '%DECLARED_VALUE_REQUIRED%', v_err);

    -- K. God Admin ceiling change governs NEW shipments only
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    PERFORM public.admin_set_finance_policy(
      p_mission_type => 'envoyer', p_max_declared_value_gnf => 200000,
      p_effective_from => now(), p_note => 'QA S6 ceiling reduction');
    SELECT max_declared_value_gnf INTO v_ceiling FROM public.finance_policy_current('envoyer');
    r := r || public._qa_s5_ok('K1 God Admin ceiling edit is effective-dated and applied',
      v_ceiling = 200000, v_ceiling::text);
    r := r || public._qa_s5_ok('K2 ceiling edit is audited',
      EXISTS (SELECT 1 FROM public.audit_logs WHERE action='finance_policy_set'
               AND actor_user_id = v_god AND note='QA S6 ceiling reduction'));
    SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = v_pkg;
    r := r || public._qa_s5_ok('K3 already-authorized shipment keeps its frozen economics',
      v_rt.collateral_gnf = 375000 AND v_rt.claims_exposure_gnf = 125000
      AND v_rt.declared_value_gnf = 500000
      AND (v_rt.policy_snapshot->>'max_declared_value_gnf')::bigint = 500000);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_send), true);
    v_q := public._qa_s6_quote(v_send, 100000);
    PERFORM public.package_evidence_register(v_q, format('%s/%s/front.jpg', v_send, v_q), 'item');
    BEGIN
      v_j := public.package_delivery_create_checkout(
        v_q,'QA Destinataire','+224620000001',NULL,NULL,'qa-s6-k-'||substr(v_q::text,1,8),
        NULL,'orange_money',false,NULL,300000,'cash',true,'Je certifie la valeur declaree.');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('K4 new shipment above the NEW ceiling is refused',
      v_err LIKE '%DECLARED_VALUE_ABOVE_CEILING%', v_err);
    r := r || public._qa_s5_ok('K5 frozen runtime is protected by the immutability trigger',
      (SELECT count(*) FROM public.package_runtime WHERE collateral_gnf = 375000) = 1);

    RAISE EXCEPTION 'QA_S6_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S6_ROLLBACK' THEN
      r := r || public._qa_s5_ok('HARNESS_PART1_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || public._qa_s5_ok('Z1 master wallet naturally restored by rollback',
    v_master1 = v_master0 AND v_master1 = -100435, v_master1::text);
  SELECT count(*) INTO v_n FROM public.package_runtime;
  r := r || public._qa_s5_ok('Z2 no runtime residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.package_evidence_photos;
  r := r || public._qa_s5_ok('Z3 no evidence residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.feature_flags
   WHERE enabled AND key IN ('envoyer_enabled','envoyer_declared_value_enabled',
                             'envoyer_claims_enabled','chop_pay_checkout_enabled');
  r := r || public._qa_s5_ok('Z4 Slice 6 flags restored to OFF', v_n = 0, v_n::text);

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total
    FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('part',1,'total',v_total,'passed',v_pass,'failed',v_total-v_pass,
    'failures',(SELECT COALESCE(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(r) x
                 WHERE NOT (x->>'ok')::boolean));
END; $$;

REVOKE ALL ON FUNCTION public._qa_s6_run1() FROM PUBLIC, anon, authenticated;