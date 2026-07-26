-- =========================================================================
-- Orange Money Sandbox — Slice A
-- Server-authoritative sandbox reference submission + financial isolation.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. Guard: production confirm/fail/capture must not touch sandbox rows.
--    Sandbox intents transition exclusively via
--    om_payment_submit_sandbox_reference (below).
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.confirm_payment_intent(
  p_intent_id uuid,
  p_provider_reference text DEFAULT NULL::text,
  p_note text DEFAULT NULL::text
)
RETURNS payment_intents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.payment_intents;
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

  UPDATE public.payment_intents
     SET state = 'confirmed',
         provider_reference = COALESCE(p_provider_reference, provider_reference),
         metadata = metadata || jsonb_build_object('confirmed_at', now(), 'note', p_note)
   WHERE id = p_intent_id
     AND state IN ('pending','processing')
   RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'intent not found or not in pending/processing state';
  END IF;

  INSERT INTO public.payment_reconciliation_events (intent_id, event_type, provider, provider_reference, payload, actor_user_id)
  VALUES (v_row.id, 'provider_confirmed', v_row.provider, v_row.provider_reference,
          jsonb_build_object('note', p_note), auth.uid());

  RETURN v_row;
END $function$;

CREATE OR REPLACE FUNCTION public.fail_payment_intent(
  p_intent_id uuid,
  p_reason text DEFAULT NULL::text
)
RETURNS payment_intents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.payment_intents;
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

  UPDATE public.payment_intents
     SET state = 'failed',
         metadata = metadata || jsonb_build_object('failed_at', now(), 'reason', p_reason)
   WHERE id = p_intent_id
     AND state IN ('pending','processing')
   RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'intent not found or not in pending/processing state';
  END IF;

  INSERT INTO public.payment_reconciliation_events (intent_id, event_type, provider, provider_reference, payload, actor_user_id)
  VALUES (v_row.id, 'provider_failed', v_row.provider, v_row.provider_reference,
          jsonb_build_object('reason', p_reason), auth.uid());

  RETURN v_row;
END $function$;

CREATE OR REPLACE FUNCTION public.choppay_capture_payment_intent(
  p_payment_intent_id uuid,
  p_reason text DEFAULT 'Capture CHOPPay payment'::text
)
RETURNS payment_intents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_intent public.payment_intents;
  v_hold public.wallet_transactions;
  v_pay  public.wallet_transactions;
BEGIN
  SELECT * INTO v_intent FROM public.payment_intents
    WHERE id = p_payment_intent_id FOR UPDATE;
  IF v_intent.id IS NULL THEN
    RAISE EXCEPTION 'intent_not_found';
  END IF;
  IF v_intent.is_sandbox THEN
    RAISE EXCEPTION 'sandbox_intent_cannot_touch_master_wallet';
  END IF;

  IF v_intent.state = 'confirmed' THEN
    RETURN v_intent;
  END IF;

  IF v_intent.state NOT IN ('pending','processing') THEN
    RAISE EXCEPTION 'intent_not_capturable: state=%', v_intent.state;
  END IF;

  IF v_intent.wallet_hold_tx_id IS NULL THEN
    RAISE EXCEPTION 'no_wallet_hold_to_capture';
  END IF;

  SELECT * INTO v_hold FROM public.wallet_transactions
    WHERE id = v_intent.wallet_hold_tx_id FOR UPDATE;

  v_pay := public.wallet_capture(
    p_hold_id := v_intent.wallet_hold_tx_id,
    p_to_user_id := NULL,
    p_to_party_type := 'master',
    p_actual_amount_gnf := v_intent.amount_gnf,
    p_description := p_reason
  );

  UPDATE public.payment_intents
     SET state = 'confirmed',
         captured_tx_id = v_pay.id,
         captured_at = now(),
         metadata = metadata || jsonb_build_object('captured_reason', p_reason)
   WHERE id = v_intent.id
   RETURNING * INTO v_intent;

  INSERT INTO public.payment_reconciliation_events
    (intent_id, event_type, provider, payload, actor_user_id)
  VALUES
    (v_intent.id, 'wallet_credited', v_intent.provider,
     jsonb_build_object('captured_tx_id', v_pay.id, 'reason', p_reason),
     auth.uid());

  RETURN v_intent;
END;
$function$;

