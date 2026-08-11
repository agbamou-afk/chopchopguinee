-- ============================================================
-- SLICE 11 — Merchant settlement + generalized payout engine
-- ============================================================

-- 1. Generalized payout spine ---------------------------------
CREATE TABLE public.payout_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_key text NOT NULL UNIQUE,
  party_type public.party_type NOT NULL,
  party_user_id uuid NOT NULL,
  merchant_store_id uuid,
  source_kind text NOT NULL CHECK (source_kind IN ('merchant_settlement','driver_cashout')),
  source_request_id uuid,
  provider text NOT NULL DEFAULT 'orange_money',
  destination_msisdn text NOT NULL,
  environment text NOT NULL CHECK (environment IN ('production','sandbox')),
  requested_principal_gnf bigint NOT NULL CHECK (requested_principal_gnf > 0),
  provider_fee_gnf bigint NOT NULL DEFAULT 0 CHECK (provider_fee_gnf >= 0),
  fee_borne_by text NOT NULL DEFAULT 'recipient' CHECK (fee_borne_by IN ('recipient','platform')),
  merchant_liability_debit_gnf bigint NOT NULL CHECK (merchant_liability_debit_gnf >= 0),
  recipient_net_gnf bigint NOT NULL CHECK (recipient_net_gnf >= 0),
  reservation_gnf bigint NOT NULL CHECK (reservation_gnf >= 0),
  status text NOT NULL DEFAULT 'reserved'
    CHECK (status IN ('reserved','needs_review','mismatch','rejected','released','settled')),
  policy_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  evidence_id uuid,
  settled_gnf bigint NOT NULL DEFAULT 0 CHECK (settled_gnf >= 0),
  reject_reason text,
  settled_at timestamptz,
  released_at timestamptz,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_payout_orders_party ON public.payout_orders(party_type, party_user_id, created_at DESC);
CREATE INDEX idx_payout_orders_store ON public.payout_orders(merchant_store_id, created_at DESC);
CREATE INDEX idx_payout_orders_status ON public.payout_orders(status, created_at DESC);
CREATE UNIQUE INDEX idx_payout_orders_source_request
  ON public.payout_orders(source_kind, source_request_id) WHERE source_request_id IS NOT NULL;

GRANT SELECT ON public.payout_orders TO authenticated;
GRANT ALL ON public.payout_orders TO service_role;
ALTER TABLE public.payout_orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Party reads own payout orders" ON public.payout_orders
FOR SELECT TO authenticated
USING (
  party_user_id = auth.uid()
  OR EXISTS (SELECT 1 FROM public.merchant_stores ms
              WHERE ms.id = payout_orders.merchant_store_id AND ms.owner_user_id = auth.uid())
);
CREATE POLICY "Finance admins read payout orders" ON public.payout_orders
FOR SELECT TO authenticated
USING (public.is_god_admin(auth.uid()) OR public.has_admin_role(auth.uid(),'finance_admin'::admin_role));

-- 2. Outbound provider transfer evidence ----------------------
CREATE TABLE public.payout_provider_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payout_order_id uuid REFERENCES public.payout_orders(id) ON DELETE RESTRICT,
  provider text NOT NULL,
  provider_reference text NOT NULL,
  normalized_reference text GENERATED ALWAYS AS (lower(btrim(provider_reference))) STORED,
  recipient_msisdn text,
  amount_gnf bigint,
  fee_gnf bigint,
  net_gnf bigint,
  provider_status text,
  transferred_at timestamptz,
  environment text,
  raw jsonb NOT NULL DEFAULT '{}'::jsonb,
  reconciliation_state text NOT NULL DEFAULT 'recorded'
    CHECK (reconciliation_state IN ('recorded','evidence_incomplete','mismatch','reconciled','rejected')),
  mismatch_reason text,
  recorded_by uuid,
  reconciled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX payout_provider_evidence_ref_uniq
  ON public.payout_provider_evidence(normalized_reference);

GRANT SELECT ON public.payout_provider_evidence TO authenticated;
GRANT ALL ON public.payout_provider_evidence TO service_role;
ALTER TABLE public.payout_provider_evidence ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Finance admins read payout evidence" ON public.payout_provider_evidence
FOR SELECT TO authenticated
USING (public.is_god_admin(auth.uid()) OR public.has_admin_role(auth.uid(),'finance_admin'::admin_role));

