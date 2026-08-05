-- =====================================================================
-- Shared guard: privileged finance caller (God Admin, finance admin, or
-- trusted server-side code running without an end-user session).
-- =====================================================================
CREATE OR REPLACE FUNCTION public._finance_privileged(p_caller uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_caller IS NULL
      OR public.is_god_admin(p_caller)
      OR public.has_admin_role(p_caller, 'finance_admin'::admin_role);
$$;
REVOKE ALL ON FUNCTION public._finance_privileged(uuid) FROM PUBLIC, anon;

-- =====================================================================
-- 1. Chop Pay customer order money
-- =====================================================================
CREATE OR REPLACE FUNCTION public.chop_pay_customer_hold_place(
  p_source_module text, p_source_id uuid, p_amount_gnf bigint,
  p_mission_type text DEFAULT NULL, p_customer uuid DEFAULT NULL,
  p_is_sandbox boolean DEFAULT false, p_snapshot jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_cust uuid := COALESCE(p_customer, auth.uid());
  v_w public.wallets; v_avail bigint; v_key text; v_tx public.wallet_transactions;
BEGIN
  IF v_cust IS NULL THEN RAISE EXCEPTION 'Customer required'; END IF;
  IF v_cust <> v_caller AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF COALESCE(p_amount_gnf,0) <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;
  IF public.is_user_banned(v_cust) OR public.is_user_frozen(v_cust) THEN
    RAISE EXCEPTION 'ACCOUNT_RESTRICTED';
  END IF;

  IF EXISTS (SELECT 1 FROM public.mission_financial_holds
              WHERE source_module = p_source_module AND source_id = p_source_id
                AND kind = 'customer_payment') THEN
    RETURN jsonb_build_object('status','already_held');
  END IF;

  INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_cust, 'client')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT * INTO v_w FROM public.wallets
   WHERE owner_user_id = v_cust AND party_type = 'client' FOR UPDATE;
  IF v_w.status <> 'active' THEN RAISE EXCEPTION 'Wallet not active'; END IF;

  v_avail := GREATEST(v_w.balance_gnf - v_w.held_gnf, 0);
  IF v_avail < p_amount_gnf THEN
    RAISE EXCEPTION 'INSUFFICIENT_CUSTOMER_BALANCE'
      USING DETAIL = format('required=%s available=%s', p_amount_gnf, v_avail);
  END IF;

  v_key := format('cust-hold:%s:%s', p_source_module, p_source_id);

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, related_user_id,
     related_entity, description, metadata)
  VALUES (v_key, 'hold', 'pending', p_amount_gnf, v_w.id, v_cust,
          p_source_module || ':' || p_source_id::text, 'Paiement Chop Pay (réservé)',
          jsonb_build_object('mission_type', p_mission_type, 'is_sandbox', p_is_sandbox))
  RETURNING * INTO v_tx;

  UPDATE public.wallets SET held_gnf = held_gnf + p_amount_gnf, updated_at = now() WHERE id = v_w.id;

  PERFORM public._ledger_post(v_key, p_source_module, p_source_id, 'customer_payment_hold',
    jsonb_build_array(
      jsonb_build_object('account','L_CUSTOMER_CHOPPAY','amount_gnf',p_amount_gnf,
                         'party_type','client','party_user_id',v_cust,'memo','customer funds reserved'),
      jsonb_build_object('account','L_CUSTOMER_HOLD','amount_gnf',-p_amount_gnf,
                         'party_type','client','party_user_id',v_cust,'memo','order hold')),
    p_mission_type, v_caller, p_snapshot, p_is_sandbox);

  INSERT INTO public.mission_financial_holds
    (driver_user_id, party_type, party_user_id, mission_type, source_module, source_id, kind,
     amount_gnf, customer_gnf, hold_tx_id, policy_snapshot, basis_value_gnf, is_sandbox, journal_key)
  VALUES (NULL, 'client', v_cust, COALESCE(p_mission_type,'ride'), p_source_module, p_source_id,
          'customer_payment', p_amount_gnf, p_amount_gnf, v_tx.id, p_snapshot,
          p_amount_gnf, p_is_sandbox, v_key);

  RETURN jsonb_build_object('status','held','amount_gnf',p_amount_gnf);
END;
$$;

