-- 1) Canonical net_gnf semantics on outbound payout evidence.
--    amount_gnf is already the amount transferred to the recipient
--    (expected_provider_transfer_gnf). Subtracting fee_gnf again double-counted a
--    recipient-borne fee. net_gnf = amount landing with the recipient.
COMMENT ON COLUMN public.payout_provider_evidence.net_gnf IS
  'Amount actually landing with the recipient. Equals amount_gnf (the outbound transfer). Provider fee is tracked separately in fee_gnf and is never subtracted twice.';

CREATE OR REPLACE FUNCTION public.payout_record_provider_evidence(p_payout_order_id uuid, p_provider text, p_provider_reference text, p_recipient_msisdn text, p_amount_gnf bigint, p_provider_status text, p_environment text, p_transferred_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_fee_gnf bigint DEFAULT NULL::bigint, p_raw jsonb DEFAULT '{}'::jsonb)
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
          p_amount_gnf,
          NULLIF(btrim(COALESCE(p_provider_status,'')),''), p_transferred_at,
          p_environment, COALESCE(p_raw,'{}'::jsonb), v_state, v_reason, v_caller)
  RETURNING * INTO v_e;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_caller,'finance','payout.evidence.recorded','payout_provider_evidence', v_e.id::text,
          jsonb_build_object('payout_order_id',v_o.id,'state',v_state,'reason',v_reason,
                             'evidence_source', COALESCE(p_raw->>'source','finance_generic')));

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