-- 3. Per-payable settlement allocations -----------------------
CREATE TABLE public.payout_settlement_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payout_order_id uuid NOT NULL REFERENCES public.payout_orders(id) ON DELETE RESTRICT,
  merchant_payable_id uuid NOT NULL REFERENCES public.merchant_payables(id) ON DELETE RESTRICT,
  amount_gnf bigint NOT NULL CHECK (amount_gnf > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (payout_order_id, merchant_payable_id)
);
GRANT SELECT ON public.payout_settlement_allocations TO authenticated;
GRANT ALL ON public.payout_settlement_allocations TO service_role;
ALTER TABLE public.payout_settlement_allocations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Finance admins read allocations" ON public.payout_settlement_allocations
FOR SELECT TO authenticated
USING (public.is_god_admin(auth.uid()) OR public.has_admin_role(auth.uid(),'finance_admin'::admin_role));
CREATE POLICY "Merchant reads own allocations" ON public.payout_settlement_allocations
FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.payout_orders o
               JOIN public.merchant_stores ms ON ms.id = o.merchant_store_id
              WHERE o.id = payout_settlement_allocations.payout_order_id
                AND ms.owner_user_id = auth.uid()));

-- 4. Scheduled settlement runs --------------------------------
CREATE TABLE public.merchant_settlement_schedule_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_store_id uuid NOT NULL,
  period_key text NOT NULL,
  as_of timestamptz NOT NULL DEFAULT now(),
  candidate_amount_gnf bigint NOT NULL DEFAULT 0,
  request_id uuid,
  policy_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_store_id, period_key)
);
GRANT SELECT ON public.merchant_settlement_schedule_runs TO authenticated;
GRANT ALL ON public.merchant_settlement_schedule_runs TO service_role;
ALTER TABLE public.merchant_settlement_schedule_runs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Finance admins read schedule runs" ON public.merchant_settlement_schedule_runs
FOR SELECT TO authenticated
USING (public.is_god_admin(auth.uid()) OR public.has_admin_role(auth.uid(),'finance_admin'::admin_role));

CREATE TRIGGER trg_payout_orders_touch BEFORE UPDATE ON public.payout_orders
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER trg_payout_evidence_touch BEFORE UPDATE ON public.payout_provider_evidence
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Immutability of the economic terms of a payout order
CREATE OR REPLACE FUNCTION public._payout_order_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
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
     OR NEW.destination_msisdn IS DISTINCT FROM OLD.destination_msisdn
     OR NEW.environment IS DISTINCT FROM OLD.environment
     OR NEW.policy_snapshot IS DISTINCT FROM OLD.policy_snapshot
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'PAYOUT_ORDER_IMMUTABLE';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_payout_orders_immutable BEFORE UPDATE ON public.payout_orders
FOR EACH ROW EXECUTE FUNCTION public._payout_order_immutable();

-- 5. Helpers --------------------------------------------------
CREATE OR REPLACE FUNCTION public._payout_env()
RETURNS text LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE WHEN public._finance_flag('om_environment') THEN 'production' ELSE 'sandbox' END
$$;

