-- ============================================================================
-- SLICE 8 — CENTRALIZED CANCELLATION + CUSTOMER DEBT ENGINE
-- One canonical calculator. Quote and execution bind to the same frozen snapshot.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. THE canonical calculator. Every cancellation amount in the platform
--    is produced here and nowhere else.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._cancellation_compute(
  p_snapshot jsonb,
  p_stage text,
  p_fare_gnf bigint DEFAULT 0,
  p_merchandise_subtotal_gnf bigint DEFAULT 0,
  p_delivery_fee_gnf bigint DEFAULT 0,
  p_responsible_party text DEFAULT 'customer'
) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'public'
AS $fn$
DECLARE
  v_kind text; v_basis bigint; v_bps int; v_fee bigint;
BEGIN
  IF p_stage NOT IN ('before_dispatch','after_dispatch') THEN
    RAISE EXCEPTION 'INVALID_CANCELLATION_STAGE' USING DETAIL = COALESCE(p_stage,'null');
  END IF;
  IF COALESCE(p_responsible_party,'customer')
       NOT IN ('customer','provider','platform','merchant','driver') THEN
    RAISE EXCEPTION 'INVALID_RESPONSIBLE_PARTY';
  END IF;

  v_kind := COALESCE(p_snapshot->>'cancel_basis','none');

  v_basis := CASE v_kind
    WHEN 'fare' THEN GREATEST(COALESCE(p_fare_gnf,0),0)
    WHEN 'merchandise_plus_delivery'
      THEN GREATEST(COALESCE(p_merchandise_subtotal_gnf,0),0)
         + GREATEST(COALESCE(p_delivery_fee_gnf,0),0)
    WHEN 'merchandise_subtotal' THEN GREATEST(COALESCE(p_merchandise_subtotal_gnf,0),0)
    WHEN 'delivery_fee' THEN GREATEST(COALESCE(p_delivery_fee_gnf,0),0)
    ELSE 0 END;

  v_bps := CASE p_stage
    WHEN 'before_dispatch' THEN COALESCE((p_snapshot->>'cancel_before_dispatch_bps')::int, 0)
    ELSE COALESCE((p_snapshot->>'cancel_after_dispatch_bps')::int, 0) END;

  -- Only a customer-caused cancellation can ever produce a customer fee.
  IF COALESCE(p_responsible_party,'customer') <> 'customer' THEN
    RETURN jsonb_build_object(
      'cancel_basis_kind', v_kind, 'basis_gnf', v_basis,
      'fee_bps', v_bps, 'fee_gnf', 0::bigint,
      'responsible_party', p_responsible_party,
      'exempt', true, 'exempt_reason', format('not_customer_caused:%s', p_responsible_party),
      'stage', p_stage,
      'policy_effective_from', p_snapshot->>'effective_from',
      'policy_id', p_snapshot->>'policy_id');
  END IF;

  v_fee := (v_basis * v_bps) / 10000;

  RETURN jsonb_build_object(
    'cancel_basis_kind', v_kind, 'basis_gnf', v_basis,
    'fee_bps', v_bps, 'fee_gnf', v_fee,
    'responsible_party', 'customer', 'exempt', false,
    'stage', p_stage,
    'policy_effective_from', p_snapshot->>'effective_from',
    'policy_id', p_snapshot->>'policy_id');
END; $fn$;