CREATE OR REPLACE FUNCTION public.chop_pay_customer_capture(
  p_source_module text, p_source_id uuid,
  p_merchant_store_id uuid, p_merchant_gnf bigint,
  p_driver uuid, p_driver_earning_gnf bigint,
  p_commission_gnf bigint, p_fee_gnf bigint,
  p_refund_remainder boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_h public.mission_financial_holds;
  v_m bigint := GREATEST(COALESCE(p_merchant_gnf,0),0);
  v_d bigint := GREATEST(COALESCE(p_driver_earning_gnf,0),0);
  v_c bigint := GREATEST(COALESCE(p_commission_gnf,0),0);
  v_f bigint := GREATEST(COALESCE(p_fee_gnf,0),0);
  v_total bigint; v_remainder bigint;
  v_lines jsonb;
  v_cw public.wallets; v_dw public.wallets; v_mw public.wallets; v_master public.wallets;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND kind = 'customer_payment' FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'Customer hold not found'; END IF;
  IF v_h.state <> 'held' THEN
    RETURN jsonb_build_object('status','already_resolved','captured_gnf',v_h.captured_gnf);
  END IF;

  v_total := v_m + v_d + v_c + v_f;
  IF v_total > v_h.amount_gnf THEN
    RAISE EXCEPTION 'SPLIT_EXCEEDS_HOLD' USING DETAIL = format('split=%s hold=%s', v_total, v_h.amount_gnf);
  END IF;
  v_remainder := v_h.amount_gnf - v_total;
  IF v_remainder > 0 AND NOT p_refund_remainder THEN
    RAISE EXCEPTION 'SPLIT_MUST_BE_EXACT' USING DETAIL = format('unallocated=%s', v_remainder);
  END IF;
  IF v_m > 0 AND p_merchant_store_id IS NULL THEN RAISE EXCEPTION 'Merchant store required'; END IF;
  IF v_d > 0 AND p_driver IS NULL THEN RAISE EXCEPTION 'Driver required'; END IF;

  SELECT * INTO v_cw FROM public.wallets
   WHERE owner_user_id = v_h.party_user_id AND party_type = 'client' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_h.amount_gnf, 0),
                            balance_gnf = balance_gnf - v_total, updated_at = now()
   WHERE id = v_cw.id;

  v_lines := jsonb_build_array(jsonb_build_object(
    'account','L_CUSTOMER_HOLD','amount_gnf',v_total,
    'party_type','client','party_user_id',v_h.party_user_id,'memo','order captured'));

  IF v_m > 0 THEN
    v_lines := v_lines || jsonb_build_object('account','L_MERCHANT_PAYABLE','amount_gnf',-v_m,
      'party_type','merchant','merchant_store_id',p_merchant_store_id,'memo','merchant amount payable');
  END IF;
  IF v_d > 0 THEN
    INSERT INTO public.wallets (owner_user_id, party_type) VALUES (p_driver,'driver')
    ON CONFLICT (owner_user_id, party_type) DO NOTHING;
    SELECT * INTO v_dw FROM public.wallets
     WHERE owner_user_id = p_driver AND party_type = 'driver' FOR UPDATE;
    UPDATE public.wallets SET balance_gnf = balance_gnf + v_d, updated_at = now() WHERE id = v_dw.id;
    v_lines := v_lines || jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_d,
      'party_type','driver','party_user_id',p_driver,'memo','delivery earning');
  END IF;
  IF v_c > 0 THEN
    v_lines := v_lines || jsonb_build_object('account','R_COMMISSION','amount_gnf',-v_c,'memo','commission revenue');
  END IF;
  IF v_f > 0 THEN
    v_lines := v_lines || jsonb_build_object('account','R_TRANSACTION_FEE','amount_gnf',-v_f,'memo','service fee revenue');
  END IF;
  IF (v_c + v_f) > 0 AND v_master.id IS NOT NULL THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf + v_c + v_f, updated_at = now() WHERE id = v_master.id;
  END IF;

  IF v_total > 0 THEN
    PERFORM public._ledger_post(
      format('cust-capture:%s:%s', p_source_module, p_source_id),
      p_source_module, p_source_id, 'customer_payment_capture', v_lines,
      v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox);
  END IF;

  IF v_remainder > 0 THEN
    PERFORM public._ledger_post(
      format('cust-refund:%s:%s', p_source_module, p_source_id),
      p_source_module, p_source_id, 'customer_payment_refund',
      jsonb_build_array(
        jsonb_build_object('account','L_CUSTOMER_HOLD','amount_gnf',v_remainder,
                           'party_type','client','party_user_id',v_h.party_user_id,'memo','unused hold'),
        jsonb_build_object('account','L_CUSTOMER_CHOPPAY','amount_gnf',-v_remainder,
                           'party_type','client','party_user_id',v_h.party_user_id,'memo','returned to customer balance')),
      v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox);
  END IF;

  UPDATE public.wallet_transactions SET status='completed', completed_at=now()
   WHERE id = v_h.hold_tx_id AND status='pending';

  UPDATE public.mission_financial_holds
     SET state='captured', captured_gnf = v_total, released_gnf = v_remainder,
         resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','captured','captured_gnf',v_total,
    'merchant_gnf',v_m,'driver_earning_gnf',v_d,'commission_gnf',v_c,'fee_gnf',v_f,
    'refunded_gnf',v_remainder);
END;
$$;

CREATE OR REPLACE FUNCTION public.chop_pay_customer_refund(
  p_source_module text, p_source_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_h public.mission_financial_holds; v_open bigint; v_cw public.wallets;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND kind = 'customer_payment' FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'Customer hold not found'; END IF;
  v_open := v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf;
  IF v_open <= 0 THEN RETURN jsonb_build_object('status','nothing_to_refund'); END IF;

  SELECT * INTO v_cw FROM public.wallets
   WHERE owner_user_id = v_h.party_user_id AND party_type = 'client' FOR UPDATE;
  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_open, 0), updated_at = now() WHERE id = v_cw.id;

  PERFORM public._ledger_post(
    format('cust-refund:%s:%s', p_source_module, p_source_id),
    p_source_module, p_source_id, 'customer_payment_refund',
    jsonb_build_array(
      jsonb_build_object('account','L_CUSTOMER_HOLD','amount_gnf',v_open,
                         'party_type','client','party_user_id',v_h.party_user_id,'memo','hold released'),
      jsonb_build_object('account','L_CUSTOMER_CHOPPAY','amount_gnf',-v_open,
                         'party_type','client','party_user_id',v_h.party_user_id,'memo','refunded to customer balance')),
    v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox, p_reason);

  UPDATE public.wallet_transactions SET status='cancelled', completed_at=now()
   WHERE id = v_h.hold_tx_id AND status='pending';
  UPDATE public.mission_financial_holds
     SET state='released', released_gnf = released_gnf + v_open, reason = COALESCE(p_reason, reason),
         resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','refunded','refunded_gnf',v_open);