CREATE OR REPLACE FUNCTION public._payout_fee_snapshot(p_provider text, p_principal bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path = public AS $$
DECLARE
  f public.provider_fee_schedules;
  sp public.merchant_settlement_policies;
  v_fee bigint := 0;
  v_borne text := 'recipient';
BEGIN
  SELECT * INTO f FROM public.provider_fee_schedule_at(COALESCE(p_provider,'orange_money'), now());
  SELECT * INTO sp FROM public.merchant_settlement_policy_at(now());
  IF f.id IS NOT NULL THEN
    v_fee := COALESCE(f.fee_fixed_gnf,0) + (p_principal * COALESCE(f.fee_bps,0)) / 10000;
    v_fee := GREATEST(v_fee, COALESCE(f.min_fee_gnf,0));
    IF f.max_fee_gnf IS NOT NULL THEN v_fee := LEAST(v_fee, f.max_fee_gnf); END IF;
    v_borne := CASE WHEN COALESCE(f.passthrough_to_recipient,true) THEN 'recipient' ELSE 'platform' END;
  END IF;
  IF sp.id IS NOT NULL AND sp.fee_passthrough IS NOT NULL THEN
    v_borne := CASE WHEN sp.fee_passthrough THEN 'recipient' ELSE 'platform' END;
  END IF;
  v_fee := LEAST(GREATEST(v_fee,0), p_principal);
  RETURN jsonb_build_object(
    'provider', COALESCE(p_provider,'orange_money'),
    'provider_fee_gnf', v_fee,
    'fee_borne_by', v_borne,
    'requested_principal_gnf', p_principal,
    'merchant_liability_debit_gnf', p_principal,
    'recipient_net_gnf', CASE WHEN v_borne = 'recipient' THEN p_principal - v_fee ELSE p_principal END,
    'fee_schedule_id', f.id,
    'fee_bps', f.fee_bps,
    'fee_fixed_gnf', f.fee_fixed_gnf,
    'settlement_policy_id', sp.id,
    'cadence', sp.cadence,
    'min_settlement_gnf', sp.min_settlement_gnf,
    'frozen_at', now()
  );
END $$;

-- Create a payout order (reservation only, never money) -------
CREATE OR REPLACE FUNCTION public._payout_order_create_internal(
  p_party_type public.party_type,
  p_party_user_id uuid,
  p_store_id uuid,
  p_source_kind text,
  p_source_request_id uuid,
  p_principal bigint,
  p_provider text,
  p_msisdn text,
  p_order_key text,
  p_actor uuid
) RETURNS public.payout_orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
    fee_borne_by, merchant_liability_debit_gnf, recipient_net_gnf, reservation_gnf,
    policy_snapshot, created_by)
  VALUES (
    p_order_key, p_party_type, p_party_user_id, p_store_id, p_source_kind, p_source_request_id,
    COALESCE(p_provider,'orange_money'), btrim(p_msisdn), public._payout_env(), p_principal,
    (v_fee->>'provider_fee_gnf')::bigint, v_fee->>'fee_borne_by',
    (v_fee->>'merchant_liability_debit_gnf')::bigint, (v_fee->>'recipient_net_gnf')::bigint,
    p_principal, v_fee, p_actor)
  RETURNING * INTO v_o;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (p_actor,'finance','payout.order.reserved','payout_order', v_o.id::text,
          jsonb_build_object('principal_gnf',p_principal,'party',p_party_type,'fee',v_fee));
  RETURN v_o;
END $$;
REVOKE ALL ON FUNCTION public._payout_order_create_internal(public.party_type,uuid,uuid,text,uuid,bigint,text,text,text,uuid) FROM PUBLIC, anon, authenticated;

-- 6. Internal settlement executor ------------------------------
CREATE OR REPLACE FUNCTION public._payout_settle_internal(p_order_id uuid, p_evidence_id uuid, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_o public.payout_orders;
  v_e public.payout_provider_evidence;
  v_remaining bigint;
  v_take bigint;
  v_p record;
  v_lines jsonb;
BEGIN
  SELECT * INTO v_o FROM public.payout_orders WHERE id = p_order_id FOR UPDATE;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'PAYOUT_ORDER_NOT_FOUND'; END IF;
  IF v_o.status = 'settled' THEN
    RETURN jsonb_build_object('status','already_settled','payout_order_id',v_o.id,'settled_gnf',v_o.settled_gnf,'moved_gnf',0);
  END IF;
  SELECT * INTO v_e FROM public.payout_provider_evidence WHERE id = p_evidence_id FOR UPDATE;
  IF v_e.id IS NULL THEN RAISE EXCEPTION 'EVIDENCE_NOT_FOUND'; END IF;

  -- Stage 5 gate: no outbound settlement posting while the rail is off.
  IF v_o.source_kind = 'merchant_settlement'
     AND NOT public._finance_flag('merchant_om_settlement_enabled') THEN
    RAISE EXCEPTION 'STAGE_DISABLED:merchant_om_settlement_enabled';
  END IF;
  IF v_o.source_kind = 'driver_cashout'
     AND NOT public._finance_flag('driver_cashout_enabled') THEN
    RAISE EXCEPTION 'STAGE_DISABLED:driver_cashout_enabled';
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
                             'provider_reference',v_e.provider_reference,
                             'evidence_id',v_e.id));

  RETURN jsonb_build_object('status','settled','payout_order_id',v_o.id,
    'moved_gnf', v_o.merchant_liability_debit_gnf, 'evidence_id', v_e.id);
END $$;
REVOKE ALL ON FUNCTION public._payout_settle_internal(uuid,uuid,uuid) FROM PUBLIC, anon, authenticated;

