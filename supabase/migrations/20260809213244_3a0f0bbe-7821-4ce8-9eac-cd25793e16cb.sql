CREATE OR REPLACE FUNCTION public._qa_s2_run()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $qa$
DECLARE out_text text;
BEGIN
  BEGIN
    DECLARE
      r text := E'\n===== SLICE 2 QA (self-rolling-back) =====\n';
      god uuid := '2e547148-69f3-43f6-80f8-264de2d8fa67';
      fin uuid; ops uuid;
      snap_ride jsonb; snap_repas jsonb; snap_env jsonb; snap_ride_after jsonb;
      p record; s record; po record;
      j_before bigint; j_cnt_before bigint; j_after bigint; j_cnt_after bigint;
      ok boolean; n int;
    BEGIN
      SELECT user_id INTO fin FROM public.user_roles WHERE role='client' ORDER BY user_id LIMIT 1;
      SELECT user_id INTO ops FROM public.user_roles WHERE role='client' AND user_id <> fin ORDER BY user_id LIMIT 1;
      INSERT INTO public.user_roles(user_id, role) VALUES (fin,'finance_admin'), (ops,'operations_admin')
        ON CONFLICT DO NOTHING;

      SELECT count(*), COALESCE(sum(amount_gnf),0) INTO j_cnt_before, j_before FROM public.ledger_postings;

      -- 1
      SELECT * INTO p FROM public.finance_policy_current('ride');
      r := r || format('T1 ride 10%%/5%%/10%%/fare: %s (%s/%s/%s/%s)%s',
        CASE WHEN p.commission_bps=1000 AND p.cancel_before_dispatch_bps=500 AND p.cancel_after_dispatch_bps=1000 AND p.cancel_basis='fare' THEN 'PASS' ELSE 'FAIL' END,
        p.commission_bps,p.cancel_before_dispatch_bps,p.cancel_after_dispatch_bps,p.cancel_basis, E'\n');

      -- 2 / 3
      FOR n IN 1..2 LOOP
        SELECT * INTO p FROM public.finance_policy_current(CASE WHEN n=1 THEN 'repas' ELSE 'marche' END);
        r := r || format('T%s %s collateral50/fee1%%/cash100%%: %s (%s,%s,%s,%s,%s)%s', n+1,
          CASE WHEN n=1 THEN 'repas' ELSE 'marche' END,
          CASE WHEN p.collateral_pct_bps=5000 AND p.collateral_basis='merchandise_subtotal'
                 AND p.transaction_fee_bps=100 AND p.fee_basis='merchandise_subtotal'
                 AND p.cash_funding_pct_bps=10000 AND p.commission_bps=0 THEN 'PASS' ELSE 'FAIL' END,
          p.collateral_pct_bps,p.collateral_basis,p.transaction_fee_bps,p.fee_basis,p.cash_funding_pct_bps, E'\n');
      END LOOP;

      -- 4
      SELECT * INTO p FROM public.finance_policy_current('envoyer');
      snap_env := public.finance_policy_snapshot('envoyer', now(), 'chop_pay', 0,0, 20000, 500000, false);
      r := r || format('T4 envoyer 75%%/1%% delivery_fee/max500k/exposure125k: %s (coll=%s basis=%s fee=%s/%s max=%s envelope=%s)%s',
        CASE WHEN p.collateral_pct_bps=7500 AND p.collateral_basis='declared_value' AND p.transaction_fee_bps=100
               AND p.fee_basis='delivery_fee' AND p.max_declared_value_gnf=500000
               AND (snap_env->>'claim_envelope_gnf')::bigint = 125000 THEN 'PASS' ELSE 'FAIL' END,
        p.collateral_pct_bps,p.collateral_basis,p.transaction_fee_bps,p.fee_basis,p.max_declared_value_gnf,
        snap_env->>'claim_envelope_gnf', E'\n');

      -- 5
      SELECT * INTO s FROM public.starter_credit_policy_current();
      r := r || format('T5 starter bonus 25000 restricted: %s (%s, enabled=%s)%s',
        CASE WHEN s.amount_gnf=25000 THEN 'PASS' ELSE 'FAIL' END, s.amount_gnf, s.enabled, E'\n');

      snap_ride  := public.finance_policy_snapshot('ride',  now(), 'chop_pay', 50000,0,0,0,false);
      snap_repas := public.finance_policy_snapshot('repas', now(), 'cash', 0,120000,15000,0,false);

      -- 22 validator
      BEGIN
        PERFORM public.finance_policy_snapshot_validate(snap_ride);
        PERFORM public.finance_policy_snapshot_validate(snap_env);
        ok := true;
      EXCEPTION WHEN OTHERS THEN ok := false; END;
      r := r || format('T22a validator accepts canonical snapshots: %s%s', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, E'\n');
      BEGIN
        PERFORM public.finance_policy_snapshot_validate(snap_ride || '{"transaction_fee_bps":100,"fee_basis":"none"}'::jsonb);
        ok := false;
      EXCEPTION WHEN OTHERS THEN ok := true; END;
      r := r || format('T22b validator rejects ambiguous fee basis: %s%s', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, E'\n');
      BEGIN
        PERFORM public.finance_policy_snapshot_validate(snap_env || '{"collateral_pct_bps":9000,"claims_exposure_pct_bps":2500}'::jsonb);
        ok := false;
      EXCEPTION WHEN OTHERS THEN ok := true; END;
      r := r || format('T22c validator rejects >100%% combined coverage: %s%s', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, E'\n');

      PERFORM set_config('request.jwt.claims', json_build_object('sub', god::text)::text, true);

      -- 6/7
      PERFORM public.admin_set_finance_policy('ride', 1200, 5000, 'none',0,0,0,NULL,0,false,
        now() + interval '1 hour', 'QA future ride 12%', NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL);
      snap_ride_after := public.finance_policy_snapshot('ride', now() + interval '2 hours', 'chop_pay', 50000,0,0,0,false);
      r := r || format('T6 pre-existing ride snapshot unchanged at 10%%: %s (%s)%s',
        CASE WHEN (snap_ride->>'commission_bps')::int=1000 THEN 'PASS' ELSE 'FAIL' END, snap_ride->>'commission_bps', E'\n');
      r := r || format('T7 future snapshot resolves 12%%: %s (%s)%s',
        CASE WHEN (snap_ride_after->>'commission_bps')::int=1200 THEN 'PASS' ELSE 'FAIL' END, snap_ride_after->>'commission_bps', E'\n');
      r := r || format('T13 current resolution still 10%% before effective time: %s%s',
        CASE WHEN (public.finance_policy_current('ride')).commission_bps=1000 THEN 'PASS' ELSE 'FAIL' END, E'\n');

      -- 8
      PERFORM public.admin_set_finance_policy('repas', 0, 5000, 'percentage', 6000, 0,0, 1000000, 0, false,
        now() + interval '1 hour', 'QA repas collateral 60%', 'merchandise_subtotal', 100, 'merchandise_subtotal',
        500, 1000, 'merchandise_plus_delivery', 'merchandise_subtotal', 10000, NULL, NULL, NULL);
      r := r || format('T8 repas snapshot stays 50%% / future is 60%%: %s (%s vs %s)%s',
        CASE WHEN (snap_repas->>'collateral_pct_bps')::int=5000
               AND (public.finance_policy_snapshot('repas', now()+interval '2 hours','cash',0,120000,15000,0,false)->>'collateral_pct_bps')::int=6000
             THEN 'PASS' ELSE 'FAIL' END,
        snap_repas->>'collateral_pct_bps',
        (public.finance_policy_snapshot('repas', now()+interval '2 hours','cash',0,120000,15000,0,false)->>'collateral_pct_bps'), E'\n');

      -- 9/10
      PERFORM public.admin_set_finance_policy('envoyer', 0, 5000, 'percentage', 8000, 0,0, 320000, 0, false,
        now() + interval '1 hour', 'QA envoyer 80% / max 400k', 'declared_value', 100, 'delivery_fee',
        500, 1000, 'delivery_fee', NULL, NULL, NULL, 400000, NULL);
      r := r || format('T9 accepted 500k envoyer snapshot survives cap change: %s (declared=%s cap=%s)%s',
        CASE WHEN (snap_env->>'declared_value_gnf')::bigint=500000 AND (snap_env->>'max_declared_value_gnf')::bigint=500000 THEN 'PASS' ELSE 'FAIL' END,
        snap_env->>'declared_value_gnf', snap_env->>'max_declared_value_gnf', E'\n');
      r := r || format('T10 existing claim envelope unchanged (125000): %s (%s)%s',
        CASE WHEN (snap_env->>'claim_envelope_gnf')::bigint=125000 THEN 'PASS' ELSE 'FAIL' END, snap_env->>'claim_envelope_gnf', E'\n');

      -- 12
      PERFORM public.admin_set_finance_policy('bonbonna', 1000, 5000, 'none',0,0,0,NULL,0,false,
        now() + interval '1 hour', 'QA bonbonna cancel 8/15', NULL,NULL,NULL, 800, 1500, 'fare', NULL,NULL,NULL,NULL,NULL);
      r := r || format('T12 snapshotted cancellation stays 5%%/10%%: %s (%s/%s, basis=%s)%s',
        CASE WHEN (snap_ride->>'cancel_before_dispatch_bps')::int=500 AND (snap_ride->>'cancel_after_dispatch_bps')::int=1000
               AND snap_ride->>'cancel_basis'='fare' THEN 'PASS' ELSE 'FAIL' END,
        snap_ride->>'cancel_before_dispatch_bps', snap_ride->>'cancel_after_dispatch_bps', snap_ride->>'cancel_basis', E'\n');

      -- 14
      BEGIN
        PERFORM public.admin_set_finance_policy('ride', 900, 5000,'none',0,0,0,NULL,0,false,
          now() - interval '2 days','QA backdate',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL);
        ok := false;
      EXCEPTION WHEN OTHERS THEN ok := true; END;
      r := r || format('T14a backdated policy rejected: %s%s', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, E'\n');
      BEGIN
        PERFORM public.admin_set_finance_policy('ride', 900, 5000,'none',0,0,0,NULL,0,false,
          now() + interval '30 minutes','QA overlap before scheduled row',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL);
        ok := false;
      EXCEPTION WHEN OTHERS THEN ok := true; END;
      r := r || format('T14b non-monotonic insert before scheduled row rejected: %s%s', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, E'\n');
      BEGIN
        UPDATE public.finance_policies SET commission_bps = 4200 WHERE mission_type='ride';
        ok := false;
      EXCEPTION WHEN OTHERS THEN ok := true; END;
      r := r || format('T14c historical policy row UPDATE blocked (append-only): %s%s', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, E'\n');

      -- 17
      SELECT count(*) INTO n FROM public.audit_logs
       WHERE action='finance_policy_set' AND actor_user_id=god AND created_at > now() - interval '5 minutes';
      r := r || format('T17 God Admin future rows created with audit evidence: %s (%s audit rows)%s',
        CASE WHEN n >= 4 THEN 'PASS' ELSE 'FAIL' END, n, E'\n');

      -- 19
      SELECT * INTO po FROM public.driver_payout_policy_at(now());
      r := r || format('T19 payout 10k/500k/250k/60s/1-5min/OM-only/passthrough: %s (%s,%s,%s,%s,%s-%s,%s,%s,pending_one=%s,restricted=%s)%s',
        CASE WHEN po.min_request_gnf=10000 AND po.max_request_gnf=500000 AND po.daily_limit_gnf=250000
               AND po.cancel_window_seconds=60 AND po.processing_estimate_min_minutes=1
               AND po.processing_estimate_max_minutes=5 AND po.registered_om_phone_only
               AND po.provider_fee_passthrough AND po.one_pending_request_only
               AND NOT po.restricted_funds_withdrawable THEN 'PASS' ELSE 'FAIL' END,
        po.min_request_gnf, po.max_request_gnf, po.daily_limit_gnf, po.cancel_window_seconds,
        po.processing_estimate_min_minutes, po.processing_estimate_max_minutes,
        po.registered_om_phone_only, po.provider_fee_passthrough, po.one_pending_request_only,
        po.restricted_funds_withdrawable, E'\n');

      -- 15
      PERFORM set_config('request.jwt.claims', json_build_object('sub', fin::text)::text, true);
      BEGIN PERFORM public.admin_set_finance_policy('ride', 1500, 5000,'none',0,0,0,NULL,0,false, now()+interval '3 hours','QA fin',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL); ok := false;
      EXCEPTION WHEN OTHERS THEN ok := true; END;
      r := r || format('T15a finance admin cannot change economics: %s%s', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, E'\n');
      BEGIN PERFORM public.admin_set_feature_flag('chop_pay_enabled', true, 'QA fin'); ok := false;
      EXCEPTION WHEN OTHERS THEN ok := true; END;
      r := r || format('T15b finance admin cannot toggle flags: %s%s', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, E'\n');
      BEGIN PERFORM public.admin_set_starter_credit_policy(50000, true, now()+interval '3 hours','QA fin'); ok := false;
      EXCEPTION WHEN OTHERS THEN ok := true; END;
      r := r || format('T15c finance admin cannot change starter bonus: %s%s', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, E'\n');
      BEGIN PERFORM public.admin_set_payout_policy(1000, 900000, 900000, 60,1,5,true, now()+interval '3 hours','QA fin'); ok := false;
      EXCEPTION WHEN OTHERS THEN ok := true; END;
      r := r || format('T15d finance admin cannot change payout limits: %s%s', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, E'\n');
      BEGIN PERFORM public.admin_set_provider_fee_schedule('orange_money', 150, 0,0,NULL,true, now()+interval '3 hours','QA fin undelegated'); ok := false;
      EXCEPTION WHEN OTHERS THEN ok := true; END;
      r := r || format('T15e finance admin provider fee denied while undelegated: %s%s', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, E'\n');

      PERFORM set_config('request.jwt.claims', json_build_object('sub', god::text)::text, true);
      PERFORM public.admin_set_finance_delegation(true, 'QA delegate');
      PERFORM set_config('request.jwt.claims', json_build_object('sub', fin::text)::text, true);
      BEGIN PERFORM public.admin_set_provider_fee_schedule('orange_money', 150, 0,0,NULL,true, now()+interval '3 hours','QA fin delegated'); ok := true;
      EXCEPTION WHEN OTHERS THEN ok := false; END;
      r := r || format('T15f finance admin provider fee allowed once delegated: %s%s', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, E'\n');

      -- 16
      PERFORM set_config('request.jwt.claims', json_build_object('sub', ops::text)::text, true);
      BEGIN PERFORM public.admin_set_finance_policy('ride', 1500, 5000,'none',0,0,0,NULL,0,false, now()+interval '4 hours','QA ops',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL); ok := false;
      EXCEPTION WHEN OTHERS THEN ok := true; END;
      r := r || format('T16a operations admin cannot change economics: %s%s', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, E'\n');
      BEGIN PERFORM public.admin_set_feature_flag('driver_cashout_enabled', true, 'QA ops'); ok := false;
      EXCEPTION WHEN OTHERS THEN ok := true; END;
      r := r || format('T16b operations admin cannot toggle flags: %s%s', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, E'\n');
      BEGIN PERFORM public.admin_set_provider_fee_schedule('orange_money', 200,0,0,NULL,true, now()+interval '4 hours','QA ops'); ok := false;
      EXCEPTION WHEN OTHERS THEN ok := true; END;
      r := r || format('T16c operations admin cannot change provider fees: %s%s', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, E'\n');

      -- 18
      PERFORM set_config('request.jwt.claims', '', true);
      BEGIN PERFORM public.admin_set_finance_policy('ride', 1500, 5000,'none',0,0,0,NULL,0,false, now()+interval '5 hours','QA anon',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL); ok := false;
      EXCEPTION WHEN OTHERS THEN ok := true; END;
      r := r || format('T18 unauthenticated write rejected: %s%s', CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END, E'\n');

      -- 20
      SELECT count(*) INTO n FROM public.feature_flags
       WHERE enabled = true AND key IN ('chop_pay_enabled','chop_pay_checkout_enabled','chop_pay_p2p_enabled',
         'chop_pay_balance_enabled','chop_pay_ecosystem_spend_enabled','cash_order_funding_enabled',
         'driver_balance_gate_enabled','driver_starter_credit_enabled','driver_cashout_enabled',
         'merchant_wallet_enabled','merchant_om_settlement_enabled','om_payout_reconciliation_enabled',
         'non_ride_transaction_fee_enabled','cancellation_policy_enabled','envoyer_claims_enabled',
         'om_direct_checkout_enabled');
      SELECT enabled INTO ok FROM public.feature_flags WHERE key='om_topup_enabled';
      r := r || format('T20 all financial flags OFF (%s on) and om_topup_enabled ON (%s): %s%s',
        n, ok, CASE WHEN n=0 AND ok THEN 'PASS' ELSE 'FAIL' END, E'\n');

      -- 11 / 21
      SELECT count(*), COALESCE(sum(amount_gnf),0) INTO j_cnt_after, j_after FROM public.ledger_postings;
      r := r || format('T11 posted journals unchanged by policy edits: %s (%s rows / %s GNF)%s',
        CASE WHEN j_cnt_after=j_cnt_before AND j_after=j_before THEN 'PASS' ELSE 'FAIL' END, j_cnt_after, j_after, E'\n');

      r := r || E'T21 rollback: harness raises below, all QA rows discarded\n';
      RAISE EXCEPTION '%', r;
    END;
  EXCEPTION WHEN OTHERS THEN
    out_text := SQLERRM;
  END;
  RETURN out_text;
END; $qa$;
GRANT EXECUTE ON FUNCTION public._qa_s2_run() TO PUBLIC;