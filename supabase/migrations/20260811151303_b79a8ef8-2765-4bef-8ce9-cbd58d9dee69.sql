-- ============================================================
-- SLICE 11 FINAL HARDENING CLOSEOUT
-- ============================================================

-- (3) Canonical, singular expected outbound transfer amount.
ALTER TABLE public.payout_orders
  ADD COLUMN IF NOT EXISTS expected_provider_transfer_gnf bigint;

UPDATE public.payout_orders
   SET expected_provider_transfer_gnf = recipient_net_gnf
 WHERE expected_provider_transfer_gnf IS NULL;

ALTER TABLE public.payout_orders
  ALTER COLUMN expected_provider_transfer_gnf SET NOT NULL;

CREATE OR REPLACE FUNCTION public._payout_order_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.order_key IS DISTINCT FROM OLD.order_key
     OR NEW.party_user_id IS DISTINCT FROM OLD.party_user_id
     OR NEW.party_type IS DISTINCT FROM OLD.party_type
     OR NEW.merchant_store_id IS DISTINCT FROM OLD.merchant_store_id
     OR NEW.requested_principal_gnf IS DISTINCT FROM OLD.requested_principal_gnf
     OR NEW.provider_fee_gnf IS DISTINCT FROM OLD.provider_fee_gnf
     OR NEW.fee_borne_by IS DISTINCT FROM OLD.fee_borne_by
     OR NEW.merchant_liability_debit_gnf IS DISTINCT FROM OLD.merchant_liability_debit_gnf
     OR NEW.recipient_net_gnf IS DISTINCT FROM OLD.recipient_net_gnf
     OR NEW.expected_provider_transfer_gnf IS DISTINCT FROM OLD.expected_provider_transfer_gnf
     OR NEW.destination_msisdn IS DISTINCT FROM OLD.destination_msisdn
     OR NEW.environment IS DISTINCT FROM OLD.environment
     OR NEW.policy_snapshot IS DISTINCT FROM OLD.policy_snapshot
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'PAYOUT_ORDER_IMMUTABLE';
  END IF;
  RETURN NEW;
END $function$;

-- Freeze the canonical expected transfer at reservation time.
CREATE OR REPLACE FUNCTION public._payout_order_create_internal(
  p_party_type party_type, p_party_user_id uuid, p_store_id uuid, p_source_kind text,
  p_source_request_id uuid, p_principal bigint, p_provider text, p_msisdn text,
  p_order_key text, p_actor uuid)
 RETURNS payout_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_o public.payout_orders; v_fee jsonb;
BEGIN
  SELECT * INTO v_o FROM public.payout_orders WHERE order_key = p_order_key;
  IF v_o.id IS NOT NULL THEN RETURN v_o; END IF;
  IF p_msisdn IS NULL OR length(btrim(p_msisdn)) < 8 THEN
    RAISE EXCEPTION 'PAYOUT_DESTINATION_REQUIRED';
  END IF;
  v_fee := public._payout_fee_snapshot(p_provider, p_principal);

  INSERT INTO public.payout_orders (
    order_key, party_type, party_user_id, merchant_store_id, source_kind, source_request_id,
    provider, destination_msisdn, environment, requested_principal_gnf, provider_fee_gnf,
    fee_borne_by, merchant_liability_debit_gnf, recipient_net_gnf,
    expected_provider_transfer_gnf, reservation_gnf, policy_snapshot, created_by)
  VALUES (
    p_order_key, p_party_type, p_party_user_id, p_store_id, p_source_kind, p_source_request_id,
    COALESCE(p_provider,'orange_money'), btrim(p_msisdn), public._payout_env(), p_principal,
    (v_fee->>'provider_fee_gnf')::bigint, v_fee->>'fee_borne_by',
    (v_fee->>'merchant_liability_debit_gnf')::bigint, (v_fee->>'recipient_net_gnf')::bigint,
    (v_fee->>'recipient_net_gnf')::bigint,
    p_principal, v_fee, p_actor)
  RETURNING * INTO v_o;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (p_actor,'finance','payout.order.reserved','payout_order', v_o.id::text,
          jsonb_build_object('principal_gnf',p_principal,'party',p_party_type,'fee',v_fee,
                             'expected_provider_transfer_gnf',(v_fee->>'recipient_net_gnf')::bigint));
  RETURN v_o;