REVOKE ALL ON FUNCTION public._cancellation_compute(jsonb,text,bigint,bigint,bigint,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cancellation_compute(jsonb,text,bigint,bigint,bigint,text) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. Debt creation now delegates all arithmetic to the calculator.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._customer_cancellation_debt_create_internal(
  p_source_module text, p_source_id uuid, p_customer uuid, p_mission_type text,
  p_stage text, p_fare_gnf bigint DEFAULT 0, p_merchandise_subtotal_gnf bigint DEFAULT 0,
  p_delivery_fee_gnf bigint DEFAULT 0, p_preparation_started boolean DEFAULT false,
  p_responsible_party text DEFAULT 'customer', p_is_sandbox boolean DEFAULT false,
  p_policy_snapshot jsonb DEFAULT NULL, p_actor uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_req jsonb; v_snap jsonb; v_calc jsonb;
  v_bps int; v_basis bigint; v_amount bigint;
  v_row public.customer_cancellation_debts;
BEGIN
  IF p_stage NOT IN ('before_dispatch','after_dispatch') THEN RAISE EXCEPTION 'Invalid stage'; END IF;
  IF p_responsible_party NOT IN ('customer','provider','platform','merchant','driver') THEN
    RAISE EXCEPTION 'Invalid responsible party';
  END IF;

  IF p_mission_type IN ('repas','marche') AND COALESCE(p_preparation_started,false)
     AND p_responsible_party = 'customer' THEN
    RAISE EXCEPTION 'REPAS_CANCELLATION_LOCKED'
      USING DETAIL = 'Customer cancellation is prohibited once preparation has started';
  END IF;

  IF p_responsible_party <> 'customer' THEN
    RETURN jsonb_build_object('status','exempt','amount_gnf',0,
      'exempt_reason', format('not_customer_caused:%s', p_responsible_party));
  END IF;

  IF p_policy_snapshot IS NOT NULL AND p_policy_snapshot <> '{}'::jsonb THEN
    v_snap := p_policy_snapshot;
  ELSE
    v_req := public.finance_mission_requirement_v2(p_mission_type,0,0,0,0,'cash');
    v_snap := COALESCE(v_req->'policy_snapshot','{}'::jsonb);
  END IF;

  v_calc   := public._cancellation_compute(v_snap, p_stage, p_fare_gnf,
                p_merchandise_subtotal_gnf, p_delivery_fee_gnf, 'customer');
  v_basis  := (v_calc->>'basis_gnf')::bigint;
  v_bps    := (v_calc->>'fee_bps')::int;
  v_amount := (v_calc->>'fee_gnf')::bigint;

  INSERT INTO public.customer_cancellation_debts
    (debt_key, customer_user_id, source_module, source_id, mission_type, stage,
     basis_gnf, applied_bps, amount_gnf, state, exempt_reason, policy_snapshot, is_sandbox)
  VALUES (format('cancel:%s:%s', p_source_module, p_source_id), p_customer, p_source_module,
          p_source_id, p_mission_type, p_stage, v_basis, v_bps, v_amount,
          CASE WHEN v_amount > 0 THEN 'outstanding' ELSE 'exempt' END,
          CASE WHEN v_amount > 0 THEN NULL ELSE 'zero_fee_policy' END,
          v_snap || jsonb_build_object('cancel_basis_kind', v_calc->>'cancel_basis_kind',
                                       'preparation_started', COALESCE(p_preparation_started,false)),
          p_is_sandbox)
  ON CONFLICT (source_module, source_id) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN RETURN jsonb_build_object('status','already_exists'); END IF;

  IF v_amount > 0 THEN
    PERFORM public._ledger_post(v_row.debt_key, p_source_module, p_source_id, 'cancellation_fee_charged',
      jsonb_build_array(
        jsonb_build_object('account','A_CUSTOMER_DEBT','amount_gnf',v_amount,
                           'party_type','client','party_user_id',p_customer,'memo','cancellation fee receivable'),
        jsonb_build_object('account','R_CANCELLATION_FEE','amount_gnf',-v_amount,'memo','cancellation fee revenue')),
      p_mission_type, p_actor, v_snap, p_is_sandbox);
  END IF;

  RETURN jsonb_build_object('status', CASE WHEN v_amount > 0 THEN 'charged' ELSE 'exempt' END,
                            'debt_id',v_row.id,'basis_kind',v_calc->>'cancel_basis_kind',
                            'basis_gnf',v_basis,'amount_gnf',v_amount,'applied_bps',v_bps);
END; $fn$;

-- ---------------------------------------------------------------------------
-- 3. Chop Pay order cancellation delegates arithmetic to the calculator.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._chop_pay_cancel_internal(
  p_source_module text, p_source_id uuid, p_responsible_party text,
  p_reason text, p_actor uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_row public.chop_pay_order_runtime; v_snap jsonb; v_stage text; v_bps int;
  v_basis bigint; v_charge bigint := 0; v_open bigint; v_rev jsonb; v_calc jsonb;
  v_col jsonb; v_ref jsonb; v_chg jsonb := jsonb_build_object('status','none','captured_gnf',0);
  v_basis_kind text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(format('choppay:%s:%s',p_source_module,p_source_id), 0));
  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
  IF v_row.state IN ('cancelled','merchant_rejected') THEN
    RETURN jsonb_build_object('status','already_cancelled');
  END IF;
  IF v_row.state IN ('preparing','completed','disputed','dispute_resolved') THEN
    RAISE EXCEPTION 'CHOP_PAY_PREPARATION_LOCKED'
      USING DETAIL = 'Preparation has started; open a dispute instead';
  END IF;

  v_snap  := v_row.policy_snapshot;
  v_stage := CASE WHEN v_row.state = 'authorized' THEN 'before_dispatch' ELSE 'after_dispatch' END;
  v_calc  := public._cancellation_compute(v_snap, v_stage, 0,
               v_row.merchandise_subtotal_gnf, v_row.delivery_fee_gnf, p_responsible_party);
  v_basis_kind := v_calc->>'cancel_basis_kind';
  v_basis := (v_calc->>'basis_gnf')::bigint;
  v_bps   := (v_calc->>'fee_bps')::int;

  -- Historical gate preserved verbatim (see DEF-FIN-S8-001).
  IF public._finance_flag('cancellation_policy_enabled') THEN
    v_charge := (v_calc->>'fee_gnf')::bigint;
  ELSE
    v_charge := 0;
  END IF;

  IF v_row.state = 'merchant_accepted' THEN
    v_rev := public._chop_pay_merchant_capture_reverse_internal(
      p_source_module, p_source_id, COALESCE(p_reason,'chop_pay_cancelled'), p_actor);
    IF v_rev->>'status' = 'reconciliation_required' THEN
      RAISE EXCEPTION 'FINANCE_RECONCILIATION_REQUIRED'
        USING DETAIL = COALESCE(v_rev->>'detail','merchant liability not recoverable');
    END IF;
  END IF;

  SELECT GREATEST(amount_gnf - captured_gnf - released_gnf, 0) INTO v_open
    FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'customer_payment';
  v_charge := LEAST(COALESCE(v_charge,0), COALESCE(v_open,0));

  IF v_charge > 0 THEN
    v_chg := public._chop_pay_customer_capture_internal(
      p_source_module, p_source_id, v_charge, 'cancellation_fee', p_actor);
  END IF;

  v_col := public._driver_mission_hold_release_internal(
    p_source_module, p_source_id, 'collateral', COALESCE(p_reason,'chop_pay_cancelled'), p_actor);
  v_ref := public._chop_pay_customer_release_internal(
    p_source_module, p_source_id, COALESCE(p_reason,'chop_pay_cancelled'), p_actor);

  UPDATE public.merchant_payables
     SET state='reversed', reason=COALESCE(p_reason,'chop_pay_cancelled'), updated_at = now()
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND state = 'pending_funding' AND funded_gnf = 0;

  UPDATE public.chop_pay_order_runtime
     SET state='cancelled', cancelled_at = now(),
         cancellation_charge_gnf = v_charge,
         merchant_credited_gnf = CASE WHEN v_rev->>'status' = 'reversed' THEN 0 ELSE merchant_credited_gnf END,
         customer_refunded_gnf = COALESCE((v_ref->>'released_gnf')::bigint,0)
                                 + COALESCE((v_rev->>'reversed_gnf')::bigint,0)
   WHERE id = v_row.id;

  PERFORM public._chop_pay_deactivate_source(p_source_module, p_source_id, v_row.mission_id);

  RETURN jsonb_build_object('status','cancelled','stage',v_stage,
    'responsible_party',p_responsible_party,
    'cancel_basis_kind',v_basis_kind,'basis_gnf',v_basis,'applied_bps',v_bps,
    'cancellation_charge_gnf',v_charge,'charge_capture',v_chg,
    'merchant_reversal',v_rev,'collateral_release',v_col,'customer_refund',v_ref,
    'cash_debt_created', false);
END; $fn$;

-- ---------------------------------------------------------------------------
-- 4. ride_cancel delegates arithmetic to the calculator.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ride_cancel(p_ride_id uuid, p_reason text DEFAULT 'Course annulée'::text)
RETURNS public.rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_claims text := current_setting('request.jwt.claims', true);
  v_ride public.rides; v_by text; v_stage text; v_mtype text; v_pay text;
  v_snap jsonb; v_bps int; v_fee bigint := 0; v_fee_tx public.wallet_transactions;
  v_release text := 'not_applicable'; v_responsible text; v_debt jsonb; v_calc jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;

  IF v_ride.client_id = v_uid THEN v_by := 'client';
  ELSIF v_ride.driver_id = v_uid THEN v_by := 'driver';
  ELSIF public.has_role(v_uid,'admin') THEN v_by := 'admin';
  ELSE RAISE EXCEPTION 'Not authorized'; END IF;

  IF v_ride.status IN ('completed','cancelled') THEN
    IF v_ride.driver_id IS NOT NULL THEN
      UPDATE public.driver_profiles SET presence='online', last_seen_at=now()
       WHERE user_id = v_ride.driver_id AND presence='on_trip';
    END IF;
    RETURN v_ride;
  END IF;
  IF v_ride.status='in_progress' AND v_by='client' THEN
    RAISE EXCEPTION 'ride_in_progress_cancel_not_allowed';
  END IF;

  v_mtype := public._ride_mission_type(v_ride.mode::text);
  v_pay   := public._ride_payment_mode(v_ride);
  v_stage := CASE WHEN v_ride.driver_id IS NOT NULL THEN 'after_dispatch' ELSE 'before_dispatch' END;
  v_snap  := COALESCE(v_ride.metadata->'finance_snapshot',
                      public.finance_policy_snapshot(v_mtype, now(), v_pay, v_ride.fare_gnf,0,0,0,false));
  v_responsible := CASE v_by WHEN 'client' THEN 'customer' WHEN 'driver' THEN 'driver' ELSE 'platform' END;

  v_calc := public._cancellation_compute(v_snap, v_stage, v_ride.fare_gnf, 0, 0, v_responsible);
  v_bps  := (v_calc->>'fee_bps')::int;
  v_fee  := (v_calc->>'fee_gnf')::bigint;

  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.driver_mission_hold_release('ride', p_ride_id, 'commission', p_reason);

  IF v_pay='chop_pay' AND v_ride.hold_tx_id IS NOT NULL
     AND COALESCE((v_ride.metadata->>'cancellation_fee_gnf')::bigint,0)=0 THEN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ride.client_id), true);
    IF v_fee > 0 THEN
      BEGIN
        PERFORM public.wallet_ensure_master();
        v_fee_tx := public.wallet_capture(
          p_hold_id := v_ride.hold_tx_id, p_to_user_id := NULL,
          p_to_party_type := 'master'::public.party_type,
          p_actual_amount_gnf := v_fee, p_description := 'Frais d''annulation client CHOPCHOP');
        v_release := 'fee_captured';
      EXCEPTION WHEN OTHERS THEN
        v_release := 'fee_capture_error: ' || SQLERRM; v_fee := 0;
        BEGIN PERFORM public.wallet_release(p_hold_id := v_ride.hold_tx_id, p_reason := p_reason);
        EXCEPTION WHEN OTHERS THEN v_release := v_release || ' — release_error: ' || SQLERRM; END;
      END;
    ELSE
      BEGIN PERFORM public.wallet_release(p_hold_id := v_ride.hold_tx_id, p_reason := p_reason);
        v_release := 'released_no_fee';
      EXCEPTION WHEN OTHERS THEN v_release := 'release_error: ' || SQLERRM; END;
    END IF;
    PERFORM set_config('request.jwt.claims', '', true);
  ELSIF v_pay='cash' AND v_ride.fare_gnf > 0 THEN
    BEGIN
      v_debt := public._customer_cancellation_debt_create_internal(
        p_source_module := 'ride', p_source_id := p_ride_id, p_customer := v_ride.client_id,
        p_mission_type := v_mtype, p_stage := v_stage, p_fare_gnf := v_ride.fare_gnf,
        p_merchandise_subtotal_gnf := 0, p_delivery_fee_gnf := 0,
        p_preparation_started := false, p_responsible_party := v_responsible,
        p_is_sandbox := false, p_policy_snapshot := v_snap, p_actor := v_uid);
      v_release := 'cash_debt:' || COALESCE(v_debt->>'status','unknown');
      v_fee := COALESCE((v_debt->>'amount_gnf')::bigint, 0);
    EXCEPTION WHEN OTHERS THEN v_release := 'debt_error: ' || SQLERRM; v_fee := 0; END;
  END IF;

  PERFORM set_config('request.jwt.claims', COALESCE(v_claims,''), true);

  UPDATE public.ride_offers SET status='cancelled', responded_at=COALESCE(responded_at, now())
   WHERE ride_id = p_ride_id AND status='pending';

  UPDATE public.rides SET status='cancelled',
    metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
      'cancelled_by', v_by, 'cancelled_at', to_jsonb(now()), 'cancel_reason', p_reason,
      'cancel_stage', v_stage, 'cancel_bps', v_bps, 'responsible_party', v_responsible,
      'hold_release', v_release, 'cancellation_fee_gnf', v_fee,
      'cancellation_fee_tx_id', COALESCE(v_fee_tx.id::text, NULL),
      'driver_deployed_at_cancel', (v_ride.driver_id IS NOT NULL)),
    updated_at = now()
  WHERE id = p_ride_id RETURNING * INTO v_ride;

  IF v_ride.driver_id IS NOT NULL THEN
    UPDATE public.driver_profiles SET presence='online', last_seen_at=now()
     WHERE user_id = v_ride.driver_id AND presence='on_trip';
  END IF;

  IF v_fee > 0 THEN
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
    VALUES (v_uid,'wallet','cancellation_fee_charged','ride', p_ride_id::text,
            jsonb_build_object('fee_gnf',v_fee,'stage',v_stage,'bps',v_bps,
                               'payment_mode',v_pay,'responsible',v_responsible),
            'Frais d''annulation CHOPCHOP');
  END IF;
  RETURN v_ride;
