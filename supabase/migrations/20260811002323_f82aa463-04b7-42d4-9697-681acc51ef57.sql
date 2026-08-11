-- ============================================================
-- SLICE 6 — Envoyer declared-value & claims engine (functions)
-- ============================================================

-- ---------- storage policies: private package-evidence bucket ----------
DROP POLICY IF EXISTS "Package evidence: sender upload" ON storage.objects;
CREATE POLICY "Package evidence: sender upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'package-evidence'
              AND (auth.uid())::text = (storage.foldername(name))[1]);

DROP POLICY IF EXISTS "Package evidence: sender read" ON storage.objects;
CREATE POLICY "Package evidence: sender read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'package-evidence'
         AND (auth.uid())::text = (storage.foldername(name))[1]);

DROP POLICY IF EXISTS "Package evidence: assigned courier read" ON storage.objects;
CREATE POLICY "Package evidence: assigned courier read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'package-evidence' AND EXISTS (
    SELECT 1 FROM public.package_evidence_photos p
      JOIN public.package_deliveries pd ON pd.id = p.package_id
      JOIN public.missions m ON m.id = pd.mission_id
     WHERE p.storage_path = storage.objects.name
       AND m.courier_id = auth.uid()));

DROP POLICY IF EXISTS "Package evidence: ops read" ON storage.objects;
CREATE POLICY "Package evidence: ops read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'package-evidence' AND public.can_manage_operations(auth.uid()));

