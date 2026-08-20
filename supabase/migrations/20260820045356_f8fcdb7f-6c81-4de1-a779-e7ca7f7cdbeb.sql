CREATE OR REPLACE FUNCTION public.marche_finance_order_audit(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  caller uuid := auth.uid();
  o public.marche_orders; p public.merchant_payables;
  v_alloc bigint := 0; v_unproven bigint := 0; v_codes text[] := ARRAY[]::text[];
BEGIN
  IF NOT public._finance_privileged(caller) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;

  SELECT * INTO p FROM public.merchant_payables
   WHERE source_module='marche' AND source_id=o.id AND merchant_store_id=o.merchant_store_id;

  IF p.id IS NULL THEN
    IF o.fulfillment_state = 'delivered' THEN
      v_codes := v_codes || 'PAYABLE_MISSING_AFTER_DELIVERY'::text;
    END IF;
  ELSE
    SELECT COALESCE(sum(a.amount_gnf),0) INTO v_alloc
      FROM public.payout_settlement_allocations a WHERE a.merchant_payable_id = p.id;

    IF o.merchant_payable_gnf IS NOT NULL AND p.amount_gnf <> o.merchant_payable_gnf THEN
      v_codes := v_codes || 'ORDER_PAYABLE_AMOUNT_MISMATCH'::text;
    END IF;
    IF p.settled_gnf <> v_alloc THEN
      v_codes := v_codes || 'ALLOCATION_COVERAGE_MISMATCH'::text;
    END IF;
    IF p.settled_gnf > p.funded_gnf AND p.funding_source <> 'platform' THEN
      v_codes := v_codes || 'SETTLED_EXCEEDS_FUNDED'::text;
    END IF;
    IF p.state = 'settled' AND p.settled_gnf < p.amount_gnf THEN
      v_codes := v_codes || 'SETTLED_STATE_WITHOUT_FULL_SETTLEMENT'::text;
    END IF;

    SELECT COALESCE(sum(a.amount_gnf),0) INTO v_unproven
      FROM public.payout_settlement_allocations a
      JOIN public.payout_orders po ON po.id = a.payout_order_id
     WHERE a.merchant_payable_id = p.id
       AND NOT EXISTS (SELECT 1 FROM public.payout_provider_evidence e
                        WHERE e.payout_order_id = po.id AND e.reconciliation_state = 'reconciled');
    IF v_unproven > 0 THEN
      v_codes := v_codes || 'SETTLEMENT_WITHOUT_RECONCILED_EVIDENCE'::text;
    END IF;

    IF EXISTS (SELECT 1 FROM public.payout_settlement_allocations a
                JOIN public.payout_orders po ON po.id = a.payout_order_id
               WHERE a.merchant_payable_id = p.id
                 AND po.status IN ('needs_review','mismatch','rejected')) THEN
      v_codes := v_codes || 'PAYOUT_ORDER_NEEDS_REVIEW'::text;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'order_id', o.id,
    'merchant_store_id', o.merchant_store_id,
    'fulfillment_state', o.fulfillment_state,
    'frozen_merchant_payable_gnf', o.merchant_payable_gnf,
    'frozen_merchant_fee_gnf', o.merchant_fee_gnf,
    'payable_present', (p.id IS NOT NULL),
    'payable_state', p.state,
    'payable_amount_gnf', p.amount_gnf,
    'funded_gnf', p.funded_gnf,
    'settled_gnf', p.settled_gnf,
    'allocated_gnf', v_alloc,
    'unproven_settled_gnf', v_unproven,
    'tender', public._marche_order_tender(o.id, o.source_offer_id),
    'mismatch_codes', to_jsonb(v_codes),
    'clean', (array_length(v_codes,1) IS NULL));
END $$;

REVOKE ALL ON FUNCTION public.marche_finance_order_audit(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_finance_order_audit(uuid) TO authenticated, service_role;