END;
$$;

-- =====================================================================
-- 2. Merchant payables
-- =====================================================================
CREATE OR REPLACE FUNCTION public.merchant_payable_create(
  p_source_module text, p_source_id uuid, p_merchant_store_id uuid,
  p_subtotal_gnf bigint, p_deduction_gnf bigint DEFAULT 0,
  p_mission_type text DEFAULT NULL, p_snapshot jsonb DEFAULT '{}'::jsonb,
  p_is_sandbox boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_owner uuid; v_amount bigint; v_row public.merchant_payables;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  v_amount := GREATEST(COALESCE(p_subtotal_gnf,0) - GREATEST(COALESCE(p_deduction_gnf,0),0), 0);
  SELECT owner_user_id INTO v_owner FROM public.merchant_stores WHERE id = p_merchant_store_id;

  INSERT INTO public.merchant_payables
    (payable_key, source_module, source_id, merchant_store_id, merchant_user_id, mission_type,
     subtotal_gnf, deduction_gnf, amount_gnf, policy_snapshot, is_sandbox)
  VALUES (format('payable:%s:%s:%s', p_source_module, p_source_id, p_merchant_store_id),
          p_source_module, p_source_id, p_merchant_store_id, v_owner, p_mission_type,
          GREATEST(COALESCE(p_subtotal_gnf,0),0), GREATEST(COALESCE(p_deduction_gnf,0),0),
          v_amount, p_snapshot, p_is_sandbox)
  ON CONFLICT (source_module, source_id, merchant_store_id) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    SELECT * INTO v_row FROM public.merchant_payables
     WHERE source_module = p_source_module AND source_id = p_source_id
       AND merchant_store_id = p_merchant_store_id;
    RETURN jsonb_build_object('status','already_exists','payable_id',v_row.id,'amount_gnf',v_row.amount_gnf);
  END IF;
  RETURN jsonb_build_object('status','created','payable_id',v_row.id,'amount_gnf',v_row.amount_gnf,
                            'note','Obligation recorded; no value moves until it is funded');
END;
$$;

CREATE OR REPLACE FUNCTION public.merchant_payable_fund(
  p_source_module text, p_source_id uuid, p_merchant_store_id uuid, p_funding_source text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_p public.merchant_payables; v_h public.mission_financial_holds;
  v_amount bigint; v_from text; v_mw public.wallets;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_funding_source NOT IN ('customer_choppay','driver_cash_funding','platform') THEN
    RAISE EXCEPTION 'Invalid funding source';
  END IF;

  SELECT * INTO v_p FROM public.merchant_payables
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND merchant_store_id = p_merchant_store_id FOR UPDATE;
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'Payable not found'; END IF;
  IF v_p.funded_gnf >= v_p.amount_gnf THEN
    RETURN jsonb_build_object('status','already_funded','payable_id',v_p.id);
  END IF;
  v_amount := v_p.amount_gnf - v_p.funded_gnf;

  IF p_funding_source = 'driver_cash_funding' THEN
    SELECT * INTO v_h FROM public.mission_financial_holds
     WHERE source_module = p_source_module AND source_id = p_source_id
       AND kind = 'cash_funding' AND state IN ('held','partially_captured') FOR UPDATE;
    IF v_h.id IS NULL THEN RAISE EXCEPTION 'CASH_FUNDING_HOLD_MISSING'; END IF;
    IF (v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf) < v_amount THEN
      RAISE EXCEPTION 'CASH_FUNDING_INSUFFICIENT';
    END IF;
    IF v_h.promo_gnf > 0 THEN
      RAISE EXCEPTION 'RESTRICTED_FUNDS_CANNOT_FUND_MERCHANDISE';
    END IF;
    v_from := 'L_HOLD_CASH_FUNDING';
    UPDATE public.mission_financial_holds
       SET captured_gnf = captured_gnf + v_amount,
           state = CASE WHEN captured_gnf + v_amount >= amount_gnf THEN 'captured' ELSE 'partially_captured' END
     WHERE id = v_h.id;
    UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_amount,0),
                              balance_gnf = balance_gnf - v_amount, updated_at = now()
     WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver';
  ELSIF p_funding_source = 'customer_choppay' THEN
    SELECT * INTO v_h FROM public.mission_financial_holds
     WHERE source_module = p_source_module AND source_id = p_source_id
       AND kind = 'customer_payment' FOR UPDATE;
    IF v_h.id IS NULL THEN RAISE EXCEPTION 'CUSTOMER_HOLD_MISSING'; END IF;
    v_from := 'L_CUSTOMER_HOLD';
  ELSE
    v_from := 'EQ_PLATFORM';
  END IF;

  -- Merchant wallet is a CHOPCHOP liability, credited on funding.
  IF v_p.merchant_user_id IS NOT NULL THEN
    INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_p.merchant_user_id,'merchant')
    ON CONFLICT (owner_user_id, party_type) DO NOTHING;
    UPDATE public.wallets SET balance_gnf = balance_gnf + v_amount, updated_at = now()
     WHERE owner_user_id = v_p.merchant_user_id AND party_type = 'merchant';
  END IF;

  PERFORM public._ledger_post(
    format('payable-fund:%s:%s:%s', p_source_module, p_source_id, p_merchant_store_id),
    p_source_module, p_source_id, 'merchant_payable_funded',
    jsonb_build_array(
      jsonb_build_object('account',v_from,'amount_gnf',v_amount,'memo','funding source consumed'),
      jsonb_build_object('account','L_MERCHANT_PAYABLE','amount_gnf',-v_amount,
                         'party_type','merchant','party_user_id',v_p.merchant_user_id,
                         'merchant_store_id',p_merchant_store_id,'memo','merchant payable funded')),
    v_p.mission_type, v_caller, v_p.policy_snapshot, v_p.is_sandbox);

  UPDATE public.merchant_payables
     SET funded_gnf = funded_gnf + v_amount, funding_source = p_funding_source,
         state = 'funded', updated_at = now()
   WHERE id = v_p.id;

  RETURN jsonb_build_object('status','funded','payable_id',v_p.id,'funded_gnf',v_amount,
                            'funding_source',p_funding_source,
                            'preparation_authorized',true);