-- -------------------------------------------------------------------------
-- 2. Sandbox reference registry (server-authoritative).
--    Small helper so the outcome map lives in one place.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.om_sandbox_reference_outcome(p_reference text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT CASE upper(btrim(coalesce(p_reference,'')))
    WHEN 'OM-SBX-SUCCESS-001'        THEN 'success'
    WHEN 'OM-SBX-REVIEW-001'         THEN 'review'
    WHEN 'OM-SBX-REJECT-001'         THEN 'reject'
    WHEN 'OM-SBX-DUPLICATE-001'      THEN 'duplicate'
    WHEN 'OM-SBX-EXPIRED-001'        THEN 'expired'
    WHEN 'OM-SBX-REFUND-001'         THEN 'refund'
    WHEN 'OM-SBX-REFUND-REVIEW-001'  THEN 'refund_review'
    ELSE NULL
  END;
$function$;

-- -------------------------------------------------------------------------
-- 3. om_payment_submit_sandbox_reference
--    Server-authoritative deterministic sandbox execution. Drives the real
--    payment_intents state machine + real payment_provider_events table.
--    NEVER touches wallet_transactions or wallets.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.om_payment_submit_sandbox_reference(
  p_payment_intent_id uuid,
  p_provider_reference text,
  p_payer_phone text DEFAULT NULL,
  p_test_run_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid          uuid := auth.uid();
  v_is_god       boolean;
  v_intent       public.payment_intents;
  v_ref          text;
  v_outcome      text;
  v_new_state    payment_state;
  v_event        public.payment_provider_events;
  v_event_status text;
  v_env_ok       boolean;
  v_sbx_ok       boolean;
  v_tx_id        text;
  v_recon_type   text;
  v_dup_count    int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501';
  END IF;

  v_is_god := public.is_god_admin(v_uid);

  -- Environment / sandbox master switches must both be on.
  SELECT COALESCE((SELECT enabled FROM public.feature_flags WHERE key='om_environment'),   false)
    INTO v_env_ok;
  SELECT COALESCE((SELECT enabled FROM public.feature_flags WHERE key='om_sandbox_enabled'),false)
    INTO v_sbx_ok;
  IF NOT (v_env_ok AND v_sbx_ok) THEN
    RAISE EXCEPTION 'sandbox_disabled' USING ERRCODE='42501';
  END IF;

  -- Normalize reference.
  v_ref := upper(btrim(coalesce(p_provider_reference,'')));
  IF v_ref = '' THEN
    RAISE EXCEPTION 'reference_required';
  END IF;

  -- Reject anything that does not look like a sandbox reference on this RPC.
  IF v_ref NOT LIKE 'OM-SBX-%' THEN
    RAISE EXCEPTION 'live_reference_rejected_on_sandbox_rpc';
  END IF;

  v_outcome := public.om_sandbox_reference_outcome(v_ref);
  IF v_outcome IS NULL THEN
    RAISE EXCEPTION 'unknown_sandbox_reference';
  END IF;

  -- Lock intent.
  SELECT * INTO v_intent FROM public.payment_intents
   WHERE id = p_payment_intent_id FOR UPDATE;
  IF v_intent.id IS NULL THEN
    RAISE EXCEPTION 'intent_not_found';
  END IF;

  -- Ownership: caller must own the intent unless caller is God Admin.
  IF NOT v_is_god AND v_intent.user_id <> v_uid THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Intent must itself be sandbox-tagged. Prevents contamination of live rows.
  IF NOT v_intent.is_sandbox THEN
    RAISE EXCEPTION 'not_a_sandbox_intent';
  END IF;

  -- Idempotency: if the intent already carries this exact reference and has
  -- reached a terminal / semi-terminal state, return the current snapshot
  -- without creating another provider event or transition.
  IF v_intent.provider_reference IS NOT NULL
     AND upper(btrim(v_intent.provider_reference)) = v_ref
     AND v_intent.state IN ('authorized','confirmed','failed','expired','needs_review','cancelled','refunded','reversed') THEN
    RETURN jsonb_build_object(
      'idempotent', true,
      'intent_id', v_intent.id,
      'intent_state', v_intent.state,
      'outcome', v_outcome,
      'is_sandbox', true,
      'test_run_id', v_intent.test_run_id
    );
  END IF;

  -- Duplicate rule: the DUPLICATE fixture explicitly simulates re-use of a
  -- reference already consumed by another sandbox intent.
  IF v_outcome = 'duplicate' THEN
    SELECT COUNT(*) INTO v_dup_count
      FROM public.payment_provider_events
     WHERE provider = 'orange_money'
       AND is_sandbox = true
       AND upper(btrim(provider_transaction_id)) LIKE 'OM-SBX-DUPLICATE-%';
    -- Force a stable duplicate provider_transaction_id so the unique index
    -- rejects the second attempt across intents.
    v_tx_id := 'OM-SBX-DUPLICATE-FIXED';
  ELSE
    -- Unique per (provider, provider_transaction_id).
    v_tx_id := v_ref || '::' || v_intent.id::text;
  END IF;

  -- Only pending/processing intents can transition (matches production).
  IF v_intent.state NOT IN ('pending','processing') THEN
    RAISE EXCEPTION 'intent_not_transitionable: state=%', v_intent.state;
  END IF;

  -- Decide the state machine outcome. Sandbox NEVER calls wallet_*.
  v_new_state    := v_intent.state;
  v_event_status := 'received';
  v_recon_type   := 'provider_pending';

  IF v_outcome = 'success' THEN
    v_new_state    := 'authorized';
    v_event_status := 'matched';
    v_recon_type   := 'provider_confirmed';
  ELSIF v_outcome = 'review' THEN
    v_new_state    := 'needs_review';
    v_event_status := 'needs_review';
    v_recon_type   := 'provider_pending';
  ELSIF v_outcome = 'reject' THEN
    v_new_state    := 'failed';
    v_event_status := 'rejected';
    v_recon_type   := 'provider_failed';
  ELSIF v_outcome = 'expired' THEN
    v_new_state    := 'expired';
    v_event_status := 'rejected';
    v_recon_type   := 'provider_failed';
  ELSIF v_outcome = 'duplicate' THEN
    v_new_state    := 'needs_review';
    v_event_status := 'duplicate';
    v_recon_type   := 'provider_pending';
  ELSIF v_outcome IN ('refund','refund_review') THEN
    -- Refund fixtures require an already-authorized/confirmed intent.
    -- Slice A records the recon event only; a dedicated refund RPC lands
    -- in a later slice. Return needs_review so callers can observe.
    v_new_state    := 'needs_review';
    v_event_status := 'needs_review';
    v_recon_type   := CASE WHEN v_outcome='refund' THEN 'refund_created' ELSE 'provider_pending' END;
  END IF;

  -- Insert provider event. Unique on (provider, provider_transaction_id)
  -- gives us idempotency + duplicate rejection for free.
  BEGIN
    INSERT INTO public.payment_provider_events (
      provider, event_type, provider_transaction_id,
      payer_phone, amount_gnf, currency, status,
      raw_payload, processing_status,
      is_sandbox, environment, test_run_id
    ) VALUES (
      'orange_money', 'sandbox.payment.simulated', v_tx_id,
      NULLIF(btrim(coalesce(p_payer_phone,'')), ''),
      v_intent.amount_gnf, v_intent.currency,
      CASE v_outcome
        WHEN 'success' THEN 'successful'
        WHEN 'reject'  THEN 'failed'
        WHEN 'expired' THEN 'expired'
        ELSE 'pending'
      END,
      jsonb_build_object(
        'sandbox', true,
        'reference', v_ref,
        'outcome', v_outcome,
        'intent_id', v_intent.id,
        'test_run_id', COALESCE(p_test_run_id, v_intent.test_run_id)
      ),
      v_event_status,
      true, 'sandbox',
      COALESCE(p_test_run_id, v_intent.test_run_id)
    )
    RETURNING * INTO v_event;
  EXCEPTION WHEN unique_violation THEN
    -- Same (provider, provider_transaction_id) already existed. This is the
    -- deterministic duplicate path. Do NOT transition the intent again.
    SELECT * INTO v_event FROM public.payment_provider_events
     WHERE provider='orange_money' AND provider_transaction_id = v_tx_id;

    INSERT INTO public.payment_reconciliation_events
      (intent_id, event_type, provider, provider_reference, payload, actor_user_id,
       is_sandbox, environment, test_run_id)
    VALUES (v_intent.id, 'provider_pending', 'orange_money', v_ref,
            jsonb_build_object('sandbox', true, 'duplicate_of_event', v_event.id, 'outcome', 'duplicate'),
            v_uid, true, 'sandbox', COALESCE(p_test_run_id, v_intent.test_run_id));

    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
    VALUES (v_uid, 'payments', 'sandbox.payment.duplicate_rejected',
            'payment_intent', v_intent.id::text,
            jsonb_build_object('reference', v_ref, 'existing_event_id', v_event.id));

    RETURN jsonb_build_object(
      'idempotent', true,
      'duplicate', true,
      'intent_id', v_intent.id,
      'intent_state', v_intent.state,
      'outcome', 'duplicate',
      'is_sandbox', true
    );
  END;

  -- Transition the intent.
  UPDATE public.payment_intents pi
     SET state              = v_new_state,
         provider_reference = v_ref,
         provider_event_id  = v_event.id,
         payer_phone        = COALESCE(pi.payer_phone, NULLIF(btrim(coalesce(p_payer_phone,'')),'')),
         test_run_id        = COALESCE(pi.test_run_id, p_test_run_id),
         authorized_at      = CASE WHEN v_new_state='authorized' THEN now() ELSE pi.authorized_at END,
         rejected_at        = CASE WHEN v_new_state='failed'     THEN now() ELSE pi.rejected_at END,
         rejection_reason   = CASE WHEN v_new_state='failed'     THEN v_outcome ELSE pi.rejection_reason END,
         metadata           = pi.metadata || jsonb_build_object(
                                 'sandbox', true,
                                 'sandbox_outcome', v_outcome,
                                 'sandbox_reference', v_ref,
                                 'sandbox_event_id', v_event.id
                               ),
         updated_at         = now()
   WHERE id = v_intent.id
   RETURNING * INTO v_intent;

  -- Recon event.
  INSERT INTO public.payment_reconciliation_events
    (intent_id, event_type, provider, provider_reference, payload, actor_user_id,
     is_sandbox, environment, test_run_id)
  VALUES (v_intent.id, v_recon_type::payment_recon_event, 'orange_money', v_ref,
          jsonb_build_object('sandbox', true, 'outcome', v_outcome, 'event_id', v_event.id),
          v_uid, true, 'sandbox', COALESCE(p_test_run_id, v_intent.test_run_id));

  -- Audit.
  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'payments',
          'sandbox.payment.' || CASE
            WHEN v_new_state='authorized'    THEN 'authorized'
            WHEN v_new_state='failed'        THEN 'rejected'
            WHEN v_new_state='expired'       THEN 'expired'
            WHEN v_new_state='needs_review'  THEN 'needs_review'
            ELSE 'transitioned'
          END,
          'payment_intent', v_intent.id::text,
          jsonb_build_object(
            'reference', v_ref,
            'outcome', v_outcome,
            'event_id', v_event.id,
            'new_state', v_new_state,
            'test_run_id', v_intent.test_run_id
          ));

  RETURN jsonb_build_object(
    'idempotent', false,
    'intent_id', v_intent.id,
    'intent_state', v_intent.state,
    'outcome', v_outcome,
    'event_id', v_event.id,
    'is_sandbox', true,
    'test_run_id', v_intent.test_run_id,
    'source_finalization', 'not_wired_in_slice_a',
    'needs_review', v_new_state = 'needs_review'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.om_payment_submit_sandbox_reference(uuid, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_payment_submit_sandbox_reference(uuid, text, text, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.om_sandbox_reference_outcome(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_reference_outcome(text) TO authenticated;

-- -------------------------------------------------------------------------
-- 4. Financial isolation sweep — admin preview functions gain
--    p_include_sandbox (default false) so sandbox rows do not contaminate
--    production totals. Ordinary users cannot call these anyway (admin gate).
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_preview_payment_intents(
  p_state text DEFAULT NULL::text,
  p_source_module text DEFAULT NULL::text,
  p_limit integer DEFAULT 100,
  p_include_sandbox boolean DEFAULT false
)
RETURNS TABLE(id uuid, source_module text, source_id uuid, payer_user_id uuid, payee_user_id uuid, merchant_store_id uuid, amount_gnf bigint, state payment_state, provider payment_provider, internal_reference text, wallet_hold_tx_id uuid, captured_tx_id uuid, settlement_tx_id uuid, metadata jsonb, created_at timestamp with time zone, captured_at timestamp with time zone, cancelled_at timestamp with time zone, is_sandbox boolean, test_run_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_any_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden: admin required';
  END IF;
  -- Only God Admin may opt into sandbox-included view.
  IF p_include_sandbox AND NOT public.is_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden: god_admin required for sandbox view';
  END IF;
  RETURN QUERY
  SELECT pi.id, pi.source_module, pi.source_id, pi.user_id,
         pi.payee_user_id, pi.related_store_id, pi.amount_gnf,
         pi.state, pi.provider, pi.internal_reference,
         pi.wallet_hold_tx_id, pi.captured_tx_id, pi.settlement_tx_id,
         pi.metadata, pi.created_at, pi.captured_at, pi.cancelled_at,
         pi.is_sandbox, pi.test_run_id
    FROM public.payment_intents pi
   WHERE (p_state IS NULL OR pi.state::text = p_state)
     AND (p_source_module IS NULL OR pi.source_module = p_source_module)
     AND (p_include_sandbox OR pi.is_sandbox = false)
   ORDER BY pi.created_at DESC
   LIMIT coalesce(p_limit,100);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_preview_marche_payment_intents(
  p_limit integer DEFAULT 100,
  p_include_sandbox boolean DEFAULT false
)
RETURNS TABLE(offer_id uuid, listing_id uuid, listing_title text, buyer_user_id uuid, merchant_user_id uuid, merchant_store_id uuid, amount_gnf bigint, offer_status text, payment_status text, payment_intent_id uuid, payment_intent_state payment_state, wallet_hold_tx_id uuid, captured_tx_id uuid, settlement_tx_id uuid, created_at timestamp with time zone, authorized_at timestamp with time zone)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_any_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden: admin required' USING ERRCODE = '42501';
  END IF;
  IF p_include_sandbox AND NOT public.is_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden: god_admin required for sandbox view';
  END IF;
  RETURN QUERY
  SELECT o.id, o.listing_id, l.title, o.buyer_user_id, o.merchant_user_id,
         COALESCE(o.merchant_store_id, l.store_id),
         COALESCE(o.counter_amount_gnf, o.offer_amount_gnf),
         o.status, o.payment_status, o.payment_intent_id,
         pi.state, pi.wallet_hold_tx_id, pi.captured_tx_id, pi.settlement_tx_id,
         o.created_at, o.authorized_at
    FROM public.marketplace_offers o
    LEFT JOIN public.marketplace_listings l ON l.id = o.listing_id
    LEFT JOIN public.payment_intents pi ON pi.id = o.payment_intent_id
   WHERE (o.status = 'accepted' OR o.payment_status <> 'unpaid')
     AND (p_include_sandbox OR pi.id IS NULL OR pi.is_sandbox = false)
   ORDER BY o.created_at DESC
   LIMIT COALESCE(p_limit, 100);
END;
$function$;

-- -------------------------------------------------------------------------
-- 5. Documentation of the invariant enforced by this migration.
--
-- INVARIANT: Sandbox payment intents may progress through the real state
-- machine (pending -> authorized/needs_review/failed/expired) and produce
-- provider_events + reconciliation_events + audit_logs, but the sandbox
-- code path is FORBIDDEN from calling any wallet_* function
-- (wallet_hold / wallet_capture / wallet_release / wallet_settle_* /
-- wallet_credit_mission_earning / wallet_pay_merchant*). Therefore:
--   - master wallet balance (wallets.party_type='master')      - unchanged
--   - driver wallet balance / held_gnf                          - unchanged
--   - driver_cashout_create_request eligibility (reads wallets) - unchanged
--   - merchant settlement totals (wallet_transactions)          - unchanged
--   - reconciliation totals (wallet_transactions)               - unchanged
--
-- Production RPCs (confirm/fail/capture) now REFUSE sandbox intents at the
-- boundary, so the invariant is enforced defensively even if calling code
-- is ever mistakenly wired to a sandbox row.
-- -------------------------------------------------------------------------
COMMENT ON FUNCTION public.om_payment_submit_sandbox_reference(uuid, text, text, uuid) IS
  'Sandbox-only: drives the real payment state machine deterministically from OM-SBX-* references. Never touches wallets or wallet_transactions. Requires om_environment=true AND om_sandbox_enabled=true. Caller must own the intent or be God Admin.';