-- ---------- economics (frozen at authorisation) ----------
CREATE OR REPLACE FUNCTION public._package_economics(
  p_declared_value_gnf bigint, p_delivery_fee_gnf bigint, p_tender text,
  p_is_sandbox boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_req jsonb; v_snap jsonb; v_col bigint; v_fee bigint; v_exposure bigint; v_max bigint;
BEGIN
  IF p_tender NOT IN ('cash','chop_pay') THEN RAISE EXCEPTION 'ENVOYER_TENDER_REQUIRED'; END IF;
  IF COALESCE(p_declared_value_gnf,0) <= 0 THEN RAISE EXCEPTION 'DECLARED_VALUE_REQUIRED'; END IF;
  IF COALESCE(p_delivery_fee_gnf,0) <= 0 THEN RAISE EXCEPTION 'DELIVERY_FEE_REQUIRED'; END IF;

  v_req := public.finance_mission_requirement_v2(
             'envoyer', 0, 0, p_delivery_fee_gnf, p_declared_value_gnf, p_tender);
  IF NOT COALESCE((v_req->>'has_policy')::boolean,false) THEN RAISE EXCEPTION 'NO_ACTIVE_POLICY'; END IF;
  IF COALESCE((v_req->>'declared_value_exceeds_cap')::boolean,false) THEN
    RAISE EXCEPTION 'DECLARED_VALUE_ABOVE_CEILING'
      USING DETAIL = format('declared=%s ceiling=%s',
                            p_declared_value_gnf, v_req->>'max_declared_value_gnf');
  END IF;
  IF COALESCE((v_req->>'commission_gnf')::bigint,0) <> 0 THEN
    RAISE EXCEPTION 'ENVOYER_COMMISSION_MUST_BE_ZERO';
  END IF;
  IF COALESCE(v_req->>'fee_basis','none') <> 'delivery_fee' THEN
    RAISE EXCEPTION 'ENVOYER_FEE_BASIS_MUST_BE_DELIVERY_FEE' USING DETAIL = COALESCE(v_req->>'fee_basis','none');
  END IF;

  v_col := GREATEST(COALESCE((v_req->>'collateral_gnf')::bigint,0),0);
  v_fee := GREATEST(COALESCE((v_req->>'platform_fee_gnf')::bigint,0),0);
  v_snap := public.finance_policy_snapshot('envoyer', now(), p_tender, 0, 0,
                                           p_delivery_fee_gnf, p_declared_value_gnf,
                                           COALESCE(p_is_sandbox,false));
  v_max := (v_snap->>'claims_exposure_max_gnf')::bigint;
  v_exposure := GREATEST(p_declared_value_gnf - v_col, 0);
  IF v_max IS NOT NULL THEN v_exposure := LEAST(v_exposure, v_max); END IF;

  RETURN jsonb_build_object(
    'declared_value_gnf', p_declared_value_gnf,
    'delivery_fee_gnf', p_delivery_fee_gnf,
    'tender', p_tender,
    'collateral_gnf', v_col,
    'claims_exposure_gnf', v_exposure,
    'platform_fee_gnf', v_fee,
    'commission_gnf', 0,
    'customer_hold_gnf', CASE WHEN p_tender = 'chop_pay' THEN p_delivery_fee_gnf + v_fee ELSE 0 END,
    'cash_due_gnf', CASE WHEN p_tender = 'cash' THEN p_delivery_fee_gnf + v_fee ELSE 0 END,
    'requirement', v_req,
    'policy_snapshot', v_snap);
END; $$;

-- ---------- dispatch (mission + verification codes) ----------
CREATE OR REPLACE FUNCTION public._package_dispatch_internal(p_package_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_pkg public.package_deliveries; v_mission public.missions;
BEGIN
  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_package_id FOR UPDATE;
  IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'package_not_found'; END IF;
  IF v_pkg.mission_id IS NOT NULL THEN
    RETURN jsonb_build_object('idempotent', true, 'package_id', v_pkg.id, 'mission_id', v_pkg.mission_id);
  END IF;

  INSERT INTO public.missions(
    type, state, customer_id, courier_id,
    pickup_address, pickup_lat, pickup_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    payload_summary, estimated_earning_gnf, estimated_distance_m, estimated_duration_s)
  VALUES (
    'package_delivery'::public.mission_type, 'assigned'::public.mission_state,
    v_pkg.sender_user_id, NULL,
    v_pkg.pickup_label, v_pkg.pickup_lat, v_pkg.pickup_lng,
    v_pkg.destination_label, v_pkg.destination_lat, v_pkg.destination_lng,
    'Colis ' || v_pkg.reference || ' · ' || v_pkg.category, v_pkg.quoted_amount_gnf,
    v_pkg.distance_meters, v_pkg.duration_seconds)
  RETURNING * INTO v_mission;

  INSERT INTO public.package_delivery_secrets(package_id, pickup_code, delivery_code)
  VALUES (v_pkg.id, public._package_new_code(), public._package_new_code())
  ON CONFLICT (package_id) DO NOTHING;

  UPDATE public.package_deliveries
     SET mission_id = v_mission.id, package_status = 'dispatching'
   WHERE id = v_pkg.id;

  UPDATE public.package_runtime SET mission_id = v_mission.id WHERE package_id = v_pkg.id;

  PERFORM public._package_notify(
    v_pkg.sender_user_id, 'package_dispatching',
    jsonb_build_object('package_id', v_pkg.id, 'reference', v_pkg.reference,
                       'mission_id', v_mission.id, 'sandbox', v_pkg.is_sandbox), 'high');

  RETURN jsonb_build_object('idempotent', false, 'package_id', v_pkg.id, 'mission_id', v_mission.id);
END; $$;

-- ---------- Chop Pay customer hold / capture / release (Envoyer) ----------
CREATE OR REPLACE FUNCTION public._package_choppay_hold_internal(p_package_id uuid, p_actor uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_r public.package_runtime; v_w public.wallets; v_avail bigint;
  v_tx public.wallet_transactions; v_key text; v_total bigint;
BEGIN
  IF NOT public._finance_flag('chop_pay_checkout_enabled') THEN
    RAISE EXCEPTION 'CHOP_PAY_CHECKOUT_DISABLED';
  END IF;
  SELECT * INTO v_r FROM public.package_runtime WHERE package_id = p_package_id FOR UPDATE;
  IF v_r.id IS NULL THEN RAISE EXCEPTION 'PACKAGE_NOT_AUTHORIZED'; END IF;
  IF v_r.tender <> 'chop_pay' THEN RAISE EXCEPTION 'CHOP_PAY_TENDER_REQUIRED'; END IF;
  v_total := v_r.customer_hold_gnf;
  IF v_total <= 0 THEN RAISE EXCEPTION 'INVALID_CUSTOMER_HOLD'; END IF;

  IF EXISTS (SELECT 1 FROM public.mission_financial_holds
              WHERE source_module = 'package' AND source_id = p_package_id
                AND kind = 'customer_payment') THEN
    RETURN jsonb_build_object('status','already_held','held_gnf',v_total);
  END IF;

  INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_r.customer_user_id,'client')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT * INTO v_w FROM public.wallets
   WHERE owner_user_id = v_r.customer_user_id AND party_type = 'client' FOR UPDATE;
  IF v_w.status <> 'active' THEN RAISE EXCEPTION 'WALLET_NOT_ACTIVE'; END IF;
  v_avail := GREATEST(v_w.balance_gnf - v_w.held_gnf, 0);
  IF v_avail < v_total THEN
    RAISE EXCEPTION 'INSUFFICIENT_CHOP_PAY_BALANCE'
      USING DETAIL = format('required=%s available=%s', v_total, v_avail);
  END IF;

  v_key := format('pkg-cph:%s:customer_payment', p_package_id);

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, related_user_id,
     related_entity, description, metadata)
  VALUES (v_key, 'hold','pending', v_total, v_w.id, v_r.customer_user_id,
     'package:' || p_package_id::text, 'Réservation Chop Pay (livraison Envoyer)',
     jsonb_build_object('mission_type','envoyer','kind','customer_payment',
                        'delivery_gnf', v_r.delivery_fee_gnf, 'platform_fee_gnf', v_r.platform_fee_gnf))
  RETURNING * INTO v_tx;

  UPDATE public.wallets SET held_gnf = held_gnf + v_total, updated_at = now() WHERE id = v_w.id;

  INSERT INTO public.mission_financial_holds
    (driver_user_id, party_type, party_user_id, mission_type, source_module, source_id, kind,
     amount_gnf, customer_gnf, hold_tx_id, policy_snapshot, basis_value_gnf, is_sandbox, journal_key)
  VALUES (NULL, 'client', v_r.customer_user_id, 'envoyer', 'package', p_package_id,
     'customer_payment', v_total, v_total, v_tx.id, v_r.policy_snapshot,
     v_r.delivery_fee_gnf, v_r.is_sandbox, v_key);

  PERFORM public._ledger_post(v_key, 'package', p_package_id, 'hold_customer_payment',
    jsonb_build_array(
      jsonb_build_object('account','L_CUSTOMER_CHOPPAY','amount_gnf',v_total,
                         'party_type','client','party_user_id',v_r.customer_user_id,
                         'memo','customer chop pay reserved'),
      jsonb_build_object('account','L_CUSTOMER_HOLD','amount_gnf',-v_total,
                         'party_type','client','party_user_id',v_r.customer_user_id,
                         'memo','envoyer delivery hold')),
    'envoyer', p_actor, v_r.policy_snapshot, v_r.is_sandbox);

  RETURN jsonb_build_object('status','held','held_gnf',v_total);
END; $$;

CREATE OR REPLACE FUNCTION public._package_choppay_capture_internal(
  p_package_id uuid, p_amount bigint, p_purpose text, p_actor uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_r public.package_runtime; v_h public.mission_financial_holds; v_open bigint;
  v_cw public.wallets; v_target uuid; v_ttype public.party_type; v_target_wallet public.wallets;
  v_key text; v_account text; v_desc text;
BEGIN
  IF p_purpose NOT IN ('delivery','platform_fee') THEN RAISE EXCEPTION 'INVALID_CAPTURE_PURPOSE'; END IF;
  IF COALESCE(p_amount,0) <= 0 THEN RETURN jsonb_build_object('status','zero','captured_gnf',0); END IF;

  SELECT * INTO v_r FROM public.package_runtime WHERE package_id = p_package_id;
  IF v_r.id IS NULL THEN RAISE EXCEPTION 'PACKAGE_NOT_AUTHORIZED'; END IF;
  IF p_purpose = 'delivery' AND v_r.driver_user_id IS NULL THEN RAISE EXCEPTION 'NO_ASSIGNED_COURIER'; END IF;

  v_key := format('pkg-cph-capture:%s:%s', p_package_id, p_purpose);
  IF EXISTS (SELECT 1 FROM public.ledger_journals WHERE journal_key = v_key) THEN
    RETURN jsonb_build_object('status','already_captured','captured_gnf',0);
  END IF;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = 'package' AND source_id = p_package_id AND kind = 'customer_payment'
   FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_HOLD_MISSING'; END IF;
  IF v_h.state = 'frozen' THEN RAISE EXCEPTION 'SETTLEMENT_FROZEN_BY_CLAIM'; END IF;
  v_open := v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf;
  IF v_open < p_amount THEN
    RAISE EXCEPTION 'CHOP_PAY_HOLD_INSUFFICIENT' USING DETAIL = format('open=%s requested=%s', v_open, p_amount);
  END IF;

  SELECT * INTO v_cw FROM public.wallets
   WHERE owner_user_id = v_r.customer_user_id AND party_type = 'client' FOR UPDATE;
  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - p_amount,0),
                            balance_gnf = balance_gnf - p_amount, updated_at = now()
   WHERE id = v_cw.id;

  IF p_purpose = 'delivery' THEN
    v_target := v_r.driver_user_id; v_ttype := 'driver';
    v_account := 'L_DRIVER_UNRESTRICTED'; v_desc := 'Gain de livraison Envoyer (Chop Pay)';
    INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_target, v_ttype)
    ON CONFLICT (owner_user_id, party_type) DO NOTHING;
    UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount, updated_at = now()
     WHERE owner_user_id = v_target AND party_type = v_ttype RETURNING * INTO v_target_wallet;
  ELSE
    v_target := NULL; v_ttype := NULL;
    v_account := 'R_TRANSACTION_FEE'; v_desc := 'Frais de transaction CHOPCHOP (1% livraison)';
    SELECT * INTO v_target_wallet FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
    IF v_target_wallet.id IS NULL THEN RAISE EXCEPTION 'MASTER_WALLET_MISSING'; END IF;
    UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount, updated_at = now()
     WHERE id = v_target_wallet.id;
  END IF;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES (v_key, 'capture','completed', p_amount, v_cw.id, v_target_wallet.id,
     v_r.customer_user_id, 'package:' || p_package_id::text, v_desc,
     jsonb_build_object('purpose',p_purpose,'mission_type','envoyer','tender','chop_pay',
                        'is_sandbox', v_r.is_sandbox), now());

  PERFORM public._ledger_post(v_key, 'package', p_package_id, 'capture_customer_'||p_purpose,
    jsonb_build_array(
      jsonb_build_object('account','L_CUSTOMER_HOLD','amount_gnf',p_amount,
                         'party_type','client','party_user_id',v_r.customer_user_id,
                         'memo','consume customer hold'),
      jsonb_build_object('account',v_account,'amount_gnf',-p_amount,
                         'party_type', v_ttype, 'party_user_id', v_target, 'memo', v_desc)),
    'envoyer', p_actor, v_r.policy_snapshot, v_r.is_sandbox);

  UPDATE public.mission_financial_holds
     SET captured_gnf = captured_gnf + p_amount,
         state = CASE WHEN captured_gnf + p_amount + released_gnf >= amount_gnf
                      THEN 'captured' ELSE 'partially_captured' END,
         resolved_at = CASE WHEN captured_gnf + p_amount + released_gnf >= amount_gnf
                            THEN now() ELSE resolved_at END
   WHERE id = v_h.id;

  UPDATE public.wallet_transactions SET status = 'completed', completed_at = now()
   WHERE id = v_h.hold_tx_id AND status = 'pending'
     AND EXISTS (SELECT 1 FROM public.mission_financial_holds h
                  WHERE h.id = v_h.id AND h.captured_gnf + h.released_gnf >= h.amount_gnf);

  RETURN jsonb_build_object('status','captured','captured_gnf',p_amount,'purpose',p_purpose);