END;
$$;

CREATE OR REPLACE FUNCTION public.merchant_settlement_hold(p_payable_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid(); v_p public.merchant_payables; v_amount bigint;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT * INTO v_p FROM public.merchant_payables WHERE id = p_payable_id FOR UPDATE;
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'Payable not found'; END IF;
  IF v_p.state = 'settlement_held' THEN RETURN jsonb_build_object('status','already_held'); END IF;
  IF v_p.state <> 'funded' AND v_p.state <> 'due' THEN
    RAISE EXCEPTION 'PAYABLE_NOT_FUNDED' USING DETAIL = v_p.state;
  END IF;
  v_amount := v_p.funded_gnf - v_p.settled_gnf;
  IF v_amount <= 0 THEN RETURN jsonb_build_object('status','nothing_due'); END IF;

  IF v_p.merchant_user_id IS NOT NULL THEN
    UPDATE public.wallets SET held_gnf = held_gnf + v_amount, updated_at = now()
     WHERE owner_user_id = v_p.merchant_user_id AND party_type = 'merchant';
  END IF;

  PERFORM public._ledger_post('settle-hold:' || v_p.id::text, 'merchant_settlement', v_p.id,
    'merchant_settlement_hold',
    jsonb_build_array(
      jsonb_build_object('account','L_MERCHANT_PAYABLE','amount_gnf',v_amount,
                         'party_type','merchant','party_user_id',v_p.merchant_user_id,
                         'merchant_store_id',v_p.merchant_store_id,'memo','payable reserved for settlement'),
      jsonb_build_object('account','L_HOLD_SETTLEMENT','amount_gnf',-v_amount,
                         'party_type','merchant','merchant_store_id',v_p.merchant_store_id,'memo','settlement hold')),
    v_p.mission_type, v_caller, v_p.policy_snapshot, v_p.is_sandbox);

  UPDATE public.merchant_payables SET state = 'settlement_held', updated_at = now() WHERE id = v_p.id;
  RETURN jsonb_build_object('status','settlement_held','amount_gnf',v_amount);
END;
$$;

CREATE OR REPLACE FUNCTION public.merchant_settlement_complete(p_payable_id uuid, p_evidence_ref text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid(); v_p public.merchant_payables; v_amount bigint;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_evidence_ref IS NULL OR length(btrim(p_evidence_ref)) < 4 THEN
    RAISE EXCEPTION 'SETTLEMENT_EVIDENCE_REQUIRED';
  END IF;
  SELECT * INTO v_p FROM public.merchant_payables WHERE id = p_payable_id FOR UPDATE;
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'Payable not found'; END IF;
  IF v_p.state = 'settled' THEN RETURN jsonb_build_object('status','already_settled'); END IF;
  IF v_p.state <> 'settlement_held' THEN RAISE EXCEPTION 'SETTLEMENT_NOT_HELD'; END IF;
  v_amount := v_p.funded_gnf - v_p.settled_gnf;

  IF v_p.merchant_user_id IS NOT NULL THEN
    UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_amount,0),
                              balance_gnf = balance_gnf - v_amount, updated_at = now()
     WHERE owner_user_id = v_p.merchant_user_id AND party_type = 'merchant';
  END IF;

  PERFORM public._ledger_post('settle-paid:' || v_p.id::text, 'merchant_settlement', v_p.id,
    'merchant_settlement_paid',
    jsonb_build_array(
      jsonb_build_object('account','L_HOLD_SETTLEMENT','amount_gnf',v_amount,
                         'party_type','merchant','merchant_store_id',v_p.merchant_store_id,'memo','settlement released'),
      jsonb_build_object('account','A_PROVIDER_CLEARING','amount_gnf',-v_amount,'memo','paid out to provider')),
    v_p.mission_type, v_caller, v_p.policy_snapshot, v_p.is_sandbox, p_evidence_ref);

  UPDATE public.merchant_payables
     SET settled_gnf = settled_gnf + v_amount, state = 'settled', evidence_ref = p_evidence_ref,
         resolved_by = v_caller, resolved_at = now(), updated_at = now()
   WHERE id = v_p.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller,'wallet','merchant_settlement_paid','merchant_payable',v_p.id::text,
          jsonb_build_object('amount_gnf',v_amount,'evidence_ref',p_evidence_ref), p_evidence_ref);

  RETURN jsonb_build_object('status','settled','amount_gnf',v_amount);
END;
$$;