END; $fn$;

-- ---------------------------------------------------------------------------
-- 5. Envoyer: canonical basis = frozen delivery/service fee ONLY.
--    Replaces the hard-coded 10%-of-quoted-amount rule (DEF-FIN-S8-002).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._package_cancel_release_internal(
  p_package_id uuid, p_reason text DEFAULT NULL, p_actor uuid DEFAULT NULL,
  p_responsible_party text DEFAULT 'customer'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_r public.package_runtime; v_rel jsonb; v_cust jsonb; v_stage text;
  v_calc jsonb; v_fee bigint := 0; v_open bigint; v_cap jsonb; v_debt jsonb;
BEGIN
  SELECT * INTO v_r FROM public.package_runtime WHERE package_id = p_package_id FOR UPDATE;
  IF v_r.id IS NULL THEN RETURN jsonb_build_object('status','no_runtime'); END IF;
  IF v_r.claim_state <> 'none' THEN RAISE EXCEPTION 'SETTLEMENT_FROZEN_BY_CLAIM'; END IF;
  IF v_r.state = 'cancelled' THEN RETURN jsonb_build_object('status','already_cancelled'); END IF;
  IF v_r.state NOT IN ('authorized','accepted') THEN
    RAISE EXCEPTION 'CUSTODY_ESTABLISHED_CLAIM_REQUIRED' USING DETAIL = v_r.state;
  END IF;

  v_stage := CASE WHEN v_r.state = 'authorized' THEN 'before_dispatch' ELSE 'after_dispatch' END;
  -- Declared value and collateral are NEVER part of the cancellation basis.
  v_calc  := public._cancellation_compute(v_r.policy_snapshot, v_stage, 0, 0,
               v_r.delivery_fee_gnf, COALESCE(p_responsible_party,'customer'));
  v_fee   := (v_calc->>'fee_gnf')::bigint;

  IF v_fee > 0 AND v_r.tender = 'chop_pay' THEN
    SELECT GREATEST(amount_gnf - captured_gnf - released_gnf, 0) INTO v_open
      FROM public.mission_financial_holds
     WHERE source_module = 'package' AND source_id = p_package_id AND kind = 'customer_payment';
    v_fee := LEAST(v_fee, COALESCE(v_open,0));
    IF v_fee > 0 THEN
      v_cap := public._package_choppay_capture_internal(p_package_id, v_fee, 'cancellation_fee', p_actor);
    END IF;
  END IF;

  v_rel := public._driver_mission_hold_release_internal('package', p_package_id, NULL,
                                                        COALESCE(p_reason,'envoyer_cancelled'), p_actor);
  IF v_r.tender = 'chop_pay' THEN
    v_cust := public._package_choppay_release_internal(p_package_id,
                COALESCE(p_reason,'envoyer_cancelled'), p_actor);
  ELSIF v_fee > 0 THEN
    v_debt := public._customer_cancellation_debt_create_internal(
      'package', p_package_id, v_r.customer_user_id, 'envoyer', v_stage,
      0, 0, v_r.delivery_fee_gnf, false, 'customer', false, v_r.policy_snapshot, p_actor);
  END IF;

  UPDATE public.package_runtime SET state = 'cancelled', cancelled_at = now() WHERE id = v_r.id;

  RETURN jsonb_build_object('status','cancelled','stage',v_stage,
    'cancel_basis_kind', v_calc->>'cancel_basis_kind',
    'basis_gnf', (v_calc->>'basis_gnf')::bigint,
    'applied_bps', (v_calc->>'fee_bps')::int,
    'cancellation_fee_gnf', v_fee,
    'fee_capture', v_cap, 'cash_debt', v_debt,
    'driver_release',v_rel,'customer_release',v_cust);
END; $fn$;

REVOKE ALL ON FUNCTION public._package_cancel_release_internal(uuid,text,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._package_cancel_release_internal(uuid,text,uuid,text) TO service_role;

CREATE OR REPLACE FUNCTION public.package_delivery_cancel(p_package_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid(); v_pkg public.package_deliveries; v_m public.missions;
  v_s public.package_delivery_secrets; v_rt public.package_runtime;
  v_fee bigint := 0; v_refund bigint; v_req uuid; v_issue uuid; v_rel jsonb;
  v_snap jsonb; v_stage text; v_calc jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_package_id FOR UPDATE;
  IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'package_not_found'; END IF;
  IF v_pkg.sender_user_id <> v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  IF v_pkg.cancelled_at IS NOT NULL THEN
    RETURN jsonb_build_object('idempotent', true, 'status', v_pkg.package_status,
      'refund_request_id', v_pkg.refund_request_id, 'fee_gnf', v_pkg.cancellation_fee_gnf);
  END IF;

  SELECT * INTO v_m FROM public.missions WHERE id = v_pkg.mission_id FOR UPDATE;
  SELECT * INTO v_s FROM public.package_delivery_secrets WHERE package_id = p_package_id;
  SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = p_package_id;

  IF v_rt.id IS NOT NULL AND v_rt.claim_state <> 'none' THEN
    RAISE EXCEPTION 'SETTLEMENT_FROZEN_BY_CLAIM' USING ERRCODE='22023';
  END IF;

  IF v_s.pickup_verified_at IS NOT NULL OR v_pkg.package_status IN ('in_transit','delivered') THEN
    IF v_pkg.support_issue_id IS NULL THEN
      INSERT INTO public.support_issues(
        issue_type, severity, title, description, reporter_user_id,
        related_mission_id, related_payment_intent_id, related_customer_id, metadata)
      VALUES ('package_dispute','high',
        'Colis déjà récupéré — demande d''annulation ' || v_pkg.reference,
        COALESCE(p_reason, 'Annulation demandée après récupération du colis.'), v_uid,
        v_pkg.mission_id, v_pkg.payment_intent_id, v_uid,
        jsonb_build_object('package_id', v_pkg.id, 'reference', v_pkg.reference,
                           'sandbox', v_pkg.is_sandbox))
      RETURNING id INTO v_issue;
      UPDATE public.package_deliveries SET support_issue_id = v_issue WHERE id = p_package_id;
    ELSE
      v_issue := v_pkg.support_issue_id;
    END IF;
    RETURN jsonb_build_object('idempotent', false, 'self_service', false,
      'error', 'CUSTODY_ESTABLISHED_CLAIM_REQUIRED', 'claim_required', true,
      'support_issue_id', v_issue, 'status', v_pkg.package_status);
  END IF;

  IF v_rt.id IS NOT NULL THEN
    v_rel := public._package_cancel_release_internal(p_package_id,
               COALESCE(p_reason,'client_cancelled'), v_uid, 'customer');
    v_fee := COALESCE((v_rel->>'cancellation_fee_gnf')::bigint, 0);
  ELSE
    -- Legacy pre-runtime package: freeze policy at creation time, basis = quoted
    -- delivery/service fee only.
    v_stage := CASE WHEN v_m.id IS NOT NULL AND v_m.courier_id IS NOT NULL
                    THEN 'after_dispatch' ELSE 'before_dispatch' END;
    v_snap  := COALESCE(v_pkg.metadata->'finance_snapshot',
                 public.finance_policy_snapshot('envoyer', v_pkg.created_at, 'chop_pay',
                                                0, 0, v_pkg.quoted_amount_gnf, 0, v_pkg.is_sandbox));
    v_calc  := public._cancellation_compute(v_snap, v_stage, 0, 0, v_pkg.quoted_amount_gnf, 'customer');
    v_fee   := (v_calc->>'fee_gnf')::bigint;
  END IF;
  v_refund := GREATEST(v_pkg.quoted_amount_gnf - v_fee, 0);

  IF v_m.id IS NOT NULL THEN
    UPDATE public.missions SET state = 'failed'::public.mission_state,
           issue_reason = COALESCE(p_reason, 'client_cancelled') WHERE id = v_m.id;
  END IF;

  UPDATE public.package_deliveries
     SET package_status = 'cancelled', cancelled_at = now(),
         cancellation_reason = left(COALESCE(p_reason,'client_cancelled'), 300),
         cancellation_fee_gnf = v_fee
   WHERE id = p_package_id;

  IF v_pkg.payment_intent_id IS NOT NULL
     AND v_pkg.payment_status IN ('authorized','settled')
     AND v_refund > 0 AND v_rt.id IS NULL THEN
    INSERT INTO public.payment_refund_requests(
      payment_intent_id, user_id, source_module, source_id,
      original_amount_gnf, fee_gnf, amount_gnf, reason,
      is_sandbox, environment, test_run_id, metadata)
    VALUES (v_pkg.payment_intent_id, v_uid, 'package', v_pkg.id,
      v_pkg.quoted_amount_gnf, v_fee, v_refund,
      COALESCE(p_reason, 'client_cancelled'), v_pkg.is_sandbox, v_pkg.environment, v_pkg.test_run_id,
      jsonb_build_object('package_reference', v_pkg.reference))
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_req;
    IF v_req IS NOT NULL THEN
      UPDATE public.package_deliveries SET refund_request_id = v_req WHERE id = p_package_id;
    END IF;
  END IF;

  RETURN jsonb_build_object('idempotent', false, 'self_service', true, 'status','cancelled',
    'fee_gnf', v_fee, 'refund_gnf', v_refund, 'refund_request_id', v_req, 'release', v_rel);
END; $fn$;

-- ---------------------------------------------------------------------------
-- 6. THE canonical quote. Preview and execution share _cancellation_compute.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancellation_quote(
  p_service text, p_source_id uuid, p_source_module text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides; v_cash public.cash_order_runtime; v_cp public.chop_pay_order_runtime;
  v_pkg public.package_deliveries; v_rt public.package_runtime;
  v_s public.package_delivery_secrets; v_m public.missions;
  v_f jsonb; v_e jsonb; v_snap jsonb; v_calc jsonb;
  v_stage text; v_mtype text; v_pay text; v_cancelable boolean := true;
  v_lock text; v_debt bigint := 0; v_refund bigint := 0; v_open bigint := 0;
  v_sub bigint := 0; v_del bigint := 0; v_fare bigint := 0; v_fee bigint := 0;
  v_customer uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;

  IF p_service = 'ride' THEN
    SELECT * INTO v_ride FROM public.rides WHERE id = p_source_id;
    IF v_ride.id IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
    IF v_ride.client_id <> v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
    v_customer := v_ride.client_id;
    v_mtype := public._ride_mission_type(v_ride.mode::text);
    v_pay   := public._ride_payment_mode(v_ride);
    v_fare  := v_ride.fare_gnf;
    v_stage := CASE WHEN v_ride.driver_id IS NOT NULL THEN 'after_dispatch' ELSE 'before_dispatch' END;
    v_snap  := COALESCE(v_ride.metadata->'finance_snapshot',
                 public.finance_policy_snapshot(v_mtype, now(), v_pay, v_ride.fare_gnf,0,0,0,false));
    IF v_ride.status IN ('completed','cancelled') THEN
      v_cancelable := false; v_lock := 'already_closed';
    ELSIF v_ride.status = 'in_progress' THEN
      v_cancelable := false; v_lock := 'ride_in_progress';
    END IF;

  ELSIF p_service = 'cash_order' THEN
    IF p_source_module IS NULL THEN RAISE EXCEPTION 'source_module_required'; END IF;
    v_f := public._cash_order_facts(p_source_module, p_source_id);
    IF (v_f->>'customer_user_id')::uuid <> v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
    v_customer := v_uid; v_mtype := v_f->>'mission_type'; v_pay := 'cash';
    SELECT * INTO v_cash FROM public.cash_order_runtime
     WHERE source_module = p_source_module AND source_id = p_source_id;
    IF v_cash.id IS NULL THEN
      v_e := public._cash_order_economics(v_f);
      v_stage := 'before_dispatch';
      v_snap := COALESCE(v_e->'policy_snapshot','{}'::jsonb);
      v_sub  := (v_e->>'merchandise_subtotal_gnf')::bigint;
      v_del  := (v_e->>'delivery_fee_gnf')::bigint;
    ELSE
      v_stage := 'after_dispatch';
      v_snap := v_cash.policy_snapshot; v_sub := v_cash.merchandise_subtotal_gnf;
      v_del := v_cash.delivery_fee_gnf;
      IF v_cash.state = 'cancelled' THEN v_cancelable := false; v_lock := 'already_cancelled';
      ELSIF v_cash.state IN ('preparing','completed','disputed','dispute_resolved') THEN
        v_cancelable := false; v_lock := 'preparation_started';
      ELSIF v_cash.state = 'merchant_accepted' THEN
        v_cancelable := false; v_lock := 'merchandise_funded';
      END IF;
    END IF;

  ELSIF p_service = 'chop_pay_order' THEN
    IF p_source_module IS NULL THEN RAISE EXCEPTION 'source_module_required'; END IF;
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime
     WHERE source_module = p_source_module AND source_id = p_source_id;
    IF v_cp.id IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
    IF v_cp.customer_user_id <> v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
    v_customer := v_cp.customer_user_id; v_mtype := v_cp.mission_type; v_pay := 'chop_pay';
    v_snap := v_cp.policy_snapshot; v_sub := v_cp.merchandise_subtotal_gnf; v_del := v_cp.delivery_fee_gnf;
    v_stage := CASE WHEN v_cp.state = 'authorized' THEN 'before_dispatch' ELSE 'after_dispatch' END;
    IF v_cp.state IN ('cancelled','merchant_rejected') THEN v_cancelable := false; v_lock := 'already_cancelled';
    ELSIF v_cp.state IN ('preparing','completed','disputed','dispute_resolved') THEN
      v_cancelable := false; v_lock := 'preparation_started';
    END IF;
    SELECT GREATEST(amount_gnf - captured_gnf - released_gnf, 0) INTO v_open
      FROM public.mission_financial_holds
     WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'customer_payment';

  ELSIF p_service = 'package' THEN
    SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_source_id;
    IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
    IF v_pkg.sender_user_id <> v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
    v_customer := v_pkg.sender_user_id; v_mtype := 'envoyer';
    SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = p_source_id;
    SELECT * INTO v_s  FROM public.package_delivery_secrets WHERE package_id = p_source_id;
    SELECT * INTO v_m  FROM public.missions WHERE id = v_pkg.mission_id;
    v_del := COALESCE(NULLIF(v_rt.delivery_fee_gnf,0), v_pkg.quoted_amount_gnf);
    v_pay := COALESCE(v_rt.tender, 'chop_pay');
    IF v_rt.id IS NOT NULL THEN
      v_snap := v_rt.policy_snapshot;
      v_stage := CASE WHEN v_rt.state = 'authorized' THEN 'before_dispatch' ELSE 'after_dispatch' END;
    ELSE
      v_stage := CASE WHEN v_m.courier_id IS NOT NULL THEN 'after_dispatch' ELSE 'before_dispatch' END;
      v_snap := COALESCE(v_pkg.metadata->'finance_snapshot',
                  public.finance_policy_snapshot('envoyer', v_pkg.created_at, 'chop_pay',
                                                 0, 0, v_pkg.quoted_amount_gnf, 0, v_pkg.is_sandbox));
    END IF;
    IF v_pkg.cancelled_at IS NOT NULL THEN v_cancelable := false; v_lock := 'already_cancelled';
    ELSIF v_rt.id IS NOT NULL AND v_rt.claim_state <> 'none' THEN
      v_cancelable := false; v_lock := 'claim_open';
    ELSIF v_s.pickup_verified_at IS NOT NULL OR v_pkg.package_status IN ('in_transit','delivered') THEN
      v_cancelable := false; v_lock := 'custody_established';
    END IF;

  ELSE
    RAISE EXCEPTION 'unsupported_service' USING DETAIL = COALESCE(p_service,'null');
  END IF;

  v_calc := public._cancellation_compute(v_snap, v_stage, v_fare, v_sub, v_del, 'customer');
  v_fee  := (v_calc->>'fee_gnf')::bigint;

  -- Bind the quote to the exact gate the execution path applies.
  IF p_service = 'chop_pay_order' AND NOT public._finance_flag('cancellation_policy_enabled') THEN
    v_fee := 0;
  END IF;
  IF NOT v_cancelable THEN v_fee := 0; END IF;

  IF v_pay = 'chop_pay' THEN
    IF p_service = 'chop_pay_order' THEN
      v_fee := LEAST(v_fee, v_open);
      v_refund := GREATEST(v_open - v_fee, 0);
    ELSIF p_service = 'ride' THEN
      v_refund := GREATEST(v_fare - v_fee, 0);
    ELSE
      v_refund := GREATEST(v_del - v_fee, 0);
    END IF;
  ELSE
    v_debt := v_fee;
  END IF;

  RETURN jsonb_build_object(
    'schema','chopchop.finance.cancellation_quote','version',1,
    'service', p_service, 'source_module', COALESCE(p_source_module, p_service),
    'source_id', p_source_id, 'mission_type', v_mtype,
    'payment_mode', v_pay, 'cancelable', v_cancelable, 'lock_reason', v_lock,
    'stage', v_stage, 'responsible_party','customer',
    'cancel_basis_kind', v_calc->>'cancel_basis_kind',
    'basis_gnf', (v_calc->>'basis_gnf')::bigint,
    'fee_bps', (v_calc->>'fee_bps')::int,
    'fee_gnf', v_fee,
    'debt_if_cash_gnf', v_debt,
    'refundable_gnf', v_refund,
    'policy_id', v_snap->>'policy_id',
    'policy_effective_from', v_snap->>'effective_from',
    'snapshot_version', v_snap->>'version',
    'quoted_at', now());
END; $fn$;

REVOKE ALL ON FUNCTION public.cancellation_quote(text,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancellation_quote(text,uuid,text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. Cash-exposure restriction driven by outstanding cancellation debt.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._customer_cash_restricted(p_user uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM public.customer_cancellation_debts
     WHERE customer_user_id = p_user
       AND state = 'outstanding'
       AND (amount_gnf - paid_gnf - waived_gnf) > 0
  )
$fn$;

REVOKE ALL ON FUNCTION public._customer_cash_restricted(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._customer_cash_restricted(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.customer_cash_eligibility()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_uid uuid := auth.uid(); v_out bigint; v_n int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  SELECT COALESCE(SUM(amount_gnf - paid_gnf - waived_gnf),0), COUNT(*)
    INTO v_out, v_n
    FROM public.customer_cancellation_debts
   WHERE customer_user_id = v_uid AND state = 'outstanding'
     AND (amount_gnf - paid_gnf - waived_gnf) > 0;
  RETURN jsonb_build_object(
    'schema','chopchop.finance.cash_eligibility','version',1,
    'cash_orders_allowed', (v_out <= 0),
    'outstanding_debt_gnf', v_out,
    'outstanding_debt_count', v_n,
    'account_locked', false,
    'still_allowed', jsonb_build_array('auth','history','receipts','support','debt_repayment','chop_pay'),
    'checked_at', now());
END; $fn$;

REVOKE ALL ON FUNCTION public.customer_cash_eligibility() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_cash_eligibility() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public._block_new_cash_exposure()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_user uuid; v_is_cash boolean;
BEGIN
  IF TG_TABLE_NAME = 'rides' THEN
    v_user := NEW.client_id;
    v_is_cash := (public._ride_payment_mode(NEW) = 'cash');
  ELSIF TG_TABLE_NAME = 'cash_order_runtime' THEN
    v_user := NEW.customer_user_id; v_is_cash := true;
  ELSIF TG_TABLE_NAME = 'package_runtime' THEN
    v_user := NEW.customer_user_id; v_is_cash := (NEW.tender = 'cash');
  ELSE
    RETURN NEW;
  END IF;

  IF v_is_cash AND v_user IS NOT NULL AND public._customer_cash_restricted(v_user) THEN
    RAISE EXCEPTION 'CUSTOMER_CASH_RESTRICTED_BY_DEBT'
      USING DETAIL = 'Outstanding cancellation debt blocks new cash orders only';
  END IF;
  RETURN NEW;
END; $fn$;

DROP TRIGGER IF EXISTS trg_block_cash_exposure_rides ON public.rides;
CREATE TRIGGER trg_block_cash_exposure_rides
  BEFORE INSERT ON public.rides
  FOR EACH ROW EXECUTE FUNCTION public._block_new_cash_exposure();

DROP TRIGGER IF EXISTS trg_block_cash_exposure_cash_order ON public.cash_order_runtime;
CREATE TRIGGER trg_block_cash_exposure_cash_order
  BEFORE INSERT ON public.cash_order_runtime
  FOR EACH ROW EXECUTE FUNCTION public._block_new_cash_exposure();

DROP TRIGGER IF EXISTS trg_block_cash_exposure_package ON public.package_runtime;
CREATE TRIGGER trg_block_cash_exposure_package
  BEFORE INSERT ON public.package_runtime
  FOR EACH ROW EXECUTE FUNCTION public._block_new_cash_exposure();

-- ---------------------------------------------------------------------------
-- 8. Debt repayment. Server-authoritative, partial-capable, never over-collects.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._customer_cancellation_debt_settle_internal(
  p_debt_id uuid, p_amount_gnf bigint, p_actor uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_d public.customer_cancellation_debts; v_w public.wallets; v_master public.wallets;
  v_take bigint; v_avail bigint; v_owed bigint; v_key text;
BEGIN
  SELECT * INTO v_d FROM public.customer_cancellation_debts WHERE id = p_debt_id FOR UPDATE;
  IF v_d.id IS NULL THEN RAISE EXCEPTION 'Debt not found'; END IF;
  IF v_d.state <> 'outstanding' THEN RETURN jsonb_build_object('status','not_outstanding'); END IF;

  v_owed := v_d.amount_gnf - v_d.paid_gnf - v_d.waived_gnf;
  IF v_owed <= 0 THEN RETURN jsonb_build_object('status','nothing_outstanding'); END IF;

  SELECT * INTO v_w FROM public.wallets
   WHERE owner_user_id = v_d.customer_user_id AND party_type = 'client' FOR UPDATE;
  -- Restricted (promotional) funds can never settle a customer receivable.
  v_avail := GREATEST(COALESCE(v_w.balance_gnf,0) - COALESCE(v_w.held_gnf,0), 0);

  v_take := LEAST(v_owed, v_avail);
  IF p_amount_gnf IS NOT NULL THEN
    IF p_amount_gnf <= 0 THEN RAISE EXCEPTION 'INVALID_REPAYMENT_AMOUNT'; END IF;
    v_take := LEAST(v_take, p_amount_gnf);
  END IF;
  IF v_take <= 0 THEN
    RETURN jsonb_build_object('status','no_funds','outstanding_gnf', v_owed);
  END IF;

  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
  UPDATE public.wallets SET balance_gnf = balance_gnf - v_take, updated_at = now() WHERE id = v_w.id;
  IF v_master.id IS NOT NULL THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf + v_take, updated_at = now() WHERE id = v_master.id;
  END IF;

  -- Keyed on the pre-state so a replayed identical call cannot double-post.
  v_key := format('cancel-collect:%s:%s', v_d.id::text, v_d.paid_gnf);
  PERFORM public._ledger_post(v_key, v_d.source_module, v_d.source_id,
    'cancellation_fee_collected',
    jsonb_build_array(
      jsonb_build_object('account','L_CUSTOMER_CHOPPAY','amount_gnf',v_take,
                         'party_type','client','party_user_id',v_d.customer_user_id,'memo','debt settled from balance'),
      jsonb_build_object('account','A_CUSTOMER_DEBT','amount_gnf',-v_take,
                         'party_type','client','party_user_id',v_d.customer_user_id,'memo','receivable cleared')),
    v_d.mission_type, p_actor, v_d.policy_snapshot, v_d.is_sandbox);

  UPDATE public.customer_cancellation_debts
     SET paid_gnf = paid_gnf + v_take,
         state = CASE WHEN paid_gnf + v_take + waived_gnf >= amount_gnf THEN 'paid' ELSE 'outstanding' END,
         resolved_by = CASE WHEN paid_gnf + v_take + waived_gnf >= amount_gnf THEN p_actor ELSE resolved_by END,
         resolved_at = CASE WHEN paid_gnf + v_take + waived_gnf >= amount_gnf THEN now() ELSE resolved_at END,
         updated_at = now()
   WHERE id = v_d.id;

  RETURN jsonb_build_object('status','collected','collected_gnf',v_take,
    'outstanding_gnf', v_owed - v_take,
    'fully_paid', (v_owed - v_take) <= 0);
END; $fn$;

REVOKE ALL ON FUNCTION public._customer_cancellation_debt_settle_internal(uuid,bigint,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._customer_cancellation_debt_settle_internal(uuid,bigint,uuid) TO service_role;

-- Finance/ops collection path keeps its existing authority, now single-sourced.
CREATE OR REPLACE FUNCTION public.customer_cancellation_debt_collect(p_debt_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_caller uuid := auth.uid();
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  RETURN public._customer_cancellation_debt_settle_internal(p_debt_id, NULL, v_caller);
END; $fn$;

REVOKE ALL ON FUNCTION public.customer_cancellation_debt_collect(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.customer_cancellation_debt_collect(uuid) TO service_role;

-- Customer self-service repayment.
CREATE OR REPLACE FUNCTION public.customer_cancellation_debt_repay(
  p_debt_id uuid, p_amount_gnf bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_uid uuid := auth.uid(); v_owner uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  SELECT customer_user_id INTO v_owner
    FROM public.customer_cancellation_debts WHERE id = p_debt_id;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'Debt not found'; END IF;
  IF v_owner <> v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  RETURN public._customer_cancellation_debt_settle_internal(p_debt_id, p_amount_gnf, v_uid);
END; $fn$;

REVOKE ALL ON FUNCTION public.customer_cancellation_debt_repay(uuid,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_cancellation_debt_repay(uuid,bigint) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 9. Customer-facing debt read model (self-only).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.customer_cancellation_debts_overview()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_uid uuid := auth.uid(); v_items jsonb; v_out bigint; v_avail bigint;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;

  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'created_at' DESC), '[]'::jsonb),
         COALESCE(SUM((x->>'outstanding_gnf')::bigint), 0)
    INTO v_items, v_out
  FROM (
    SELECT jsonb_build_object(
      'debt_id', d.id, 'source_module', d.source_module, 'source_id', d.source_id,
      'mission_type', d.mission_type, 'stage', d.stage, 'state', d.state,
      'basis_gnf', d.basis_gnf, 'applied_bps', d.applied_bps, 'amount_gnf', d.amount_gnf,
      'paid_gnf', d.paid_gnf, 'waived_gnf', d.waived_gnf,
      'outstanding_gnf', GREATEST(d.amount_gnf - d.paid_gnf - d.waived_gnf, 0),
      'created_at', d.created_at, 'resolved_at', d.resolved_at) AS x
    FROM public.customer_cancellation_debts d
    WHERE d.customer_user_id = v_uid AND d.state = 'outstanding'
      AND (d.amount_gnf - d.paid_gnf - d.waived_gnf) > 0
  ) s;

  SELECT GREATEST(COALESCE(balance_gnf,0) - COALESCE(held_gnf,0), 0) INTO v_avail
    FROM public.wallets WHERE owner_user_id = v_uid AND party_type = 'client';

  RETURN jsonb_build_object(
    'schema','chopchop.finance.cancellation_debts','version',1,
    'outstanding_total_gnf', v_out,
    'available_gnf', COALESCE(v_avail,0),
    'cash_orders_allowed', (v_out <= 0),
    'account_locked', false,
    'items', v_items,
    'generated_at', now());
END; $fn$;

REVOKE ALL ON FUNCTION public.customer_cancellation_debts_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_cancellation_debts_overview() TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 10. Retire the divergent Envoyer preview: it now proxies the canonical quote.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.package_delivery_cancel_preview(p_package_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_q jsonb; v_pkg public.package_deliveries;
BEGIN
  v_q := public.cancellation_quote('package', p_package_id, 'package');
  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_package_id;
  RETURN v_q || jsonb_build_object(
    'already_cancelled', (v_pkg.cancelled_at IS NOT NULL),
    'self_service', (v_q->>'cancelable')::boolean,
    'reason', v_q->>'lock_reason',
    'courier_assigned', (v_q->>'stage' = 'after_dispatch'),
    'fee_gnf', (v_q->>'fee_gnf')::bigint,
    'refund_gnf', (v_q->>'refundable_gnf')::bigint,
    'paid', (v_pkg.payment_status IN ('authorized','settled')));
END; $fn$;

REVOKE ALL ON FUNCTION public.package_delivery_cancel_preview(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.package_delivery_cancel_preview(uuid) TO authenticated, service_role;