END; $$;

CREATE OR REPLACE FUNCTION public._package_choppay_release_internal(
  p_package_id uuid, p_reason text DEFAULT NULL::text, p_actor uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_r public.package_runtime; v_h public.mission_financial_holds; v_open bigint; v_cw public.wallets;
BEGIN
  SELECT * INTO v_r FROM public.package_runtime WHERE package_id = p_package_id;
  IF v_r.id IS NULL THEN RAISE EXCEPTION 'PACKAGE_NOT_AUTHORIZED'; END IF;
  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = 'package' AND source_id = p_package_id AND kind = 'customer_payment' FOR UPDATE;
  IF v_h.id IS NULL THEN RETURN jsonb_build_object('status','no_hold','released_gnf',0); END IF;
  IF v_h.state = 'frozen' THEN RAISE EXCEPTION 'SETTLEMENT_FROZEN_BY_CLAIM'; END IF;
  v_open := v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf;
  IF v_open <= 0 THEN RETURN jsonb_build_object('status','already_resolved','released_gnf',0); END IF;

  SELECT * INTO v_cw FROM public.wallets
   WHERE owner_user_id = v_r.customer_user_id AND party_type = 'client' FOR UPDATE;
  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_open, 0), updated_at = now() WHERE id = v_cw.id;
  UPDATE public.wallet_transactions SET status = 'cancelled', completed_at = now()
   WHERE id = v_h.hold_tx_id AND status = 'pending';

  PERFORM public._ledger_post(format('pkg-cph-release:%s', p_package_id),
    'package', p_package_id, 'release_customer_payment',
    jsonb_build_array(
      jsonb_build_object('account','L_CUSTOMER_HOLD','amount_gnf',v_open,
                         'party_type','client','party_user_id',v_r.customer_user_id,'memo','release customer hold'),
      jsonb_build_object('account','L_CUSTOMER_CHOPPAY','amount_gnf',-v_open,
                         'party_type','client','party_user_id',v_r.customer_user_id,'memo','restored to chop pay balance')),
    'envoyer', p_actor, v_r.policy_snapshot, v_r.is_sandbox, p_reason);

  UPDATE public.mission_financial_holds
     SET released_gnf = released_gnf + v_open,
         state = CASE WHEN captured_gnf > 0 THEN 'captured' ELSE 'released' END,
         reason = COALESCE(p_reason, reason), resolved_at = now(), resolved_by = p_actor
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','released','released_gnf',v_open);
END; $$;

