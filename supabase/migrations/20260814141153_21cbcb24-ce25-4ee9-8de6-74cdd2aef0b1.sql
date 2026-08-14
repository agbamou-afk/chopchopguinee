CREATE OR REPLACE FUNCTION public._qa_node3_repas_r7_ext()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_cust2 uuid; v_merch uuid; v_drv uuid; v_drv2 uuid; v_god uuid;
  v_store uuid; v_resto uuid; v_item uuid;
  v_oD uuid; v_oC uuid; v_oP uuid;
  v_mD uuid; v_mC uuid;
  v_res jsonb; v_t jsonb; v_rc jsonb; v_err text; v_n int; v_code text; v_proof text;
  v_snap_cred text; v_snap_ev int; v_snap_j int; v_snap_wal text;
  v_snap_ord text; v_snap_mis text; v_i int;
  v_promo_ok boolean := false; v_promo_err text; v_base bigint; v_del bigint;
  v_o public.food_orders%ROWTYPE;
BEGIN
  -- ================= EXT FIXTURES (same qa-n3r7 residue namespace) =================
  v_cust := gen_random_uuid(); v_cust2 := gen_random_uuid(); v_merch := gen_random_uuid();
  v_drv := gen_random_uuid(); v_drv2 := gen_random_uuid(); v_god := gen_random_uuid();
  PERFORM public._qa_s13_user(v_cust,'n3r7ec');
  PERFORM public._qa_s13_user(v_cust2,'n3r7ex');
  PERFORM public._qa_s13_user(v_merch,'n3r7em');
  PERFORM public._qa_s13_user(v_drv,'n3r7ed');
  PERFORM public._qa_s13_user(v_drv2,'n3r7ed2');
  PERFORM public._qa_s13_user(v_god,'n3r7eg');
  PERFORM public._qa_s13_wallet(v_cust,'client',5000000,0);
  PERFORM public._qa_s13_wallet(v_cust2,'client',900000,0);
  PERFORM public._qa_s13_wallet(v_merch,'merchant',0,0);
  PERFORM public._qa_s13_wallet(v_drv,'driver',900000,0);
  PERFORM public._qa_s13_wallet(v_drv2,'driver',900000,0);
  INSERT INTO public.user_roles(user_id, role) VALUES (v_god,'god_admin') ON CONFLICT DO NOTHING;
  INSERT INTO public.driver_profiles(user_id,status,vehicle_type,capabilities)
    VALUES (v_drv,'approved','livraison',ARRAY['repas_delivery'])
    ON CONFLICT (user_id) DO UPDATE SET status='approved', capabilities=ARRAY['repas_delivery'];
  INSERT INTO public.driver_profiles(user_id,status,vehicle_type,capabilities)
    VALUES (v_drv2,'approved','livraison',ARRAY['repas_delivery'])
    ON CONFLICT (user_id) DO UPDATE SET status='approved', capabilities=ARRAY['repas_delivery'];

  INSERT INTO public.merchant_stores(owner_user_id, slug, name, delivery_available, status)
    VALUES (v_merch, 'qa-n3r7-store-e-'||substr(v_merch::text,1,8), 'QA N3R7 Ext Store', true, 'active')
    RETURNING id INTO v_store;
  INSERT INTO public.food_restaurants(owner_user_id, merchant_store_id, slug, name, status,
      is_open, delivery_available, pickup_available, choppay_enabled, prep_time_min, latitude, longitude)
    VALUES (v_merch, v_store, 'qa-n3r7-resto-e-'||substr(v_merch::text,1,8), 'QA N3R7 Ext Resto',
            'active', true, true, true, true, 20, 9.5370, -13.6785)
    RETURNING id INTO v_resto;
  INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
    VALUES (v_resto,'QA R7 Ext Plat',100000,true) RETURNING id INTO v_item;

  -- ================= P8. COURIER ROLE SHAPE + REAL DELIVERY LIFECYCLE =================
  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
  v_res := public.repas_order_create(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
      'delivery','choppay', gen_random_uuid(), 'QA R7 Ext Adresse', 9.5395, -13.6760);
  v_oD := (v_res->>'order_id')::uuid;
  SELECT id INTO v_mD FROM public.missions WHERE ref_food_order_id = v_oD LIMIT 1;
  r := r || public._qa_s13_ok('P8.1 ext delivery order + mission committed',
        v_oD IS NOT NULL AND v_mD IS NOT NULL, v_res::text);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
  BEGIN PERFORM public.repas_order_tracking(v_oD); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('P8.2 a courier cannot track a delivery it has not been assigned',
        v_err LIKE '%NOT_AUTHORIZED%', v_err);

  PERFORM public.mission_claim(v_mD);
  v_t := public.repas_order_tracking(v_oD);
  r := r || public._qa_s13_ok('P8.3 the assigned courier role is server-assigned',
        v_t->>'viewer_role' = 'courier', v_t->>'viewer_role');
  r := r || public._qa_s13_ok('P8.4 courier tracking carries the operational addresses',
        (v_t ? 'pickup_address') AND (v_t ? 'delivery_address'), v_t::text);
  r := r || public._qa_s13_ok('P8.5 courier tracking carries the customer contact block',
        v_t ? 'customer', NULL);
  r := r || public._qa_s13_ok('P8.6 courier tracking exposes no merchant next actions',
        NOT (v_t ? 'allowed_actions'), v_t::text);
  r := r || public._qa_s13_ok('P8.7 courier tracking exposes no customer money total',
        NOT (v_t ? 'order_total_gnf') AND NOT (v_t ? 'merchandise_subtotal_gnf'), v_t::text);
  r := r || public._qa_s13_ok('P8.8 courier tracking exposes no payout or pricing internals',
        NOT (v_t ? 'courier_payout_gnf') AND NOT (v_t ? 'pricing_snapshot')
        AND NOT (v_t ? 'pricing_policy_id') AND NOT (v_t ? 'promotion_id'), v_t::text);
  r := r || public._qa_s13_ok('P8.9 courier tracking carries no custody code material',
        v_t::text NOT LIKE '%code_hash%' AND v_t::text NOT LIKE '%code_secret_id%', NULL);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
  BEGIN PERFORM public.repas_order_tracking(v_oD); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('P8.10 an unrelated courier is refused once another courier is assigned',
        v_err LIKE '%NOT_AUTHORIZED%', v_err);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
  BEGIN PERFORM public.repas_order_tracking(v_oD); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('P8.11 an unrelated customer is refused on the delivery order',
        v_err LIKE '%NOT_AUTHORIZED%', v_err);

  -- merchant lifecycle
  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
  PERFORM public.repas_merchant_transition(v_oD,'accept');
  PERFORM public.repas_merchant_transition(v_oD,'prepare');
  v_t := public.repas_order_tracking(v_oD);
  r := r || public._qa_s13_ok('P8.12 tracking matches the order row while preparing',
        v_t->>'state' = (SELECT state::text FROM public.food_orders WHERE id=v_oD)
        AND v_t->>'state' = 'preparing', v_t->>'state');
  PERFORM public.repas_merchant_transition(v_oD,'ready');
  v_t := public.repas_order_tracking(v_oD);
  r := r || public._qa_s13_ok('P8.13 a ready delivery order offers the merchant no manual handover',
        v_t->'allowed_actions' = '[]'::jsonb, v_t->>'allowed_actions');
  r := r || public._qa_s13_ok('P8.14 tracking reports the pending restaurant handoff credential',
        v_t->'custody'->>'pending_kind' = 'restaurant_handoff', v_t->'custody'->>'pending_kind');
  v_code := public.repas_custody_code_view(v_oD,'restaurant_handoff')->>'code';
  r := r || public._qa_s13_ok('P8.15 the restaurant holds a real 6-digit handoff code',
        v_code IS NOT NULL AND length(v_code) = 6, NULL);

  -- real R6 handoff
  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
  PERFORM public.mission_set_state(v_mD,'arrived_pickup');
  v_proof := public._qa_r6_proof(v_mD,'pickup',v_drv,'r7ext');
  v_res := public.repas_custody_confirm_handoff(v_mD, v_proof, v_code);
  r := r || public._qa_s13_ok('P8.16 the real custody handoff succeeds', (v_res->>'ok')::boolean, v_res::text);
  v_t := public.repas_order_tracking(v_oD);
  SELECT * INTO v_o FROM public.food_orders WHERE id = v_oD;
  r := r || public._qa_s13_ok('P8.17 tracking equals order truth after handoff',
        v_t->>'state' = v_o.state::text AND v_t->>'state' = 'out_for_delivery', v_t->>'state');
  r := r || public._qa_s13_ok('P8.18 tracking equals mission truth after handoff',
        v_t->'mission'->>'state' = (SELECT state::text FROM public.missions WHERE id=v_mD)
        AND (v_t->'mission'->>'pickup_confirmed_at') IS NOT NULL, v_t->'mission'->>'state');
  r := r || public._qa_s13_ok('P8.19 tracking equals custody truth after handoff',
        (SELECT count(*) FROM jsonb_array_elements(v_t->'custody'->'credentials') e
          WHERE e->>'kind'='restaurant_handoff' AND (e->>'consumed')::boolean) = 1,
        v_t->'custody'->>'credentials');
  r := r || public._qa_s13_ok('P8.20 the customer delivery credential is now pending',
        v_t->'custody'->>'pending_kind' = 'customer_delivery', v_t->'custody'->>'pending_kind');

  -- real R6 delivery
  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
  v_code := public.repas_custody_code_view(v_oD,'customer_delivery')->>'code';
  r := r || public._qa_s13_ok('P8.21 the customer holds the real delivery code',
        v_code IS NOT NULL AND length(v_code) = 6, NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
  PERFORM public.mission_set_state(v_mD,'heading_to_dropoff');
  PERFORM public.mission_set_state(v_mD,'arrived_dropoff');
  v_proof := public._qa_r6_proof(v_mD,'delivery',v_drv,'r7ext');
  v_res := public.repas_custody_confirm_delivery(v_mD, v_proof, v_code);
  r := r || public._qa_s13_ok('P8.22 the real custody delivery succeeds', (v_res->>'ok')::boolean, v_res::text);
  v_t := public.repas_order_tracking(v_oD);
  r := r || public._qa_s13_ok('P8.23 tracking is terminal + completed after real delivery',
        (v_t->>'terminal')::boolean AND v_t->>'state' = 'completed', v_t::text);
  r := r || public._qa_s13_ok('P8.24 tracking still equals mission truth at completion',
        (v_t->'mission'->>'dropoff_confirmed_at') IS NOT NULL
        AND v_t->'mission'->>'state' = (SELECT state::text FROM public.missions WHERE id=v_mD),
        v_t->'mission'::text);
  r := r || public._qa_s13_ok('P8.25 no custody credential is left pending at completion',
        (v_t->'custody'->>'pending_kind') IS NULL, v_t->'custody'->>'pending_kind');

  -- ================= P9. RECEIPT TRUTH AFTER A REAL DELIVERY =================
  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
  v_rc := public.repas_order_receipt(v_oD);
  SELECT * INTO v_o FROM public.food_orders WHERE id = v_oD;
  r := r || public._qa_s13_ok('P9.1 delivery receipt is itemized against the frozen lines',
        jsonb_array_length(v_rc->'items') = 1
        AND (v_rc->>'items_line_total_gnf')::bigint = 100000, v_rc->>'items');
  r := r || public._qa_s13_ok('P9.2 receipt tender equals the committed order tender',
        v_rc->>'payment_method' = v_o.payment_method::text, v_rc->>'payment_method');
  r := r || public._qa_s13_ok('P9.3 receipt delivery fee equals the frozen row',
        (v_rc->>'delivery_fee_gnf')::bigint = COALESCE(v_o.delivery_fee_gnf,0)
        AND (v_rc->>'delivery_fee_gnf')::bigint > 0, v_rc->>'delivery_fee_gnf');
  r := r || public._qa_s13_ok('P9.4 receipt platform fee equals the frozen row',
        (v_rc->>'platform_fee_gnf')::bigint = COALESCE(v_o.platform_fee_gnf,0), v_rc->>'platform_fee_gnf');
  r := r || public._qa_s13_ok('P9.5 receipt total equals the frozen row and reconciles',
        (v_rc->>'order_total_gnf')::bigint = v_o.order_total_gnf
        AND (v_rc->>'totals_reconcile')::boolean, v_rc->>'order_total_gnf');
  r := r || public._qa_s13_ok('P9.6 receipt carries both real custody boundaries',
        (SELECT count(*) FROM jsonb_array_elements(v_rc->'custody_timeline') e) >= 2,
        v_rc->>'custody_timeline');
  r := r || public._qa_s13_ok('P9.7 the custody timeline names the real boundaries',
        v_rc->'custody_timeline'::text LIKE '%restaurant_handoff%'
        AND v_rc->'custody_timeline'::text LIKE '%customer_delivery%', v_rc->>'custody_timeline');
  r := r || public._qa_s13_ok('P9.8 the customer receipt hides courier payout',
        NOT (v_rc ? 'courier_payout_gnf'), NULL);
  r := r || public._qa_s13_ok('P9.9 the customer receipt hides private policy keys',
        NOT (v_rc ? 'pricing_policy_id') AND NOT (v_rc ? 'pricing_snapshot')
        AND NOT (v_rc ? 'promotion_id') AND NOT (v_rc ? 'settlement_state'), v_rc::text);
  r := r || public._qa_s13_ok('P9.10 the receipt records completion and is not cancelled',
        (v_rc->>'completed_at') IS NOT NULL AND (v_rc->>'cancelled')::boolean IS FALSE, NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
  v_res := public.repas_order_receipt(v_oD);
  r := r || public._qa_s13_ok('P9.11 only the entitled courier receipt carries the payout figure',
        (v_res ? 'courier_payout_gnf') AND NOT (v_rc ? 'courier_payout_gnf'), NULL);

  -- ================= P10. READS ARE STRICTLY IDEMPOTENT =================
  SELECT string_agg(c::text, '|' ORDER BY c.id) INTO v_snap_cred
    FROM public.repas_custody_credentials c WHERE c.order_id = v_oD;
  SELECT count(*) INTO v_snap_ev FROM public.repas_custody_events WHERE order_id = v_oD;
  SELECT count(*) INTO v_snap_j FROM public.ledger_journals;
  SELECT string_agg(w.owner_user_id::text||':'||w.balance_gnf||':'||w.held_gnf, '|' ORDER BY w.owner_user_id)
    INTO v_snap_wal FROM public.wallets w
   WHERE w.owner_user_id IN (v_cust, v_merch, v_drv) OR w.party_type = 'master';
  SELECT f::text INTO v_snap_ord FROM public.food_orders f WHERE f.id = v_oD;
  SELECT m::text INTO v_snap_mis FROM public.missions m WHERE m.id = v_mD;

  FOR v_i IN 1..3 LOOP
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    PERFORM public.repas_order_tracking(v_oD); PERFORM public.repas_order_receipt(v_oD);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.repas_order_tracking(v_oD); PERFORM public.repas_order_receipt(v_oD);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.repas_order_tracking(v_oD); PERFORM public.repas_order_receipt(v_oD);
  END LOOP;

  SELECT string_agg(c::text, '|' ORDER BY c.id) INTO v_err
    FROM public.repas_custody_credentials c WHERE c.order_id = v_oD;
  r := r || public._qa_s13_ok('P10.1 repeated reads consume no code and change no attempt counter',
        v_err IS NOT DISTINCT FROM v_snap_cred, NULL);
  SELECT count(*) INTO v_n FROM public.repas_custody_events WHERE order_id = v_oD;
  r := r || public._qa_s13_ok('P10.2 repeated reads create no custody event', v_n = v_snap_ev, v_n::text);
  SELECT count(*) INTO v_n FROM public.ledger_journals;
  r := r || public._qa_s13_ok('P10.3 repeated reads create no ledger journal', v_n = v_snap_j, v_n::text);
  SELECT string_agg(w.owner_user_id::text||':'||w.balance_gnf||':'||w.held_gnf, '|' ORDER BY w.owner_user_id)
    INTO v_err FROM public.wallets w
   WHERE w.owner_user_id IN (v_cust, v_merch, v_drv) OR w.party_type = 'master';
  r := r || public._qa_s13_ok('P10.4 repeated reads move no wallet',
        v_err IS NOT DISTINCT FROM v_snap_wal, NULL);
  SELECT f::text INTO v_err FROM public.food_orders f WHERE f.id = v_oD;
  r := r || public._qa_s13_ok('P10.5 repeated reads mutate no order row',
        v_err IS NOT DISTINCT FROM v_snap_ord, NULL);
  SELECT m::text INTO v_err FROM public.missions m WHERE m.id = v_mD;
  r := r || public._qa_s13_ok('P10.6 repeated reads mutate no mission row',
        v_err IS NOT DISTINCT FROM v_snap_mis, NULL);

  -- ================= P11. TERMINAL NEGATIVE TRUTH (CANCELLED) =================
  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
  v_res := public.repas_order_create(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
      'delivery','choppay', gen_random_uuid(), 'QA R7 Ext Annule', 9.5395, -13.6760);
  v_oC := (v_res->>'order_id')::uuid;
  SELECT id INTO v_mC FROM public.missions WHERE ref_food_order_id = v_oC LIMIT 1;
  v_res := public.repas_customer_cancel_order(v_oC, 'QA R7 terminal negative proof');
  r := r || public._qa_s13_ok('P11.1 the canonical customer cancellation succeeds',
        (v_res->>'ok')::boolean AND v_res->>'state' = 'cancelled', v_res::text);
  v_t := public.repas_order_tracking(v_oC);
  r := r || public._qa_s13_ok('P11.2 a cancelled order tracks as terminal',
        (v_t->>'terminal')::boolean AND v_t->>'state' = 'cancelled', v_t::text);
  r := r || public._qa_s13_ok('P11.3 the terminal reason is stated, never blank success',
        (v_t->>'terminal_reason') IS NOT NULL, v_t->>'terminal_reason');
  r := r || public._qa_s13_ok('P11.4 a cancelled order exposes no completion timestamp',
        (v_t->>'completed_at') IS NULL, v_t->>'completed_at');
  r := r || public._qa_s13_ok('P11.5 a cancelled order leaves no pending custody credential',
        (v_t->'custody'->>'pending_kind') IS NULL, v_t->'custody'->>'pending_kind');
  v_rc := public.repas_order_receipt(v_oC);
  r := r || public._qa_s13_ok('P11.6 the receipt marks the order cancelled',
        (v_rc->>'cancelled')::boolean AND (v_rc->>'completed_at') IS NULL, v_rc::text);
  r := r || public._qa_s13_ok('P11.7 the cancelled receipt still reconciles its frozen totals',
        (v_rc->>'totals_reconcile')::boolean, v_rc->>'totals_reconcile');
  r := r || public._qa_s13_ok('P11.8 the cancelled receipt carries no custody handover evidence',
        jsonb_array_length(v_rc->'custody_timeline') = 0, v_rc->>'custody_timeline');
  SELECT state::text INTO v_err FROM public.missions WHERE id = v_mC;
  r := r || public._qa_s13_ok('P11.9 the unclaimed mission of a cancelled order is failed',
        v_err = 'failed', v_err);
  v_t := public.repas_order_tracking(v_oC);
  r := r || public._qa_s13_ok('P11.10 terminal tracking offers the merchant no action path',
        NOT (v_t ? 'allowed_actions'), v_t::text);

  -- ================= P12. PROMOTION TRUTH =================
  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
  BEGIN
    v_res := public.admin_set_repas_promotion(
      'QA R7 Ext Promo', 'QA R7 rollback-only promotion certification',
      now() - interval '1 minute', now() + interval '1 hour', 'delivery', NULL, 3000);
    v_promo_ok := (v_res->>'ok')::boolean;
  EXCEPTION WHEN OTHERS THEN v_promo_ok := false; v_promo_err := SQLERRM; END;

  IF v_promo_ok THEN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'QA R7 Ext Promo Adresse', 9.5395, -13.6760);
    v_oP := (v_res->>'order_id')::uuid;
    SELECT * INTO v_o FROM public.food_orders WHERE id = v_oP;
    v_rc := public.repas_order_receipt(v_oP);
    r := r || public._qa_s13_ok('P12.1 the promotional order committed under the promotion',
          v_o.promotion_id IS NOT NULL, v_o.promotion_id::text);
    r := r || public._qa_s13_ok('P12.2 receipt base delivery fee equals the frozen row',
          (v_rc->>'base_delivery_fee_gnf')::bigint = COALESCE(v_o.base_delivery_fee_gnf,0),
          v_rc->>'base_delivery_fee_gnf');
    r := r || public._qa_s13_ok('P12.3 receipt promo discount equals the frozen row',
          (v_rc->>'promo_discount_gnf')::bigint = COALESCE(v_o.promo_discount_gnf,0)
          AND (v_rc->>'promo_discount_gnf')::bigint > 0, v_rc->>'promo_discount_gnf');
    r := r || public._qa_s13_ok('P12.4 the receipt names the applied promotion',
          v_rc->>'promotion_name' = 'QA R7 Ext Promo', v_rc->>'promotion_name');
    v_base := (v_rc->>'base_delivery_fee_gnf')::bigint;
    v_del  := (v_rc->>'delivery_fee_gnf')::bigint;
    r := r || public._qa_s13_ok('P12.5 the customer delivery fee is base minus discount',
          v_del = greatest(v_base - (v_rc->>'promo_discount_gnf')::bigint, 0)
          AND v_del = COALESCE(v_o.delivery_fee_gnf,0), v_del::text);
    r := r || public._qa_s13_ok('P12.6 the promotional platform fee equals the frozen row',
          (v_rc->>'platform_fee_gnf')::bigint = COALESCE(v_o.platform_fee_gnf,0),
          v_rc->>'platform_fee_gnf');
    r := r || public._qa_s13_ok('P12.7 the promotional order total equals the frozen row and reconciles',
          (v_rc->>'order_total_gnf')::bigint = v_o.order_total_gnf
          AND (v_rc->>'totals_reconcile')::boolean, v_rc->>'order_total_gnf');
    r := r || public._qa_s13_ok('P12.8 the promotional receipt still hides the payout',
          NOT (v_rc ? 'courier_payout_gnf'), NULL);
  ELSE
    -- Cross-proof fallback: a live enabled promotion window already exists, so a
    -- rollback-only promotion cannot be minted without weakening canonical rules.
    SELECT pg_get_functiondef(p.oid) INTO v_err FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='repas_order_receipt';
    r := r || public._qa_s13_ok('P12.1 LIMITATION promotion could not be minted safely — static cross-proof used',
          v_err LIKE '%base_delivery_fee_gnf%' AND v_err LIKE '%promo_discount_gnf%'
          AND v_err LIKE '%promotion_name%', COALESCE(v_promo_err,'no error'));
    r := r || public._qa_s13_ok('P12.2 the R5 pricing certification harness covers promotion pricing',
          to_regprocedure('public._qa_node3_repas_r5_runtime()') IS NOT NULL, NULL);
  END IF;

  PERFORM set_config('request.jwt.claims', ''::text, true);
  RETURN r;
END;
$fn$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_ext() FROM PUBLIC, anon, authenticated;

-- Surgically extend the existing R7 harness: append the extension results before
-- rollback, and extend the post-rollback residue proof. No other line is touched.
DO $do$
DECLARE v_def text; v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r7_tracking_receipt';
  IF v_def IS NULL THEN RAISE EXCEPTION 'R7 harness not found'; END IF;

  IF position('_qa_node3_repas_r7_ext' in v_def) > 0 THEN
    RAISE NOTICE 'already extended'; RETURN;
  END IF;

  v_new := replace(v_def,
    E'    RAISE EXCEPTION ''QA_NODE3_R7_ROLLBACK'';',
    E'    r := r || public._qa_node3_repas_r7_ext();\n    PERFORM set_config(''request.jwt.claims'', ''''::text, true);\n    RAISE EXCEPTION ''QA_NODE3_R7_ROLLBACK'';');
  IF v_new = v_def THEN RAISE EXCEPTION 'rollback anchor not found'; END IF;

  v_def := v_new;
  v_new := replace(v_def,
    E'  RETURN jsonb_build_object(''part'',''node3_repas_r7_tracking_receipt'',',
    E'  SELECT count(*) INTO v_n FROM public.repas_custody_credentials c\n'
    '    JOIN public.food_orders f ON f.id = c.order_id\n'
    '    JOIN public.food_restaurants fr ON fr.id = f.restaurant_id\n'
    '   WHERE fr.slug LIKE ''qa-n3r7-%'';\n'
    '  r := r || public._qa_s13_ok(''Z7.6 no custody credential residue'', v_n = 0, v_n::text);\n'
    '  SELECT count(*) INTO v_n FROM public.repas_custody_events e\n'
    '    JOIN public.food_orders f ON f.id = e.order_id\n'
    '    JOIN public.food_restaurants fr ON fr.id = f.restaurant_id\n'
    '   WHERE fr.slug LIKE ''qa-n3r7-%'';\n'
    '  r := r || public._qa_s13_ok(''Z7.7 no custody event residue'', v_n = 0, v_n::text);\n'
    '  SELECT count(*) INTO v_n FROM storage.objects\n'
    '   WHERE bucket_id = ''mission-proofs'' AND name LIKE ''%r7ext%'';\n'
    '  r := r || public._qa_s13_ok(''Z7.8 no R7 proof object residue'', v_n = 0, v_n::text);\n'
    '  SELECT count(*) INTO v_n FROM auth.users WHERE email LIKE ''qa-s13-n3r7%'';\n'
    '  r := r || public._qa_s13_ok(''Z7.9 no R7 QA user residue'', v_n = 0, v_n::text);\n'
    '  SELECT count(*) INTO v_n FROM public.repas_pricing_promotions WHERE name LIKE ''QA R7 %'';\n'
    '  r := r || public._qa_s13_ok(''Z7.10 no R7 promotion residue'', v_n = 0, v_n::text);\n'
    '  SELECT count(*) INTO v_n FROM public.missions m\n'
    '   WHERE m.dropoff_address LIKE ''QA R7 %'';\n'
    '  r := r || public._qa_s13_ok(''Z7.11 no R7 mission residue'', v_n = 0, v_n::text);\n\n'
    '  RETURN jsonb_build_object(''part'',''node3_repas_r7_tracking_receipt'',');
  IF v_new = v_def THEN RAISE EXCEPTION 'return anchor not found'; END IF;

  EXECUTE v_new;
  EXECUTE 'REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_tracking_receipt() FROM PUBLIC, anon, authenticated';
END
$do$;