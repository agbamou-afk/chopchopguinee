-- 1. Patch the harness cleanup to use the sanctioned server-write context.
DO $mig$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r11';
  v_def := replace(v_def,
    '  DELETE FROM public.payout_provider_evidence WHERE payout_order_id = v_po;',
    '  PERFORM set_config(''marche.rpc'',''1'', true);
  DELETE FROM public.payout_provider_evidence WHERE payout_order_id = v_po;');
  v_def := replace(v_def,
    '  DELETE FROM public.marche_orders WHERE id = v_o1;',
    '  DELETE FROM public.marche_orders WHERE id = v_o1;
  PERFORM set_config(''marche.rpc'','''', true);');
  IF v_def NOT LIKE '%set_config(''marche.rpc'',''1'', true);
  DELETE FROM public.payout_provider_evidence%' THEN
    RAISE EXCEPTION 'CLEANUP_PATCH_TARGET_NOT_FOUND';
  END IF;
  EXECUTE v_def;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r11() FROM PUBLIC, anon, authenticated;

-- 2. Purge residue left by the interrupted self-test run.
DO $purge$
DECLARE v_orders uuid[]; v_stores uuid[];
BEGIN
  SELECT COALESCE(array_agg(id), '{}') INTO v_orders
    FROM public.marche_orders WHERE client_request_id LIKE 'qa-n411-%';
  SELECT COALESCE(array_agg(id), '{}') INTO v_stores
    FROM public.merchant_stores WHERE slug LIKE 'qa-n411-%';

  PERFORM set_config('marche.rpc','1', true);
  DELETE FROM public.payout_provider_evidence
   WHERE payout_order_id IN (SELECT id FROM public.payout_orders WHERE order_key LIKE 'qa-n411-po-%');
  DELETE FROM public.payout_settlement_allocations
   WHERE payout_order_id IN (SELECT id FROM public.payout_orders WHERE order_key LIKE 'qa-n411-po-%');
  DELETE FROM public.payout_orders WHERE order_key LIKE 'qa-n411-po-%';
  DELETE FROM public.merchant_payables WHERE payable_key LIKE 'qa-n411-%';
  DELETE FROM public.marche_fulfillment_transitions WHERE order_id = ANY(v_orders);
  DELETE FROM public.marche_fulfillment_observations WHERE order_id = ANY(v_orders);
  DELETE FROM public.marche_fulfillment_events WHERE order_id = ANY(v_orders);
  DELETE FROM public.marche_fulfillment_profiles WHERE order_id = ANY(v_orders);
  DELETE FROM public.marche_order_items WHERE order_id = ANY(v_orders);
  UPDATE public.marche_orders SET mission_id = NULL WHERE id = ANY(v_orders);
  DELETE FROM public.mission_events WHERE mission_id IN
    (SELECT id FROM public.missions WHERE ref_market_order_id = ANY(v_orders));
  DELETE FROM public.missions WHERE ref_market_order_id = ANY(v_orders);
  DELETE FROM public.marche_orders WHERE id = ANY(v_orders);
  DELETE FROM public.marketplace_listings WHERE store_id = ANY(v_stores);
  DELETE FROM public.merchant_stores WHERE id = ANY(v_stores);
  PERFORM set_config('marche.rpc','', true);

  DELETE FROM public.user_roles WHERE user_id IN
    (SELECT id FROM auth.users WHERE email LIKE 'n411%');
  DELETE FROM public.admin_users WHERE user_id IN
    (SELECT id FROM auth.users WHERE email LIKE 'n411%');
  DELETE FROM public.driver_profiles WHERE user_id IN
    (SELECT id FROM auth.users WHERE email LIKE 'n411%');
  DELETE FROM public.wallet_transactions WHERE from_wallet_id IN
      (SELECT id FROM public.wallets WHERE owner_user_id IN (SELECT id FROM auth.users WHERE email LIKE 'n411%'))
     OR to_wallet_id IN
      (SELECT id FROM public.wallets WHERE owner_user_id IN (SELECT id FROM auth.users WHERE email LIKE 'n411%'));
  DELETE FROM public.wallets WHERE owner_user_id IN (SELECT id FROM auth.users WHERE email LIKE 'n411%');
  DELETE FROM auth.users WHERE email LIKE 'n411%';
END $purge$;