-- 7. Evidence recording + reconciliation (Finance/God only) ----
CREATE OR REPLACE FUNCTION public.payout_record_provider_evidence(
  p_payout_order_id uuid,
  p_provider text,
  p_provider_reference text,
  p_recipient_msisdn text,
  p_amount_gnf bigint,
  p_provider_status text,
  p_environment text,
  p_transferred_at timestamptz DEFAULT NULL,
  p_fee_gnf bigint DEFAULT NULL,
  p_raw jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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

  -- Completeness first — never backfill from merchant/customer data.
  IF p_recipient_msisdn IS NULL OR length(btrim(p_recipient_msisdn)) < 8
     OR p_amount_gnf IS NULL OR p_amount_gnf <= 0
     OR p_provider IS NULL OR length(btrim(p_provider)) = 0
     OR p_provider_status IS NULL OR length(btrim(p_provider_status)) = 0
     OR p_environment IS NULL OR p_environment NOT IN ('production','sandbox') THEN
    v_state := 'evidence_incomplete';
    v_reason := 'missing_required_evidence_fields';
  ELSIF p_environment IS DISTINCT FROM v_o.environment THEN
    v_state := 'mismatch'; v_reason := 'environment_mismatch';
  ELSIF btrim(p_provider) IS DISTINCT FROM v_o.provider THEN
    v_state := 'mismatch'; v_reason := 'provider_mismatch';
  ELSIF public._normalize_guinea_phone(p_recipient_msisdn)
        IS DISTINCT FROM public._normalize_guinea_phone(v_o.destination_msisdn) THEN
    v_state := 'mismatch'; v_reason := 'recipient_mismatch';
  ELSIF p_amount_gnf IS DISTINCT FROM v_o.recipient_net_gnf
        AND p_amount_gnf IS DISTINCT FROM v_o.requested_principal_gnf THEN
    v_state := 'mismatch'; v_reason := 'amount_mismatch';
  ELSIF lower(btrim(p_provider_status)) NOT IN ('success','successful','completed','confirmed','paid') THEN
    v_state := 'mismatch'; v_reason := 'provider_status_not_successful';
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
END $$;
REVOKE ALL ON FUNCTION public.payout_record_provider_evidence(uuid,text,text,text,bigint,text,text,timestamptz,bigint,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.payout_record_provider_evidence(uuid,text,text,text,bigint,text,text,timestamptz,bigint,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.payout_reconcile_evidence(p_evidence_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_caller uuid := auth.uid(); v_e public.payout_provider_evidence;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF NOT (public.is_god_admin(v_caller) OR public.has_admin_role(v_caller,'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  SELECT * INTO v_e FROM public.payout_provider_evidence WHERE id = p_evidence_id;
  IF v_e.id IS NULL THEN RAISE EXCEPTION 'EVIDENCE_NOT_FOUND'; END IF;
  IF v_e.reconciliation_state = 'reconciled' THEN
    RETURN jsonb_build_object('status','already_reconciled','moved_gnf',0,'evidence_id',v_e.id);
  END IF;
  IF v_e.reconciliation_state <> 'recorded' THEN
    RETURN jsonb_build_object('status', v_e.reconciliation_state, 'reason', v_e.mismatch_reason,
                              'moved_gnf', 0, 'evidence_id', v_e.id);
  END IF;
  IF v_e.payout_order_id IS NULL THEN RAISE EXCEPTION 'EVIDENCE_NOT_LINKED'; END IF;
  RETURN public._payout_settle_internal(v_e.payout_order_id, v_e.id, v_caller);
END $$;
REVOKE ALL ON FUNCTION public.payout_reconcile_evidence(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.payout_reconcile_evidence(uuid) TO authenticated;

-- 8. Reject / release ------------------------------------------
CREATE OR REPLACE FUNCTION public.payout_reject_release(p_payout_order_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_caller uuid := auth.uid(); v_o public.payout_orders;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF NOT (public.is_god_admin(v_caller) OR public.has_admin_role(v_caller,'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  SELECT * INTO v_o FROM public.payout_orders WHERE id = p_payout_order_id FOR UPDATE;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'PAYOUT_ORDER_NOT_FOUND'; END IF;
  IF v_o.status = 'settled' THEN RAISE EXCEPTION 'ALREADY_SETTLED'; END IF;
  IF v_o.status IN ('rejected','released') THEN
    RETURN jsonb_build_object('status', v_o.status, 'released_gnf', 0, 'duplicate', true);
  END IF;

  UPDATE public.payout_orders
     SET status = 'rejected', reservation_gnf = 0, reject_reason = btrim(p_reason),
         released_at = now(), updated_at = now()
   WHERE id = v_o.id;

  UPDATE public.payout_provider_evidence
     SET reconciliation_state = 'rejected', updated_at = now()
   WHERE payout_order_id = v_o.id AND reconciliation_state <> 'reconciled';

  IF v_o.source_request_id IS NOT NULL AND v_o.source_kind = 'merchant_settlement' THEN
    UPDATE public.merchant_settlement_requests
       SET status = 'rejected', reject_reason = btrim(p_reason),
           reviewed_by = v_caller, reviewed_at = now(), updated_at = now()
     WHERE id = v_o.source_request_id AND status IN ('requested','pending_review');
  END IF;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_caller,'finance','payout.rejected_released','payout_order', v_o.id::text,
          jsonb_build_object('released_gnf', v_o.reservation_gnf, 'reason', btrim(p_reason)));

  RETURN jsonb_build_object('status','rejected','released_gnf', v_o.reservation_gnf, 'duplicate', false);
END $$;
REVOKE ALL ON FUNCTION public.payout_reject_release(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.payout_reject_release(uuid,text) TO authenticated;

-- 9. Merchant request now reserves through the payout spine ----
CREATE OR REPLACE FUNCTION public.merchant_settlement_request_create(
  p_amount_gnf bigint, p_idempotency_key text, p_store_id uuid DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_store uuid := p_store_id;
  v_owner uuid; v_phone text; v_ov jsonb; v_eligible bigint; v_key text;
  v_row public.merchant_settlement_requests; v_o public.payout_orders;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  IF p_idempotency_key IS NULL OR length(trim(p_idempotency_key)) < 8 THEN
    RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED';
  END IF;

  IF v_store IS NULL THEN
    SELECT id INTO v_store FROM public.merchant_stores WHERE owner_user_id = v_uid LIMIT 1;
  END IF;
  IF v_store IS NULL THEN RAISE EXCEPTION 'MERCHANT_STORE_NOT_FOUND'; END IF;
  SELECT owner_user_id, phone INTO v_owner, v_phone FROM public.merchant_stores WHERE id = v_store;
  IF v_owner IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  v_key := v_store::text || ':' || trim(p_idempotency_key);

  SELECT * INTO v_row FROM public.merchant_settlement_requests WHERE request_key = v_key;
  IF v_row.id IS NOT NULL THEN
    SELECT * INTO v_o FROM public.payout_orders
     WHERE source_kind = 'merchant_settlement' AND source_request_id = v_row.id;
    RETURN jsonb_build_object('request_id', v_row.id, 'status', v_row.status,
      'amount_gnf', v_row.amount_gnf, 'duplicate', true, 'payout_order_id', v_o.id);
  END IF;

  v_ov := public.merchant_finance_overview(v_store);
  v_eligible := (v_ov->>'eligible_settlement_gnf')::bigint;
  IF p_amount_gnf > v_eligible THEN
    RAISE EXCEPTION 'AMOUNT_EXCEEDS_ELIGIBLE: % > %', p_amount_gnf, v_eligible;
  END IF;

  INSERT INTO public.merchant_settlement_requests
    (request_key, merchant_store_id, merchant_user_id, amount_gnf, eligible_snapshot_gnf, note)
  VALUES (v_key, v_store, v_uid, p_amount_gnf, v_eligible, p_note)
  RETURNING * INTO v_row;

  v_o := public._payout_order_create_internal(
    'merchant'::public.party_type, v_uid, v_store, 'merchant_settlement', v_row.id,
    p_amount_gnf, 'orange_money', v_phone, 'msr:' || v_row.id::text, v_uid);

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'finance', 'merchant.settlement_request.created',
          'merchant_settlement_request', v_row.id::text,
          jsonb_build_object('store_id', v_store, 'amount_gnf', p_amount_gnf,
                             'eligible_gnf', v_eligible, 'payout_order_id', v_o.id));

  RETURN jsonb_build_object('request_id', v_row.id, 'status', v_row.status,
    'amount_gnf', v_row.amount_gnf, 'duplicate', false,
    'payout_order_id', v_o.id,
    'requested_principal_gnf', v_o.requested_principal_gnf,
    'provider_fee_gnf', v_o.provider_fee_gnf,
    'fee_borne_by', v_o.fee_borne_by,
    'merchant_liability_debit_gnf', v_o.merchant_liability_debit_gnf,
    'recipient_net_gnf', v_o.recipient_net_gnf,
    'environment', v_o.environment);
END $$;

-- Internal variant used by the scheduler (no auth.uid()).
CREATE OR REPLACE FUNCTION public._merchant_settlement_request_queue_internal(
  p_store_id uuid, p_amount_gnf bigint, p_request_key text, p_note text)
RETURNS public.merchant_settlement_requests
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_owner uuid; v_phone text; v_row public.merchant_settlement_requests; v_ov jsonb; v_eligible bigint;
BEGIN
  SELECT * INTO v_row FROM public.merchant_settlement_requests WHERE request_key = p_request_key;
  IF v_row.id IS NOT NULL THEN RETURN v_row; END IF;
  SELECT owner_user_id, phone INTO v_owner, v_phone FROM public.merchant_stores WHERE id = p_store_id;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'MERCHANT_STORE_NOT_FOUND'; END IF;
  v_ov := public.merchant_finance_overview(p_store_id);
  v_eligible := (v_ov->>'eligible_settlement_gnf')::bigint;
  IF p_amount_gnf > v_eligible THEN RAISE EXCEPTION 'AMOUNT_EXCEEDS_ELIGIBLE'; END IF;

  INSERT INTO public.merchant_settlement_requests
    (request_key, merchant_store_id, merchant_user_id, amount_gnf, eligible_snapshot_gnf, channel, note)
  VALUES (p_request_key, p_store_id, v_owner, p_amount_gnf, v_eligible, 'scheduled', p_note)
  RETURNING * INTO v_row;

  PERFORM public._payout_order_create_internal(
    'merchant'::public.party_type, v_owner, p_store_id, 'merchant_settlement', v_row.id,
    p_amount_gnf, 'orange_money', v_phone, 'msr:' || v_row.id::text, NULL);
  RETURN v_row;
END $$;
REVOKE ALL ON FUNCTION public._merchant_settlement_request_queue_internal(uuid,bigint,text,text) FROM PUBLIC, anon, authenticated;

-- 10. Scheduled settlement queue generation --------------------
CREATE OR REPLACE FUNCTION public.merchant_settlement_schedule_generate(p_as_of timestamptz DEFAULT now())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  sp public.merchant_settlement_policies;
  v_store record; v_ov jsonb; v_eligible bigint; v_period text; v_min bigint;
  v_created int := 0; v_skipped int := 0; v_row public.merchant_settlement_requests;
BEGIN
  IF v_caller IS NULL OR NOT (public.is_god_admin(v_caller)
      OR public.has_admin_role(v_caller,'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  SELECT * INTO sp FROM public.merchant_settlement_policy_at(p_as_of);
  IF sp.id IS NULL OR NOT sp.configured THEN
    RETURN jsonb_build_object('status','policy_not_configured','created',0,'skipped',0);
  END IF;
  IF COALESCE(sp.cadence,'on_demand') = 'on_demand' THEN
    RETURN jsonb_build_object('status','cadence_on_demand','created',0,'skipped',0);
  END IF;
  v_min := COALESCE(sp.min_settlement_gnf, 0);
  v_period := sp.cadence || ':' || CASE sp.cadence
      WHEN 'daily'    THEN to_char(date_trunc('day',  p_as_of), 'YYYY-MM-DD')
      WHEN 'weekly'   THEN to_char(date_trunc('week', p_as_of), 'IYYY-"W"IW')
      WHEN 'biweekly' THEN to_char(date_trunc('week', p_as_of), 'IYYY-"W"IW')
      ELSE to_char(date_trunc('month', p_as_of), 'YYYY-MM') END;

  FOR v_store IN SELECT DISTINCT merchant_store_id AS id FROM public.merchant_payables
                  WHERE state IN ('funded','due') AND (amount_gnf - settled_gnf) > 0
  LOOP
    IF EXISTS (SELECT 1 FROM public.merchant_settlement_schedule_runs
                WHERE merchant_store_id = v_store.id AND period_key = v_period) THEN
      v_skipped := v_skipped + 1; CONTINUE;
    END IF;
    v_ov := public.merchant_finance_overview(v_store.id);
    v_eligible := (v_ov->>'eligible_settlement_gnf')::bigint;
    IF v_eligible < GREATEST(v_min,1) THEN v_skipped := v_skipped + 1; CONTINUE; END IF;
    IF sp.max_settlement_gnf IS NOT NULL THEN v_eligible := LEAST(v_eligible, sp.max_settlement_gnf); END IF;

    v_row := public._merchant_settlement_request_queue_internal(
      v_store.id, v_eligible, 'sched:' || v_store.id::text || ':' || v_period,
      'Règlement programmé (' || sp.cadence || ')');

    INSERT INTO public.merchant_settlement_schedule_runs
      (merchant_store_id, period_key, as_of, candidate_amount_gnf, request_id, policy_snapshot)
    VALUES (v_store.id, v_period, p_as_of, v_eligible, v_row.id, to_jsonb(sp));
    v_created := v_created + 1;
  END LOOP;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_caller,'finance','merchant.settlement.scheduled','settlement_schedule', v_period,
          jsonb_build_object('created',v_created,'skipped',v_skipped));

  RETURN jsonb_build_object('status','ok','period_key',v_period,'created',v_created,'skipped',v_skipped);
END $$;
REVOKE ALL ON FUNCTION public.merchant_settlement_schedule_generate(timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.merchant_settlement_schedule_generate(timestamptz) TO authenticated;

-- 11. Finance Admin queue read model ---------------------------
CREATE OR REPLACE FUNCTION public.finance_payout_queue(p_bucket text DEFAULT 'requested', p_limit int DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_caller uuid := auth.uid(); v_rows jsonb;
BEGIN
  IF v_caller IS NULL OR NOT (public.is_god_admin(v_caller)
      OR public.has_admin_role(v_caller,'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'created_at' DESC), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT jsonb_build_object(
      'payout_order_id', o.id, 'status', o.status, 'party_type', o.party_type,
      'merchant_store_id', o.merchant_store_id, 'store_name', ms.name,
      'destination_msisdn', o.destination_msisdn, 'provider', o.provider,
      'environment', o.environment,
      'requested_principal_gnf', o.requested_principal_gnf,
      'provider_fee_gnf', o.provider_fee_gnf, 'fee_borne_by', o.fee_borne_by,
      'merchant_liability_debit_gnf', o.merchant_liability_debit_gnf,
      'recipient_net_gnf', o.recipient_net_gnf, 'reservation_gnf', o.reservation_gnf,
      'settled_gnf', o.settled_gnf, 'request_id', o.source_request_id,
      'reject_reason', o.reject_reason, 'settled_at', o.settled_at,
      'created_at', o.created_at,
      'evidence', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'evidence_id', e.id, 'provider_reference', e.provider_reference,
            'state', e.reconciliation_state, 'reason', e.mismatch_reason,
            'amount_gnf', e.amount_gnf, 'recipient_msisdn', e.recipient_msisdn,
            'provider_status', e.provider_status, 'environment', e.environment,
            'transferred_at', e.transferred_at)), '[]'::jsonb)
          FROM public.payout_provider_evidence e WHERE e.payout_order_id = o.id)
    ) AS x
    FROM public.payout_orders o
    LEFT JOIN public.merchant_stores ms ON ms.id = o.merchant_store_id
    WHERE CASE COALESCE(p_bucket,'requested')
            WHEN 'requested'       THEN o.status = 'reserved'
                                        AND NOT EXISTS (SELECT 1 FROM public.payout_provider_evidence e
                                                         WHERE e.payout_order_id = o.id)
            WHEN 'awaiting_proof'  THEN o.status = 'reserved'
                                        AND EXISTS (SELECT 1 FROM public.payout_provider_evidence e
                                                     WHERE e.payout_order_id = o.id)
            WHEN 'manual_review'   THEN o.status IN ('needs_review','mismatch')
            WHEN 'settled'         THEN o.status = 'settled'
            WHEN 'rejected'        THEN o.status IN ('rejected','released')
            ELSE true END
    ORDER BY o.created_at DESC
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit,50), 200))
  ) s;
  RETURN jsonb_build_object('bucket', COALESCE(p_bucket,'requested'), 'items', v_rows);
END $$;
REVOKE ALL ON FUNCTION public.finance_payout_queue(text,int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_payout_queue(text,int) TO authenticated;

-- 12. Merchant settlement receipt (only after reconciliation) --
CREATE OR REPLACE FUNCTION public.merchant_settlement_receipt(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
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
    'provider', v_o.provider, 'provider_reference', v_e.provider_reference,
    'destination_msisdn', v_o.destination_msisdn,
    'provider_status', v_e.provider_status, 'transferred_at', v_e.transferred_at,
    'settled_at', v_o.settled_at, 'environment', v_o.environment,
    'ledger', COALESCE(v_journal, '{}'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.merchant_settlement_receipt(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.merchant_settlement_receipt(uuid) TO authenticated;

-- 13. Overview exposes reservation truth -----------------------
CREATE OR REPLACE FUNCTION public.merchant_finance_overview(p_store_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid(); v_store uuid := p_store_id; v_owner uuid; v_w public.wallets;
  v_pending bigint := 0; v_funded bigint := 0; v_settled bigint := 0;
  v_reversed bigint := 0; v_held_state bigint := 0;
  v_open_req bigint := 0; v_reserved bigint := 0; v_eligible bigint := 0; v_avail bigint := 0;
  v_settlement_on boolean := false;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF v_store IS NULL THEN
    SELECT id INTO v_store FROM public.merchant_stores WHERE owner_user_id = v_uid LIMIT 1;
  END IF;
  IF v_store IS NULL THEN RAISE EXCEPTION 'MERCHANT_STORE_NOT_FOUND'; END IF;
  SELECT owner_user_id INTO v_owner FROM public.merchant_stores WHERE id = v_store;
  IF v_owner IS DISTINCT FROM v_uid AND NOT public._finance_privileged(v_uid) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT * INTO v_w FROM public.wallets WHERE owner_user_id = v_owner AND party_type = 'merchant';
  v_avail := GREATEST(COALESCE(v_w.balance_gnf,0) - COALESCE(v_w.held_gnf,0), 0);

  SELECT
    COALESCE(SUM(amount_gnf - settled_gnf) FILTER (WHERE state IN ('pending_funding','funded','due')), 0),
    COALESCE(SUM(amount_gnf - settled_gnf) FILTER (WHERE state IN ('funded','due')), 0),
    COALESCE(SUM(settled_gnf), 0),
    COALESCE(SUM(amount_gnf) FILTER (WHERE state = 'reversed'), 0),
    COALESCE(SUM(amount_gnf - settled_gnf) FILTER (WHERE state = 'settlement_held'), 0)
  INTO v_pending, v_funded, v_settled, v_reversed, v_held_state
  FROM public.merchant_payables
  WHERE merchant_store_id = v_store;

  SELECT COALESCE(SUM(amount_gnf), 0) INTO v_open_req
    FROM public.merchant_settlement_requests
   WHERE merchant_store_id = v_store AND status IN ('requested','pending_review');

  SELECT COALESCE(SUM(reservation_gnf), 0) INTO v_reserved
    FROM public.payout_orders
   WHERE merchant_store_id = v_store AND status IN ('reserved','needs_review','mismatch');

  v_eligible := GREATEST(LEAST(v_avail, v_funded) - GREATEST(v_open_req, v_reserved), 0);

  SELECT COALESCE(enabled, false) INTO v_settlement_on
    FROM public.feature_flags WHERE key = 'merchant_om_settlement_enabled';

  RETURN jsonb_build_object(
    'store_id', v_store, 'wallet_id', v_w.id,
    'wallet_status', COALESCE(v_w.status::text,'active'),
    'sales_balance_gnf', COALESCE(v_w.balance_gnf, 0),
    'held_gnf', COALESCE(v_w.held_gnf, 0),
    'available_gnf', v_avail,
    'pending_payable_gnf', v_pending,
    'funded_unsettled_gnf', v_funded,
    'settlement_held_gnf', v_held_state,
    'settled_total_gnf', v_settled,
    'reversed_total_gnf', v_reversed,
    'open_request_gnf', v_open_req,
    'reserved_for_settlement_gnf', v_reserved,
    'eligible_settlement_gnf', v_eligible,
    'settlement_rail_enabled', COALESCE(v_settlement_on, false)
  );
END $$;

-- 14. Driver wrapper on the same spine (Stage 6 stays OFF) -----
CREATE OR REPLACE FUNCTION public.driver_payout_request_create(
  p_amount_gnf bigint, p_payout_phone text, p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_o public.payout_orders; v_cashout_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF NOT public._finance_flag('driver_cashout_enabled') THEN
    RAISE EXCEPTION 'STAGE_DISABLED:driver_cashout_enabled';
  END IF;
  IF p_idempotency_key IS NULL OR length(trim(p_idempotency_key)) < 8 THEN
    RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED';
  END IF;
  v_cashout_id := public.driver_cashout_create_request(p_amount_gnf, p_payout_phone, NULL);
  v_o := public._payout_order_create_internal(
    'driver'::public.party_type, v_uid, NULL, 'driver_cashout', v_cashout_id,
    p_amount_gnf, 'orange_money', p_payout_phone, 'dco:' || v_cashout_id::text, v_uid);
  RETURN jsonb_build_object('cashout_request_id', v_cashout_id, 'payout_order_id', v_o.id,
    'requested_principal_gnf', v_o.requested_principal_gnf,
    'provider_fee_gnf', v_o.provider_fee_gnf, 'fee_borne_by', v_o.fee_borne_by,
    'recipient_net_gnf', v_o.recipient_net_gnf, 'environment', v_o.environment);
END $$;
REVOKE ALL ON FUNCTION public.driver_payout_request_create(bigint,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_payout_request_create(bigint,text,text) TO authenticated;

REVOKE ALL ON FUNCTION public._payout_env() FROM anon;
REVOKE ALL ON FUNCTION public._payout_fee_snapshot(text,bigint) FROM anon;
REVOKE ALL ON FUNCTION public.merchant_settlement_request_create(bigint,text,uuid,text) FROM anon;
REVOKE ALL ON FUNCTION public.merchant_finance_overview(uuid) FROM anon;