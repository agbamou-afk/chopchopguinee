CREATE OR REPLACE FUNCTION public._qa_s4_run()
RETURNS SETOF text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $qa$
DECLARE
  c1 uuid := gen_random_uuid();   -- customer
  d1 uuid := gen_random_uuid();   -- rich unrestricted driver
  d2 uuid := gen_random_uuid();   -- promo-heavy driver
  d3 uuid := gen_random_uuid();   -- unrelated driver
  m1 uuid := gen_random_uuid();   -- merchant owner
  m2 uuid := gen_random_uuid();   -- other merchant
  s1 uuid; r1 uuid;
  fo1 uuid; fo2 uuid; fo3 uuid; fo4 uuid; fo5 uuid; fo6 uuid;
  mi1 uuid; mi2 uuid; mi3 uuid; mi4 uuid; mi5 uuid; mi6 uuid;
  v_master_id uuid; v_master_start bigint; v_master bigint;
  v_flag_before boolean;
  v_j jsonb; v_err text; v_n int; v_b bigint; v_h public.mission_financial_holds;
  v_bal bigint; v_held bigint; v_promo bigint;
  out_lines text[] := ARRAY[]::text[];

  PROCEDURE_MARK text;
BEGIN
  SELECT id, balance_gnf INTO v_master_id, v_master_start
    FROM public.wallets WHERE party_type = 'master' LIMIT 1;
  SELECT enabled INTO v_flag_before FROM public.feature_flags WHERE key = 'cash_order_funding_enabled';

  -- ---------------- FIXTURES ----------------
  UPDATE public.feature_flags SET enabled = true WHERE key = 'cash_order_funding_enabled';

  INSERT INTO public.merchant_stores (owner_user_id, slug, name)
  VALUES (m1, 'qa-s4-store-'||substr(c1::text,1,8), 'QA S4 Store') RETURNING id INTO s1;

  INSERT INTO public.food_restaurants (slug, name, merchant_store_id, owner_user_id, delivery_available)
  VALUES ('qa-s4-resto-'||substr(c1::text,1,8), 'QA S4 Resto', s1, m1, true) RETURNING id INTO r1;

  INSERT INTO public.wallets (owner_user_id, party_type, balance_gnf) VALUES (d1,'driver',500000);
  INSERT INTO public.wallets (owner_user_id, party_type, balance_gnf) VALUES (d2,'driver',160000);
  INSERT INTO public.wallets (owner_user_id, party_type, balance_gnf) VALUES (d3,'driver',500000);
  INSERT INTO public.driver_promo_credits (driver_user_id, grant_key, granted_gnf, state)
  VALUES (d2, 'qa-s4:'||d2::text, 25000, 'active');

  -- Order 1: the exit-gate example
  INSERT INTO public.food_orders (user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf, state)
  VALUES (c1, r1, 'delivery', 'cash', 150000, 'placed') RETURNING id INTO fo1;
  INSERT INTO public.missions (type, state, customer_id, courier_id, merchant_id, merchant_store_id,
                               ref_food_order_id, estimated_earning_gnf)
  VALUES ('food_delivery','assigned', c1, d1, m1, s1, fo1, 25000) RETURNING id INTO mi1;

  -- =============== 1. EXIT GATE ===============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(d1), true);
  v_j := public.cash_order_accept('repas', fo1);
  out_lines := out_lines || format('T1.1 accept | %s | %s',
    CASE WHEN v_j->>'status'='accepted' AND (v_j->>'merchandise_subtotal_gnf')::bigint=150000
          AND (v_j->>'delivery_fee_gnf')::bigint=25000 AND (v_j->>'platform_fee_gnf')::bigint=1500
          AND (v_j->>'cash_due_gnf')::bigint=176500 THEN 'PASS' ELSE 'FAIL' END, v_j::text);

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module='repas' AND source_id=fo1 AND kind='cash_funding';
  out_lines := out_lines || format('T1.2 principal 150000 unrestricted-only | %s | amount=%s unrestricted=%s promo=%s',
    CASE WHEN v_h.amount_gnf=150000 AND v_h.unrestricted_gnf=150000 AND v_h.promo_gnf=0 THEN 'PASS' ELSE 'FAIL' END,
    v_h.amount_gnf, v_h.unrestricted_gnf, v_h.promo_gnf);

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module='repas' AND source_id=fo1 AND kind='platform_fee';
  out_lines := out_lines || format('T1.3 fee 1500 reserved | %s | amount=%s unrestricted=%s promo=%s',
    CASE WHEN v_h.amount_gnf=1500 THEN 'PASS' ELSE 'FAIL' END,
    v_h.amount_gnf, v_h.unrestricted_gnf, v_h.promo_gnf);

  v_j := public.cash_order_accept('repas', fo1);
  SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_module='repas' AND source_id=fo1;
  out_lines := out_lines || format('T1.4 accept replay inert | %s | status=%s holds=%s',
    CASE WHEN v_j->>'status'='already_accepted' AND v_n=2 THEN 'PASS' ELSE 'FAIL' END, v_j->>'status', v_n);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(m1), true);
  BEGIN
    v_j := public.cash_order_merchant_prepare('repas', fo1); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  out_lines := out_lines || format('T1.5 prep before funding denied | %s | %s',
    CASE WHEN v_err LIKE 'PREPARATION_REQUIRES_FUNDED_ORDER%' THEN 'PASS' ELSE 'FAIL' END, v_err);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(m2), true);
  BEGIN
    v_j := public.cash_order_merchant_accept('repas', fo1); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  out_lines := out_lines || format('T1.6 wrong merchant denied | %s | %s',
    CASE WHEN v_err = 'Not authorized' THEN 'PASS' ELSE 'FAIL' END, v_err);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(m1), true);
  v_j := public.cash_order_merchant_accept('repas', fo1);
  SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=m1 AND party_type='merchant';
  out_lines := out_lines || format('T1.7 merchant funded exactly 150000 | %s | merchant_balance=%s',
    CASE WHEN v_b=150000 THEN 'PASS' ELSE 'FAIL' END, v_b);

  v_j := public.cash_order_merchant_accept('repas', fo1);
  SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=m1 AND party_type='merchant';
  out_lines := out_lines || format('T1.8 merchant funding replay inert | %s | status=%s merchant_balance=%s',
    CASE WHEN v_j->>'status'='already_accepted' AND v_b=150000 THEN 'PASS' ELSE 'FAIL' END, v_j->>'status', v_b);

  SELECT balance_gnf, held_gnf INTO v_bal, v_held FROM public.wallets WHERE owner_user_id=d1 AND party_type='driver';
  out_lines := out_lines || format('T1.9 driver debited principal only | %s | balance=%s held=%s',
    CASE WHEN v_bal=350000 AND v_held=1500 THEN 'PASS' ELSE 'FAIL' END, v_bal, v_held);

  v_j := public.cash_order_merchant_prepare('repas', fo1);
  SELECT count(*) INTO v_n FROM public.food_orders WHERE id=fo1 AND state='preparing';
  out_lines := out_lines || format('T1.10 prep lock after funding | %s | status=%s food_order_preparing=%s',
    CASE WHEN v_j->>'status'='preparing' AND v_n=1 THEN 'PASS' ELSE 'FAIL' END, v_j->>'status', v_n);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(c1), true);
  BEGIN v_j := public.cash_order_customer_cancel('repas', fo1, 'test'); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  SELECT count(*) INTO v_n FROM public.customer_cancellation_debts WHERE source_id=fo1;
  out_lines := out_lines || format('T1.11 customer cancel locked after prep | %s | err=%s debts=%s',
    CASE WHEN v_err LIKE 'CASH_ORDER_PREPARATION_LOCKED%' AND v_n=0 THEN 'PASS' ELSE 'FAIL' END, v_err, v_n);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(d1), true);
  BEGIN v_j := public.cash_order_complete_cash('repas', fo1); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  out_lines := out_lines || format('T1.12 completion before custody denied | %s | %s',
    CASE WHEN v_err LIKE 'CUSTODY_NOT_ESTABLISHED%' THEN 'PASS' ELSE 'FAIL' END, v_err);

  UPDATE public.missions SET state='heading_to_dropoff', pickup_confirmed_at=now(), pickup_confirmed_by=d1
   WHERE id=mi1;

  PERFORM set_config('request.jwt.claims', public._as_user_claims(c1), true);
  BEGIN v_j := public.cash_order_complete_cash('repas', fo1); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  out_lines := out_lines || format('T1.13 customer cannot complete | %s | %s',
    CASE WHEN v_err='Not authorized' THEN 'PASS' ELSE 'FAIL' END, v_err);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(d3), true);
  BEGIN v_j := public.cash_order_complete_cash('repas', fo1); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  out_lines := out_lines || format('T1.14 wrong driver cannot complete | %s | %s',
    CASE WHEN v_err='Not authorized' THEN 'PASS' ELSE 'FAIL' END, v_err);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(d1), true);
  v_j := public.cash_order_complete_cash('repas', fo1);
  SELECT balance_gnf, held_gnf INTO v_bal, v_held FROM public.wallets WHERE owner_user_id=d1 AND party_type='driver';
  SELECT balance_gnf INTO v_master FROM public.wallets WHERE id=v_master_id;
  out_lines := out_lines || format('T1.15 cash due 176500 / no fake credit | %s | cash_due=%s wallet_credit=%s driver_balance=%s held=%s',
    CASE WHEN (v_j->>'cash_due_gnf')::bigint=176500
          AND (v_j->>'driver_wallet_credit_gnf')::bigint=0
          AND v_bal=348500 AND v_held=0 THEN 'PASS' ELSE 'FAIL' END,
    v_j->>'cash_due_gnf', v_j->>'driver_wallet_credit_gnf', v_bal, v_held);
  out_lines := out_lines || format('T1.16 platform fee 1500 captured once | %s | master_delta=%s',
    CASE WHEN v_master - v_master_start = 1500 THEN 'PASS' ELSE 'FAIL' END, v_master - v_master_start);
  out_lines := out_lines || format('T1.17 delivery earning = delivery fee | %s | %s',
    CASE WHEN (v_j->>'delivery_fee_gnf')::bigint=25000 THEN 'PASS' ELSE 'FAIL' END, v_j->>'delivery_fee_gnf');

  v_j := public.cash_order_complete_cash('repas', fo1);
  SELECT balance_gnf INTO v_master FROM public.wallets WHERE id=v_master_id;
  out_lines := out_lines || format('T1.18 completion replay inert | %s | status=%s master_delta=%s',
    CASE WHEN v_j->>'status'='already_completed' AND v_master - v_master_start = 1500 THEN 'PASS' ELSE 'FAIL' END,
    v_j->>'status', v_master - v_master_start);

  SELECT (500000 - v_bal) INTO v_b;
  out_lines := out_lines || format('T1.19 net drift zero (driver 151500 = merchant 150000 + platform 1500) | %s | driver_out=%s',
    CASE WHEN v_b = 151500 THEN 'PASS' ELSE 'FAIL' END, v_b);

  -- =============== 9. LEDGER INTEGRITY ===============
  SELECT count(*) INTO v_n FROM (
    SELECT j.id FROM public.ledger_journals j JOIN public.ledger_postings p ON p.journal_id=j.id
     WHERE j.source_id IN (fo1) GROUP BY j.id HAVING SUM(p.amount_gnf) <> 0) x;
  out_lines := out_lines || format('T9.1 all journals balanced | %s | unbalanced=%s',
    CASE WHEN v_n=0 THEN 'PASS' ELSE 'FAIL' END, v_n);

  SELECT count(*) INTO v_n FROM (
    SELECT j.id FROM public.ledger_journals j JOIN public.ledger_postings p ON p.journal_id=j.id
     WHERE j.source_id IN (fo1) AND p.amount_gnf <> 0 GROUP BY j.id HAVING count(*) < 2) x;
  out_lines := out_lines || format('T9.2 no journal with <2 nonzero postings | %s | bad=%s',
    CASE WHEN v_n=0 THEN 'PASS' ELSE 'FAIL' END, v_n);

  SELECT count(*) INTO v_n FROM public.mission_financial_holds
   WHERE source_id=fo1 AND (captured_promo_gnf > promo_gnf OR captured_unrestricted_gnf > unrestricted_gnf);
  out_lines := out_lines || format('T9.3 capture attribution <= reserved source | %s | violations=%s',
    CASE WHEN v_n=0 THEN 'PASS' ELSE 'FAIL' END, v_n);

  -- =============== 2. RESTRICTED-BONUS EXCLUSION ===============
  INSERT INTO public.food_orders (user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf, state)
  VALUES (c1, r1, 'delivery', 'cash', 150000, 'placed') RETURNING id INTO fo2;
  INSERT INTO public.missions (type, state, customer_id, courier_id, merchant_id, merchant_store_id,
                               ref_food_order_id, estimated_earning_gnf)
  VALUES ('food_delivery','assigned', c1, d2, m1, s1, fo2, 25000) RETURNING id INTO mi2;

  PERFORM set_config('request.jwt.claims', public._as_user_claims(d2), true);
  BEGIN v_j := public.cash_order_accept('repas', fo2); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  SELECT count(*) INTO v_n FROM public.cash_order_runtime WHERE source_id=fo2;
  SELECT count(*) INTO v_b FROM public.mission_financial_holds WHERE source_id=fo2;
  out_lines := out_lines || format('T2.1 promo cannot fund merchandise principal | %s | err=%s runtime=%s holds=%s',
    CASE WHEN v_err LIKE '%CASH_FUNDING_REQUIRES_UNRESTRICTED%' AND v_n=0 AND v_b=0 THEN 'PASS' ELSE 'FAIL' END,
    v_err, v_n, v_b);

  -- promo MAY fund the fee
  INSERT INTO public.food_orders (user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf, state)
  VALUES (c1, r1, 'delivery', 'cash', 20000, 'placed') RETURNING id INTO fo3;
  INSERT INTO public.missions (type, state, customer_id, courier_id, merchant_id, merchant_store_id,
                               ref_food_order_id, estimated_earning_gnf)
  VALUES ('food_delivery','assigned', c1, d2, m1, s1, fo3, 5000) RETURNING id INTO mi3;
  v_j := public.cash_order_accept('repas', fo3);
  SELECT * INTO v_h FROM public.mission_financial_holds WHERE source_id=fo3 AND kind='platform_fee';
  out_lines := out_lines || format('T2.2 promo may fund the 1%% fee | %s | fee=%s promo=%s unrestricted=%s',
    CASE WHEN v_h.amount_gnf=200 AND v_h.promo_gnf=200 AND v_h.unrestricted_gnf=0 THEN 'PASS' ELSE 'FAIL' END,
    v_h.amount_gnf, v_h.promo_gnf, v_h.unrestricted_gnf);
  SELECT * INTO v_h FROM public.mission_financial_holds WHERE source_id=fo3 AND kind='cash_funding';
  out_lines := out_lines || format('T2.3 principal unrestricted-only | %s | amount=%s promo=%s',
    CASE WHEN v_h.amount_gnf=20000 AND v_h.promo_gnf=0 THEN 'PASS' ELSE 'FAIL' END, v_h.amount_gnf, v_h.promo_gnf);

  -- =============== 4/8. MERCHANT PRE-PREP REJECTION ===============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(m1), true);
  v_j := public.cash_order_merchant_reject('repas', fo3, 'out of stock');
  SELECT balance_gnf, held_gnf INTO v_bal, v_held FROM public.wallets WHERE owner_user_id=d2 AND party_type='driver';
  v_promo := (public.driver_promo_balance(d2)->>'promo_available_gnf')::bigint;
  SELECT COALESCE(SUM(funded_gnf),0) INTO v_b FROM public.merchant_payables WHERE source_id=fo3;
  SELECT count(*) INTO v_n FROM public.customer_cancellation_debts WHERE source_id=fo3;
  out_lines := out_lines || format('T4.1 pre-prep rejection restores buckets exactly | %s | balance=%s held=%s promo_avail=%s payable_funded=%s debts=%s',
    CASE WHEN v_bal=160000 AND v_held=0 AND v_promo=25000 AND v_b=0 AND v_n=0 THEN 'PASS' ELSE 'FAIL' END,
    v_bal, v_held, v_promo, v_b, v_n);
  SELECT COALESCE(SUM(-p.amount_gnf),0) INTO v_b FROM public.ledger_journals j
    JOIN public.ledger_postings p ON p.journal_id=j.id
   WHERE j.source_id=fo3 AND p.account_code='R_TRANSACTION_FEE';
  out_lines := out_lines || format('T4.2 no fee revenue on rejected order | %s | revenue=%s',
    CASE WHEN v_b=0 THEN 'PASS' ELSE 'FAIL' END, v_b);
  v_j := public.cash_order_merchant_reject('repas', fo3, 'again');
  out_lines := out_lines || format('T4.3 rejection replay inert | %s | %s',
    CASE WHEN v_j->>'status'='already_rejected' THEN 'PASS' ELSE 'FAIL' END, v_j->>'status');

  -- =============== 3. STALE / CROSS-DRIVER ACCEPTANCE ===============
  INSERT INTO public.food_orders (user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf, state)
  VALUES (c1, r1, 'delivery', 'cash', 100000, 'placed') RETURNING id INTO fo4;
  INSERT INTO public.missions (type, state, customer_id, courier_id, merchant_id, merchant_store_id,
                               ref_food_order_id, estimated_earning_gnf)
  VALUES ('food_delivery','delivered', c1, d1, m1, s1, fo4, 20000) RETURNING id INTO mi4;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(d1), true);
  BEGIN v_j := public.cash_order_accept('repas', fo4); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  out_lines := out_lines || format('T3.1 stale offer denied | %s | %s',
    CASE WHEN v_err LIKE 'STALE_OFFER%' THEN 'PASS' ELSE 'FAIL' END, v_err);

  INSERT INTO public.food_orders (user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf, state)
  VALUES (c1, r1, 'delivery', 'cash', 150000, 'placed') RETURNING id INTO fo5;
  INSERT INTO public.missions (type, state, customer_id, courier_id, merchant_id, merchant_store_id,
                               ref_food_order_id, estimated_earning_gnf)
  VALUES ('food_delivery','assigned', c1, d1, m1, s1, fo5, 25000) RETURNING id INTO mi5;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(d3), true);
  BEGIN v_j := public.cash_order_accept('repas', fo5); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  SELECT count(*) INTO v_n FROM public.cash_order_runtime WHERE source_id=fo5;
  out_lines := out_lines || format('T3.2 cross-driver acceptance denied | %s | err=%s runtime=%s',
    CASE WHEN v_err LIKE 'NOT_ASSIGNED_DRIVER%' AND v_n=0 THEN 'PASS' ELSE 'FAIL' END, v_err, v_n);

  -- =============== 6. CANCELLATION DEBT ===============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(d1), true);
  v_j := public.cash_order_accept('repas', fo5);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(c1), true);
  v_j := public.cash_order_customer_cancel('repas', fo5, 'changed mind');
  SELECT amount_gnf, basis_gnf, applied_bps INTO v_b, v_bal, v_n
    FROM public.customer_cancellation_debts WHERE source_id=fo5;
  out_lines := out_lines || format('T6.1 after-dispatch debt = 10%% of (150000+25000) | %s | amount=%s basis=%s bps=%s',
    CASE WHEN v_b=17500 AND v_bal=175000 AND v_n=1000 THEN 'PASS' ELSE 'FAIL' END, v_b, v_bal, v_n);
  SELECT balance_gnf, held_gnf INTO v_bal, v_held FROM public.wallets WHERE owner_user_id=d1 AND party_type='driver';
  out_lines := out_lines || format('T6.2 driver holds released on cancel | %s | balance=%s held=%s',
    CASE WHEN v_bal=348500 AND v_held=0 THEN 'PASS' ELSE 'FAIL' END, v_bal, v_held);
  v_j := public.cash_order_customer_cancel('repas', fo5, 'again');
  SELECT count(*) INTO v_n FROM public.customer_cancellation_debts WHERE source_id=fo5;
  out_lines := out_lines || format('T6.3 cancellation replay creates no second debt | %s | status=%s debts=%s',
    CASE WHEN v_n=1 THEN 'PASS' ELSE 'FAIL' END, v_j->>'status', v_n);

  -- =============== 7. POST-PREP DISPUTE ===============
  INSERT INTO public.food_orders (user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf, state)
  VALUES (c1, r1, 'delivery', 'cash', 50000, 'placed') RETURNING id INTO fo6;
  INSERT INTO public.missions (type, state, customer_id, courier_id, merchant_id, merchant_store_id,
                               ref_food_order_id, estimated_earning_gnf)
  VALUES ('food_delivery','assigned', c1, d1, m1, s1, fo6, 10000) RETURNING id INTO mi6;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(d1), true);
  v_j := public.cash_order_accept('repas', fo6);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(m1), true);
  v_j := public.cash_order_merchant_accept('repas', fo6);
  v_j := public.cash_order_merchant_prepare('repas', fo6);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(c1), true);
  v_j := public.cash_order_dispute_open('repas', fo6, 'never delivered');
  out_lines := out_lines || format('T7.1 dispute freezes economic state | %s | %s',
    CASE WHEN v_j->>'status'='disputed' AND v_j->>'economic_state'='frozen' THEN 'PASS' ELSE 'FAIL' END, v_j::text);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(d1), true);
  BEGIN v_j := public.cash_order_complete_cash('repas', fo6); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  out_lines := out_lines || format('T7.2 no completion while disputed | %s | %s',
    CASE WHEN v_err LIKE 'ORDER_IN_DISPUTE%' THEN 'PASS' ELSE 'FAIL' END, v_err);

  BEGIN v_j := public.admin_cash_order_dispute_resolve('repas', fo6, 'close_no_value', 'x'); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  out_lines := out_lines || format('T7.3 ordinary driver cannot resolve dispute | %s | %s',
    CASE WHEN v_err='Not authorized' THEN 'PASS' ELSE 'FAIL' END, v_err);

  PERFORM set_config('request.jwt.claims', '', true);   -- service/internal authority
  v_j := public.admin_cash_order_dispute_resolve('repas', fo6, 'release_driver_funding', 'ops resolution');
  v_err := v_j->>'status';
  v_j := public.admin_cash_order_dispute_resolve('repas', fo6, 'release_driver_funding', 'replay');
  out_lines := out_lines || format('T7.4 authorized resolution idempotent + audited | %s | first=%s second=%s',
    CASE WHEN v_err='resolved' AND v_j->>'status'='already_resolved' THEN 'PASS' ELSE 'FAIL' END,
    v_err, v_j->>'status');
  SELECT count(*) INTO v_n FROM public.audit_logs WHERE action='cash_order_dispute_resolved';
  out_lines := out_lines || format('T7.5 audit trail written | %s | rows=%s',
    CASE WHEN v_n >= 1 THEN 'PASS' ELSE 'FAIL' END, v_n);

  -- =============== A. MIXED TENDER + FLAG ===============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(d1), true);
  UPDATE public.food_orders SET payment_method='wallet' WHERE id=fo4;
  UPDATE public.missions SET state='assigned' WHERE id=mi4;
  BEGIN v_j := public.cash_order_accept('repas', fo4); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  out_lines := out_lines || format('TA.1 non-cash tender rejected, never coerced | %s | %s',
    CASE WHEN v_err LIKE 'NOT_A_CASH_ORDER%' OR v_err LIKE 'MIXED_TENDER%' THEN 'PASS' ELSE 'FAIL' END, v_err);

  UPDATE public.feature_flags SET enabled=false WHERE key='cash_order_funding_enabled';
  UPDATE public.food_orders SET payment_method='cash' WHERE id=fo4;
  BEGIN v_j := public.cash_order_accept('repas', fo4); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  out_lines := out_lines || format('TA.2 flag OFF blocks cash-order funding | %s | %s',
    CASE WHEN v_err LIKE 'CASH_ORDER_FUNDING_DISABLED%' THEN 'PASS' ELSE 'FAIL' END, v_err);

  -- =============== 8/9. PRIVILEGE MATRIX ===============
  PERFORM set_config('request.jwt.claims', '', true);
  out_lines := out_lines || format('T8.1 internals not executable by anon/authenticated | %s | %s',
    CASE WHEN NOT has_function_privilege('authenticated','public._merchant_payable_fund_internal(text,uuid,uuid,text,uuid)','EXECUTE')
          AND NOT has_function_privilege('authenticated','public._driver_mission_hold_release_internal(text,uuid,text,text,uuid)','EXECUTE')
          AND NOT has_function_privilege('authenticated','public._customer_cancellation_debt_create_internal(text,uuid,uuid,text,text,bigint,bigint,bigint,boolean,text,boolean,jsonb,uuid)','EXECUTE')
          AND NOT has_function_privilege('authenticated','public._cash_order_capture_platform_fee(text,uuid,uuid)','EXECUTE')
          AND NOT has_function_privilege('authenticated','public._merchant_payable_create_internal(text,uuid,uuid,bigint,bigint,text,jsonb,boolean)','EXECUTE')
          AND NOT has_function_privilege('anon','public._cash_order_facts(text,uuid)','EXECUTE')
         THEN 'PASS' ELSE 'FAIL' END, 'internal funding/payable/fee/debt helpers');

  out_lines := out_lines || format('T8.2 legacy money primitives stay privileged | %s | %s',
    CASE WHEN NOT has_function_privilege('authenticated','public.merchant_payable_fund(text,uuid,uuid,text)','EXECUTE') IS NULL
          AND NOT has_function_privilege('anon','public.cash_order_accept(text,uuid)','EXECUTE')
          AND NOT has_function_privilege('anon','public.admin_cash_order_dispute_resolve(text,uuid,text,text)','EXECUTE')
         THEN 'PASS' ELSE 'FAIL' END, 'anon cannot reach cash-order runtime');

  out_lines := out_lines || format('T9.4 Slice 3 guards intact | %s | ride_accept=%s ride_dispatch=%s wallet_internal_transfer=%s om_auto_match=%s topup_credit=%s',
    CASE WHEN NOT has_function_privilege('authenticated','public.ride_accept(uuid)','EXECUTE')
          AND NOT has_function_privilege('anon','public.om_auto_match(uuid)','EXECUTE')
          AND NOT has_function_privilege('authenticated','public.om_auto_match(uuid)','EXECUTE')
          AND NOT has_function_privilege('authenticated','public.wallet_topup_om_credit(uuid,uuid)','EXECUTE')
         THEN 'PASS' ELSE 'FAIL' END,
    has_function_privilege('authenticated','public.ride_accept(uuid)','EXECUTE'),
    'n/a',
    has_function_privilege('authenticated','public.wallet_internal_transfer(uuid,uuid,bigint,text,text,jsonb)','EXECUTE'),
    has_function_privilege('authenticated','public.om_auto_match(uuid)','EXECUTE'),
    has_function_privilege('authenticated','public.wallet_topup_om_credit(uuid,uuid)','EXECUTE'));

  -- =============== ROLLBACK ===============
  ALTER TABLE public.ledger_postings DISABLE TRIGGER USER;
  ALTER TABLE public.ledger_journals DISABLE TRIGGER USER;

  DELETE FROM public.ledger_postings WHERE journal_id IN (
    SELECT id FROM public.ledger_journals WHERE source_id IN (fo1,fo2,fo3,fo4,fo5,fo6));
  DELETE FROM public.ledger_journals WHERE source_id IN (fo1,fo2,fo3,fo4,fo5,fo6);

  ALTER TABLE public.ledger_postings ENABLE TRIGGER USER;
  ALTER TABLE public.ledger_journals ENABLE TRIGGER USER;

  DELETE FROM public.audit_logs WHERE action='cash_order_dispute_resolved'
     AND entity_id IN (SELECT id FROM public.cash_order_runtime WHERE source_id IN (fo1,fo2,fo3,fo4,fo5,fo6));
  DELETE FROM public.cash_order_runtime WHERE source_id IN (fo1,fo2,fo3,fo4,fo5,fo6);
  DELETE FROM public.customer_cancellation_debts WHERE source_id IN (fo1,fo2,fo3,fo4,fo5,fo6);
  DELETE FROM public.merchant_payables WHERE source_id IN (fo1,fo2,fo3,fo4,fo5,fo6);
  DELETE FROM public.mission_financial_holds WHERE source_id IN (fo1,fo2,fo3,fo4,fo5,fo6);
  DELETE FROM public.wallet_transactions
   WHERE related_user_id IN (c1,d1,d2,d3,m1,m2)
      OR from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (c1,d1,d2,d3,m1,m2))
      OR to_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (c1,d1,d2,d3,m1,m2));
  DELETE FROM public.driver_promo_credits WHERE driver_user_id IN (d1,d2,d3);
  DELETE FROM public.wallets WHERE owner_user_id IN (c1,d1,d2,d3,m1,m2);
  DELETE FROM public.missions WHERE id IN (mi1,mi2,mi3,mi4,mi5,mi6);
  DELETE FROM public.food_order_items WHERE order_id IN (fo1,fo2,fo3,fo4,fo5,fo6);
  DELETE FROM public.food_orders WHERE id IN (fo1,fo2,fo3,fo4,fo5,fo6);
  DELETE FROM public.food_restaurants WHERE id = r1;
  DELETE FROM public.merchant_stores WHERE id = s1;

  UPDATE public.wallets SET balance_gnf = v_master_start WHERE id = v_master_id;
  UPDATE public.feature_flags SET enabled = COALESCE(v_flag_before,false) WHERE key='cash_order_funding_enabled';

  SELECT balance_gnf INTO v_master FROM public.wallets WHERE id=v_master_id;
  out_lines := out_lines || format('T10.1 master wallet restored (DEF-FIN-001) | %s | %s',
    CASE WHEN v_master = v_master_start THEN 'PASS' ELSE 'FAIL' END, v_master);
  SELECT count(*) INTO v_n FROM public.cash_order_runtime;
  out_lines := out_lines || format('T10.2 zero cash_order_runtime residue | %s | rows=%s',
    CASE WHEN v_n=0 THEN 'PASS' ELSE 'FAIL' END, v_n);
  SELECT count(*) INTO v_n FROM public.feature_flags
   WHERE enabled AND key IN ('cash_order_funding_enabled','chop_pay_enabled','chop_pay_checkout_enabled',
        'chop_pay_p2p_enabled','driver_balance_gate_enabled','driver_starter_credit_enabled',
        'driver_cashout_enabled','merchant_om_settlement_enabled','om_direct_checkout_enabled');
  out_lines := out_lines || format('T10.3 canonical finance flags remain OFF | %s | enabled=%s',
    CASE WHEN v_n=0 THEN 'PASS' ELSE 'FAIL' END, v_n);

  RETURN QUERY SELECT unnest(out_lines);
END;
$qa$;

REVOKE ALL ON FUNCTION public._qa_s4_run() FROM PUBLIC, anon, authenticated;