-- Slice 13 · Fix 1 — QA residue purge + anon finance EXECUTE lockdown
-- Defect S13-D1 (P0): _qa_s7_* helpers were left installed as SECURITY DEFINER
--   with EXECUTE granted to anon/authenticated. _qa_s7_wallet() could fabricate
--   wallets and balances for an arbitrary user id from an unauthenticated session.
-- Defect S13-D2 (P2): _qa_s5/6/7/8_results tables left installed, anon-readable.
-- Defect S13-D3 (P1): anon retained EXECUTE on money-moving / admin-finance RPCs.
-- Forward-only migration; no historical migration is rewritten.

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname LIKE '\_qa\_s%'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %s CASCADE', r.sig);
  END LOOP;
END $$;

DROP TABLE IF EXISTS public._qa_s5_results CASCADE;
DROP TABLE IF EXISTS public._qa_s6_results CASCADE;
DROP TABLE IF EXISTS public._qa_s7_results CASCADE;
DROP TABLE IF EXISTS public._qa_s8_results CASCADE;

DO $$
DECLARE
  r record;
  v_names text[] := ARRAY[
    'wallet_admin_credit','wallet_ensure','wallet_ensure_master','wallet_get_master_balance',
    'wallet_pay_driver_commission','wallet_pay_driver_commission_batch','wallet_pay_merchant',
    'wallet_reverse_driver_commission','wallet_topup_admin_cancel','wallet_topup_admin_mark_expired',
    'merchant_ensure_wallet','merchant_respond_marketplace_offer',
    'marche_complete_offer','marche_create_offer_payment_intent',
    'admin_marche_capture_and_settle_offer','admin_preview_marche_payment_settlement',
    'admin_preview_marche_payment_intents','admin_preview_payment_intents',
    'admin_preview_p2p_transfers','admin_generate_payout_statement','admin_set_statement_status',
    'can_manage_wallet','_driver_finance_eligible','_payout_fee_snapshot',
    'finance_policy_predecessor','_om_sandbox_register_test_run',
    'om_payment_submit_sandbox_reference','om_sandbox_admin_list_runs','om_sandbox_admin_metrics',
    'om_sandbox_admin_run_detail','om_sandbox_archive_test_run','om_sandbox_assign_mock_driver',
    'om_sandbox_cancel_ride','om_sandbox_complete_test_run','om_sandbox_create_marche_intent',
    'om_sandbox_create_repas_intent','om_sandbox_create_ride_intent',
    'om_sandbox_finalize_authorized_intent','om_sandbox_reference_outcome',
    'om_sandbox_refund_reference_outcome','om_sandbox_request_marche_refund',
    'om_sandbox_request_repas_refund','om_sandbox_submit_refund_reference',
    'ride_confirm_pickup','ride_integrity_check','ride_rate'
  ];
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.proname = ANY(v_names)
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.sig);
  END LOOP;
END $$;

-- Re-grant to authenticated the wrappers the signed-in app legitimately calls.
DO $$
DECLARE
  r record;
  v_auth text[] := ARRAY[
    'wallet_admin_credit','wallet_ensure','wallet_ensure_master','wallet_get_master_balance',
    'wallet_pay_driver_commission','wallet_pay_driver_commission_batch','wallet_pay_merchant',
    'wallet_reverse_driver_commission','wallet_topup_admin_cancel','wallet_topup_admin_mark_expired',
    'merchant_ensure_wallet','merchant_respond_marketplace_offer',
    'marche_complete_offer','marche_create_offer_payment_intent',
    'admin_marche_capture_and_settle_offer','admin_preview_marche_payment_settlement',
    'admin_preview_marche_payment_intents','admin_preview_payment_intents',
    'admin_preview_p2p_transfers','admin_generate_payout_statement','admin_set_statement_status',
    'can_manage_wallet','finance_policy_predecessor',
    'om_payment_submit_sandbox_reference','om_sandbox_admin_list_runs','om_sandbox_admin_metrics',
    'om_sandbox_admin_run_detail','om_sandbox_archive_test_run','om_sandbox_assign_mock_driver',
    'om_sandbox_cancel_ride','om_sandbox_complete_test_run','om_sandbox_create_marche_intent',
    'om_sandbox_create_repas_intent','om_sandbox_create_ride_intent',
    'om_sandbox_finalize_authorized_intent','om_sandbox_reference_outcome',
    'om_sandbox_refund_reference_outcome','om_sandbox_request_marche_refund',
    'om_sandbox_request_repas_refund','om_sandbox_submit_refund_reference',
    'ride_confirm_pickup','ride_integrity_check','ride_rate'
  ];
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.proname = ANY(v_auth)
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
  END LOOP;
END $$;