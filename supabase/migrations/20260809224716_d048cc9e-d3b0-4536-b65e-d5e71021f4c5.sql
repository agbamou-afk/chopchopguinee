DROP FUNCTION IF EXISTS public.customer_cancellation_debt_create(text,uuid,uuid,text,text,bigint,bigint,bigint,boolean,text,boolean);

CREATE OR REPLACE FUNCTION public.customer_cancellation_debt_create(
  p_source_module text, p_source_id uuid, p_customer uuid, p_mission_type text, p_stage text,
  p_fare_gnf bigint DEFAULT 0, p_merchandise_subtotal_gnf bigint DEFAULT 0,
  p_delivery_fee_gnf bigint DEFAULT 0, p_preparation_started boolean DEFAULT false,
  p_responsible_party text DEFAULT 'customer', p_is_sandbox boolean DEFAULT false,
  p_policy_snapshot jsonb DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid(); v_req jsonb; v_snap jsonb; v_basis_kind text;
  v_bps int; v_basis bigint; v_amount bigint; v_exempt text;
  v_row public.customer_cancellation_debts;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_stage NOT IN ('before_dispatch','after_dispatch') THEN RAISE EXCEPTION 'Invalid stage'; END IF;
  IF p_responsible_party NOT IN ('customer','provider','platform','merchant','driver') THEN
    RAISE EXCEPTION 'Invalid responsible party';
  END IF;

  IF p_mission_type = 'repas' AND COALESCE(p_preparation_started,false)
     AND p_responsible_party = 'customer' THEN
    RAISE EXCEPTION 'REPAS_CANCELLATION_LOCKED'
      USING DETAIL = 'Customer cancellation is prohibited once preparation has started';
  END IF;

  -- Non-customer-caused cancellations never create a customer debt row.
  IF p_responsible_party <> 'customer' THEN
    RETURN jsonb_build_object('status','exempt','amount_gnf',0,
      'exempt_reason', format('not_customer_caused:%s', p_responsible_party));
  END IF;

  -- Snapshot authority: the mission's frozen snapshot wins over current policy.
  IF p_policy_snapshot IS NOT NULL AND p_policy_snapshot <> '{}'::jsonb THEN
    v_snap := p_policy_snapshot;
  ELSE
    v_req := public.finance_mission_requirement_v2(p_mission_type,0,0,0,0,'choppay');
    v_snap := COALESCE(v_req->'policy_snapshot','{}'::jsonb);
  END IF;
  v_basis_kind := COALESCE(v_snap->>'cancel_basis','none');

  v_basis := CASE v_basis_kind
    WHEN 'fare' THEN GREATEST(COALESCE(p_fare_gnf,0),0)
    WHEN 'merchandise_plus_delivery' THEN GREATEST(COALESCE(p_merchandise_subtotal_gnf,0),0)
                                        + GREATEST(COALESCE(p_delivery_fee_gnf,0),0)
    WHEN 'delivery_fee' THEN GREATEST(COALESCE(p_delivery_fee_gnf,0),0)
    ELSE GREATEST(COALESCE(p_fare_gnf,0),0) END;

  v_bps := CASE p_stage
    WHEN 'before_dispatch' THEN COALESCE((v_snap->>'cancel_before_dispatch_bps')::int,
                                         (v_req->>'cancel_before_dispatch_bps')::int, 0)
    ELSE COALESCE((v_snap->>'cancel_after_dispatch_bps')::int,
                  (v_req->>'cancel_after_dispatch_bps')::int, 0) END;
  v_amount := (v_basis * v_bps) / 10000;

  INSERT INTO public.customer_cancellation_debts
    (debt_key, customer_user_id, source_module, source_id, mission_type, stage,
     basis_gnf, applied_bps, amount_gnf, state, exempt_reason, policy_snapshot, is_sandbox)
  VALUES (format('cancel:%s:%s', p_source_module, p_source_id), p_customer, p_source_module,
          p_source_id, p_mission_type, p_stage, v_basis, v_bps, v_amount,
          CASE WHEN v_amount > 0 THEN 'outstanding' ELSE 'exempt' END,
          CASE WHEN v_amount > 0 THEN NULL ELSE 'zero_fee_policy' END,
          v_snap || jsonb_build_object('cancel_basis_kind', v_basis_kind,
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
      p_mission_type, v_caller, v_snap, p_is_sandbox);
  END IF;

  RETURN jsonb_build_object('status', CASE WHEN v_amount > 0 THEN 'charged' ELSE 'exempt' END,
                            'debt_id',v_row.id,'basis_kind',v_basis_kind,'basis_gnf',v_basis,
                            'amount_gnf',v_amount,'applied_bps',v_bps);
END; $function$;

REVOKE ALL ON FUNCTION public.customer_cancellation_debt_create(text,uuid,uuid,text,text,bigint,bigint,bigint,boolean,text,boolean,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.customer_cancellation_debt_create(text,uuid,uuid,text,text,bigint,bigint,bigint,boolean,text,boolean,jsonb) TO service_role;

DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef('public.ride_cancel(uuid,text)'::regprocedure) INTO d;
  d := replace(d,
    'p_preparation_started := false, p_responsible_party := v_responsible, p_is_sandbox := false);',
    'p_preparation_started := false, p_responsible_party := v_responsible, p_is_sandbox := false, p_policy_snapshot := v_snap);');
  EXECUTE d;
END $$;