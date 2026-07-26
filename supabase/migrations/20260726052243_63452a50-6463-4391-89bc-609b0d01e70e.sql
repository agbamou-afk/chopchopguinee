
CREATE OR REPLACE FUNCTION public.om_sandbox_submit_refund_reference(
  p_refund_request_id uuid, p_provider_reference text, p_test_run_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_god boolean;
  v_refund public.payment_refund_requests;
  v_intent public.payment_intents;
  v_ref text; v_outcome text;
  v_event public.payment_provider_events;
  v_issue_id uuid; v_test_run uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  PERFORM public._om_sandbox_require_active();
  v_is_god := public.is_god_admin(v_uid);
  IF p_provider_reference IS NULL OR btrim(p_provider_reference)='' THEN
    RAISE EXCEPTION 'provider_reference_required'; END IF;
  v_ref := upper(btrim(p_provider_reference));
  IF position('OM-SBX-' in v_ref) <> 1 THEN
    RAISE EXCEPTION 'live_reference_not_allowed_on_sandbox_refund_rpc'; END IF;
  v_outcome := public.om_sandbox_refund_reference_outcome(v_ref);
  IF v_outcome IS NULL THEN RAISE EXCEPTION 'unknown_sandbox_refund_reference: %',v_ref; END IF;

  SELECT * INTO v_refund FROM public.payment_refund_requests WHERE id=p_refund_request_id FOR UPDATE;
  IF v_refund.id IS NULL THEN RAISE EXCEPTION 'refund_request_not_found'; END IF;
  IF NOT v_refund.is_sandbox THEN RAISE EXCEPTION 'not_a_sandbox_refund'; END IF;
  IF NOT v_is_god AND v_refund.user_id<>v_uid THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT * INTO v_intent FROM public.payment_intents WHERE id=v_refund.payment_intent_id FOR UPDATE;
  IF v_intent.id IS NULL THEN RAISE EXCEPTION 'intent_missing'; END IF;
  IF NOT v_intent.is_sandbox THEN RAISE EXCEPTION 'sandbox_reference_rejected_on_non_sandbox_intent'; END IF;
  v_test_run := COALESCE(p_test_run_id, v_refund.test_run_id, v_intent.test_run_id);

  IF v_refund.provider_reference=v_ref AND v_refund.status IN ('paid','needs_review') THEN
    RETURN jsonb_build_object('idempotent',true,'refund_request_id',v_refund.id,
      'status',v_refund.status,'amount_gnf',v_refund.amount_gnf,'provider_reference',v_ref,
      'intent_id',v_intent.id,'test_run_id',v_refund.test_run_id); END IF;

  IF v_refund.status<>'pending' THEN RAISE EXCEPTION 'refund_not_in_pending_state: state=%',v_refund.status; END IF;

  IF EXISTS (SELECT 1 FROM public.payment_refund_requests
    WHERE payment_intent_id=v_intent.id AND id<>v_refund.id AND provider_reference=v_ref) THEN
    RAISE EXCEPTION 'duplicate_provider_reference_on_intent'; END IF;

  INSERT INTO public.payment_provider_events(
    provider,event_type,provider_transaction_id,amount_gnf,status,raw_payload,om_code_normalized,
    is_sandbox,environment,test_run_id
  ) VALUES (
    'orange_money',
    CASE WHEN v_outcome='paid' THEN 'sandbox.refund_paid' ELSE 'sandbox.refund_review' END,
    'om-sbx-refund:' || v_ref || ':' || v_refund.id::text,
    v_refund.amount_gnf,
    CASE WHEN v_outcome='paid' THEN 'successful' ELSE 'pending' END,
    jsonb_build_object('sandbox',true,'module',v_refund.source_module,'intent_id',v_intent.id,
      'refund_request_id',v_refund.id,'amount_gnf',v_refund.amount_gnf,
      'fixture',v_ref,'outcome',v_outcome),
    v_ref, true,'sandbox',v_test_run
  ) RETURNING * INTO v_event;

  IF v_outcome='paid' THEN
    UPDATE public.payment_refund_requests SET status='paid', provider_reference=v_ref,
      provider_event_id=v_event.id, resolved_at=now(), test_run_id=v_test_run,
      metadata=metadata||jsonb_build_object('sandbox_paid_at',now(),'sandbox_fixture',v_ref),
      updated_at=now() WHERE id=v_refund.id RETURNING * INTO v_refund;

    IF v_refund.source_module='repas' THEN
      UPDATE public.food_orders SET payment_status='refunded', updated_at=now()
       WHERE id=v_refund.source_id;
    ELSIF v_refund.source_module='marketplace' THEN
      UPDATE public.marketplace_offers SET payment_status='refunded',
        fulfillment_status=CASE WHEN fulfillment_status IN ('handed_over','delivered','completed')
                                 THEN fulfillment_status ELSE 'cancelled' END,
        updated_at=now() WHERE id=v_refund.source_id;
    END IF;

    UPDATE public.payment_intents SET state='refunded',
      metadata=metadata||jsonb_build_object('sandbox_refunded_at',now(),'sandbox_refund_request_id',v_refund.id),
      updated_at=now() WHERE id=v_intent.id;

    INSERT INTO public.payment_reconciliation_events(
      intent_id,event_type,provider,provider_reference,payload,actor_user_id,
      is_sandbox,environment,test_run_id
    ) VALUES (
      v_intent.id,'refund_completed','orange_money',v_ref,
      jsonb_build_object('sandbox',true,'module',v_refund.source_module,
        'refund_request_id',v_refund.id,'amount_gnf',v_refund.amount_gnf),
      v_uid,true,'sandbox',v_test_run);

    INSERT INTO public.audit_logs(actor_user_id,module,action,target_type,target_id,after)
    VALUES (v_uid,'payments','sandbox.refund.paid','payment_refund_request',v_refund.id::text,
      jsonb_build_object('module',v_refund.source_module,'source_id',v_refund.source_id,
        'intent_id',v_intent.id,'amount_gnf',v_refund.amount_gnf,
        'fixture',v_ref,'test_run_id',v_test_run));

  ELSE
    INSERT INTO public.support_issues(issue_type,severity,title,description,
      reporter_user_id,related_payment_intent_id,metadata)
    VALUES ('payment_failed','high',
      'Sandbox refund needs review ('||v_refund.source_module||')',
      'OM-SBX-REFUND-REVIEW-001: refund flagged for manual review. No real money moved.',
      v_refund.user_id,v_intent.id,
      jsonb_build_object('sandbox',true,'refund_request_id',v_refund.id,
        'source_module',v_refund.source_module,'source_id',v_refund.source_id,
        'provider_reference',v_ref,'amount_gnf',v_refund.amount_gnf,
        'test_run_id',v_test_run,'fixture',v_ref)
    ) RETURNING id INTO v_issue_id;

    UPDATE public.payment_refund_requests SET status='needs_review', provider_reference=v_ref,
      provider_event_id=v_event.id, support_issue_id=v_issue_id, test_run_id=v_test_run,
      metadata=metadata||jsonb_build_object('sandbox_review_at',now(),
        'sandbox_fixture',v_ref,'sandbox_support_issue_id',v_issue_id),
      updated_at=now() WHERE id=v_refund.id RETURNING * INTO v_refund;

    INSERT INTO public.payment_reconciliation_events(
      intent_id,event_type,provider,provider_reference,payload,actor_user_id,
      is_sandbox,environment,test_run_id
    ) VALUES (
      v_intent.id,'refund_created','orange_money',v_ref,
      jsonb_build_object('sandbox',true,'module',v_refund.source_module,
        'refund_request_id',v_refund.id,'outcome','needs_review','support_issue_id',v_issue_id),
      v_uid,true,'sandbox',v_test_run);

    INSERT INTO public.audit_logs(actor_user_id,module,action,target_type,target_id,after)
    VALUES (v_uid,'payments','sandbox.refund.needs_review','payment_refund_request',v_refund.id::text,
      jsonb_build_object('support_issue_id',v_issue_id,'intent_id',v_intent.id,
        'fixture',v_ref,'test_run_id',v_test_run));
  END IF;

  RETURN jsonb_build_object('idempotent',false,'refund_request_id',v_refund.id,
    'status',v_refund.status,'amount_gnf',v_refund.amount_gnf,
    'provider_reference',v_ref,'intent_id',v_intent.id,
    'provider_event_id',v_event.id,'support_issue_id',v_refund.support_issue_id,
    'is_sandbox',true,'test_run_id',v_test_run);
END $$;
