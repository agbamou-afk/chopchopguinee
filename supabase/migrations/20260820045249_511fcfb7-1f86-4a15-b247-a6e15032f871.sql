CREATE OR REPLACE FUNCTION public.marche_order_settlement_receipt(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  caller uuid := auth.uid();
  o public.marche_orders; p public.merchant_payables; v_allocs jsonb; v_money jsonb;
BEGIN
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF NOT public._marche_merchant_ops_authorized(o, caller) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  v_money := public._marche_order_money(o);

  SELECT * INTO p FROM public.merchant_payables
   WHERE source_module='marche' AND source_id=o.id AND merchant_store_id=o.merchant_store_id;

  IF p.id IS NULL THEN
    RETURN jsonb_build_object('order_id', o.id, 'receipt_available', false,
      'settled', false, 'money', v_money,
      'message','Aucune créance marchande n''existe encore pour cette commande.');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'allocation_id', a.id,
      'amount_gnf', a.amount_gnf,
      'allocated_at', a.created_at,
      'payout_order_id', po.id,
      'payout_status', po.status,
      'provider', po.provider,
      'destination_msisdn', po.destination_msisdn,
      'settled_at', po.settled_at,
      'provider_reference', ev.provider_reference,
      'provider_status', ev.provider_status,
      'evidence_state', ev.reconciliation_state,
      'transferred_at', ev.transferred_at,
      'evidence_backed', (ev.id IS NOT NULL AND ev.reconciliation_state = 'reconciled')
    ) ORDER BY a.created_at), '[]'::jsonb)
   INTO v_allocs
   FROM public.payout_settlement_allocations a
   JOIN public.payout_orders po ON po.id = a.payout_order_id
   LEFT JOIN LATERAL (
     SELECT e.* FROM public.payout_provider_evidence e
      WHERE e.payout_order_id = po.id
      ORDER BY (e.reconciliation_state = 'reconciled') DESC, e.created_at DESC LIMIT 1) ev ON true
   WHERE a.merchant_payable_id = p.id;

  RETURN jsonb_build_object(
    'order_id', o.id,
    'payable_id', p.id,
    'receipt_available', jsonb_array_length(v_allocs) > 0,
    'settled', (v_money->>'settled')::boolean,
    'money', v_money,
    'allocations', v_allocs);
END $$;

REVOKE ALL ON FUNCTION public.marche_order_settlement_receipt(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_order_settlement_receipt(uuid) TO authenticated, service_role;

DO $mig$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='marche_finance_order_audit';
  v_def := replace(v_def, 'e.state = ''reconciled''', 'e.reconciliation_state = ''reconciled''');
  IF v_def NOT LIKE '%e.reconciliation_state%' THEN RAISE EXCEPTION 'AUDIT_PATCH_TARGET_NOT_FOUND'; END IF;
  EXECUTE v_def;

  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r11';
  v_def := replace(v_def, 'provider_status, environment, state)', 'provider_status, environment, reconciliation_state)');
  v_def := replace(v_def, 'payout_provider_evidence SET state=', 'payout_provider_evidence SET reconciliation_state=');
  IF v_def NOT LIKE '%environment, reconciliation_state)%' THEN RAISE EXCEPTION 'QA_PATCH_TARGET_NOT_FOUND'; END IF;
  EXECUTE v_def;
END $mig$;

REVOKE ALL ON FUNCTION public.marche_finance_order_audit(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_finance_order_audit(uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public._qa_node4_marche_r11() FROM PUBLIC, anon, authenticated;