CREATE OR REPLACE FUNCTION public.merchant_settlement_fail(p_payable_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid(); v_p public.merchant_payables; v_res jsonb; v_amount bigint;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN RAISE EXCEPTION 'A documented reason is required'; END IF;
  SELECT * INTO v_p FROM public.merchant_payables WHERE id = p_payable_id FOR UPDATE;
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'Payable not found'; END IF;
  IF v_p.state <> 'settlement_held' THEN RETURN jsonb_build_object('status','not_held'); END IF;
  v_amount := v_p.funded_gnf - v_p.settled_gnf;

  v_res := public._ledger_reverse('settle-hold:' || v_p.id::text, p_reason, NULL, v_caller);
  IF v_p.merchant_user_id IS NOT NULL THEN
    UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_amount,0), updated_at = now()
     WHERE owner_user_id = v_p.merchant_user_id AND party_type = 'merchant';
  END IF;
  UPDATE public.merchant_payables SET state = 'due', reason = p_reason, updated_at = now() WHERE id = v_p.id;
  RETURN jsonb_build_object('status','returned_to_due','amount_gnf',v_amount,'journal',v_res);
END;
$$;

-- =====================================================================
-- 3. Mission service-fee capture (from the platform_fee reserve)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.driver_mission_fee_capture(
  p_source_module text, p_source_id uuid, p_final_fee_basis_gnf bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid(); v_h public.mission_financial_holds;
  v_due bigint; v_cap bigint; v_ex bigint;
  v_cp bigint; v_cu bigint; v_rp bigint; v_ru bigint;
  v_dw public.wallets; v_master public.wallets;
BEGIN
  IF v_caller IS NULL AND NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'platform_fee' FOR UPDATE;
  IF v_h.id IS NULL THEN RETURN jsonb_build_object('status','no_hold','captured_gnf',0); END IF;
  IF v_h.state <> 'held' THEN RETURN jsonb_build_object('status','already_resolved','captured_gnf',v_h.captured_gnf); END IF;

  v_due := CASE WHEN p_final_fee_basis_gnf IS NULL THEN v_h.amount_gnf
           ELSE (GREATEST(p_final_fee_basis_gnf,0) *
                 COALESCE((v_h.policy_snapshot->>'transaction_fee_bps')::int,0)) / 10000 END;
  v_cap := LEAST(v_due, v_h.amount_gnf);
  v_ex := v_h.amount_gnf - v_cap;
  v_cp := LEAST(v_h.promo_gnf, v_cap); v_cu := v_cap - v_cp;
  v_rp := v_h.promo_gnf - v_cp; v_ru := v_ex - v_rp;

  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_h.amount_gnf,0), updated_at = now() WHERE id = v_dw.id;
  IF v_cap > 0 THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_cap, updated_at = now() WHERE id = v_dw.id;
    IF v_master.id IS NOT NULL THEN
      UPDATE public.wallets SET balance_gnf = balance_gnf + v_cap, updated_at = now() WHERE id = v_master.id;
    END IF;
    IF v_cp > 0 THEN PERFORM public._promo_consume(v_h.driver_user_id, v_cp); END IF;
    PERFORM public._ledger_post(
      format('mfh-capture:%s:%s:platform_fee', p_source_module, p_source_id),
      p_source_module, p_source_id, 'capture_platform_fee',
      jsonb_build_array(
        jsonb_build_object('account','L_HOLD_PLATFORM_FEE','amount_gnf',v_cap,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','fee reserve consumed'),
        jsonb_build_object('account','R_TRANSACTION_FEE','amount_gnf',-v_cap,'memo','transaction fee revenue')),
      v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox);
  END IF;
  IF v_ex > 0 THEN
    PERFORM public._ledger_post(
      format('mfh-release:%s:%s:platform_fee', p_source_module, p_source_id),
      p_source_module, p_source_id, 'release_platform_fee',
      jsonb_build_array(
        jsonb_build_object('account','L_HOLD_PLATFORM_FEE','amount_gnf',v_ex,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','excess fee reserve'),
        jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',-v_rp,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored restricted'),
        jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_ru,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored unrestricted')),
      v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox);
  END IF;

  UPDATE public.wallet_transactions SET status='completed', completed_at=now()
   WHERE id = v_h.hold_tx_id AND status='pending';
  UPDATE public.mission_financial_holds
     SET state='captured', captured_gnf = v_cap, released_gnf = v_ex,
         resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','captured','captured_gnf',v_cap,'released_gnf',v_ex);
END;
$$;

-- =====================================================================
-- 4. Customer cancellation debt
-- =====================================================================
CREATE OR REPLACE FUNCTION public.customer_cancellation_debt_create(
  p_source_module text, p_source_id uuid, p_customer uuid, p_mission_type text,
  p_stage text, p_basis_gnf bigint, p_exempt_reason text DEFAULT NULL,
  p_is_sandbox boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid(); v_req jsonb; v_bps int; v_amount bigint; v_row public.customer_cancellation_debts;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_stage NOT IN ('before_dispatch','after_dispatch') THEN RAISE EXCEPTION 'Invalid stage'; END IF;

  v_req := public.finance_mission_requirement_v2(p_mission_type,0,0,0,0,'choppay');
  v_bps := CASE p_stage WHEN 'before_dispatch' THEN COALESCE((v_req->>'cancel_before_dispatch_bps')::int,0)
                        ELSE COALESCE((v_req->>'cancel_after_dispatch_bps')::int,0) END;
  v_amount := (GREATEST(COALESCE(p_basis_gnf,0),0) * v_bps) / 10000;

  IF p_exempt_reason IS NOT NULL THEN v_amount := 0; END IF;

  INSERT INTO public.customer_cancellation_debts
    (debt_key, customer_user_id, source_module, source_id, mission_type, stage,
     basis_gnf, applied_bps, amount_gnf, state, exempt_reason, policy_snapshot, is_sandbox)
  VALUES (format('cancel:%s:%s', p_source_module, p_source_id), p_customer, p_source_module,
          p_source_id, p_mission_type, p_stage, GREATEST(COALESCE(p_basis_gnf,0),0), v_bps, v_amount,
          CASE WHEN p_exempt_reason IS NOT NULL THEN 'exempt' ELSE 'outstanding' END,
          p_exempt_reason, COALESCE(v_req->'policy_snapshot','{}'::jsonb), p_is_sandbox)
  ON CONFLICT (source_module, source_id) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN RETURN jsonb_build_object('status','already_exists'); END IF;
  IF v_amount > 0 THEN
    PERFORM public._ledger_post(v_row.debt_key, p_source_module, p_source_id, 'cancellation_fee_charged',
      jsonb_build_array(
        jsonb_build_object('account','A_CUSTOMER_DEBT','amount_gnf',v_amount,
                           'party_type','client','party_user_id',p_customer,'memo','cancellation fee receivable'),
        jsonb_build_object('account','R_CANCELLATION_FEE','amount_gnf',-v_amount,'memo','cancellation fee revenue')),
      p_mission_type, v_caller, COALESCE(v_req->'policy_snapshot','{}'::jsonb), p_is_sandbox);
  END IF;

  RETURN jsonb_build_object('status', CASE WHEN p_exempt_reason IS NOT NULL THEN 'exempt' ELSE 'charged' END,
                            'debt_id',v_row.id,'amount_gnf',v_amount,'applied_bps',v_bps);
END;
$$;

CREATE OR REPLACE FUNCTION public.customer_cancellation_debt_collect(p_debt_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid(); v_d public.customer_cancellation_debts;
  v_w public.wallets; v_master public.wallets; v_take bigint; v_avail bigint;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT * INTO v_d FROM public.customer_cancellation_debts WHERE id = p_debt_id FOR UPDATE;
  IF v_d.id IS NULL THEN RAISE EXCEPTION 'Debt not found'; END IF;
  IF v_d.state <> 'outstanding' THEN RETURN jsonb_build_object('status','not_outstanding'); END IF;

  SELECT * INTO v_w FROM public.wallets
   WHERE owner_user_id = v_d.customer_user_id AND party_type = 'client' FOR UPDATE;
  v_avail := GREATEST(COALESCE(v_w.balance_gnf,0) - COALESCE(v_w.held_gnf,0), 0);
  v_take := LEAST(v_d.amount_gnf - v_d.paid_gnf - v_d.waived_gnf, v_avail);
  IF v_take <= 0 THEN RETURN jsonb_build_object('status','no_funds','outstanding_gnf', v_d.amount_gnf - v_d.paid_gnf); END IF;

  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
  UPDATE public.wallets SET balance_gnf = balance_gnf - v_take, updated_at = now() WHERE id = v_w.id;
  IF v_master.id IS NOT NULL THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf + v_take, updated_at = now() WHERE id = v_master.id;
  END IF;

  PERFORM public._ledger_post('cancel-collect:' || v_d.id::text, v_d.source_module, v_d.source_id,
    'cancellation_fee_collected',
    jsonb_build_array(
      jsonb_build_object('account','L_CUSTOMER_CHOPPAY','amount_gnf',v_take,
                         'party_type','client','party_user_id',v_d.customer_user_id,'memo','debt settled from balance'),
      jsonb_build_object('account','A_CUSTOMER_DEBT','amount_gnf',-v_take,
                         'party_type','client','party_user_id',v_d.customer_user_id,'memo','receivable cleared')),
    v_d.mission_type, v_caller, v_d.policy_snapshot, v_d.is_sandbox);

  UPDATE public.customer_cancellation_debts
     SET paid_gnf = paid_gnf + v_take,
         state = CASE WHEN paid_gnf + v_take + waived_gnf >= amount_gnf THEN 'paid' ELSE 'outstanding' END,
         resolved_by = v_caller, resolved_at = now(), updated_at = now()
   WHERE id = v_d.id;

  RETURN jsonb_build_object('status','collected','collected_gnf',v_take);
END;
$$;

CREATE OR REPLACE FUNCTION public.customer_cancellation_debt_waive(p_debt_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid(); v_d public.customer_cancellation_debts; v_open bigint;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN RAISE EXCEPTION 'A documented reason is required'; END IF;
  SELECT * INTO v_d FROM public.customer_cancellation_debts WHERE id = p_debt_id FOR UPDATE;
  IF v_d.id IS NULL THEN RAISE EXCEPTION 'Debt not found'; END IF;
  v_open := v_d.amount_gnf - v_d.paid_gnf - v_d.waived_gnf;
  IF v_open <= 0 THEN RETURN jsonb_build_object('status','nothing_to_waive'); END IF;

  PERFORM public._ledger_post('cancel-waive:' || v_d.id::text, v_d.source_module, v_d.source_id,
    'cancellation_fee_waived',
    jsonb_build_array(
      jsonb_build_object('account','R_CANCELLATION_FEE','amount_gnf',v_open,'memo','revenue reversed'),
      jsonb_build_object('account','A_CUSTOMER_DEBT','amount_gnf',-v_open,
                         'party_type','client','party_user_id',v_d.customer_user_id,'memo','receivable written off')),
    v_d.mission_type, v_caller, v_d.policy_snapshot, v_d.is_sandbox, p_reason);

  UPDATE public.customer_cancellation_debts
     SET waived_gnf = waived_gnf + v_open, state = 'waived', exempt_reason = p_reason,
         resolved_by = v_caller, resolved_at = now(), updated_at = now()
   WHERE id = v_d.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller,'wallet','cancellation_fee_waived','cancellation_debt',v_d.id::text,
          jsonb_build_object('waived_gnf',v_open), p_reason);

  RETURN jsonb_build_object('status','waived','waived_gnf',v_open);
END;
$$;

-- =====================================================================
-- 5. Claims reserve (never automatic insurance)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.claims_reserve_allocate(
  p_source_module text, p_source_id uuid, p_authorized_gnf bigint,
  p_evidence_ref text, p_reason text, p_customer uuid DEFAULT NULL,
  p_driver uuid DEFAULT NULL, p_declared_value_gnf bigint DEFAULT 0,
  p_mission_type text DEFAULT 'envoyer', p_is_sandbox boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid(); v_row public.claims_reserves;
BEGIN
  IF v_caller IS NULL OR NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can authorise a claims reserve';
  END IF;
  IF p_evidence_ref IS NULL OR length(btrim(p_evidence_ref)) < 4 THEN RAISE EXCEPTION 'CLAIM_EVIDENCE_REQUIRED'; END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN RAISE EXCEPTION 'A documented reason is required'; END IF;
  IF COALESCE(p_authorized_gnf,0) <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;

  INSERT INTO public.claims_reserves
    (claim_key, source_module, source_id, mission_type, customer_user_id, driver_user_id,
     declared_value_gnf, authorized_gnf, evidence_ref, reason, authorized_by, is_sandbox)
  VALUES (format('claim:%s:%s', p_source_module, p_source_id), p_source_module, p_source_id,
          p_mission_type, p_customer, p_driver, GREATEST(COALESCE(p_declared_value_gnf,0),0),
          p_authorized_gnf, p_evidence_ref, p_reason, v_caller, p_is_sandbox)
  ON CONFLICT (source_module, source_id) DO NOTHING
  RETURNING * INTO v_row;
  IF v_row.id IS NULL THEN RETURN jsonb_build_object('status','already_exists'); END IF;

  PERFORM public._ledger_post(v_row.claim_key, p_source_module, p_source_id, 'claims_reserve_allocated',
    jsonb_build_array(
      jsonb_build_object('account','E_CLAIMS','amount_gnf',p_authorized_gnf,'memo','claims expense recognised'),
      jsonb_build_object('account','L_CLAIMS_RESERVE','amount_gnf',-p_authorized_gnf,'memo','reserve set aside')),
    p_mission_type, v_caller, jsonb_build_object('evidence_ref',p_evidence_ref), p_is_sandbox, p_reason);

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller,'wallet','claims_reserve_allocated','claim',v_row.id::text,
          jsonb_build_object('authorized_gnf',p_authorized_gnf,'evidence_ref',p_evidence_ref), p_reason);

  RETURN jsonb_build_object('status','allocated','claim_id',v_row.id,'authorized_gnf',p_authorized_gnf,
                            'note','Discretionary claims reserve after investigation — never automatic insurance');
END;
$$;

CREATE OR REPLACE FUNCTION public.claims_reserve_resolve(
  p_claim_id uuid, p_pay_gnf bigint, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid(); v_c public.claims_reserves; v_pay bigint; v_rel bigint; v_w public.wallets;
BEGIN
  IF v_caller IS NULL OR NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can resolve a claims reserve';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN RAISE EXCEPTION 'A documented reason is required'; END IF;
  SELECT * INTO v_c FROM public.claims_reserves WHERE id = p_claim_id FOR UPDATE;
  IF v_c.id IS NULL THEN RAISE EXCEPTION 'Claim not found'; END IF;
  IF v_c.state <> 'allocated' THEN RETURN jsonb_build_object('status','already_resolved'); END IF;

  v_pay := LEAST(GREATEST(COALESCE(p_pay_gnf,0),0), v_c.authorized_gnf);
  v_rel := v_c.authorized_gnf - v_pay;

  IF v_pay > 0 THEN
    IF v_c.customer_user_id IS NULL THEN RAISE EXCEPTION 'Claim has no customer to pay'; END IF;
    INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_c.customer_user_id,'client')
    ON CONFLICT (owner_user_id, party_type) DO NOTHING;
    UPDATE public.wallets SET balance_gnf = balance_gnf + v_pay, updated_at = now()
     WHERE owner_user_id = v_c.customer_user_id AND party_type = 'client';
    PERFORM public._ledger_post('claim-pay:' || v_c.id::text, v_c.source_module, v_c.source_id,
      'claims_reserve_paid',
      jsonb_build_array(
        jsonb_build_object('account','L_CLAIMS_RESERVE','amount_gnf',v_pay,'memo','reserve consumed'),
        jsonb_build_object('account','L_CUSTOMER_CHOPPAY','amount_gnf',-v_pay,
                           'party_type','client','party_user_id',v_c.customer_user_id,'memo','claim paid to customer')),
      v_c.mission_type, v_caller, '{}'::jsonb, v_c.is_sandbox, p_reason);
  END IF;

  IF v_rel > 0 THEN
    PERFORM public._ledger_post('claim-release:' || v_c.id::text, v_c.source_module, v_c.source_id,
      'claims_reserve_released',
      jsonb_build_array(
        jsonb_build_object('account','L_CLAIMS_RESERVE','amount_gnf',v_rel,'memo','unused reserve released'),
        jsonb_build_object('account','E_CLAIMS','amount_gnf',-v_rel,'memo','claims expense reversed')),
      v_c.mission_type, v_caller, '{}'::jsonb, v_c.is_sandbox, p_reason);
  END IF;

  UPDATE public.claims_reserves
     SET paid_gnf = v_pay, released_gnf = v_rel,
         state = CASE WHEN v_pay > 0 THEN 'paid' ELSE 'denied' END,
         resolved_by = v_caller, resolved_at = now(), updated_at = now()
   WHERE id = v_c.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller,'wallet','claims_reserve_resolved','claim',v_c.id::text,
          jsonb_build_object('paid_gnf',v_pay,'released_gnf',v_rel), p_reason);

  RETURN jsonb_build_object('status','resolved','paid_gnf',v_pay,'released_gnf',v_rel);
END;
$$;

-- =====================================================================
-- 6. Driver payout hold (restricted credit can never be reserved)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.driver_payout_hold_place(
  p_request_id uuid, p_driver uuid, p_amount_gnf bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid(); v_w public.wallets; v_promo bigint; v_withdrawable bigint; v_key text;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF EXISTS (SELECT 1 FROM public.mission_financial_holds
              WHERE source_module = 'cashout' AND source_id = p_request_id AND kind = 'cashout') THEN
    RETURN jsonb_build_object('status','already_held');
  END IF;

  SELECT * INTO v_w FROM public.wallets
   WHERE owner_user_id = p_driver AND party_type = 'driver' FOR UPDATE;
  IF v_w.id IS NULL THEN RAISE EXCEPTION 'Driver wallet not found'; END IF;

  v_promo := COALESCE((public.driver_promo_balance(p_driver)->>'available_gnf')::bigint, 0);
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
$$;

CREATE OR REPLACE FUNCTION public.driver_payout_confirm(p_request_id uuid, p_evidence_ref text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid(); v_h public.mission_financial_holds;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_evidence_ref IS NULL OR length(btrim(p_evidence_ref)) < 4 THEN
    RAISE EXCEPTION 'PAYOUT_EVIDENCE_REQUIRED';
  END IF;
  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = 'cashout' AND source_id = p_request_id AND kind = 'cashout' FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'Payout hold not found'; END IF;
  IF v_h.state <> 'held' THEN RETURN jsonb_build_object('status','already_resolved'); END IF;

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
     SET state='captured', captured_gnf = amount_gnf, evidence_ref = p_evidence_ref,
         resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','paid','amount_gnf',v_h.amount_gnf);
END;
$$;

CREATE OR REPLACE FUNCTION public.driver_payout_cancel(p_request_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid(); v_h public.mission_financial_holds; v_res jsonb;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = 'cashout' AND source_id = p_request_id AND kind = 'cashout' FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'Payout hold not found'; END IF;
  IF v_h.state <> 'held' THEN RETURN jsonb_build_object('status','already_resolved'); END IF;

  v_res := public._ledger_reverse('cashout-hold:' || p_request_id::text, COALESCE(p_reason,'payout cancelled'), NULL, v_caller);
  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_h.amount_gnf,0), updated_at = now()
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver';
  UPDATE public.mission_financial_holds
     SET state='released', released_gnf = amount_gnf, reason = p_reason,
         resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','cancelled','released_gnf',v_h.amount_gnf,'journal',v_res);
END;
$$;

-- =====================================================================
-- Grants: privileged primitives are service-role / admin-session only.
-- =====================================================================
DO $$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'chop_pay_customer_capture(text,uuid,uuid,bigint,uuid,bigint,bigint,bigint,boolean)',
    'chop_pay_customer_refund(text,uuid,text)',
    'merchant_payable_create(text,uuid,uuid,bigint,bigint,text,jsonb,boolean)',
    'merchant_payable_fund(text,uuid,uuid,text)',
    'merchant_settlement_hold(uuid)',
    'merchant_settlement_complete(uuid,text)',
    'merchant_settlement_fail(uuid,text)',
    'driver_mission_fee_capture(text,uuid,bigint)',
    'customer_cancellation_debt_create(text,uuid,uuid,text,text,bigint,text,boolean)',
    'customer_cancellation_debt_collect(uuid)',
    'customer_cancellation_debt_waive(uuid,text)',
    'claims_reserve_allocate(text,uuid,bigint,text,text,uuid,uuid,bigint,text,boolean)',
    'claims_reserve_resolve(uuid,bigint,text)',
    'driver_payout_hold_place(uuid,uuid,bigint)',
    'driver_payout_confirm(uuid,text)',
    'driver_payout_cancel(uuid,text)']
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated, service_role', fn);
  END LOOP;
END $$;

REVOKE ALL ON FUNCTION public.chop_pay_customer_hold_place(text,uuid,bigint,text,uuid,boolean,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chop_pay_customer_hold_place(text,uuid,bigint,text,uuid,boolean,jsonb) TO authenticated, service_role;

-- Canonical correction: the parcel service fee is charged on the delivery fee,
-- never on the declared package value (canonical policy §7).
UPDATE public.finance_policies SET fee_basis = 'delivery_fee'
 WHERE mission_type = 'envoyer' AND fee_basis = 'declared_value';