-- ---------- authorisation (freeze economics) ----------
CREATE OR REPLACE FUNCTION public._package_authorize_internal(p_package_id uuid, p_actor uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_pkg public.package_deliveries; v_e jsonb; v_r public.package_runtime; v_photos int;
BEGIN
  IF NOT public._finance_flag('envoyer_declared_value_enabled') THEN
    RAISE EXCEPTION 'ENVOYER_DECLARED_VALUE_DISABLED';
  END IF;
  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_package_id FOR UPDATE;
  IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'package_not_found'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('package:'||p_package_id::text, 0));
  SELECT * INTO v_r FROM public.package_runtime WHERE package_id = p_package_id;
  IF v_r.id IS NOT NULL THEN
    RETURN jsonb_build_object('status','already_authorized','runtime_id',v_r.id,
      'declared_value_gnf',v_r.declared_value_gnf,'collateral_gnf',v_r.collateral_gnf,
      'claims_exposure_gnf',v_r.claims_exposure_gnf,'platform_fee_gnf',v_r.platform_fee_gnf);
  END IF;

  IF COALESCE(v_pkg.declared_value_gnf,0) <= 0 THEN RAISE EXCEPTION 'DECLARED_VALUE_REQUIRED'; END IF;
  IF v_pkg.tender IS NULL THEN RAISE EXCEPTION 'ENVOYER_TENDER_REQUIRED'; END IF;
  IF v_pkg.value_attested_at IS NULL OR v_pkg.value_attested_by IS DISTINCT FROM v_pkg.sender_user_id THEN
    RAISE EXCEPTION 'VALUE_ATTESTATION_REQUIRED';
  END IF;

  SELECT count(*) INTO v_photos FROM public.package_evidence_photos
   WHERE package_id = p_package_id AND owner_user_id = v_pkg.sender_user_id;
  IF v_photos < 1 THEN RAISE EXCEPTION 'SHIPMENT_PHOTOS_REQUIRED'; END IF;

  v_e := public._package_economics(v_pkg.declared_value_gnf, v_pkg.quoted_amount_gnf,
                                   v_pkg.tender, v_pkg.is_sandbox);

  INSERT INTO public.package_runtime
    (order_key, package_id, customer_user_id, tender, declared_value_gnf, delivery_fee_gnf,
     platform_fee_gnf, collateral_gnf, claims_exposure_gnf, customer_hold_gnf, cash_due_gnf,
     policy_snapshot, is_sandbox, state)
  VALUES ('package:'||p_package_id::text, p_package_id, v_pkg.sender_user_id, v_pkg.tender,
     (v_e->>'declared_value_gnf')::bigint, (v_e->>'delivery_fee_gnf')::bigint,
     (v_e->>'platform_fee_gnf')::bigint, (v_e->>'collateral_gnf')::bigint,
     (v_e->>'claims_exposure_gnf')::bigint, (v_e->>'customer_hold_gnf')::bigint,
     (v_e->>'cash_due_gnf')::bigint, v_e->'policy_snapshot', v_pkg.is_sandbox, 'authorized')
  RETURNING * INTO v_r;

  UPDATE public.package_deliveries
     SET finance_snapshot = v_e,
         payment_status = CASE WHEN v_pkg.tender = 'chop_pay' THEN 'authorized' ELSE 'due_on_delivery' END
   WHERE id = p_package_id;

  IF v_pkg.tender = 'chop_pay' THEN
    PERFORM public._package_choppay_hold_internal(p_package_id, p_actor);
  END IF;

  PERFORM public._package_dispatch_internal(p_package_id);

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (p_actor, 'package', 'package.value.authorized', 'package_delivery', p_package_id::text,
          jsonb_build_object('declared_value_gnf', v_r.declared_value_gnf,
                             'collateral_gnf', v_r.collateral_gnf,
                             'claims_exposure_gnf', v_r.claims_exposure_gnf,
                             'platform_fee_gnf', v_r.platform_fee_gnf,
                             'tender', v_r.tender));

  RETURN jsonb_build_object('status','authorized','runtime_id',v_r.id,
    'declared_value_gnf',v_r.declared_value_gnf,'collateral_gnf',v_r.collateral_gnf,
    'claims_exposure_gnf',v_r.claims_exposure_gnf,'platform_fee_gnf',v_r.platform_fee_gnf,
    'customer_hold_gnf',v_r.customer_hold_gnf,'cash_due_gnf',v_r.cash_due_gnf,
    'mission_id',(SELECT mission_id FROM public.package_deliveries WHERE id = p_package_id));
