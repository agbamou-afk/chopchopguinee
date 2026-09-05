-- G2.D/E — Wire admin_enforce into the real sensitive business RPCs.

CREATE OR REPLACE FUNCTION public._g2_internal_caller()
RETURNS boolean LANGUAGE sql STABLE SET search_path TO 'public'
AS $function$
  SELECT auth.uid() IS NULL AND (
    COALESCE(NULLIF(current_setting('request.jwt.claims', true), ''), '') = ''
    OR COALESCE((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),'') = 'service_role');
$function$;

DO $wire$
DECLARE
  r record;
  v record;
  v_args text; v_ret text; v_names text; v_body text; v_ar boolean; v_call text; v_sql text;
  v_ident text; v_new_ident text;
  m record;
BEGIN
  FOR m IN
    SELECT * FROM (VALUES
      ('admin_adjust_agent_float','finance.wallet.adjust','''agent_wallet''','p_agent_user_id::text',$$jsonb_build_object('delta_gnf',p_delta_gnf,'currency','GNF')$$,'wallet'),
      ('admin_reverse_starter_credit','finance.wallet.adjust','''driver''','p_driver::text','''{}''::jsonb','wallet'),
      ('admin_backfill_missing_driver_earnings','finance.wallet.credit','''batch''','NULL',$$jsonb_build_object('dry_run',p_dry_run,'limit',p_limit)$$,'wallet'),
      ('admin_manual_om_credit','finance.wallet.credit','''payment_provider_event''','p_event_id::text',$$jsonb_build_object('topup_request_id',p_topup_request_id)$$,'payments'),
      ('admin_retry_om_credit','finance.wallet.credit','''payment_provider_event''','p_event_id::text','''{}''::jsonb','payments'),
      ('admin_record_om_receipt','finance.topup.manage','''om_receipt''','p_provider_transaction_id',$$jsonb_build_object('amount_gnf',p_amount_gnf,'currency','GNF')$$,'payments'),
      ('admin_mark_om_conflict','finance.topup.manage','''payment_provider_event''','p_event_id::text','''{}''::jsonb','payments'),
      ('admin_set_finance_policy','finance.policy.change','''finance_policy''','p_mission_type',$$jsonb_build_object('commission_bps',p_commission_bps,'transaction_fee_bps',p_transaction_fee_bps,'merchant_platform_fee_bps',p_merchant_platform_fee_bps)$$,'settings'),
      ('admin_set_payout_policy','finance.policy.change','''payout_policy''','NULL',$$jsonb_build_object('min',p_min_request_gnf,'max',p_max_request_gnf,'daily',p_daily_limit_gnf)$$,'settings'),
      ('admin_set_merchant_settlement_policy','finance.policy.change','''merchant_settlement_policy''','NULL',$$jsonb_build_object('configured',p_configured,'min',p_min_settlement_gnf,'max',p_max_settlement_gnf,'fee_bps',p_fee_bps)$$,'settings'),
      ('admin_set_provider_fee_schedule','finance.policy.change','''provider_fee_schedule''','p_provider',$$jsonb_build_object('fee_bps',p_fee_bps,'fee_fixed_gnf',p_fee_fixed_gnf)$$,'settings'),
      ('admin_set_starter_credit_policy','finance.policy.change','''starter_credit_policy''','NULL',$$jsonb_build_object('amount_gnf',p_amount_gnf,'enabled',p_enabled)$$,'settings'),
      ('admin_set_finance_delegation','finance.policy.change','''finance_delegation''','NULL',$$jsonb_build_object('provider_fee_to_finance_admin',p_provider_fee_to_finance_admin)$$,'settings'),
      ('admin_marche_capture_and_settle_offer','finance.payouts.manage','''marketplace_offer''','p_offer_id::text','''{}''::jsonb','payments'),
      ('admin_repas_capture_and_settle_order','finance.payouts.manage','''food_order''','p_food_order_id::text','''{}''::jsonb','payments'),
      ('admin_set_statement_status','finance.payouts.manage','''payout_statement''','p_statement::text',$$jsonb_build_object('status',p_status)$$,'payments'),
      ('admin_generate_payout_statement','finance.payouts.manage','''driver_group''','p_group::text',$$jsonb_build_object('from',p_from,'to',p_to)$$,'payments'),
      ('payout_reject_release','finance.payouts.manage','''payout_order''','p_payout_order_id::text','''{}''::jsonb','payments'),
      ('driver_cashout_reject_request','finance.payouts.manage','''driver_cashout_request''','p_id::text','''{}''::jsonb','payments'),
      ('driver_cashout_mark_paid','finance.payout.confirm','''driver_cashout_request''','p_id::text',$$jsonb_build_object('provider_reference',p_provider_reference)$$,'payments'),
      ('admin_cash_order_dispute_resolve','finance.dispute.resolve','p_source_module','p_source_id::text',$$jsonb_build_object('outcome',p_outcome)$$,'payments'),
      ('admin_chop_pay_dispute_resolve','finance.dispute.resolve','p_source_module','p_source_id::text',$$jsonb_build_object('outcome',p_outcome)$$,'payments'),
      ('admin_chop_pay_cancel','finance.dispute.resolve','p_source_module','p_source_id::text',$$jsonb_build_object('responsible_party',p_responsible_party)$$,'payments'),
      ('admin_package_claim_resolve','finance.dispute.resolve','''package''','p_package_id::text',$$jsonb_build_object('outcome',p_outcome,'pay_customer_gnf',p_pay_customer_gnf)$$,'payments'),
      ('admin_package_claim_set_documented_value','finance.dispute.resolve','''package''','p_package_id::text',$$jsonb_build_object('documented_actual_value_gnf',p_documented_actual_value_gnf)$$,'payments'),
      ('admin_anonymize_user','governance.account.anonymize','''user''','_target::text','''{}''::jsonb','admins'),
      ('admin_professional_offboard','governance.professional.offboard','''user''','_target::text','''{}''::jsonb','admins'),
      ('admin_account_closure_reconcile','governance.account.close','''user''','_target::text','''{}''::jsonb','admins'),
      ('admin_staff_role_grant','governance.roles.assign','''user''','_target::text',$$jsonb_build_object('role',_role)$$,'admins'),
      ('admin_staff_role_revoke','governance.roles.assign','''user''','_target::text',$$jsonb_build_object('role',_role)$$,'admins'),
      ('admin_governance_set_status','governance.staff.manage','''user''','_target::text',$$jsonb_build_object('status',_status)$$,'admins'),
      ('admin_set_repas_promotion','governance.pricing.change','''repas_promotion''','p_name',$$jsonb_build_object('scope',p_fulfillment_scope,'fee_override',p_delivery_fee_override_gnf,'discount',p_delivery_discount_gnf)$$,'pricing'),
      ('admin_disable_repas_promotion','governance.pricing.change','''repas_promotion''','p_id::text','''{}''::jsonb','pricing')
    ) AS t(fn, cap, ttype, tid, material, module)
  LOOP
    SELECT p.oid, pg_get_function_arguments(p.oid) AS args, pg_get_function_result(p.oid) AS ret,
           array_to_string(p.proargnames[1:p.pronargs], ', ') AS names
      INTO v
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname = m.fn;
    IF v.oid IS NULL THEN RAISE EXCEPTION 'G2 wiring target missing: %', m.fn; END IF;

    SELECT EXISTS (SELECT 1 FROM public.admin_capability_grants g
                    WHERE g.capability = m.cap AND g.mode='approval_required') INTO v_ar;

    v_ident := pg_get_function_identity_arguments(v.oid);
    v_new_ident := v_ident || CASE WHEN v_ar THEN ', uuid' ELSE '' END;

    EXECUTE format('ALTER FUNCTION public.%I(%s) RENAME TO %I', m.fn, v_ident, m.fn || '__g2');

    v_args := v.args || CASE WHEN v_ar THEN ', _g2_approval uuid DEFAULT NULL' ELSE '' END;
    v_call := format('public.%I(%s)', m.fn || '__g2', v.names);
    v_ret  := CASE WHEN v.ret = 'void' THEN format('PERFORM %s; RETURN;', v_call)
                   ELSE format('RETURN %s;', v_call) END;
    v_body := format($b$
BEGIN
  IF NOT public._g2_internal_caller() THEN
    PERFORM public.admin_enforce(%L, %s, %s, %s, %s, %L);
  END IF;
  %s
END;$b$, m.cap, m.ttype, m.tid, m.material,
        CASE WHEN v_ar THEN '_g2_approval' ELSE 'NULL::uuid' END, m.module, v_ret);

    v_sql := format(
      'CREATE OR REPLACE FUNCTION public.%I(%s) RETURNS %s LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''public'' AS $g2body$%s$g2body$',
      m.fn, v_args, v.ret, v_body);
    EXECUTE v_sql;

    EXECUTE format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC, anon, authenticated',
                   m.fn || '__g2', v_ident);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO service_role',
                   m.fn || '__g2', v_ident);
    EXECUTE format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC, anon', m.fn, v_new_ident);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated, service_role', m.fn, v_new_ident);
  END LOOP;

  -- Re-point existing internal engine/QA callers to the inner functions so frozen
  -- Repas/Marché/Node5/Slice-13 behaviour is byte-for-byte preserved.
  FOR r IN
    SELECT DISTINCT c.oid, c.proname
      FROM pg_proc c JOIN pg_namespace cn ON cn.oid=c.pronamespace
     WHERE cn.nspname='public'
       AND c.proname NOT LIKE '%\_\_g2'
       AND c.prolang = (SELECT oid FROM pg_language WHERE lanname='plpgsql')
       AND EXISTS (
         SELECT 1 FROM unnest(ARRAY['admin_cash_order_dispute_resolve','admin_chop_pay_dispute_resolve',
           'admin_chop_pay_cancel','admin_package_claim_resolve','admin_package_claim_set_documented_value',
           'admin_anonymize_user','admin_professional_offboard','admin_account_closure_reconcile',
           'admin_staff_role_grant','admin_staff_role_revoke','admin_governance_set_status',
           'admin_set_finance_policy','admin_set_repas_promotion','admin_disable_repas_promotion',
           'admin_manual_om_credit','admin_retry_om_credit','admin_record_om_receipt']) AS x(t)
          WHERE c.prosrc LIKE '%'||x.t||'(%')
  LOOP
    v_sql := pg_get_functiondef(r.oid);
    v_sql := replace(v_sql,'admin_cash_order_dispute_resolve(','admin_cash_order_dispute_resolve__g2(');
    v_sql := replace(v_sql,'admin_chop_pay_dispute_resolve(','admin_chop_pay_dispute_resolve__g2(');
    v_sql := replace(v_sql,'admin_chop_pay_cancel(','admin_chop_pay_cancel__g2(');
    v_sql := replace(v_sql,'admin_package_claim_resolve(','admin_package_claim_resolve__g2(');
    v_sql := replace(v_sql,'admin_package_claim_set_documented_value(','admin_package_claim_set_documented_value__g2(');
    v_sql := replace(v_sql,'admin_anonymize_user(','admin_anonymize_user__g2(');
    v_sql := replace(v_sql,'admin_professional_offboard(','admin_professional_offboard__g2(');
    v_sql := replace(v_sql,'admin_account_closure_reconcile(','admin_account_closure_reconcile__g2(');
    v_sql := replace(v_sql,'admin_staff_role_grant(','admin_staff_role_grant__g2(');
    v_sql := replace(v_sql,'admin_staff_role_revoke(','admin_staff_role_revoke__g2(');
    v_sql := replace(v_sql,'admin_governance_set_status(','admin_governance_set_status__g2(');
    v_sql := replace(v_sql,'admin_set_finance_policy(','admin_set_finance_policy__g2(');
    v_sql := replace(v_sql,'admin_set_repas_promotion(','admin_set_repas_promotion__g2(');
    v_sql := replace(v_sql,'admin_disable_repas_promotion(','admin_disable_repas_promotion__g2(');
    v_sql := replace(v_sql,'admin_manual_om_credit(','admin_manual_om_credit__g2(');
    v_sql := replace(v_sql,'admin_retry_om_credit(','admin_retry_om_credit__g2(');
    v_sql := replace(v_sql,'admin_record_om_receipt(','admin_record_om_receipt__g2(');
    -- never rewrite the caller's own header
    v_sql := replace(v_sql, 'FUNCTION public.'||r.proname||'__g2(', 'FUNCTION public.'||r.proname||'(');
    EXECUTE v_sql;
  END LOOP;
END
$wire$;

-- Feature-flag authority split by flag class (no flag state is changed).
CREATE OR REPLACE FUNCTION public.feature_flag_is_financial(_key text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $function$
  SELECT _key ~ '(payout|cashout|settlement|payment|wallet|topup|top_up|refund|treasury|ledger|chop_pay|choppay|om_|orange_money|money|finance|commission|collateral|fee|credit|debit|cash)';
$function$;

ALTER FUNCTION public.admin_set_feature_flag(text, boolean, text) RENAME TO admin_set_feature_flag__g2;

CREATE OR REPLACE FUNCTION public.admin_set_feature_flag(
  p_key text, p_enabled boolean, p_note text DEFAULT NULL::text, _g2_approval uuid DEFAULT NULL)
RETURNS feature_flags LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public._g2_internal_caller() THEN
    IF public.feature_flag_is_financial(p_key) THEN
      PERFORM public.admin_enforce('finance.flags.payment','feature_flag',p_key,
              jsonb_build_object('enabled',p_enabled), _g2_approval, 'flags');
    ELSE
      PERFORM public.admin_enforce('governance.flags.manage','feature_flag',p_key,
              jsonb_build_object('enabled',p_enabled), NULL::uuid, 'flags');
    END IF;
  END IF;
  RETURN public.admin_set_feature_flag__g2(p_key, p_enabled, p_note);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_set_feature_flag__g2(text, boolean, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_feature_flag__g2(text, boolean, text) TO service_role;
REVOKE ALL ON FUNCTION public.admin_set_feature_flag(text, boolean, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_feature_flag(text, boolean, text, uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.feature_flag_is_financial(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.feature_flag_is_financial(text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public._g2_internal_caller() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._g2_internal_caller() TO authenticated, service_role;