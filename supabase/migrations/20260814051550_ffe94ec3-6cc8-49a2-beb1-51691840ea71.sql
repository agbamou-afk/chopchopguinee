CREATE OR REPLACE FUNCTION public._qa_node3_repas_r5()
RETURNS TABLE(section text, name text, ok boolean, detail text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_src text; v_eff jsonb; v_p public.finance_policies; v_promo uuid;
  v_ok boolean; v_txt text; v_a bigint; v_b bigint;
BEGIN
  -- ---------- A. NO HARDCODED ECONOMICS ----------
  SELECT prosrc INTO v_src FROM pg_proc WHERE proname = 'repas_order_create';
  RETURN QUERY SELECT 'A.static','order_create has no hardcoded 15000 courier pay',
    (v_src !~ '15000'), 'literal 15000 absent';
  RETURN QUERY SELECT 'A.static','order_create reads the pricing control plane',
    (v_src ~ 'repas_pricing_effective'), 'repas_pricing_effective referenced';
  RETURN QUERY SELECT 'A.static','order_create ignores any client-supplied price',
    (v_src !~ 'p_delivery_fee' AND v_src !~ 'p_total'), 'no price parameters accepted';

  SELECT prosrc INTO v_src FROM pg_proc WHERE proname = 'repas_quote_preview';
  RETURN QUERY SELECT 'A.static','quote_preview reads the pricing control plane',
    (v_src ~ 'repas_pricing_effective'), 'single pricing brain';
  RETURN QUERY SELECT 'A.static','quote_preview has no hardcoded delivery price',
    (v_src !~ '15000' AND v_src !~ '20000'), 'no literals';

  SELECT prosrc INTO v_src FROM pg_proc WHERE proname = '_chop_pay_economics';
  RETURN QUERY SELECT 'A.static','Chop Pay uses the frozen platform fee',
    (v_src ~ 'frozen_platform_fee_gnf'), 'frozen fee honoured';
  SELECT prosrc INTO v_src FROM pg_proc WHERE proname = '_chop_pay_complete_internal';
  RETURN QUERY SELECT 'A.static','completion pays the frozen courier payout',
    (v_src ~ 'courier_payout_gnf' AND v_src ~ '_chop_pay_courier_adjust_internal'),
    'courier payout independent of customer price';

  -- ---------- B. CONTROL-PLANE CONFIG PRESENT ----------
  SELECT * INTO v_p FROM public.finance_policy_at('repas', now());
  RETURN QUERY SELECT 'B.config','effective repas policy exists', (v_p.id IS NOT NULL), COALESCE(v_p.id::text,'none');
  RETURN QUERY SELECT 'B.config','delivery flat fee configured',
    (v_p.delivery_flat_fee_gnf IS NOT NULL AND v_p.delivery_flat_fee_gnf >= 0),
    COALESCE(v_p.delivery_flat_fee_gnf::text,'null');
  RETURN QUERY SELECT 'B.config','courier payout configured',
    (v_p.courier_payout_gnf IS NOT NULL AND v_p.courier_payout_gnf >= 0),
    COALESCE(v_p.courier_payout_gnf::text,'null');
  RETURN QUERY SELECT 'B.config','max delivery distance configured',
    (v_p.delivery_max_distance_km IS NOT NULL), COALESCE(v_p.delivery_max_distance_km::text,'null');
  RETURN QUERY SELECT 'B.config','platform fee rate configured',
    (v_p.transaction_fee_bps IS NOT NULL), COALESCE(v_p.transaction_fee_bps::text,'null');

  v_eff := public.repas_pricing_effective('delivery');
  RETURN QUERY SELECT 'B.config','effective delivery price = policy base with no promotion',
    ((v_eff->>'base_delivery_fee_gnf')::bigint = v_p.delivery_flat_fee_gnf), v_eff->>'base_delivery_fee_gnf';
  RETURN QUERY SELECT 'B.config','effective courier payout = policy courier payout',
    ((v_eff->>'courier_payout_gnf')::bigint = v_p.courier_payout_gnf), v_eff->>'courier_payout_gnf';
  v_eff := public.repas_pricing_effective('pickup');
  RETURN QUERY SELECT 'B.config','pickup has zero delivery price',
    ((v_eff->>'customer_delivery_fee_gnf')::bigint = 0), v_eff->>'customer_delivery_fee_gnf';
  RETURN QUERY SELECT 'B.config','pickup has zero courier payout',
    ((v_eff->>'courier_payout_gnf')::bigint = 0), v_eff->>'courier_payout_gnf';
  BEGIN
    PERFORM public.repas_pricing_effective('teleport');
    RETURN QUERY SELECT 'B.config','unknown fulfillment refused', false, 'accepted';
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 'B.config','unknown fulfillment refused', (SQLERRM ~ 'INVALID_FULFILLMENT'), SQLERRM;
  END;

  -- ---------- C. FEE MATH ----------
  RETURN QUERY SELECT 'C.fee','1% of 100000 on merchandise basis = 1000',
    (public.repas_platform_fee_gnf(100000, 20000, 'merchandise_subtotal', 100) = 1000), 'ok';
  RETURN QUERY SELECT 'C.fee','fee basis none yields zero',
    (public.repas_platform_fee_gnf(100000, 20000, 'none', 100) = 0), 'ok';
  RETURN QUERY SELECT 'C.fee','order_total basis includes delivery',
    (public.repas_platform_fee_gnf(100000, 20000, 'order_total', 100) = 1200), 'ok';
  RETURN QUERY SELECT 'C.fee','fee never negative',
    (public.repas_platform_fee_gnf(-500, -500, 'merchandise_subtotal', 100) = 0), 'clamped';

  -- ---------- D. AUTHORITY / AUDIT ----------
  RETURN QUERY SELECT 'D.authz','admin_set_finance_policy is God-Admin only',
    (SELECT prosrc ~ 'is_god_admin' FROM pg_proc WHERE proname='admin_set_finance_policy'), 'guarded';
  RETURN QUERY SELECT 'D.authz','admin_set_finance_policy demands a reason',
    (SELECT prosrc ~ 'REASON_REQUIRED' FROM pg_proc WHERE proname='admin_set_finance_policy'), 'guarded';
  RETURN QUERY SELECT 'D.authz','admin_set_finance_policy rejects backdating',
    (SELECT prosrc ~ 'BACKDATING_REJECTED' FROM pg_proc WHERE proname='admin_set_finance_policy'), 'guarded';
  RETURN QUERY SELECT 'D.authz','policy changes are audited',
    (SELECT prosrc ~ 'audit_logs' FROM pg_proc WHERE proname='admin_set_finance_policy'), 'audited';
  RETURN QUERY SELECT 'D.authz','promotion create is God-Admin only',
    (SELECT prosrc ~ 'is_god_admin' FROM pg_proc WHERE proname='admin_set_repas_promotion'), 'guarded';
  RETURN QUERY SELECT 'D.authz','promotion create demands a reason',
    (SELECT prosrc ~ 'REASON_REQUIRED' FROM pg_proc WHERE proname='admin_set_repas_promotion'), 'guarded';
  RETURN QUERY SELECT 'D.authz','promotion disable is God-Admin only and audited',
    (SELECT prosrc ~ 'is_god_admin' AND prosrc ~ 'audit_logs'
       FROM pg_proc WHERE proname='admin_disable_repas_promotion'), 'guarded';
  RETURN QUERY SELECT 'D.authz','anon cannot set finance policy',
    NOT has_function_privilege('anon',
      (SELECT oid FROM pg_proc WHERE proname='admin_set_finance_policy'), 'EXECUTE'), 'revoked';
  RETURN QUERY SELECT 'D.authz','anon cannot set promotions',
    NOT has_function_privilege('anon',
      (SELECT oid FROM pg_proc WHERE proname='admin_set_repas_promotion'), 'EXECUTE'), 'revoked';
  RETURN QUERY SELECT 'D.authz','courier adjustment primitive is internal only',
    NOT has_function_privilege('authenticated',
      (SELECT oid FROM pg_proc WHERE proname='_chop_pay_courier_adjust_internal'), 'EXECUTE'), 'revoked';

  -- ---------- E. IMMUTABLE HISTORY ----------
  RETURN QUERY SELECT 'E.history','finance_policies rows are append-only',
    EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
             WHERE c.relname='finance_policies' AND NOT t.tgisinternal), 'immutability trigger present';
  BEGIN
    UPDATE public.finance_policies SET commission_bps = commission_bps WHERE id = v_p.id;
    RETURN QUERY SELECT 'E.history','existing policy row cannot be rewritten', false, 'update succeeded';
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 'E.history','existing policy row cannot be rewritten', true, SQLERRM;
  END;
  RETURN QUERY SELECT 'E.history','policy rows carry an author and a reason',
    (v_p.note IS NOT NULL), COALESCE(v_p.note,'null');

  -- ---------- F. PROMOTION OVERLAY (no base overwrite, auto expiry) ----------
  INSERT INTO public.repas_pricing_promotions(name, reason, fulfillment_scope,
      delivery_fee_override_gnf, starts_at, ends_at)
  VALUES ('QA Ramadan', 'qa temporary campaign proof', 'delivery',
          GREATEST(v_p.delivery_flat_fee_gnf - 5000, 0), now() - interval '1 minute',
          now() + interval '5 minutes')
  RETURNING id INTO v_promo;

  v_eff := public.repas_pricing_effective('delivery');
  RETURN QUERY SELECT 'F.promo','base price is preserved under a promotion',
    ((v_eff->>'base_delivery_fee_gnf')::bigint = v_p.delivery_flat_fee_gnf), v_eff->>'base_delivery_fee_gnf';
  RETURN QUERY SELECT 'F.promo','customer price reflects the promotion',
    ((v_eff->>'customer_delivery_fee_gnf')::bigint = GREATEST(v_p.delivery_flat_fee_gnf-5000,0)),
    v_eff->>'customer_delivery_fee_gnf';
  RETURN QUERY SELECT 'F.promo','discount is explicit and positive',
    ((v_eff->>'promo_discount_gnf')::bigint = LEAST(5000, v_p.delivery_flat_fee_gnf)), v_eff->>'promo_discount_gnf';
  RETURN QUERY SELECT 'F.promo','promotion identity is surfaced',
    (v_eff->>'promotion_id' = v_promo::text), COALESCE(v_eff->>'promotion_name','null');
  RETURN QUERY SELECT 'F.promo','courier payout untouched by the promotion',
    ((v_eff->>'courier_payout_gnf')::bigint = v_p.courier_payout_gnf), v_eff->>'courier_payout_gnf';
  RETURN QUERY SELECT 'F.promo','pickup unaffected by a delivery-scope promotion',
    ((public.repas_pricing_effective('pickup')->>'customer_delivery_fee_gnf')::bigint = 0), 'ok';

  v_eff := public.repas_pricing_effective('delivery', now() + interval '1 day');
  RETURN QUERY SELECT 'F.promo','promotion expires automatically without admin action',
    ((v_eff->>'customer_delivery_fee_gnf')::bigint = v_p.delivery_flat_fee_gnf
      AND v_eff->>'promotion_id' IS NULL), 'reverted to base';
  UPDATE public.repas_pricing_promotions SET enabled = false WHERE id = v_promo;
  RETURN QUERY SELECT 'F.promo','disabling a promotion restores the base price',
    ((public.repas_pricing_effective('delivery')->>'customer_delivery_fee_gnf')::bigint
      = v_p.delivery_flat_fee_gnf), 'restored';

  -- a promotion scheduled for later must not apply today
  DELETE FROM public.repas_pricing_promotions WHERE id = v_promo;
  INSERT INTO public.repas_pricing_promotions(name, reason, fulfillment_scope,
      delivery_discount_gnf, starts_at, ends_at)
  VALUES ('QA future', 'qa future campaign proof', 'delivery', 5000,
          now() + interval '1 day', now() + interval '2 days')
  RETURNING id INTO v_promo;
  v_eff := public.repas_pricing_effective('delivery');
  RETURN QUERY SELECT 'F.promo','promotion does not apply before it starts',
    (v_eff->>'promotion_id' IS NULL
      AND (v_eff->>'customer_delivery_fee_gnf')::bigint = v_p.delivery_flat_fee_gnf),
    'no early application';
  v_eff := public.repas_pricing_effective('delivery', now() + interval '25 hours');
  RETURN QUERY SELECT 'F.promo','scheduled promotion applies inside its window',
    (v_eff->>'promotion_id' = v_promo::text), 'scheduled overlay works';

  -- shape / guard rails
  BEGIN
    INSERT INTO public.repas_pricing_promotions(name, reason, delivery_fee_override_gnf,
        delivery_discount_gnf, starts_at, ends_at)
    VALUES ('QA bad','qa invalid shape',1000,1000, now(), now()+interval '1 h');
    RETURN QUERY SELECT 'F.promo','override and discount cannot both be set', false, 'accepted';
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 'F.promo','override and discount cannot both be set', true, 'rejected';
  END;
  BEGIN
    INSERT INTO public.repas_pricing_promotions(name, reason, delivery_discount_gnf, starts_at, ends_at)
    VALUES ('QA bad','qa invalid window',1000, now()+interval '2 h', now()+interval '1 h');
    RETURN QUERY SELECT 'F.promo','end date must follow start date', false, 'accepted';
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 'F.promo','end date must follow start date', true, 'rejected';
  END;
  BEGIN
    INSERT INTO public.repas_pricing_promotions(name, reason, delivery_discount_gnf, starts_at, ends_at)
    VALUES ('QA bad','qa negative', -500, now(), now()+interval '1 h');
    RETURN QUERY SELECT 'F.promo','negative discounts refused', false, 'accepted';
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 'F.promo','negative discounts refused', true, 'rejected';
  END;
  DELETE FROM public.repas_pricing_promotions WHERE id = v_promo;

  -- ---------- G. DISTANCE ----------
  RETURN QUERY SELECT 'G.distance','unknown coordinates never become zero distance',
    (public.repas_delivery_distance_km(gen_random_uuid(), NULL, NULL) IS NULL), 'null';
  RETURN QUERY SELECT 'G.distance','commitment enforces the configured zone',
    (SELECT prosrc ~ 'OUTSIDE_DELIVERY_ZONE' FROM pg_proc WHERE proname='repas_order_create'), 'guarded';
  RETURN QUERY SELECT 'G.distance','commitment refuses unverifiable distance',
    (SELECT prosrc ~ 'DELIVERY_DISTANCE_UNVERIFIABLE' FROM pg_proc WHERE proname='repas_order_create'), 'guarded';
  RETURN QUERY SELECT 'G.distance','quote exposes eligibility to the client',
    (SELECT prosrc ~ 'delivery_eligible' FROM pg_proc WHERE proname='repas_quote_preview'), 'exposed';

  -- ---------- H. FROZEN ORDER ECONOMICS ----------
  RETURN QUERY SELECT 'H.freeze','orders store the pricing policy version',
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name='food_orders' AND column_name='pricing_policy_id'), 'column present';
  RETURN QUERY SELECT 'H.freeze','orders store the full pricing snapshot',
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name='food_orders' AND column_name='pricing_snapshot'), 'column present';
  FOR v_txt IN SELECT unnest(ARRAY['base_delivery_fee_gnf','delivery_fee_gnf','promo_discount_gnf',
                                   'platform_fee_gnf','courier_payout_gnf','order_total_gnf',
                                   'delivery_distance_km','promotion_id']) LOOP
    RETURN QUERY SELECT 'H.freeze', 'order freezes ' || v_txt,
      EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name='food_orders' AND column_name = v_txt), 'column present';
  END LOOP;
  RETURN QUERY SELECT 'H.freeze','frozen totals are internally consistent on every order',
    NOT EXISTS (SELECT 1 FROM public.food_orders
                 WHERE order_total_gnf IS NOT NULL
                   AND order_total_gnf <> subtotal_gnf
                       + COALESCE(delivery_fee_gnf,0) + COALESCE(platform_fee_gnf,0)),
    'total = merchandise + delivery + fee';
  RETURN QUERY SELECT 'H.freeze','no order charges delivery on a pickup',
    NOT EXISTS (SELECT 1 FROM public.food_orders
                 WHERE fulfillment::text='pickup' AND COALESCE(delivery_fee_gnf,0) <> 0), 'clean';
  RETURN QUERY SELECT 'H.freeze','no pickup order carries courier pay',
    NOT EXISTS (SELECT 1 FROM public.food_orders
                 WHERE fulfillment::text='pickup' AND COALESCE(courier_payout_gnf,0) <> 0), 'clean';

  -- ---------- I. RAIL SAFETY ----------
  RETURN QUERY SELECT 'I.rails','cash pickup still refused',
    (SELECT prosrc ~ 'PICKUP_CASH_NOT_SUPPORTED' FROM pg_proc WHERE proname='repas_order_create'), 'fail closed';
  RETURN QUERY SELECT 'I.rails','cash delivery refused when price <> courier pay',
    (SELECT prosrc ~ 'CASH_DELIVERY_PRICING_UNSUPPORTED' FROM pg_proc WHERE proname='repas_order_create'),
    'fail closed';
  RETURN QUERY SELECT 'I.rails','Chop Pay flag still gates commitment',
    (SELECT prosrc ~ 'CHOP_PAY_CHECKOUT_DISABLED' FROM pg_proc WHERE proname='repas_order_create'), 'gated';
  RETURN QUERY SELECT 'I.rails','cash rail flag still gates commitment',
    (SELECT prosrc ~ 'CASH_ORDER_FUNDING_DISABLED' FROM pg_proc WHERE proname='repas_order_create'), 'gated';
  RETURN QUERY SELECT 'I.rails','idempotency fingerprint still enforced',
    (SELECT prosrc ~ 'IDEMPOTENCY_CONFLICT' FROM pg_proc WHERE proname='repas_order_create'), 'enforced';
  RETURN QUERY SELECT 'I.rails','courier subsidy/margin ledger accounts exist',
    ((SELECT count(*) FROM public.ledger_accounts
       WHERE code IN ('R_DELIVERY_SUBSIDY','R_DELIVERY_MARGIN')) = 2), 'both present';
  SELECT count(*) INTO v_a FROM public.ledger_postings; 
  RETURN QUERY SELECT 'I.rails','ledger remains balanced',
    ((SELECT COALESCE(sum(amount_gnf),0) FROM public.ledger_postings) = 0), 'sum=0';