END $function$;

-- Shared, single source of evidence truth. Returns NULL when evidence is exact.
CREATE OR REPLACE FUNCTION public._payout_evidence_mismatch_reason(
  p_order public.payout_orders,
  p_provider text, p_reference text, p_msisdn text, p_amount bigint,
  p_status text, p_environment text, p_fee bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_reference IS NULL OR length(btrim(p_reference)) < 4
     OR p_msisdn IS NULL OR length(btrim(p_msisdn)) < 8
     OR p_amount IS NULL OR p_amount <= 0
     OR p_provider IS NULL OR length(btrim(p_provider)) = 0
     OR p_status IS NULL OR length(btrim(p_status)) = 0
     OR p_environment IS NULL OR p_environment NOT IN ('production','sandbox') THEN
    RETURN 'missing_required_evidence_fields';
  END IF;
  IF p_environment IS DISTINCT FROM p_order.environment THEN RETURN 'environment_mismatch'; END IF;
  IF p_environment IS DISTINCT FROM public._payout_env() THEN RETURN 'environment_mismatch'; END IF;
  IF btrim(p_provider) IS DISTINCT FROM p_order.provider THEN RETURN 'provider_mismatch'; END IF;
  IF public._normalize_guinea_phone(p_msisdn)
     IS DISTINCT FROM public._normalize_guinea_phone(p_order.destination_msisdn) THEN
    RETURN 'recipient_mismatch';
  END IF;
  IF p_amount IS DISTINCT FROM p_order.expected_provider_transfer_gnf THEN
    RETURN 'amount_mismatch';
  END IF;
  IF p_fee IS NOT NULL AND p_fee IS DISTINCT FROM p_order.provider_fee_gnf THEN
    RETURN 'provider_fee_mismatch';
  END IF;
  IF lower(btrim(p_status)) NOT IN ('success','successful','completed','confirmed','paid') THEN
    RETURN 'provider_status_not_successful';
  END IF;
  RETURN NULL;
END $function$;

REVOKE ALL ON FUNCTION public._payout_evidence_mismatch_reason(public.payout_orders, text, text, text, bigint, text, text, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._payout_evidence_mismatch_reason(public.payout_orders, text, text, text, bigint, text, text, bigint) TO service_role;

-- Evidence recording now uses the exact singular contract.
CREATE OR REPLACE FUNCTION public.payout_record_provider_evidence(
  p_payout_order_id uuid, p_provider text, p_provider_reference text, p_recipient_msisdn text,
  p_amount_gnf bigint, p_provider_status text, p_environment text,
  p_transferred_at timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_fee_gnf bigint DEFAULT NULL::bigint, p_raw jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_o public.payout_orders;
  v_e public.payout_provider_evidence;
  v_state text := 'recorded';
  v_reason text := NULL;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF NOT (public.is_god_admin(v_caller) OR public.has_admin_role(v_caller,'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  SELECT * INTO v_o FROM public.payout_orders WHERE id = p_payout_order_id FOR UPDATE;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'PAYOUT_ORDER_NOT_FOUND'; END IF;
  IF p_provider_reference IS NULL OR length(btrim(p_provider_reference)) < 4 THEN
    RAISE EXCEPTION 'PROVIDER_REFERENCE_REQUIRED';
  END IF;

  SELECT * INTO v_e FROM public.payout_provider_evidence
   WHERE normalized_reference = lower(btrim(p_provider_reference));
  IF v_e.id IS NOT NULL THEN
    IF v_e.payout_order_id IS DISTINCT FROM v_o.id THEN
      RAISE EXCEPTION 'PROVIDER_REFERENCE_ALREADY_CONSUMED';
    END IF;
    RETURN jsonb_build_object('status', v_e.reconciliation_state, 'evidence_id', v_e.id,
      'payout_order_id', v_o.id, 'duplicate', true, 'moved_gnf', 0);
  END IF;

  v_reason := public._payout_evidence_mismatch_reason(
    v_o, p_provider, p_provider_reference, p_recipient_msisdn, p_amount_gnf,
    p_provider_status, p_environment, p_fee_gnf);
  IF v_reason = 'missing_required_evidence_fields' THEN
    v_state := 'evidence_incomplete';
  ELSIF v_reason IS NOT NULL THEN
    v_state := 'mismatch';
  END IF;

  INSERT INTO public.payout_provider_evidence (
    payout_order_id, provider, provider_reference, recipient_msisdn, amount_gnf, fee_gnf,
    net_gnf, provider_status, transferred_at, environment, raw, reconciliation_state,
    mismatch_reason, recorded_by)
  VALUES (v_o.id, btrim(COALESCE(p_provider,'')), btrim(p_provider_reference),
          NULLIF(btrim(COALESCE(p_recipient_msisdn,'')),''), p_amount_gnf, p_fee_gnf,
          CASE WHEN p_amount_gnf IS NOT NULL AND p_fee_gnf IS NOT NULL THEN p_amount_gnf - p_fee_gnf END,
          NULLIF(btrim(COALESCE(p_provider_status,'')),''), p_transferred_at,
          p_environment, COALESCE(p_raw,'{}'::jsonb), v_state, v_reason, v_caller)
  RETURNING * INTO v_e;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_caller,'finance','payout.evidence.recorded','payout_provider_evidence', v_e.id::text,
          jsonb_build_object('payout_order_id',v_o.id,'state',v_state,'reason',v_reason));

  IF v_state <> 'recorded' THEN
    UPDATE public.payout_orders
       SET status = CASE WHEN v_state = 'mismatch' THEN 'mismatch' ELSE 'needs_review' END,
           updated_at = now()
     WHERE id = v_o.id AND status IN ('reserved','needs_review','mismatch');
    UPDATE public.merchant_settlement_requests SET status = 'pending_review', updated_at = now()
     WHERE id = v_o.source_request_id AND status IN ('requested','pending_review');
    RETURN jsonb_build_object('status', v_state, 'reason', v_reason,
      'evidence_id', v_e.id, 'payout_order_id', v_o.id, 'moved_gnf', 0);
  END IF;

  RETURN public._payout_settle_internal(v_o.id, v_e.id, v_caller);
END $function$;

-- (3) Defense-in-depth: the debit primitive itself revalidates everything.
CREATE OR REPLACE FUNCTION public._payout_settle_internal(p_order_id uuid, p_evidence_id uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_o public.payout_orders;
  v_e public.payout_provider_evidence;
  v_remaining bigint;
  v_take bigint;
  v_p record;
  v_lines jsonb;
  v_bad text;
BEGIN
  SELECT * INTO v_o FROM public.payout_orders WHERE id = p_order_id FOR UPDATE;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'PAYOUT_ORDER_NOT_FOUND'; END IF;
  IF v_o.status = 'settled' THEN
    RETURN jsonb_build_object('status','already_settled','payout_order_id',v_o.id,'settled_gnf',v_o.settled_gnf,'moved_gnf',0);
  END IF;
  SELECT * INTO v_e FROM public.payout_provider_evidence WHERE id = p_evidence_id FOR UPDATE;
  IF v_e.id IS NULL THEN RAISE EXCEPTION 'EVIDENCE_NOT_FOUND'; END IF;

  -- Stage gates: no outbound settlement posting while the rail is off.
  IF v_o.source_kind = 'merchant_settlement'
     AND NOT public._finance_flag('merchant_om_settlement_enabled') THEN
    RAISE EXCEPTION 'STAGE_DISABLED:merchant_om_settlement_enabled';
  END IF;
  IF v_o.source_kind = 'driver_cashout'
     AND NOT public._finance_flag('driver_cashout_enabled') THEN
    RAISE EXCEPTION 'STAGE_DISABLED:driver_cashout_enabled';
  END IF;

  -- Independent re-validation BEFORE any claim, allocation, debit or posting.
  IF v_o.status NOT IN ('reserved','needs_review','mismatch') THEN
    RAISE EXCEPTION 'EVIDENCE_VALIDATION_FAILED:order_not_settleable';
  END IF;
  IF v_e.payout_order_id IS DISTINCT FROM v_o.id THEN
    RAISE EXCEPTION 'EVIDENCE_VALIDATION_FAILED:evidence_not_linked';
  END IF;
  IF v_e.reconciliation_state NOT IN ('recorded','mismatch','evidence_incomplete') THEN
    RAISE EXCEPTION 'EVIDENCE_VALIDATION_FAILED:evidence_state_%', v_e.reconciliation_state;
  END IF;
  v_bad := public._payout_evidence_mismatch_reason(
    v_o, v_e.provider, v_e.provider_reference, v_e.recipient_msisdn, v_e.amount_gnf,
    v_e.provider_status, v_e.environment, v_e.fee_gnf);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'EVIDENCE_VALIDATION_FAILED:%', v_bad;
  END IF;

  -- Global one-reference-one-settlement claim.
  PERFORM public._finance_evidence_claim(
    v_e.provider_reference,
    CASE WHEN v_o.source_kind = 'merchant_settlement' THEN 'merchant_settlement' ELSE 'driver_payout' END,
    v_o.id, v_o.merchant_liability_debit_gnf, p_actor);

  IF v_o.source_kind = 'merchant_settlement' THEN
    v_remaining := v_o.merchant_liability_debit_gnf;
    FOR v_p IN
      SELECT * FROM public.merchant_payables
       WHERE merchant_store_id = v_o.merchant_store_id
         AND state IN ('funded','due','settlement_held')
         AND (amount_gnf - settled_gnf) > 0
       ORDER BY created_at
       FOR UPDATE
    LOOP
      EXIT WHEN v_remaining <= 0;
      v_take := LEAST(v_remaining, v_p.amount_gnf - v_p.settled_gnf);
      UPDATE public.merchant_payables
         SET settled_gnf = settled_gnf + v_take,
             state = CASE WHEN settled_gnf + v_take >= amount_gnf THEN 'settled' ELSE state END,
             evidence_ref = v_e.provider_reference,
             resolved_by = p_actor,
             resolved_at = CASE WHEN settled_gnf + v_take >= amount_gnf THEN now() ELSE resolved_at END,
             updated_at = now()
       WHERE id = v_p.id;
      INSERT INTO public.payout_settlement_allocations (payout_order_id, merchant_payable_id, amount_gnf)
      VALUES (v_o.id, v_p.id, v_take);
      v_remaining := v_remaining - v_take;
    END LOOP;
    IF v_remaining > 0 THEN
      RAISE EXCEPTION 'PAYABLE_COVERAGE_INSUFFICIENT: % GNF uncovered', v_remaining;
    END IF;

    UPDATE public.wallets
       SET balance_gnf = balance_gnf - v_o.merchant_liability_debit_gnf, updated_at = now()
     WHERE owner_user_id = v_o.party_user_id AND party_type = 'merchant';

    IF v_o.fee_borne_by = 'platform' AND v_o.provider_fee_gnf > 0 THEN
      v_lines := jsonb_build_array(
        jsonb_build_object('account','L_MERCHANT_PAYABLE','amount_gnf',v_o.merchant_liability_debit_gnf,
          'party_type','merchant','party_user_id',v_o.party_user_id,
          'merchant_store_id',v_o.merchant_store_id,'memo','merchant payable settled'),
        jsonb_build_object('account','E_PROVIDER_FEE','amount_gnf',v_o.provider_fee_gnf,'memo','provider fee absorbed'),
        jsonb_build_object('account','A_PROVIDER_CLEARING',
          'amount_gnf', -(v_o.merchant_liability_debit_gnf + v_o.provider_fee_gnf),'memo','outbound transfer'));
    ELSE
      v_lines := jsonb_build_array(
        jsonb_build_object('account','L_MERCHANT_PAYABLE','amount_gnf',v_o.merchant_liability_debit_gnf,
          'party_type','merchant','party_user_id',v_o.party_user_id,
          'merchant_store_id',v_o.merchant_store_id,'memo','merchant payable settled'),
        jsonb_build_object('account','A_PROVIDER_CLEARING','amount_gnf',-v_o.merchant_liability_debit_gnf,
          'memo','outbound transfer (fee borne by recipient)'));
    END IF;

    PERFORM public._ledger_post('payout-settle:' || v_o.id::text, 'payout_settlement', v_o.id,
      'merchant_settlement_paid', v_lines, NULL, p_actor, v_o.policy_snapshot,
      v_o.environment = 'sandbox', NULL, v_e.provider_reference);
  ELSE
    RAISE EXCEPTION 'DRIVER_PAYOUT_SETTLEMENT_NOT_ENABLED';
  END IF;

  UPDATE public.payout_orders
     SET status = 'settled', settled_gnf = v_o.merchant_liability_debit_gnf,
         evidence_id = v_e.id, settled_at = now(), reservation_gnf = 0, updated_at = now()
   WHERE id = v_o.id;

  UPDATE public.payout_provider_evidence
     SET reconciliation_state = 'reconciled', mismatch_reason = NULL,
         payout_order_id = v_o.id, reconciled_at = now(), updated_at = now()
   WHERE id = v_e.id;

  IF v_o.source_request_id IS NOT NULL AND v_o.source_kind = 'merchant_settlement' THEN
    UPDATE public.merchant_settlement_requests
       SET status = 'settled', evidence_ref = v_e.provider_reference,
           settled_at = now(), reviewed_by = p_actor, reviewed_at = now(), updated_at = now()
     WHERE id = v_o.source_request_id;
  END IF;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (p_actor,'finance','payout.settled','payout_order', v_o.id::text,
          jsonb_build_object('amount_gnf',v_o.merchant_liability_debit_gnf,
                             'expected_provider_transfer_gnf',v_o.expected_provider_transfer_gnf,
                             'provider_reference',v_e.provider_reference,
                             'evidence_id',v_e.id));

  RETURN jsonb_build_object('status','settled','payout_order_id',v_o.id,
    'moved_gnf', v_o.merchant_liability_debit_gnf, 'evidence_id', v_e.id);
END $function$;

-- Receipt exposes the canonical expected transfer amount.
CREATE OR REPLACE FUNCTION public.merchant_settlement_receipt(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_r public.merchant_settlement_requests;
  v_o public.payout_orders; v_e public.payout_provider_evidence; v_owner uuid; v_journal jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO v_r FROM public.merchant_settlement_requests WHERE id = p_request_id;
  IF v_r.id IS NULL THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
  SELECT owner_user_id INTO v_owner FROM public.merchant_stores WHERE id = v_r.merchant_store_id;
  IF v_owner IS DISTINCT FROM v_uid AND NOT public._finance_privileged(v_uid) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  SELECT * INTO v_o FROM public.payout_orders
   WHERE source_kind = 'merchant_settlement' AND source_request_id = v_r.id;
  IF v_o.id IS NULL OR v_o.status <> 'settled' OR v_o.evidence_id IS NULL THEN
    RETURN jsonb_build_object('kind','request_confirmation','request_id',v_r.id,
      'status', v_r.status, 'requested_amount_gnf', v_r.amount_gnf,
      'settled', false, 'receipt_available', false,
      'message','Aucun règlement externe prouvé pour cette demande.');
  END IF;
  SELECT * INTO v_e FROM public.payout_provider_evidence WHERE id = v_o.evidence_id;
  SELECT jsonb_build_object('journal_id', j.id, 'journal_key', j.journal_key, 'posted_at', j.created_at)
    INTO v_journal FROM public.ledger_journals j
   WHERE j.journal_key = 'payout-settle:' || v_o.id::text;

  RETURN jsonb_build_object(
    'kind','settlement_receipt','receipt_available', true, 'settled', true,
    'request_id', v_r.id, 'payout_order_id', v_o.id,
    'requested_principal_gnf', v_o.requested_principal_gnf,
    'provider_fee_gnf', v_o.provider_fee_gnf, 'fee_borne_by', v_o.fee_borne_by,
    'merchant_liability_debit_gnf', v_o.merchant_liability_debit_gnf,
    'recipient_net_gnf', v_o.recipient_net_gnf,
    'expected_provider_transfer_gnf', v_o.expected_provider_transfer_gnf,
    'provider', v_o.provider, 'provider_reference', v_e.provider_reference,
    'destination_msisdn', v_o.destination_msisdn,
    'provider_status', v_e.provider_status, 'transferred_at', v_e.transferred_at,
    'settled_at', v_o.settled_at, 'environment', v_o.environment,
    'ledger', COALESCE(v_journal, '{}'::jsonb));
END $function$;

-- ============================================================
-- (1) LEGACY MERCHANT SETTLEMENT ESCAPE PATH — hard disabled
-- ============================================================
CREATE OR REPLACE FUNCTION public.merchant_settlement_hold(p_payable_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  RAISE EXCEPTION 'LEGACY_PATH_DISABLED:merchant_settlement_hold'
    USING DETAIL = 'Use merchant_settlement_request_create -> payout_record_provider_evidence.';
END $function$;

CREATE OR REPLACE FUNCTION public.merchant_settlement_complete(p_payable_id uuid, p_evidence_ref text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  RAISE EXCEPTION 'LEGACY_PATH_DISABLED:merchant_settlement_complete'
    USING DETAIL = 'Merchant payables are debited only by _payout_settle_internal against reconciled provider evidence.';
END $function$;

CREATE OR REPLACE FUNCTION public.merchant_settlement_fail(p_payable_id uuid, p_reason text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  RAISE EXCEPTION 'LEGACY_PATH_DISABLED:merchant_settlement_fail'
    USING DETAIL = 'Use payout_reject_release on the payout order.';
END $function$;

REVOKE ALL ON FUNCTION public.merchant_settlement_hold(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.merchant_settlement_complete(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.merchant_settlement_fail(uuid, text) FROM PUBLIC, anon, authenticated, service_role;

-- ============================================================
-- (2) LEGACY DRIVER PAYOUT BYPASS — stage-gated + de-exposed
-- ============================================================
CREATE OR REPLACE FUNCTION public.driver_payout_hold_place(p_request_id uuid, p_driver uuid, p_amount_gnf bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid(); v_w public.wallets; v_promo bigint; v_withdrawable bigint; v_key text;
BEGIN
  IF NOT public._finance_flag('driver_cashout_enabled') THEN
    RAISE EXCEPTION 'STAGE_DISABLED:driver_cashout_enabled';
  END IF;
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF EXISTS (SELECT 1 FROM public.mission_financial_holds
              WHERE source_module = 'cashout' AND source_id = p_request_id AND kind = 'cashout') THEN
    RETURN jsonb_build_object('status','already_held');
  END IF;

  SELECT * INTO v_w FROM public.wallets
   WHERE owner_user_id = p_driver AND party_type = 'driver' FOR UPDATE;
  IF v_w.id IS NULL THEN RAISE EXCEPTION 'Driver wallet not found'; END IF;

  v_promo := COALESCE((public.driver_promo_balance(p_driver)->>'promo_available_gnf')::bigint, 0);
  v_withdrawable := GREATEST(v_w.balance_gnf - v_w.held_gnf - v_promo, 0);
  IF v_withdrawable < p_amount_gnf THEN
    RAISE EXCEPTION 'INSUFFICIENT_WITHDRAWABLE_BALANCE'
      USING DETAIL = format('withdrawable=%s requested=%s restricted=%s', v_withdrawable, p_amount_gnf, v_promo);
  END IF;

  v_key := 'cashout-hold:' || p_request_id::text;
  UPDATE public.wallets SET held_gnf = held_gnf + p_amount_gnf, updated_at = now() WHERE id = v_w.id;

  PERFORM public._ledger_post(v_key, 'cashout', p_request_id, 'payout_hold',
    jsonb_build_array(
      jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',p_amount_gnf,
                         'party_type','driver','party_user_id',p_driver,'memo','payout reserved'),
      jsonb_build_object('account','L_HOLD_CASHOUT','amount_gnf',-p_amount_gnf,
                         'party_type','driver','party_user_id',p_driver,'memo','pending payout')),
    NULL, v_caller, jsonb_build_object('restricted_excluded_gnf', v_promo), false);

  INSERT INTO public.mission_financial_holds
    (driver_user_id, party_type, party_user_id, mission_type, source_module, source_id, kind,
     amount_gnf, unrestricted_gnf, policy_snapshot, basis_value_gnf, journal_key)
  VALUES (p_driver,'driver',p_driver,'ride','cashout',p_request_id,'cashout',
          p_amount_gnf, p_amount_gnf, jsonb_build_object('restricted_excluded_gnf', v_promo),
          p_amount_gnf, v_key);

  RETURN jsonb_build_object('status','held','amount_gnf',p_amount_gnf,'restricted_excluded_gnf',v_promo);
END;
$function$;

CREATE OR REPLACE FUNCTION public.driver_payout_confirm(p_request_id uuid, p_evidence_ref text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_caller uuid := auth.uid(); v_h public.mission_financial_holds;
BEGIN
  -- Stage 6 gate FIRST: no driver money may move while the rail is off.
  IF NOT public._finance_flag('driver_cashout_enabled') THEN
    RAISE EXCEPTION 'STAGE_DISABLED:driver_cashout_enabled';
  END IF;
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_evidence_ref IS NULL OR length(btrim(p_evidence_ref)) < 4 THEN
    RAISE EXCEPTION 'PAYOUT_EVIDENCE_REQUIRED';
  END IF;
  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = 'cashout' AND source_id = p_request_id AND kind = 'cashout' FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'Payout hold not found'; END IF;
  IF v_h.state <> 'held' THEN RETURN jsonb_build_object('status','already_resolved'); END IF;

  PERFORM public._finance_evidence_claim(p_evidence_ref,'driver_payout',p_request_id,v_h.amount_gnf,v_caller);

  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_h.amount_gnf,0),
                            balance_gnf = balance_gnf - v_h.amount_gnf, updated_at = now()
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver';

  PERFORM public._ledger_post('cashout-paid:' || p_request_id::text, 'cashout', p_request_id, 'payout_paid',
    jsonb_build_array(
      jsonb_build_object('account','L_HOLD_CASHOUT','amount_gnf',v_h.amount_gnf,
                         'party_type','driver','party_user_id',v_h.driver_user_id,'memo','payout released'),
      jsonb_build_object('account','A_PROVIDER_CLEARING','amount_gnf',-v_h.amount_gnf,'memo','paid via provider')),
    NULL, v_caller, v_h.policy_snapshot, false, p_evidence_ref);

  UPDATE public.mission_financial_holds
     SET state='captured', captured_gnf = amount_gnf, captured_unrestricted_gnf = amount_gnf,
         evidence_ref = p_evidence_ref, resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','paid','amount_gnf',v_h.amount_gnf);
END; $function$;

-- Legacy driver payout execution surfaces are internal-only from now on.
REVOKE ALL ON FUNCTION public.driver_payout_confirm(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.driver_payout_cancel(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.driver_payout_hold_place(uuid, uuid, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.driver_payout_confirm(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.driver_payout_cancel(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.driver_payout_hold_place(uuid, uuid, bigint) TO service_role;

-- Anon stays denied on every payout surface.
REVOKE ALL ON FUNCTION public.payout_record_provider_evidence(uuid, text, text, text, bigint, text, text, timestamptz, bigint, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.payout_reconcile_evidence(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.payout_reject_release(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.merchant_settlement_schedule_generate(timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._payout_order_create_internal(party_type, uuid, uuid, text, uuid, bigint, text, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._payout_settle_internal(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.payout_record_provider_evidence(uuid, text, text, text, bigint, text, text, timestamptz, bigint, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.payout_reconcile_evidence(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.payout_reject_release(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.merchant_settlement_schedule_generate(timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._payout_order_create_internal(party_type, uuid, uuid, text, uuid, bigint, text, text, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._payout_settle_internal(uuid, uuid, uuid) TO service_role;