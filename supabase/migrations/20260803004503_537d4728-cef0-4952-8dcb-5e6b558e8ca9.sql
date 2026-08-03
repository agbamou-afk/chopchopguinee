CREATE OR REPLACE FUNCTION public.confirm_payment_intent(p_intent_id uuid, p_provider_reference text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS payment_intents
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.payment_intents;
  v_pkg jsonb;
  v_issue_id uuid;
  v_err text;
BEGIN
  IF NOT (has_admin_role(auth.uid(), 'super_admin'::admin_role)
          OR has_admin_role(auth.uid(), 'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'forbidden: admin required';
  END IF;

  SELECT * INTO v_row FROM public.payment_intents WHERE id = p_intent_id FOR UPDATE;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'intent not found';
  END IF;
  IF v_row.is_sandbox THEN
    RAISE EXCEPTION 'sandbox_intent_use_om_payment_submit_sandbox_reference';
  END IF;

  -- Idempotent replay for package intents: already confirmed -> re-run the
  -- (itself idempotent) finaliser so the caller always ends with a mission.
  IF v_row.state = 'confirmed' AND v_row.source_module = 'package' THEN
    v_pkg := public.package_delivery_finalize_from_intent(v_row.id);
    RETURN v_row;
  END IF;

  UPDATE public.payment_intents
     SET state = 'confirmed',
         provider_reference = COALESCE(p_provider_reference, provider_reference),
         metadata = metadata || jsonb_build_object('confirmed_at', now(), 'note', p_note)
   WHERE id = p_intent_id
     AND state IN ('pending','processing','authorized')
   RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'intent not found or not in pending/processing state';
  END IF;

  INSERT INTO public.payment_reconciliation_events (intent_id, event_type, provider, provider_reference, payload, actor_user_id)
  VALUES (v_row.id, 'provider_confirmed', v_row.provider, v_row.provider_reference,
          jsonb_build_object('note', p_note), auth.uid());

  -- Envoyer / package: create the delivery mission + verification codes.
  IF v_row.source_module = 'package' THEN
    BEGIN
      v_pkg := public.package_delivery_finalize_from_intent(v_row.id);
    EXCEPTION WHEN OTHERS THEN
      v_err := SQLERRM;

      INSERT INTO public.support_issues(
        issue_type, severity, title, description,
        reporter_user_id, related_payment_intent_id, metadata
      ) VALUES (
        'payment_failed', 'high',
        'Envoyer: finalisation impossible après paiement confirmé',
        'Le paiement colis a été confirmé mais la mission de livraison n''a pas pu être créée: ' || v_err,
        v_row.user_id, v_row.id,
        jsonb_build_object(
          'intent_id', v_row.id,
          'source_module', 'package',
          'source_id', v_row.source_id,
          'error', v_err,
          'path', 'confirm_payment_intent'
        )
      ) RETURNING id INTO v_issue_id;

      UPDATE public.payment_intents
         SET state = 'needs_review',
             metadata = metadata || jsonb_build_object(
               'package_finalize_failed', true,
               'package_finalize_error', v_err,
               'package_support_issue_id', v_issue_id,
               'package_finalize_failed_at', now()
             ),
             updated_at = now()
       WHERE id = v_row.id
       RETURNING * INTO v_row;

      INSERT INTO public.payment_reconciliation_events (intent_id, event_type, provider, provider_reference, payload, actor_user_id)
      VALUES (v_row.id, 'provider_failed', v_row.provider, v_row.provider_reference,
              jsonb_build_object('stage', 'package_finalize', 'error', v_err, 'support_issue_id', v_issue_id), auth.uid());

      RAISE EXCEPTION 'package_finalize_failed: % (intent moved to needs_review, support issue %)', v_err, v_issue_id;
    END;
  END IF;

  RETURN v_row;
END $function$;

REVOKE ALL ON FUNCTION public.package_delivery_finalize_from_intent(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.package_delivery_finalize_from_intent(uuid) TO service_role;