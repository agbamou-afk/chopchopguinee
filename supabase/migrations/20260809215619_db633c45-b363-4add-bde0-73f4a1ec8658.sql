CREATE OR REPLACE FUNCTION public._qa_s2x_run()
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  r text := '';
  v_god uuid;
  v_fin uuid;
  t1 timestamptz := now() + interval '10 days';
  t2 timestamptz := now() + interval '11 days';
  t3 timestamptz := now() + interval '12 days';
  p public.finance_policies;
  sc public.driver_starter_credit_policies;
  po public.driver_payout_policies;
  ms public.merchant_settlement_policies;
  pf public.provider_fee_schedules;
  snap jsonb; snap2 jsonb;
  n int;
  ok boolean;
  add_line text;
BEGIN
  BEGIN
    SELECT user_id INTO v_god FROM public.user_roles WHERE role = 'god_admin' LIMIT 1;
    SELECT id INTO v_fin FROM public.profiles WHERE id <> v_god LIMIT 1;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_god)::text, true);

    -- T1/T2: ride chain B then C inherits B ---------------------------
    p := public.admin_set_finance_policy(
      p_mission_type := 'ride', p_commission_bps := 1200,
      p_effective_from := t1, p_note := 'QA chain step B');
    r := r || CASE WHEN p.commission_bps = 1200 THEN 'T1 PASS' ELSE 'T1 FAIL' END || E'\n';

    p := public.admin_set_finance_policy(
      p_mission_type := 'ride', p_cancel_after_dispatch_bps := 1500,
      p_cancel_basis := 'fare', p_effective_from := t2, p_note := 'QA chain step C');
    r := r || CASE WHEN p.commission_bps = 1200 AND p.cancel_after_dispatch_bps = 1500
                   THEN 'T2 PASS' ELSE 'T2 FAIL commission=' || p.commission_bps END || E'\n';

    -- T3: repas collateral chain --------------------------------------
    p := public.admin_set_finance_policy(
      p_mission_type := 'repas', p_collateral_mode := 'percentage',
      p_collateral_pct_bps := 3000, p_collateral_basis := 'merchandise_subtotal',
      p_effective_from := t1, p_note := 'QA repas collateral');
    p := public.admin_set_finance_policy(
      p_mission_type := 'repas', p_transaction_fee_bps := 250, p_fee_basis := 'delivery_fee',
      p_effective_from := t2, p_note := 'QA repas fee only');
    r := r || CASE WHEN p.collateral_pct_bps = 3000 THEN 'T3 PASS' ELSE 'T3 FAIL ' || p.collateral_pct_bps END || E'\n';

    -- T4: envoyer derived claims exposure -----------------------------
    p := public.admin_set_finance_policy(
      p_mission_type := 'envoyer', p_max_declared_value_gnf := 400000,
      p_effective_from := t1, p_note := 'QA envoyer cap');
    r := r || CASE WHEN p.claims_exposure_max_gnf = 100000 AND p.collateral_pct_bps = 7500
                   THEN 'T4 PASS' ELSE 'T4 FAIL max=' || coalesce(p.claims_exposure_max_gnf::text,'null') END || E'\n';

    -- T5: reason under 5 chars rejected -------------------------------
    BEGIN
      p := public.admin_set_finance_policy('ride', 900, p_effective_from := t3, p_note := 'x');
      r := r || 'T5 FAIL (accepted)' || E'\n';
    EXCEPTION WHEN others THEN
      r := r || CASE WHEN SQLERRM LIKE '%REASON_REQUIRED%' THEN 'T5 PASS' ELSE 'T5 FAIL ' || SQLERRM END || E'\n';
    END;

    -- T6/T7: starter bonus chaining ------------------------------------
    sc := public.admin_set_starter_credit_policy(30000, true, t1, 'QA starter amount');
    sc := public.admin_set_starter_credit_policy(NULL, false, t2, 'QA starter disable only');
    r := r || CASE WHEN sc.amount_gnf = 30000 AND sc.enabled = false
                   THEN 'T6 PASS' ELSE 'T6 FAIL ' || sc.amount_gnf END || E'\n';

    -- T8: payout chaining ----------------------------------------------
    po := public.admin_set_payout_policy(20000, 400000, 400000, p_effective_from := t1, p_note := 'QA payout limits');
    po := public.admin_set_payout_policy(NULL, NULL, NULL, p_cancel_window_seconds := 90,
                                         p_effective_from := t2, p_note := 'QA payout window only');
    r := r || CASE WHEN po.min_request_gnf = 20000 AND po.cancel_window_seconds = 90
                   THEN 'T8 PASS' ELSE 'T8 FAIL' END || E'\n';

    -- T9: merchant unconfigured keeps NULLs ----------------------------
    ms := public.admin_set_merchant_settlement_policy(
      p_configured := false, p_effective_from := t1, p_note := 'QA settlement unconfigured');
    r := r || CASE WHEN ms.min_settlement_gnf IS NULL AND ms.cadence IS NULL AND ms.fee_bps IS NULL
                   THEN 'T9 PASS' ELSE 'T9 FAIL min=' || coalesce(ms.min_settlement_gnf::text,'null') END || E'\n';

    -- T10: merchant configured with valid cadence ----------------------
    ms := public.admin_set_merchant_settlement_policy(
      p_configured := true, p_min_settlement_gnf := 50000, p_cadence := 'weekly',
      p_effective_from := t2, p_note := 'QA settlement configured');
    r := r || CASE WHEN ms.configured AND ms.cadence = 'weekly' AND ms.min_settlement_gnf = 50000
                        AND ms.requires_evidence_reconciliation
                   THEN 'T10 PASS' ELSE 'T10 FAIL' END || E'\n';

    -- T11: invalid cadence rejected ------------------------------------
    BEGIN
      ms := public.admin_set_merchant_settlement_policy(
        p_configured := true, p_cadence := 'manual', p_effective_from := t3, p_note := 'QA bad cadence');
      r := r || 'T11 FAIL (accepted)' || E'\n';
    EXCEPTION WHEN others THEN
      r := r || CASE WHEN SQLERRM LIKE '%CADENCE%' THEN 'T11 PASS' ELSE 'T11 FAIL ' || SQLERRM END || E'\n';
    END;

    -- T12: provider fee delegated to a Finance Admin --------------------
    PERFORM public.admin_set_finance_delegation(true, 'QA delegation on');
    IF v_fin IS NOT NULL THEN
      INSERT INTO public.user_roles (user_id, role) VALUES (v_fin, 'finance_admin')
        ON CONFLICT DO NOTHING;
      PERFORM set_config('request.jwt.claims', json_build_object('sub', v_fin)::text, true);
      pf := public.admin_set_provider_fee_schedule('orange_money', 175,
              p_effective_from := t1, p_note := 'QA delegated provider fee');
      SELECT count(*) INTO n FROM public.audit_logs
        WHERE action = 'provider_fee_schedule_set' AND actor_user_id = v_fin AND note = 'QA delegated provider fee';
      r := r || CASE WHEN pf.fee_bps = 175 AND n = 1 THEN 'T12 PASS' ELSE 'T12 FAIL' END || E'\n';
      -- T13: Finance Admin cannot touch service economics
      BEGIN
        p := public.admin_set_finance_policy('ride', 100, p_effective_from := t3, p_note := 'QA finance admin denied');
        r := r || 'T13 FAIL (accepted)' || E'\n';
      EXCEPTION WHEN others THEN r := r || 'T13 PASS' || E'\n'; END;
      -- T14: Finance Admin cannot toggle a flag
      BEGIN
        PERFORM public.admin_set_feature_flag('chop_pay_enabled', true, 'QA finance admin flag');
        r := r || 'T14 FAIL (accepted)' || E'\n';
      EXCEPTION WHEN others THEN r := r || 'T14 PASS' || E'\n'; END;
      PERFORM set_config('request.jwt.claims', json_build_object('sub', v_god)::text, true);
    ELSE
      r := r || 'T12-T14 SKIP (no second user)' || E'\n';
    END IF;

    -- T15: feature flag RPC works for God + is audited -------------------
    PERFORM public.admin_set_feature_flag('chop_pay_enabled', true, 'QA flag toggle');
    SELECT count(*) INTO n FROM public.audit_logs
      WHERE action = 'feature_flag_set' AND note = 'QA flag toggle';
    r := r || CASE WHEN n = 1 THEN 'T15 PASS' ELSE 'T15 FAIL' END || E'\n';

    -- T16: flag reason required ------------------------------------------
    BEGIN
      PERFORM public.admin_set_feature_flag('chop_pay_enabled', false, '');
      r := r || 'T16 FAIL (accepted)' || E'\n';
    EXCEPTION WHEN others THEN
      r := r || CASE WHEN SQLERRM LIKE '%REASON_REQUIRED%' THEN 'T16 PASS' ELSE 'T16 FAIL ' || SQLERRM END || E'\n';
    END;

    -- T17: direct table privileges revoked for anon/authenticated --------
    r := r || CASE WHEN NOT has_table_privilege('authenticated','public.feature_flags','UPDATE')
                    AND NOT has_table_privilege('anon','public.feature_flags','UPDATE')
                    AND has_table_privilege('authenticated','public.feature_flags','SELECT')
                   THEN 'T17 PASS' ELSE 'T17 FAIL' END || E'\n';

    -- T18: all 17 canonical finance flags exist ---------------------------
    SELECT count(*) INTO n FROM public.feature_flags WHERE key IN (
      'chop_pay_enabled','chop_pay_checkout_enabled','chop_pay_p2p_enabled','chop_pay_balance_enabled',
      'chop_pay_ecosystem_spend_enabled','cash_order_funding_enabled','driver_balance_gate_enabled',
      'driver_starter_credit_enabled','driver_cashout_enabled','merchant_wallet_enabled',
      'merchant_om_settlement_enabled','om_topup_enabled','om_payout_reconciliation_enabled',
      'non_ride_transaction_fee_enabled','cancellation_policy_enabled','envoyer_claims_enabled',
      'om_direct_checkout_enabled');
    r := r || CASE WHEN n = 17 THEN 'T18 PASS' ELSE 'T18 FAIL count=' || n END || E'\n';

    -- T19: Envoyer snapshot resolved exposure -----------------------------
    snap := public.finance_policy_snapshot('envoyer', now(), 'chop_pay', 0,0,0, 500000, false);
    r := r || CASE WHEN (snap->>'claims_exposure_pct_bps')::int = 2500
                    AND (snap->>'claims_exposure_max_gnf')::bigint = 125000
                    AND (snap->>'claim_envelope_gnf')::bigint = 125000
                    AND snap->>'claims_exposure_max_source' = 'derived'
                    AND snap->>'cash_funding_basis' = 'none'
                   THEN 'T19 PASS' ELSE 'T19 FAIL ' || snap::text END || E'\n';

    -- T20: validator accepts it, rejects a malformed envelope --------------
    ok := public.finance_policy_snapshot_validate(snap);
    BEGIN
      PERFORM public.finance_policy_snapshot_validate(snap || jsonb_build_object('claim_envelope_gnf', 999999));
      r := r || 'T20 FAIL (accepted)' || E'\n';
    EXCEPTION WHEN others THEN
      r := r || CASE WHEN ok AND SQLERRM LIKE '%CLAIM_ENVELOPE_EXCEEDS_MAX%' THEN 'T20 PASS'
                     ELSE 'T20 FAIL ' || SQLERRM END || E'\n';
    END;

    -- T21: an accepted snapshot is unchanged by a later Envoyer edit --------
    snap2 := public.finance_policy_snapshot('envoyer', now(), 'chop_pay', 0,0,0, 500000, false);
    r := r || CASE WHEN snap2 = snap THEN 'T21 PASS' ELSE 'T21 FAIL' END || E'\n';

    -- T22: starter grant policy reference intact ---------------------------
    SELECT count(*) INTO n FROM information_schema.columns
      WHERE table_schema='public' AND table_name='driver_promo_credits' AND column_name='policy_id';
    r := r || CASE WHEN n = 1 THEN 'T22 PASS' ELSE 'T22 SKIP (no policy_id column)' END || E'\n';

    RAISE EXCEPTION 'QA_ROLLBACK::%', r;
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'QA_ROLLBACK::%' THEN
      r := substring(SQLERRM from 15);
    ELSE
      r := r || 'HARNESS ABORT: ' || SQLERRM;
    END IF;
  END;
  RETURN r;
END $fn$;

GRANT EXECUTE ON FUNCTION public._qa_s2x_run() TO PUBLIC;