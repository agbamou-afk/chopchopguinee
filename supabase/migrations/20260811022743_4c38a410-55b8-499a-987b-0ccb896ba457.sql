CREATE TABLE IF NOT EXISTS public._qa_s8_results (
  id bigserial PRIMARY KEY,
  section text NOT NULL,
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public._qa_s8_results ENABLE ROW LEVEL SECURITY;
GRANT ALL ON public._qa_s8_results TO service_role;

CREATE OR REPLACE FUNCTION public._qa_s8_ok(p_case text, p_pass boolean, p_detail jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $fn$ SELECT jsonb_build_array(jsonb_build_object('case',p_case,'pass',p_pass,'detail',p_detail)) $fn$;

CREATE OR REPLACE FUNCTION public._qa_s8_run()
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'public'
AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  ride_snap jsonb; repas_snap jsonb; envoyer_snap jsonb; marche_snap jsonb;
  new_snap jsonb;
  c jsonb; c2 jsonb;
  cust uuid := gen_random_uuid();
  wid uuid; master_before bigint; master_after bigint;
  d jsonb; d2 jsonb; debt_id uuid; rep jsonb; rep2 jsonb;
  acl text; n int; z bigint;
BEGIN
  SELECT balance_gnf INTO master_before FROM public.wallets WHERE party_type='master' LIMIT 1;

  ride_snap    := public.finance_policy_snapshot('ride',      now(), 'cash', 100000,0,0,0,false);
  repas_snap   := public.finance_policy_snapshot('repas',     now(), 'cash', 0,150000,25000,0,false);
  marche_snap  := public.finance_policy_snapshot('marche',    now(), 'cash', 0,150000,25000,0,false);
  envoyer_snap := public.finance_policy_snapshot('envoyer',   now(), 'cash', 0,0,25000,500000,false);

  -- ================= B. RIDE / BONBONNA =================
  c := public._cancellation_compute(ride_snap,'before_dispatch',100000,0,0,'customer');
  r := r || public._qa_s8_ok('B1 ride pre-dispatch 100000 -> 5000',
        (c->>'fee_gnf')::bigint = 5000 AND (c->>'fee_bps')::int = 500, c);
  c := public._cancellation_compute(ride_snap,'after_dispatch',100000,0,0,'customer');
  r := r || public._qa_s8_ok('B2 ride post-dispatch 100000 -> 10000',
        (c->>'fee_gnf')::bigint = 10000 AND (c->>'fee_bps')::int = 1000, c);
  c := public._cancellation_compute(ride_snap,'after_dispatch',100000,0,0,'driver');
  r := r || public._qa_s8_ok('B3 driver-caused -> 0', (c->>'fee_gnf')::bigint = 0, c);
  c := public._cancellation_compute(ride_snap,'after_dispatch',100000,0,0,'platform');
  r := r || public._qa_s8_ok('B4 platform-caused -> 0', (c->>'fee_gnf')::bigint = 0, c);
  c := public._cancellation_compute(ride_snap,'after_dispatch',100000,0,0,'provider');
  r := r || public._qa_s8_ok('B5 provider-caused -> 0', (c->>'fee_gnf')::bigint = 0, c);
  r := r || public._qa_s8_ok('B6 ride basis kind is fare', ride_snap->>'cancel_basis' = 'fare',
        jsonb_build_object('kind', ride_snap->>'cancel_basis'));

  -- ================= C/D. REPAS + MARCHE =================
  c := public._cancellation_compute(repas_snap,'before_dispatch',0,150000,25000,'customer');
  r := r || public._qa_s8_ok('C1 repas basis 175000, pre-dispatch -> 8750',
        (c->>'basis_gnf')::bigint = 175000 AND (c->>'fee_gnf')::bigint = 8750, c);
  c := public._cancellation_compute(repas_snap,'after_dispatch',0,150000,25000,'customer');
  r := r || public._qa_s8_ok('C2 repas post-dispatch -> 17500', (c->>'fee_gnf')::bigint = 17500, c);
  c := public._cancellation_compute(repas_snap,'after_dispatch',0,150000,25000,'merchant');
  r := r || public._qa_s8_ok('C3 merchant rejection -> 0 fee', (c->>'fee_gnf')::bigint = 0, c);
  c := public._cancellation_compute(marche_snap,'before_dispatch',0,150000,25000,'customer');
  r := r || public._qa_s8_ok('D1 marche basis 175000 -> 8750',
        (c->>'basis_gnf')::bigint = 175000 AND (c->>'fee_gnf')::bigint = 8750, c);
  c := public._cancellation_compute(marche_snap,'after_dispatch',0,150000,25000,'customer');
  r := r || public._qa_s8_ok('D2 marche post-dispatch -> 17500', (c->>'fee_gnf')::bigint = 17500, c);
  r := r || public._qa_s8_ok('D3 transaction fee excluded from cancellation basis',
        (public._cancellation_compute(repas_snap,'before_dispatch',0,150000,25000,'customer')->>'basis_gnf')::bigint
          = 150000 + 25000, jsonb_build_object('note','basis is merchandise+delivery only'));

  -- ================= E. ENVOYER =================
  c := public._cancellation_compute(envoyer_snap,'before_dispatch',0,0,25000,'customer');
  r := r || public._qa_s8_ok('E1 envoyer basis = delivery fee 25000',
        (c->>'basis_gnf')::bigint = 25000 AND (c->>'cancel_basis_kind') = 'delivery_fee', c);
  r := r || public._qa_s8_ok('E2 envoyer pre-dispatch -> 1250', (c->>'fee_gnf')::bigint = 1250, c);
  c := public._cancellation_compute(envoyer_snap,'after_dispatch',0,0,25000,'customer');
  r := r || public._qa_s8_ok('E3 envoyer post-dispatch -> 2500', (c->>'fee_gnf')::bigint = 2500, c);
  -- declared value cannot leak into the basis
  c2 := public._cancellation_compute(envoyer_snap,'after_dispatch',500000,500000,25000,'customer');
  r := r || public._qa_s8_ok('E4 declared 500000 cannot change envoyer fee',
        (c2->>'fee_gnf')::bigint = 2500 AND (c2->>'basis_gnf')::bigint = 25000, c2);
  r := r || public._qa_s8_ok('E5 envoyer never bills 500000 or 525000',
        (c2->>'basis_gnf')::bigint NOT IN (500000, 525000), c2);

  -- ================= G. SNAPSHOT IMMUTABILITY =================
  BEGIN
    INSERT INTO public.finance_policies (mission_type, commission_bps, cancel_before_dispatch_bps,
      cancel_after_dispatch_bps, cancel_basis, effective_from)
    SELECT mission_type, commission_bps, 2500, 4000, cancel_basis, now() + interval '1 second'
      FROM public.finance_policies WHERE mission_type = 'ride'
      ORDER BY effective_from DESC LIMIT 1;

    PERFORM pg_sleep(1.2);
    new_snap := public.finance_policy_snapshot('ride', now(), 'cash', 100000,0,0,0,false);

    c := public._cancellation_compute(ride_snap,'before_dispatch',100000,0,0,'customer');
    r := r || public._qa_s8_ok('G1 accepted transaction keeps frozen 5% after policy change',
          (c->>'fee_gnf')::bigint = 5000 AND (c->>'fee_bps')::int = 500, c);
    c := public._cancellation_compute(ride_snap,'after_dispatch',100000,0,0,'customer');
    r := r || public._qa_s8_ok('G2 accepted transaction keeps frozen 10% after policy change',
          (c->>'fee_gnf')::bigint = 10000, c);
    c := public._cancellation_compute(new_snap,'before_dispatch',100000,0,0,'customer');
    r := r || public._qa_s8_ok('G3 new transaction uses new 25% policy',
          (c->>'fee_gnf')::bigint = 25000 AND (c->>'fee_bps')::int = 2500, c);
    c := public._cancellation_compute(new_snap,'after_dispatch',100000,0,0,'customer');
    r := r || public._qa_s8_ok('G4 new transaction uses new 40% policy',
          (c->>'fee_gnf')::bigint = 40000, c);
    r := r || public._qa_s8_ok('G5 quote and execute bind to the same calculator',
          (SELECT count(*) FROM pg_proc p JOIN pg_namespace nn ON nn.oid=p.pronamespace
            WHERE nn.nspname='public' AND p.proname='_cancellation_compute') = 1,
          jsonb_build_object('single_calculator', true));
    RAISE EXCEPTION 'QA_S8_ROLLBACK_G';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S8_ROLLBACK_G' THEN
      r := r || public._qa_s8_ok('G error', false, jsonb_build_object('err', SQLERRM));
    END IF;
  END;

  -- ================= F. DEBT / RESTRICTION / REPAYMENT =================
  BEGIN
    INSERT INTO public.wallets (owner_user_id, party_type, balance_gnf, held_gnf, status)
    VALUES (cust, 'client', 6000, 0, 'active') RETURNING id INTO wid;

    d := public._customer_cancellation_debt_create_internal(
           'ride', gen_random_uuid(), cust, 'ride', 'after_dispatch',
           100000, 0, 0, false, 'customer', false, ride_snap, cust);
    debt_id := (d->>'debt_id')::uuid;
    r := r || public._qa_s8_ok('F1 cash cancellation creates 10000 debt exactly once',
          d->>'status' = 'charged' AND (d->>'amount_gnf')::bigint = 10000, d);

    SELECT count(*) INTO n FROM public.customer_cancellation_debts WHERE id = debt_id;
    r := r || public._qa_s8_ok('F2 exactly one debt row', n = 1, jsonb_build_object('rows', n));

    d2 := public._customer_cancellation_debt_create_internal(
           'ride', (SELECT source_id FROM public.customer_cancellation_debts WHERE id = debt_id),
           cust, 'ride', 'after_dispatch', 100000, 0, 0, false, 'customer', false, ride_snap, cust);
    r := r || public._qa_s8_ok('F3 replay is inert (already_exists)', d2->>'status' = 'already_exists', d2);

    d2 := public._customer_cancellation_debt_create_internal(
           'ride', gen_random_uuid(), cust, 'ride', 'after_dispatch',
           100000, 0, 0, false, 'driver', false, ride_snap, cust);
    r := r || public._qa_s8_ok('F4 driver-caused creates zero debt', d2->>'status' = 'exempt', d2);

    r := r || public._qa_s8_ok('F5 outstanding debt restricts new cash exposure',
          public._customer_cash_restricted(cust) = true, jsonb_build_object('restricted', true));

    -- partial repayment (wallet has 6000 available, owes 10000)
    rep := public._customer_cancellation_debt_settle_internal(debt_id, 4000, cust);
    r := r || public._qa_s8_ok('F6 partial repayment collects exactly 4000',
          (rep->>'collected_gnf')::bigint = 4000 AND (rep->>'outstanding_gnf')::bigint = 6000, rep);
    r := r || public._qa_s8_ok('F7 restriction persists while debt outstanding',
          public._customer_cash_restricted(cust) = true, jsonb_build_object('restricted', true));

    -- cannot over-collect: only 2000 left in wallet, owes 6000
    rep2 := public._customer_cancellation_debt_settle_internal(debt_id, 999999, cust);
    r := r || public._qa_s8_ok('F8 cannot over-collect beyond available funds',
          (rep2->>'collected_gnf')::bigint = 2000, rep2);
    SELECT amount_gnf - paid_gnf - waived_gnf INTO z
      FROM public.customer_cancellation_debts WHERE id = debt_id;
    r := r || public._qa_s8_ok('F9 outstanding never negative and exact', z = 4000,
          jsonb_build_object('outstanding', z));

    -- fund and fully repay
    UPDATE public.wallets SET balance_gnf = balance_gnf + 4000 WHERE id = wid;
    rep2 := public._customer_cancellation_debt_settle_internal(debt_id, NULL, cust);
    r := r || public._qa_s8_ok('F10 full repayment clears the debt',
          (rep2->>'fully_paid')::boolean = true, rep2);
    r := r || public._qa_s8_ok('F11 full repayment restores cash eligibility automatically',
          public._customer_cash_restricted(cust) = false, jsonb_build_object('restricted', false));
    rep2 := public._customer_cancellation_debt_settle_internal(debt_id, 1000, cust);
    r := r || public._qa_s8_ok('F12 repayment after settlement is inert',
          rep2->>'status' = 'not_outstanding', rep2);
    SELECT balance_gnf INTO z FROM public.wallets WHERE id = wid;
    r := r || public._qa_s8_ok('F13 customer wallet debited exactly 10000', z = 0,
          jsonb_build_object('balance', z));

    -- waiver is distinct from payment
    d2 := public._customer_cancellation_debt_create_internal(
           'ride', gen_random_uuid(), cust, 'ride', 'before_dispatch',
           100000, 0, 0, false, 'customer', false, ride_snap, cust);
    rep2 := public.customer_cancellation_debt_waive((d2->>'debt_id')::uuid, 'QA slice 8 waiver reason');
    r := r || public._qa_s8_ok('F14 waiver records waived_gnf not paid_gnf',
          (SELECT waived_gnf = 5000 AND paid_gnf = 0 AND state='waived'
             FROM public.customer_cancellation_debts WHERE id = (d2->>'debt_id')::uuid), rep2);

    -- preparation lock
    BEGIN
      PERFORM public._customer_cancellation_debt_create_internal(
        'repas', gen_random_uuid(), cust, 'repas', 'after_dispatch',
        0, 150000, 25000, true, 'customer', false, repas_snap, cust);
      r := r || public._qa_s8_ok('C4 preparation lock denies cancellation', false,
            jsonb_build_object('note','no exception raised'));
    EXCEPTION WHEN OTHERS THEN
      r := r || public._qa_s8_ok('C4 preparation lock denies cancellation',
            SQLERRM = 'REPAS_CANCELLATION_LOCKED', jsonb_build_object('err', SQLERRM));
    END;

    -- H. journals zero-sum and source-linked
    SELECT count(*) INTO n FROM public.ledger_journals j
     WHERE j.event_type IN ('cancellation_fee_charged','cancellation_fee_collected','cancellation_fee_waived')
       AND j.created_at > now() - interval '5 minutes';
    r := r || public._qa_s8_ok('H1 cancellation journals written', n >= 5, jsonb_build_object('journals', n));
    SELECT count(*) INTO n FROM (
      SELECT j.id FROM public.ledger_journals j
        JOIN public.ledger_postings p ON p.journal_id = j.id
       WHERE j.created_at > now() - interval '5 minutes'
       GROUP BY j.id HAVING SUM(p.amount_gnf) <> 0) x;
    r := r || public._qa_s8_ok('H2 every journal is zero-sum', n = 0, jsonb_build_object('unbalanced', n));
    SELECT count(*) INTO n FROM public.ledger_journals
     WHERE event_type = 'cancellation_fee_charged'
       AND source_id = (SELECT source_id FROM public.customer_cancellation_debts WHERE id = debt_id);
    r := r || public._qa_s8_ok('H3 no duplicate platform cancellation revenue', n = 1,
          jsonb_build_object('charge_journals', n));

    RAISE EXCEPTION 'QA_S8_ROLLBACK_F';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S8_ROLLBACK_F' THEN
      r := r || public._qa_s8_ok('F error', false, jsonb_build_object('err', SQLERRM));
    END IF;
  END;

  -- ================= I. PRIVILEGES =================
  SELECT COALESCE(array_to_string(proacl,','),'DEFAULT') INTO acl
    FROM pg_proc p JOIN pg_namespace nn ON nn.oid=p.pronamespace
   WHERE nn.nspname='public' AND p.proname='_cancellation_compute';
  r := r || public._qa_s8_ok('I1 calculator is service-role only',
        acl NOT LIKE '%anon=%' AND acl NOT LIKE '%authenticated=%', jsonb_build_object('acl', acl));

  SELECT COALESCE(array_to_string(proacl,','),'DEFAULT') INTO acl
    FROM pg_proc p JOIN pg_namespace nn ON nn.oid=p.pronamespace
   WHERE nn.nspname='public' AND p.proname='cancellation_quote';
  r := r || public._qa_s8_ok('I2 quote denied to anon, allowed to authenticated',
        acl NOT LIKE '%anon=%' AND acl LIKE '%authenticated=%', jsonb_build_object('acl', acl));

  SELECT COALESCE(array_to_string(proacl,','),'DEFAULT') INTO acl
    FROM pg_proc p JOIN pg_namespace nn ON nn.oid=p.pronamespace
   WHERE nn.nspname='public' AND p.proname='customer_cancellation_debt_repay';
  r := r || public._qa_s8_ok('I3 repayment denied to anon',
        acl NOT LIKE '%anon=%' AND acl LIKE '%authenticated=%', jsonb_build_object('acl', acl));

  SELECT COALESCE(array_to_string(proacl,','),'DEFAULT') INTO acl
    FROM pg_proc p JOIN pg_namespace nn ON nn.oid=p.pronamespace
   WHERE nn.nspname='public' AND p.proname='customer_cancellation_debt_waive';
  r := r || public._qa_s8_ok('I4 waiver is service-role/finance only, never anon or authenticated',
        acl NOT LIKE '%anon=%' AND acl NOT LIKE '%authenticated=%', jsonb_build_object('acl', acl));

  SELECT COALESCE(array_to_string(proacl,','),'DEFAULT') INTO acl
    FROM pg_proc p JOIN pg_namespace nn ON nn.oid=p.pronamespace
   WHERE nn.nspname='public' AND p.proname='customer_cancellation_debt_collect';
  r := r || public._qa_s8_ok('I5 collection primitive closed to authenticated',
        acl NOT LIKE '%anon=%' AND acl NOT LIKE '%authenticated=%', jsonb_build_object('acl', acl));

  SELECT COALESCE(array_to_string(proacl,','),'DEFAULT') INTO acl
    FROM pg_proc p JOIN pg_namespace nn ON nn.oid=p.pronamespace
   WHERE nn.nspname='public' AND p.proname='_customer_cancellation_debt_settle_internal';
  r := r || public._qa_s8_ok('I6 settle internal is service-role only',
        acl NOT LIKE '%anon=%' AND acl NOT LIKE '%authenticated=%', jsonb_build_object('acl', acl));

  SELECT COALESCE(array_to_string(proacl,','),'DEFAULT') INTO acl
    FROM pg_proc p JOIN pg_namespace nn ON nn.oid=p.pronamespace
   WHERE nn.nspname='public' AND p.proname='_package_cancel_release_internal';
  r := r || public._qa_s8_ok('I7 package release internal is service-role only',
        acl NOT LIKE '%anon=%' AND acl NOT LIKE '%authenticated=%', jsonb_build_object('acl', acl));

  SELECT COALESCE(array_to_string(proacl,','),'DEFAULT') INTO acl
    FROM pg_proc p JOIN pg_namespace nn ON nn.oid=p.pronamespace
   WHERE nn.nspname='public' AND p.proname='_customer_cash_restricted';
  r := r || public._qa_s8_ok('I8 restriction helper is service-role only',
        acl NOT LIKE '%anon=%' AND acl NOT LIKE '%authenticated=%', jsonb_build_object('acl', acl));

  -- Slice 3-7 privilege regression spot check
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace nn ON nn.oid=p.pronamespace
   WHERE nn.nspname='public'
     AND p.proname IN ('driver_funding_allocate','_promo_consume','driver_promo_balance',
                       '_ledger_post','_ledger_reverse','chop_pay_customer_capture',
                       'merchant_payable_fund','claims_reserve_allocate')
     AND COALESCE(array_to_string(p.proacl,','),'DEFAULT') LIKE '%authenticated=%';
  r := r || public._qa_s8_ok('I9 no Slice 3-7 privilege regression on raw primitives',
        n = 0, jsonb_build_object('leaked', n));

  -- ================= A. QUOTE = EXECUTION (structural) =================
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace nn ON nn.oid=p.pronamespace
   WHERE nn.nspname='public'
     AND p.proname IN ('cancellation_quote','ride_cancel','_chop_pay_cancel_internal',
                       '_customer_cancellation_debt_create_internal','_package_cancel_release_internal',
                       'package_delivery_cancel')
     AND pg_get_functiondef(p.oid) LIKE '%_cancellation_compute%';
  r := r || public._qa_s8_ok('A1 all six cancellation paths call the one calculator',
        n = 6, jsonb_build_object('paths_wired', n));

  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace nn ON nn.oid=p.pronamespace
   WHERE nn.nspname='public' AND p.proname IN ('package_delivery_cancel','package_delivery_cancel_preview')
     AND pg_get_functiondef(p.oid) LIKE '%0.10%';
  r := r || public._qa_s8_ok('A2 hard-coded 10%% envoyer formula removed', n = 0,
        jsonb_build_object('remaining', n));

  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace nn ON nn.oid=p.pronamespace
   WHERE nn.nspname='public' AND p.proname='package_delivery_cancel_preview'
     AND pg_get_functiondef(p.oid) LIKE '%cancellation_quote%';
  r := r || public._qa_s8_ok('A3 envoyer preview proxies the canonical quote', n = 1,
        jsonb_build_object('proxied', n));

  -- ================= J. POSTURE =================
  SELECT balance_gnf INTO master_after FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || public._qa_s8_ok('J1 master wallet unchanged by harness',
        master_before = master_after,
        jsonb_build_object('before', master_before, 'after', master_after));
  SELECT count(*) INTO n FROM public.customer_cancellation_debts WHERE customer_user_id = cust;
  r := r || public._qa_s8_ok('J2 zero Slice 8 debt fixture residue', n = 0, jsonb_build_object('rows', n));
  SELECT count(*) INTO n FROM public.wallets WHERE owner_user_id = cust;
  r := r || public._qa_s8_ok('J3 zero Slice 8 wallet fixture residue', n = 0, jsonb_build_object('rows', n));
  SELECT count(*) INTO n FROM public.finance_policies WHERE cancel_before_dispatch_bps = 2500;
  r := r || public._qa_s8_ok('J4 zero Slice 8 policy fixture residue', n = 0, jsonb_build_object('rows', n));
  SELECT count(*) INTO n FROM public.feature_flags
   WHERE key IN ('chop_pay_enabled','chop_pay_checkout_enabled','cash_order_funding_enabled',
                 'driver_cashout_enabled','merchant_om_settlement_enabled','cancellation_policy_enabled',
                 'om_direct_checkout_enabled') AND enabled = true;
  r := r || public._qa_s8_ok('J5 no finance rail activated', n = 0, jsonb_build_object('enabled', n));
  r := r || public._qa_s8_ok('J6 om_topup_enabled preserved ON',
        (SELECT enabled FROM public.feature_flags WHERE key='om_topup_enabled') = true, '{}'::jsonb);

  RETURN r;
END; $fn$;

INSERT INTO public._qa_s8_results (section, payload)
SELECT 'slice8', public._qa_s8_run();

DROP FUNCTION public._qa_s8_run();
DROP FUNCTION public._qa_s8_ok(text, boolean, jsonb);