-- 2) Manual Orange Money outbound confirmation wrapper (operator-attested).
--    Thin, reference-only operator surface over the canonical evidence engine.
--    Every financial fact is derived from the frozen payout order; nothing here
--    debits a payable, wallet or ledger directly.
CREATE OR REPLACE FUNCTION public.finance_confirm_manual_om_payout(
  p_payout_order_id uuid,
  p_provider_reference text,
  p_attestation boolean DEFAULT false,
  p_transferred_at timestamp with time zone DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_o public.payout_orders;
  v_ref text := btrim(COALESCE(p_provider_reference,''));
  v_at timestamptz;
  v_res jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF NOT (public.is_god_admin(v_caller) OR public.has_admin_role(v_caller,'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF p_attestation IS NOT TRUE THEN RAISE EXCEPTION 'ATTESTATION_REQUIRED'; END IF;
  IF length(v_ref) < 6 THEN RAISE EXCEPTION 'PROVIDER_REFERENCE_REQUIRED'; END IF;

  SELECT * INTO v_o FROM public.payout_orders WHERE id = p_payout_order_id FOR UPDATE;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'PAYOUT_ORDER_NOT_FOUND'; END IF;
  IF v_o.source_kind IS DISTINCT FROM 'merchant_settlement' THEN
    RAISE EXCEPTION 'UNSUPPORTED_PAYOUT_SOURCE:%', v_o.source_kind;
  END IF;
  IF v_o.provider IS DISTINCT FROM 'orange_money' THEN
    RAISE EXCEPTION 'UNSUPPORTED_PROVIDER:%', v_o.provider;
  END IF;
  IF NOT public._finance_flag('merchant_om_settlement_enabled') THEN
    RAISE EXCEPTION 'STAGE_DISABLED:merchant_om_settlement_enabled';
  END IF;

  IF v_o.status = 'settled' THEN
    RETURN jsonb_build_object('status','already_settled','payout_order_id',v_o.id,
      'moved_gnf',0,'evidence_kind','manual_operator_attested','provider_verified',false);
  END IF;
  IF v_o.status NOT IN ('reserved','needs_review','mismatch') THEN
    RAISE EXCEPTION 'PAYOUT_ORDER_NOT_SETTLEABLE:%', v_o.status;
  END IF;

  v_at := COALESCE(p_transferred_at, now());
  IF v_at > now() + interval '5 minutes' OR v_at < now() - interval '30 days' THEN
    RAISE EXCEPTION 'INVALID_TRANSFER_TIMESTAMP';
  END IF;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_caller,'finance','payout.manual_om.attested','payout_order', v_o.id::text,
          jsonb_build_object(
            'evidence_kind','manual_operator_attested',
            'provider_verified', false,
            'provider_reference', v_ref,
            'expected_provider_transfer_gnf', v_o.expected_provider_transfer_gnf,
            'destination_msisdn', v_o.destination_msisdn,
            'provider', v_o.provider,
            'environment', v_o.environment,
            'settlement_request_id', v_o.source_request_id,
            'attested_by', v_caller,
            'attested_at', now()));

  -- Canonical path: exact server-derived evidence, engine revalidates and settles.
  v_res := public.payout_record_provider_evidence(
    v_o.id,
    v_o.provider,
    v_ref,
    v_o.destination_msisdn,
    v_o.expected_provider_transfer_gnf,
    'completed',
    v_o.environment,
    v_at,
    v_o.provider_fee_gnf,
    jsonb_build_object(
      'source','finance_manual_om',
      'evidence_kind','manual_operator_attested',
      'provider_verified', false,
      'attested_by', v_caller,
      'attested_at', now(),
      'recorded_at', now(),
      'payout_order_id', v_o.id,
      'settlement_request_id', v_o.source_request_id,
      'attestation','Finance operator attests an external Orange Money transfer of the exact frozen amount to the exact frozen recipient. Not verified by any Orange Money API.'));

  RETURN COALESCE(v_res,'{}'::jsonb) || jsonb_build_object(
    'evidence_kind','manual_operator_attested',
    'provider_verified', false,
    'expected_provider_transfer_gnf', v_o.expected_provider_transfer_gnf,
    'destination_msisdn', v_o.destination_msisdn);
END $function$;

REVOKE ALL ON FUNCTION public.finance_confirm_manual_om_payout(uuid, text, boolean, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_confirm_manual_om_payout(uuid, text, boolean, timestamptz) TO authenticated;

-- 3) Finance queue exposes the frozen expected transfer + evidence provenance.
CREATE OR REPLACE FUNCTION public.finance_payout_queue(p_bucket text DEFAULT 'requested'::text, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      'source_kind', o.source_kind,
      'merchant_store_id', o.merchant_store_id, 'store_name', ms.name,
      'destination_msisdn', o.destination_msisdn, 'provider', o.provider,
      'environment', o.environment,
      'requested_principal_gnf', o.requested_principal_gnf,
      'provider_fee_gnf', o.provider_fee_gnf, 'fee_borne_by', o.fee_borne_by,
      'merchant_liability_debit_gnf', o.merchant_liability_debit_gnf,
      'recipient_net_gnf', o.recipient_net_gnf,
      'expected_provider_transfer_gnf', o.expected_provider_transfer_gnf,
      'reservation_gnf', o.reservation_gnf,
      'settled_gnf', o.settled_gnf, 'request_id', o.source_request_id,
      'reject_reason', o.reject_reason, 'settled_at', o.settled_at,
      'created_at', o.created_at,
      'evidence', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'evidence_id', e.id, 'provider_reference', e.provider_reference,
            'state', e.reconciliation_state, 'reason', e.mismatch_reason,
            'amount_gnf', e.amount_gnf, 'recipient_msisdn', e.recipient_msisdn,
            'provider_status', e.provider_status, 'environment', e.environment,
            'evidence_source', COALESCE(e.raw->>'source','finance_generic'),
            'evidence_kind', COALESCE(e.raw->>'evidence_kind','operator_recorded'),
            'provider_verified', false,
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
END $function$;

-- 4) Receipt truthfully distinguishes manual operator attestation from API verification.
CREATE OR REPLACE FUNCTION public.merchant_settlement_receipt(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_r public.merchant_settlement_requests;
  v_o public.payout_orders; v_e public.payout_provider_evidence; v_owner uuid; v_journal jsonb;
  v_source text; v_manual boolean;
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

  v_source := COALESCE(v_e.raw->>'source','finance_generic');
  v_manual := v_source = 'finance_manual_om'
              OR COALESCE(v_e.raw->>'evidence_kind','') = 'manual_operator_attested';

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
    'evidence_source', v_source,
    'evidence_kind', CASE WHEN v_manual THEN 'manual_operator_attested' ELSE 'operator_recorded' END,
    'provider_verified', false,
    'attested_by', v_e.raw->>'attested_by',
    'verification_note', CASE WHEN v_manual
      THEN 'Référence Orange Money saisie et attestée manuellement par un administrateur Finance après un transfert exécuté hors CHOPCHOP. Aucune vérification automatique par une API Orange Money.'
      ELSE 'Référence de transfert externe enregistrée par un administrateur Finance. Aucune vérification automatique par une API Orange Money.' END,
    'ledger', COALESCE(v_journal, '{}'::jsonb));
END $function$;