END; $$;

-- ---------- courier acceptance (exact frozen collateral) ----------
CREATE OR REPLACE FUNCTION public._package_accept_internal(p_package_id uuid, p_driver uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_r public.package_runtime; v_m public.missions; v_col jsonb; v_fee jsonb;
BEGIN
  IF p_driver IS NULL THEN RAISE EXCEPTION 'NO_DRIVER'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('package:'||p_package_id::text, 0));
  SELECT * INTO v_r FROM public.package_runtime WHERE package_id = p_package_id FOR UPDATE;
  IF v_r.id IS NULL THEN RAISE EXCEPTION 'PACKAGE_NOT_AUTHORIZED'; END IF;
  IF v_r.driver_user_id IS NOT NULL THEN
    RETURN jsonb_build_object('status','already_accepted','driver_user_id',v_r.driver_user_id,
                              'collateral_gnf',v_r.collateral_gnf);
  END IF;
  IF v_r.state <> 'authorized' THEN RAISE EXCEPTION 'INVALID_STATE' USING DETAIL = v_r.state; END IF;
  IF v_r.claim_state <> 'none' THEN RAISE EXCEPTION 'SETTLEMENT_FROZEN_BY_CLAIM'; END IF;

  SELECT * INTO v_m FROM public.missions WHERE id = v_r.mission_id;
  IF v_m.id IS NULL THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF v_m.courier_id IS DISTINCT FROM p_driver THEN RAISE EXCEPTION 'NOT_ASSIGNED_DRIVER'; END IF;

  -- Frozen collateral: never re-derived from a later live policy.
  v_col := public._driver_exact_hold_place_internal(
    'envoyer', 'package', p_package_id, p_driver, v_r.collateral_gnf, 'collateral',
    v_r.policy_snapshot, v_r.declared_value_gnf, NULL, v_r.is_sandbox);

  IF v_r.tender = 'cash' THEN
    -- Cash tender: the courier collects physical cash, so the 1% delivery-fee
    -- charge is reserved from the courier balance and recovered at completion.
    v_fee := public._driver_exact_hold_place_internal(
      'envoyer', 'package', p_package_id, p_driver, v_r.platform_fee_gnf, 'platform_fee',
      v_r.policy_snapshot, v_r.delivery_fee_gnf, NULL, v_r.is_sandbox);
  END IF;

  UPDATE public.package_runtime
     SET driver_user_id = p_driver, state = 'accepted', accepted_at = now()
   WHERE id = v_r.id;

  RETURN jsonb_build_object('status','accepted','collateral_gnf',v_r.collateral_gnf,
    'claims_exposure_gnf',v_r.claims_exposure_gnf,'platform_fee_gnf',v_r.platform_fee_gnf,
    'collateral_hold',v_col,'fee_hold',v_fee);
