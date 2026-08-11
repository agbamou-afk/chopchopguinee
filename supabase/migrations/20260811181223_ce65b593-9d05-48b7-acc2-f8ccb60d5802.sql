ALTER TABLE public.package_runtime
  ADD COLUMN IF NOT EXISTS documented_actual_value_gnf bigint,
  ADD COLUMN IF NOT EXISTS documented_value_evidence_ref text,
  ADD COLUMN IF NOT EXISTS documented_value_by uuid,
  ADD COLUMN IF NOT EXISTS documented_value_at timestamptz;

ALTER TABLE public.claims_reserves
  ADD COLUMN IF NOT EXISTS documented_actual_value_gnf bigint;

CREATE OR REPLACE FUNCTION public.admin_package_claim_set_documented_value(
  p_package_id uuid,
  p_documented_actual_value_gnf bigint,
  p_evidence_ref text,
  p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_caller uuid := auth.uid(); v_rt public.package_runtime;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501',
      DETAIL='Only a God Admin can record an investigated claim value';
  END IF;
  IF p_evidence_ref IS NULL OR length(btrim(p_evidence_ref)) < 4 THEN
    RAISE EXCEPTION 'CLAIM_EVIDENCE_REQUIRED'; END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN
    RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  IF COALESCE(p_documented_actual_value_gnf, -1) < 0 THEN
    RAISE EXCEPTION 'DOCUMENTED_VALUE_INVALID'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('package:'||p_package_id::text, 0));
  SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = p_package_id FOR UPDATE;
  IF v_rt.id IS NULL THEN RAISE EXCEPTION 'PACKAGE_NOT_AUTHORIZED'; END IF;
  IF v_rt.claim_state <> 'open' THEN
    RAISE EXCEPTION 'CLAIM_NOT_OPEN' USING DETAIL = format('claim_state=%s', v_rt.claim_state);
  END IF;

  UPDATE public.package_runtime
     SET documented_actual_value_gnf = p_documented_actual_value_gnf,
         documented_value_evidence_ref = btrim(p_evidence_ref),
         documented_value_by = v_caller,
         documented_value_at = now()
   WHERE id = v_rt.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller,'package','package.claim.documented_value','package_delivery', p_package_id::text,
          jsonb_build_object('documented_actual_value_gnf', p_documented_actual_value_gnf,
                             'evidence_ref', btrim(p_evidence_ref)), btrim(p_reason));

  RETURN jsonb_build_object('status','recorded','package_id',p_package_id,
                            'documented_actual_value_gnf', p_documented_actual_value_gnf);
END; $function$;

REVOKE ALL ON FUNCTION public.admin_package_claim_set_documented_value(uuid,bigint,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_package_claim_set_documented_value(uuid,bigint,text,text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_package_claim_resolve(p_package_id uuid, p_outcome text, p_reason text, p_evidence_ref text, p_pay_customer_gnf bigint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid(); v_rt public.package_runtime; v_pkg public.package_deliveries;
  v_pay bigint; v_from_driver bigint; v_from_platform bigint;
  v_cap jsonb; v_alloc jsonb; v_res jsonb; v_rel jsonb; v_cust jsonb; v_settle jsonb;
  v_open_col bigint; v_master public.wallets; v_claim uuid;
  v_doc bigint; v_limit bigint; v_maxcomp bigint; v_bind text;
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

    -- Canonical three-way compensation cap. The documented actual value is the
    -- God-Admin-investigated persisted figure; it is never taken from the caller.
    v_doc := v_rt.documented_actual_value_gnf;
    IF v_doc IS NULL THEN
      RAISE EXCEPTION 'CLAIM_DOCUMENTED_VALUE_REQUIRED'
        USING DETAIL = 'Record the investigated actual value before authorising a payout';
    END IF;
    v_limit := v_open_col + GREATEST(COALESCE(v_rt.claims_exposure_gnf,0),0);
    v_maxcomp := LEAST(v_rt.declared_value_gnf, v_doc, v_limit);
    v_bind := CASE
                WHEN v_maxcomp = v_doc THEN 'documented_actual_value'
                WHEN v_maxcomp = v_limit THEN 'active_claim_limit'
                ELSE 'declared_value' END;
    IF v_pay > v_maxcomp THEN
      RAISE EXCEPTION 'CLAIM_EXCEEDS_MAX_COMPENSATION'
        USING DETAIL = format('requested=%s max=%s binding=%s declared=%s documented=%s limit=%s',
                              v_pay, v_maxcomp, v_bind, v_rt.declared_value_gnf, v_doc, v_limit);
    END IF;

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
      UPDATE public.claims_reserves SET documented_actual_value_gnf = v_doc
       WHERE source_module='package' AND source_id=p_package_id;
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
                               'from_platform_gnf',v_from_platform,'evidence_ref',p_evidence_ref,
                               'documented_actual_value_gnf',v_doc,'max_compensation_gnf',v_maxcomp,
                               'binding_constraint',v_bind), p_reason);

    RETURN jsonb_build_object('status','customer_upheld','paid_gnf',v_pay,
      'from_collateral_gnf',v_from_driver,'from_platform_gnf',v_from_platform,
      'documented_actual_value_gnf',v_doc,'max_compensation_gnf',v_maxcomp,'binding_constraint',v_bind,
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
END; $function$;