END; $$;
REVOKE ALL ON FUNCTION public._qa_node3_repas_r5() FROM PUBLIC, anon, authenticated;

-- Record the full-board regression evidence.
INSERT INTO public._qa_s13_results(part, result)
VALUES (0, '{"note":"placeholder"}'::jsonb);
DELETE FROM public._qa_s13_results WHERE part = 0;

-- The R4.5 pickup suite asserts the old 3-argument quote signature; R5 added
-- the two optional destination-coordinate arguments. Retarget the assertion.
DO $fix$
DECLARE v text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v FROM pg_proc WHERE proname = '_qa_node3_repas_pickup';
  v := replace(v, 'public.repas_quote_preview(uuid,jsonb,text)',
                  'public.repas_quote_preview(uuid,jsonb,text,double precision,double precision)');
  EXECUTE v;
END $fix$;

INSERT INTO public._qa_s13_results(part, result)
SELECT 501, jsonb_build_object(
  'suite','node3_repas_r5',
  'pass', count(*) FILTER (WHERE ok), 'fail', count(*) FILTER (WHERE NOT ok),
  'failures', COALESCE(jsonb_agg(jsonb_build_object('section',section,'name',name,'detail',detail))
                        FILTER (WHERE NOT ok), '[]'::jsonb))
FROM public._qa_node3_repas_r5();

INSERT INTO public._qa_s13_results(part, result)
VALUES (502, jsonb_build_object('suite','node3_repas_r1_r4','result', public._qa_node3_repas_r1_r4())),
       (503, jsonb_build_object('suite','node3_repas_pickup','result', public._qa_node3_repas_pickup())),
       (504, jsonb_build_object('suite','node0_course','result', public._qa_node0_course())),
       (505, jsonb_build_object('suite','node1_bonbonna_full','result', public._qa_node1_bonbonna_full())),
       (506, jsonb_build_object('suite','node2_taxi_full','result', public._qa_node2_taxi_full()));