END; $$;

-- ---------- completion ----------
CREATE OR REPLACE FUNCTION public._package_complete_internal(p_package_id uuid, p_actor uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_r public.package_runtime; v_s public.package_delivery_secrets;
  v_del jsonb; v_fee jsonb; v_rel jsonb; v_tail jsonb;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('package:'||p_package_id::text, 0));
  SELECT * INTO v_r FROM public.package_runtime WHERE package_id = p_package_id FOR UPDATE;
  IF v_r.id IS NULL THEN RAISE EXCEPTION 'PACKAGE_NOT_AUTHORIZED'; END IF;
  IF v_r.state = 'completed' THEN
    RETURN jsonb_build_object('status','already_completed','driver_earning_gnf',v_r.driver_earning_gnf,
                              'platform_revenue_gnf',v_r.platform_revenue_gnf);
  END IF;
  IF v_r.claim_state <> 'none' THEN RAISE EXCEPTION 'SETTLEMENT_FROZEN_BY_CLAIM'; END IF;
  IF v_r.state NOT IN ('accepted','picked_up') THEN
    RAISE EXCEPTION 'INVALID_STATE' USING DETAIL = v_r.state;
  END IF;

  SELECT * INTO v_s FROM public.package_delivery_secrets WHERE package_id = p_package_id;
  IF v_s.pickup_verified_at IS NULL THEN
    RAISE EXCEPTION 'CUSTODY_NOT_ESTABLISHED' USING DETAIL = 'pickup must be confirmed first';
  END IF;

  IF v_r.tender = 'chop_pay' THEN
    v_del := public._package_choppay_capture_internal(p_package_id, v_r.delivery_fee_gnf, 'delivery', p_actor);
    v_fee := public._package_choppay_capture_internal(p_package_id, v_r.platform_fee_gnf, 'platform_fee', p_actor);
    v_tail := public._package_choppay_release_internal(p_package_id, 'envoyer_completion_residual', p_actor);
  ELSE
    -- Physical cash: no digital courier earning is ever created.
    v_fee := public._cash_order_capture_platform_fee('package', p_package_id, p_actor);
  END IF;

  v_rel := public._driver_mission_hold_release_internal('package', p_package_id, 'collateral',
                                                        'envoyer_completion', p_actor);

  UPDATE public.package_runtime
     SET state = 'completed', completed_at = now(),
         driver_earning_gnf = CASE WHEN v_r.tender = 'chop_pay' THEN v_r.delivery_fee_gnf ELSE 0 END,
         platform_revenue_gnf = v_r.platform_fee_gnf
   WHERE id = v_r.id;

  RETURN jsonb_build_object('status','completed','tender',v_r.tender,
    'collateral_released', v_rel, 'delivery_capture', v_del, 'fee_capture', v_fee,
    'residual_release', v_tail, 'commission_gnf', 0,
    'driver_wallet_credit_gnf', CASE WHEN v_r.tender = 'chop_pay' THEN v_r.delivery_fee_gnf ELSE 0 END,
    'cash_collected_gnf', CASE WHEN v_r.tender = 'cash' THEN v_r.cash_due_gnf ELSE 0 END);
