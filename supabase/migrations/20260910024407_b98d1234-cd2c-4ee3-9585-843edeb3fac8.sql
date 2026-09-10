-- G5 · FINANCE ADMIN COMMAND CENTER
-- 1. Close the direct provider-event mutation path (any admin could write it).
DROP POLICY IF EXISTS "Admins update provider events" ON public.payment_provider_events;
REVOKE UPDATE, INSERT, DELETE ON public.payment_provider_events FROM authenticated;

-- 2. Governed rejection of an unmatched provider event (finance.topup.manage).
CREATE OR REPLACE FUNCTION public.admin_reject_om_event(p_event_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_status text;
BEGIN
  IF coalesce(btrim(p_reason),'') = '' THEN
    RAISE EXCEPTION 'reason_required' USING ERRCODE='22023';
  END IF;
  PERFORM public.admin_enforce('finance.topup.manage','payment_provider_event',p_event_id::text,
                               jsonb_build_object('action','reject'), NULL::uuid, 'payments');
  SELECT processing_status INTO v_status FROM public.payment_provider_events WHERE id = p_event_id;
  IF v_status IS NULL THEN RAISE EXCEPTION 'event_not_found' USING ERRCODE='P0002'; END IF;
  IF v_status = 'credited' THEN RAISE EXCEPTION 'event_already_credited' USING ERRCODE='22023'; END IF;
  UPDATE public.payment_provider_events
     SET processing_status = 'rejected',
         notes = p_reason,
         processed_at = now()
   WHERE id = p_event_id;
END;$$;

REVOKE ALL ON FUNCTION public.admin_reject_om_event(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reject_om_event(uuid, text) TO authenticated, service_role;

-- 3. Canonical Finance Command Center read model. Read-only, bounded, capability gated.
CREATE OR REPLACE FUNCTION public.finance_command_overview()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_role text := public.admin_role_canonical(auth.uid());
  v_snapshot jsonb;
  v_attention jsonb := '[]'::jsonb;
  v_exceptions jsonb := '[]'::jsonb;
  v_exc_total int := 0;
  v_exc_critical int := 0;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE='42501'; END IF;
  IF NOT public.admin_capability('finance.wallet.read') THEN
    RAISE EXCEPTION 'capability_denied: finance.wallet.read' USING ERRCODE='42501';
  END IF;

  SELECT jsonb_build_object(
    'topups_pending',      (SELECT count(*) FROM public.topup_requests
                             WHERE status::text IN ('pending','needs_review','matched')),
    'topups_review',       (SELECT count(*) FROM public.topup_requests WHERE status::text = 'needs_review'),
    'provider_events_open',(SELECT count(*) FROM public.payment_provider_events
                             WHERE coalesce(processing_status,'pending') IN ('pending','conflict','needs_review')
                               AND coalesce(is_sandbox,false) = false),
    'cashouts_pending',    (SELECT count(*) FROM public.driver_cashout_requests WHERE status = 'pending'),
    'settlements_pending', (SELECT count(*) FROM public.merchant_settlement_requests WHERE status = 'pending'),
    'payables_open',       (SELECT count(*) FROM public.merchant_payables WHERE state IN ('accrued','funded','held')),
    'payouts_open',        (SELECT count(*) FROM public.payout_orders
                             WHERE status IN ('queued','reserved','awaiting_evidence','pending')),
    'refunds_pending',     (SELECT count(*) FROM public.payment_refund_requests WHERE status = 'pending'),
    'intents_review',      (SELECT count(*) FROM public.payment_intents
                             WHERE state::text IN ('needs_review','in_review','proof_submitted')
                               AND coalesce(is_sandbox,false) = false),
    'wallets_frozen',      (SELECT count(*) FROM public.wallets WHERE status::text = 'frozen')
  ) INTO v_snapshot;

  BEGIN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'code', e.code, 'severity', e.severity, 'amount_gnf', e.amount_gnf,
             'entity_count', e.entity_count, 'source_module', e.source_module,
             'account_code', e.account_code, 'detail', e.detail, 'state', e.state)
             ORDER BY CASE e.severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 ELSE 2 END), '[]'::jsonb)
      INTO v_exceptions
      FROM public.finance_treasury_exceptions() e;
  EXCEPTION WHEN OTHERS THEN
    v_exceptions := '[]'::jsonb;
  END;
  v_exc_total := jsonb_array_length(v_exceptions);
  SELECT count(*) INTO v_exc_critical
    FROM jsonb_array_elements(v_exceptions) x WHERE x->>'severity' = 'critical';

  SELECT coalesce(jsonb_agg(a ORDER BY a->>'since'), '[]'::jsonb) INTO v_attention FROM (
    SELECT jsonb_build_object(
      'kind','topup_review','queue','Recharges','label','Recharge à vérifier',
      'reference', left(t.id::text,8), 'amount_gnf', t.amount_gnf, 'state', t.status::text,
      'since', t.created_at, 'severity','high',
      'mode', public.admin_capability_mode('finance.topup.manage'),
      'href','/admin/wallet/reconciliation') a
    FROM public.topup_requests t
    WHERE t.status::text IN ('needs_review','matched') ORDER BY t.created_at LIMIT 10
  ) s
  UNION ALL SELECT NULL WHERE false;

  SELECT v_attention || coalesce(jsonb_agg(a ORDER BY a->>'since'), '[]'::jsonb) INTO v_attention FROM (
    SELECT jsonb_build_object(
      'kind','cashout_pending','queue','Retraits chauffeurs','label','Retrait chauffeur en attente',
      'reference', left(c.id::text,8), 'amount_gnf', c.amount_gnf, 'state', c.status,
      'since', c.requested_at, 'severity','high',
      'mode', public.admin_capability_mode('finance.payout.confirm'),
      'href','/admin/wallet/driver-cashouts') a
    FROM public.driver_cashout_requests c
    WHERE c.status = 'pending' ORDER BY c.requested_at LIMIT 10
  ) s;

  SELECT v_attention || coalesce(jsonb_agg(a ORDER BY a->>'since'), '[]'::jsonb) INTO v_attention FROM (
    SELECT jsonb_build_object(
      'kind','settlement_pending','queue','Règlements marchands','label','Règlement marchand en attente',
      'reference', left(m.id::text,8), 'amount_gnf', m.amount_gnf, 'state', m.status,
      'since', m.created_at, 'severity','normal',
      'mode', public.admin_capability_mode('finance.payout.confirm'),
      'href','/admin/wallet/payouts') a
    FROM public.merchant_settlement_requests m
    WHERE m.status = 'pending' ORDER BY m.created_at LIMIT 10
  ) s;

  SELECT v_attention || coalesce(jsonb_agg(a ORDER BY a->>'since'), '[]'::jsonb) INTO v_attention FROM (
    SELECT jsonb_build_object(
      'kind','refund_pending','queue','Remboursements','label','Remboursement à décider',
      'reference', left(r.id::text,8), 'amount_gnf', r.amount_gnf, 'state', r.status,
      'since', r.requested_at, 'severity','high',
      'mode', public.admin_capability_mode('finance.refund.approve'),
      'href','/admin/payments') a
    FROM public.payment_refund_requests r
    WHERE r.status = 'pending' AND coalesce(r.is_sandbox,false) = false
    ORDER BY r.requested_at LIMIT 10
  ) s;

  RETURN jsonb_build_object(
    'generated_at', now(),
    'role', v_role,
    'snapshot', v_snapshot,
    'attention', v_attention,
    'exceptions', v_exceptions,
    'exceptions_total', v_exc_total,
    'exceptions_critical', v_exc_critical
  );
END;$$;

REVOKE ALL ON FUNCTION public.finance_command_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_command_overview() TO authenticated, service_role;