END; $$;

-- ---------- pre-pickup cancellation release ----------
CREATE OR REPLACE FUNCTION public._package_cancel_release_internal(
  p_package_id uuid, p_reason text DEFAULT NULL::text, p_actor uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_r public.package_runtime; v_rel jsonb; v_cust jsonb;
BEGIN
  SELECT * INTO v_r FROM public.package_runtime WHERE package_id = p_package_id FOR UPDATE;
  IF v_r.id IS NULL THEN RETURN jsonb_build_object('status','no_runtime'); END IF;
  IF v_r.claim_state <> 'none' THEN RAISE EXCEPTION 'SETTLEMENT_FROZEN_BY_CLAIM'; END IF;
  IF v_r.state = 'cancelled' THEN RETURN jsonb_build_object('status','already_cancelled'); END IF;
  IF v_r.state NOT IN ('authorized','accepted') THEN
    RAISE EXCEPTION 'CUSTODY_ESTABLISHED_CLAIM_REQUIRED' USING DETAIL = v_r.state;
  END IF;

  v_rel := public._driver_mission_hold_release_internal('package', p_package_id, NULL,
                                                        COALESCE(p_reason,'envoyer_cancelled'), p_actor);
  IF v_r.tender = 'chop_pay' THEN
    v_cust := public._package_choppay_release_internal(p_package_id,
                COALESCE(p_reason,'envoyer_cancelled'), p_actor);
  END IF;

  UPDATE public.package_runtime SET state = 'cancelled', cancelled_at = now() WHERE id = v_r.id;
  RETURN jsonb_build_object('status','cancelled','driver_release',v_rel,'customer_release',v_cust);
END; $$;

-- ---------- claim freeze ----------
CREATE OR REPLACE FUNCTION public._package_claim_freeze_internal(
  p_package_id uuid, p_reason text, p_actor uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_r public.package_runtime; v_n int;
BEGIN
  SELECT * INTO v_r FROM public.package_runtime WHERE package_id = p_package_id FOR UPDATE;
  IF v_r.id IS NULL THEN RAISE EXCEPTION 'PACKAGE_NOT_AUTHORIZED'; END IF;
  IF v_r.claim_state = 'open' THEN
    RETURN jsonb_build_object('status','already_open','runtime_id',v_r.id);
  END IF;
  IF v_r.claim_state NOT IN ('none') THEN
    RETURN jsonb_build_object('status','already_resolved','claim_state',v_r.claim_state);
  END IF;

  UPDATE public.mission_financial_holds
     SET state = 'frozen', reason = COALESCE(p_reason, reason), updated_at = now()
   WHERE source_module = 'package' AND source_id = p_package_id
     AND state IN ('held','partially_captured');
  GET DIAGNOSTICS v_n = ROW_COUNT;

  UPDATE public.package_runtime
     SET claim_state = 'open', state = 'claim_open', claim_opened_at = now()
   WHERE id = v_r.id;
  UPDATE public.package_deliveries SET claim_state = 'open' WHERE id = p_package_id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (p_actor, 'package', 'package.claim.opened', 'package_delivery', p_package_id::text,
          jsonb_build_object('frozen_holds', v_n, 'collateral_gnf', v_r.collateral_gnf,
                             'claims_exposure_gnf', v_r.claims_exposure_gnf), p_reason);

  RETURN jsonb_build_object('status','frozen','frozen_holds',v_n,
    'collateral_gnf',v_r.collateral_gnf,'claims_exposure_gnf',v_r.claims_exposure_gnf);
END; $$;

-- ---------- collateral capture towards an upheld claim ----------
CREATE OR REPLACE FUNCTION public._package_collateral_capture_internal(
  p_package_id uuid, p_amount bigint, p_reason text, p_evidence_ref text, p_actor uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_r public.package_runtime; v_h public.mission_financial_holds;
  v_open bigint; v_unrestricted_open bigint; v_key text;
  v_dw public.wallets; v_cw public.wallets;
BEGIN
  IF COALESCE(p_amount,0) <= 0 THEN RETURN jsonb_build_object('status','zero','captured_gnf',0); END IF;
  SELECT * INTO v_r FROM public.package_runtime WHERE package_id = p_package_id FOR UPDATE;
  IF v_r.id IS NULL THEN RAISE EXCEPTION 'PACKAGE_NOT_AUTHORIZED'; END IF;
  IF v_r.customer_user_id IS NULL THEN RAISE EXCEPTION 'CLAIM_BENEFICIARY_MISSING'; END IF;

  v_key := format('pkg-claim-capture:%s', p_package_id);
  IF EXISTS (SELECT 1 FROM public.ledger_journals WHERE journal_key = v_key) THEN
    RETURN jsonb_build_object('status','already_captured','captured_gnf',0);
  END IF;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = 'package' AND source_id = p_package_id AND kind = 'collateral' FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'COLLATERAL_HOLD_MISSING'; END IF;

  v_open := v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf;
  IF p_amount > v_open THEN
    RAISE EXCEPTION 'CLAIM_EXCEEDS_COLLATERAL' USING DETAIL = format('open=%s requested=%s', v_open, p_amount);
  END IF;

  -- Restricted starting credit may fund collateral, but it can never be paid out
  -- as real money to a customer. That is a reconciliation stop, not a silent fix.
  v_unrestricted_open := GREATEST(v_h.unrestricted_gnf - v_h.captured_unrestricted_gnf, 0);
  IF p_amount > v_unrestricted_open THEN
    RAISE EXCEPTION 'RECONCILIATION_REQUIRED_RESTRICTED_COLLATERAL'
      USING DETAIL = format('unrestricted_open=%s requested=%s', v_unrestricted_open, p_amount);
  END IF;

  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;
  INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_r.customer_user_id,'client')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT * INTO v_cw FROM public.wallets
   WHERE owner_user_id = v_r.customer_user_id AND party_type = 'client' FOR UPDATE;

  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - p_amount, 0),
                            balance_gnf = balance_gnf - p_amount, updated_at = now()
   WHERE id = v_dw.id;
  UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount, updated_at = now()
   WHERE id = v_cw.id;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES (v_key, 'capture','completed', p_amount, v_dw.id, v_cw.id, v_h.driver_user_id,
     'package:' || p_package_id::text, 'Caution Envoyer affectée à une réclamation',
     jsonb_build_object('mission_type','envoyer','evidence_ref',p_evidence_ref,
                        'is_sandbox', v_r.is_sandbox), now());

  PERFORM public._ledger_post(v_key, 'package', p_package_id, 'capture_collateral_claim',
    jsonb_build_array(
      jsonb_build_object('account','L_HOLD_COLLATERAL','amount_gnf',p_amount,
                         'party_type','driver','party_user_id',v_h.driver_user_id,
                         'memo','collateral consumed for upheld claim'),
      jsonb_build_object('account','L_CUSTOMER_CHOPPAY','amount_gnf',-p_amount,
                         'party_type','client','party_user_id',v_r.customer_user_id,
                         'memo','claim compensation to customer')),
    'envoyer', p_actor, v_r.policy_snapshot, v_r.is_sandbox, p_reason, p_evidence_ref);

  UPDATE public.mission_financial_holds
     SET captured_gnf = captured_gnf + p_amount,
         captured_unrestricted_gnf = captured_unrestricted_gnf + p_amount,
         state = CASE WHEN captured_gnf + p_amount + released_gnf >= amount_gnf
                      THEN 'captured' ELSE 'frozen' END,
         reason = COALESCE(p_reason, reason), resolved_by = p_actor
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','captured','captured_gnf',p_amount);
END; $$;

-- ---------- privilege lockdown for the raw helpers ----------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
       AND p.proname IN ('_package_economics','_package_dispatch_internal',
                         '_package_choppay_hold_internal','_package_choppay_capture_internal',
                         '_package_choppay_release_internal','_package_authorize_internal',
                         '_package_accept_internal','_package_complete_internal',
                         '_package_cancel_release_internal','_package_claim_freeze_internal',
                         '_package_collateral_capture_internal','_package_runtime_immutable')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;
END $$;