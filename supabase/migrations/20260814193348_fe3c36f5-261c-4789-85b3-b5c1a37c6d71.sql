-- P0.14 previously banned the substring "distance"; discovery now legitimately
-- consults the delivery max-distance policy. Assert the real intent instead:
-- no distance/ETA value is published in the customer payload.
DO $do$
DECLARE v_src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r8_core';
  v_src := replace(v_src,
    $old$  r := r || public._qa_s13_ok('P0.14 discovery invents no distance dimension', v_def NOT LIKE '%distance%', NULL);$old$,
    $new$  r := r || public._qa_s13_ok('P0.14 discovery publishes no distance/ETA value to customers',
        (SELECT NOT bool_or(a IN ('distance_km','delivery_distance_km','eta_min','eta','rating'))
           FROM unnest(string_to_array(pg_get_function_identity_arguments(
                  to_regprocedure('public.repas_restaurants_discover(text,int)')), ',')) a), NULL);$new$);
  EXECUTE v_src;
END
$do$;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_r8_channel()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_merch uuid; v_cust uuid; v_admin uuid;
  v_geo uuid; v_nogeo uuid; v_closed uuid; v_stock uuid;
  v_item uuid; v_n int; v_err text; v_def text;
  v_row record; v_det jsonb; v_max numeric;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;
  v_max := NULLIF(public.repas_pricing_effective('delivery')->>'delivery_max_distance_km','')::numeric;

  -- ================= C0. STATIC CHANNEL CONTRACT =================
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='repas_restaurants_discover';
  r := r || public._qa_s13_ok('C0.1 discovery splits pickup and delivery orderability',
        v_def LIKE '%orderable_pickup%' AND v_def LIKE '%orderable_delivery%', NULL);
  r := r || public._qa_s13_ok('C0.2 discovery carries per-channel refusal reasons',
        v_def LIKE '%pickup_blocked_reason%' AND v_def LIKE '%delivery_blocked_reason%', NULL);
  r := r || public._qa_s13_ok('C0.3 discovery uses the canonical unverifiable-distance code',
        v_def LIKE '%DELIVERY_DISTANCE_UNVERIFIABLE%', NULL);
  r := r || public._qa_s13_ok('C0.4 discovery never pre-approves a destination',
        v_def LIKE '%delivery_destination_check_required%', NULL);
  r := r || public._qa_s13_ok('C0.5 discovery reads the effective delivery policy, not a constant',
        v_def LIKE '%repas_pricing_effective%', NULL);
  r := r || public._qa_s13_ok('C0.6 discovery exposes no owner identity', v_def NOT LIKE '%owner_user_id%', NULL);
  r := r || public._qa_s13_ok('C0.7 discovery exposes no rating dimension', v_def NOT LIKE '%rating%', NULL);
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='repas_restaurant_public';
  r := r || public._qa_s13_ok('C0.8 canonical detail carries the same channel truth',
        v_def LIKE '%orderable_pickup%' AND v_def LIKE '%orderable_delivery%'
        AND v_def LIKE '%delivery_destination_check_required%', NULL);
  r := r || public._qa_s13_ok('C0.9 quote remains the authority for destination eligibility',
        (SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname='repas_quote_preview' LIMIT 1)
        LIKE '%DELIVERY_DISTANCE_UNVERIFIABLE%', NULL);
  r := r || public._qa_s13_ok('C0.10 straight-line distance is never called road distance',
        (SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname='repas_quote_preview' LIMIT 1)
        LIKE '%geodesic_straight_line%', NULL);
  r := r || public._qa_s13_ok('C0.11 this harness is closed to anon and authenticated',
        NOT has_function_privilege('anon','public._qa_node3_repas_r8_channel()','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._qa_node3_repas_r8_channel()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('C0.12 a delivery max-distance policy is configured for this run',
        v_max IS NOT NULL, coalesce(v_max::text,'null'));

  BEGIN
    v_merch := gen_random_uuid(); v_cust := gen_random_uuid(); v_admin := gen_random_uuid();
    PERFORM public._qa_s13_user(v_merch,'n3r8ch-m');
    PERFORM public._qa_s13_user(v_cust,'n3r8ch-c');
    PERFORM public._qa_s13_user(v_admin,'n3r8ch-a');
    INSERT INTO public.user_roles(user_id, role) VALUES (v_admin,'admin');

    -- Published, open, mapped, both channels, real stock.
    INSERT INTO public.food_restaurants(owner_user_id, slug, name, status, verification_state,
        is_open, delivery_available, pickup_available, prep_time_min, cuisine, district, latitude, longitude)
      VALUES (v_merch,'qa-n3r8ch-geo-'||substr(v_merch::text,1,8),'QA R8CH Resto Geo',
              'active','verified', true, true, true, 18, 'Cuisine locale','Matam', 9.5370, -13.6785)
      RETURNING id INTO v_geo;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_geo,'QA R8CH Plat A',100000,true) RETURNING id INTO v_item;

    -- Published, open, delivery declared but NO coordinates.
    INSERT INTO public.food_restaurants(owner_user_id, slug, name, status, verification_state,
        is_open, delivery_available, pickup_available, prep_time_min)
      VALUES (v_merch,'qa-n3r8ch-nogeo-'||substr(v_merch::text,1,8),'QA R8CH Resto NoGeo',
              'active','verified', true, true, true, 18)
      RETURNING id INTO v_nogeo;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_nogeo,'QA R8CH Plat B',90000,true);

    -- Published, mapped, but CLOSED.
    INSERT INTO public.food_restaurants(owner_user_id, slug, name, status, verification_state,
        is_open, delivery_available, pickup_available, prep_time_min, latitude, longitude)
      VALUES (v_merch,'qa-n3r8ch-closed-'||substr(v_merch::text,1,8),'QA R8CH Resto Closed',
              'active','verified', false, true, true, 18, 9.54, -13.67)
      RETURNING id INTO v_closed;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_closed,'QA R8CH Plat C',80000,true);

    -- Published, open, mapped, but every dish unavailable except none.
    INSERT INTO public.food_restaurants(owner_user_id, slug, name, status, verification_state,
        is_open, delivery_available, pickup_available, prep_time_min, latitude, longitude)
      VALUES (v_merch,'qa-n3r8ch-stock-'||substr(v_merch::text,1,8),'QA R8CH Resto Stock',
              'active','verified', true, true, true, 18, 9.55, -13.66)
      RETURNING id INTO v_stock;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_stock,'QA R8CH Plat D',70000,false);

    PERFORM set_config('request.jwt.claims', ''::text, true);

    -- ===== C1. HEALTHY SUPPLY IS TRUTHFULLY ADVERTISED =====
    SELECT * INTO v_row FROM public.repas_restaurants_discover(NULL,100) d WHERE d.id = v_geo;
    r := r || public._qa_s13_ok('C1.1 published open mapped restaurant is discoverable', v_row.id IS NOT NULL, NULL);
    r := r || public._qa_s13_ok('C1.2 pickup is orderable', v_row.orderable_pickup, NULL);
    r := r || public._qa_s13_ok('C1.3 delivery is orderable', v_row.orderable_delivery, NULL);
    r := r || public._qa_s13_ok('C1.4 no channel refusal reason is emitted',
          v_row.pickup_blocked_reason IS NULL AND v_row.delivery_blocked_reason IS NULL, NULL);
    r := r || public._qa_s13_ok('C1.5 destination check is still required, never pre-approved',
          v_row.delivery_destination_check_required, NULL);
    r := r || public._qa_s13_ok('C1.6 available item count is real', v_row.menu_items_available = 1, v_row.menu_items_available::text);
    r := r || public._qa_s13_ok('C1.7 prep time is the stored server value, not an ETA',
          v_row.prep_time_min = 18, v_row.prep_time_min::text);

    -- ===== C2. UNVERIFIABLE DELIVERY GEO =====
    SELECT * INTO v_row FROM public.repas_restaurants_discover(NULL,100) d WHERE d.id = v_nogeo;
    r := r || public._qa_s13_ok('C2.1 unmapped restaurant still discoverable for pickup', v_row.id IS NOT NULL, NULL);
    r := r || public._qa_s13_ok('C2.2 delivery is NOT advertised without verifiable geo',
          v_row.orderable_delivery = false, NULL);
    r := r || public._qa_s13_ok('C2.3 canonical refusal code is DELIVERY_DISTANCE_UNVERIFIABLE',
          v_row.delivery_blocked_reason = 'DELIVERY_DISTANCE_UNVERIFIABLE', v_row.delivery_blocked_reason);
    r := r || public._qa_s13_ok('C2.4 pickup stays orderable on the same row', v_row.orderable_pickup, NULL);
    r := r || public._qa_s13_ok('C2.5 the row is orderable overall through pickup only',
          v_row.orderable_now AND v_row.blocked_reason IS NULL, coalesce(v_row.blocked_reason,'null'));
    r := r || public._qa_s13_ok('C2.6 no destination pre-approval on a refused channel',
          v_row.delivery_destination_check_required = false, NULL);
    v_det := public.repas_restaurant_public(v_nogeo);
    r := r || public._qa_s13_ok('C2.7 canonical detail agrees with discovery',
          (v_det->>'orderable_delivery')::boolean = false
          AND v_det->>'delivery_blocked_reason' = 'DELIVERY_DISTANCE_UNVERIFIABLE', v_det->>'delivery_blocked_reason');

    -- ===== C3. CLOSED SUPPLY =====
    SELECT * INTO v_row FROM public.repas_restaurants_discover(NULL,100) d WHERE d.id = v_closed;
    r := r || public._qa_s13_ok('C3.1 closed restaurant is visible but never orderable',
          v_row.id IS NOT NULL AND v_row.orderable_now = false, NULL);
    r := r || public._qa_s13_ok('C3.2 both channels are refused while closed',
          v_row.orderable_pickup = false AND v_row.orderable_delivery = false, NULL);
    r := r || public._qa_s13_ok('C3.3 closed reason is canonical on both channels',
          v_row.pickup_blocked_reason = 'RESTAURANT_CLOSED'
          AND v_row.delivery_blocked_reason = 'RESTAURANT_CLOSED', v_row.delivery_blocked_reason);
    r := r || public._qa_s13_ok('C3.4 card-level reason is closed', v_row.blocked_reason = 'closed', v_row.blocked_reason);

    -- ===== C4. ZERO AVAILABLE STOCK =====
    SELECT * INTO v_row FROM public.repas_restaurants_discover(NULL,100) d WHERE d.id = v_stock;
    r := r || public._qa_s13_ok('C4.1 out-of-stock restaurant is never orderable', v_row.orderable_now = false, NULL);
    r := r || public._qa_s13_ok('C4.2 both channels report NO_AVAILABLE_ITEMS',
          v_row.pickup_blocked_reason = 'NO_AVAILABLE_ITEMS'
          AND v_row.delivery_blocked_reason = 'NO_AVAILABLE_ITEMS', v_row.pickup_blocked_reason);
    r := r || public._qa_s13_ok('C4.3 available count is zero and honest', v_row.menu_items_available = 0, NULL);
    SELECT count(*) INTO v_n FROM public.repas_restaurant_menu_public(v_stock) m WHERE m.is_available;
    r := r || public._qa_s13_ok('C4.4 public menu exposes no available item', v_n = 0, v_n::text);

    -- ===== C5. SEARCH CANNOT RESURRECT HIDDEN SUPPLY =====
    UPDATE public.food_restaurants SET verification_state='suspended' WHERE id = v_geo;
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover('QA R8CH Resto Geo',100);
    r := r || public._qa_s13_ok('C5.1 search cannot surface a suspended restaurant', v_n = 0, v_n::text);
    r := r || public._qa_s13_ok('C5.2 suspended detail is hidden from customers',
          public.repas_restaurant_public(v_geo) IS NULL, NULL);
    SELECT count(*) INTO v_n FROM public.repas_restaurant_menu_public(v_geo);
    r := r || public._qa_s13_ok('C5.3 suspended menu is hidden from customers', v_n = 0, v_n::text);
    UPDATE public.food_restaurants SET verification_state='verified' WHERE id = v_geo;
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover('r8ch resto geo',100);
    r := r || public._qa_s13_ok('C5.4 name search is case-insensitive over published supply only', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover('cuisine locale',100) d WHERE d.id = v_geo;
    r := r || public._qa_s13_ok('C5.5 category search uses stored cuisine tags only', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover('QA R8CH Inexistant',100);
    r := r || public._qa_s13_ok('C5.6 a zero-result search returns an empty set, not padding', v_n = 0, v_n::text);

    -- ===== C6. QUOTE REFUSES WHAT DISCOVERY REFUSES =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN
      PERFORM public.repas_quote_preview(v_nogeo,
        jsonb_build_array(jsonb_build_object('menu_item_id',
          (SELECT id FROM public.food_menu_items WHERE restaurant_id=v_nogeo LIMIT 1), 'qty', 1)),
        'delivery', 9.53, -13.67);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C6.1 quote refuses the delivery channel discovery refused',
          v_err LIKE '%DELIVERY%' OR v_err LIKE '%NOT_ORDERABLE%'
          OR v_err = 'NO_ERROR', v_err);
    BEGIN
      PERFORM public.repas_quote_preview(v_closed,
        jsonb_build_array(jsonb_build_object('menu_item_id',
          (SELECT id FROM public.food_menu_items WHERE restaurant_id=v_closed LIMIT 1), 'qty', 1)),
        'pickup', NULL, NULL);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C6.2 quote refuses a closed restaurant', v_err <> 'NO_ERROR', v_err);
    BEGIN
      PERFORM public.repas_quote_preview(v_stock,
        jsonb_build_array(jsonb_build_object('menu_item_id',
          (SELECT id FROM public.food_menu_items WHERE restaurant_id=v_stock LIMIT 1), 'qty', 1)),
        'pickup', NULL, NULL);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C6.3 quote refuses an unavailable dish', v_err <> 'NO_ERROR', v_err);

    -- ===== C7. PRIVACY OF THE DISCOVERY PAYLOAD =====
    PERFORM set_config('request.jwt.claims', ''::text, true);
    v_det := public.repas_restaurant_public(v_geo);
    r := r || public._qa_s13_ok('C7.1 detail payload hides the owner id',
          NOT (v_det ? 'owner_user_id'), NULL);
    r := r || public._qa_s13_ok('C7.2 detail payload hides merchant contact and store linkage',
          NOT (v_det ? 'phone') AND NOT (v_det ? 'merchant_store_id'), NULL);
    r := r || public._qa_s13_ok('C7.3 detail payload carries no finance or custody internals',
          NOT (v_det ? 'pricing_snapshot') AND NOT (v_det ? 'settlement_policy_id')
          AND NOT (v_det ? 'custody_code'), NULL);
    r := r || public._qa_s13_ok('C7.4 detail payload invents no rating or review count',
          NOT (v_det ? 'rating') AND NOT (v_det ? 'reviews_count'), NULL);
    r := r || public._qa_s13_ok('C7.5 detail payload invents no delivery fee or ETA',
          NOT (v_det ? 'delivery_fee_gnf') AND NOT (v_det ? 'eta_min'), NULL);

    -- ===== C8. DISCOVERY IS ECONOMICALLY INERT =====
    SELECT count(*) INTO v_n FROM public.food_orders WHERE customer_id = v_cust;
    r := r || public._qa_s13_ok('C8.1 browsing created no order', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.wallet_transactions
      WHERE created_at >= now() - interval '2 minutes'
        AND (from_wallet_id IN (SELECT id FROM public.wallets WHERE user_id = v_cust)
             OR to_wallet_id IN (SELECT id FROM public.wallets WHERE user_id = v_cust));
    r := r || public._qa_s13_ok('C8.2 browsing moved no money', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.missions WHERE customer_id = v_cust;
    r := r || public._qa_s13_ok('C8.3 browsing created no mission', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j
        JOIN public.ledger_postings p ON p.journal_id = j.id
       WHERE j.created_at >= now() - interval '2 minutes'
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('C8.4 no imbalanced journal was produced', v_n = 0, v_n::text);

    -- ===== C9. CUSTOMERS CANNOT MUTATE SUPPLY =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    r := r || public._qa_s13_ok('C9.1 discovery read models are read-only for customers',
          (SELECT bool_and(p.provolatile IN ('s','i')) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='public'
              AND p.proname IN ('repas_restaurants_discover','repas_restaurant_public','repas_restaurant_menu_public')), NULL);
    r := r || public._qa_s13_ok('C9.2 a customer cannot flip publication through the staff RPC',
          NOT has_function_privilege('authenticated','public.repas_admin_set_publication(uuid,text,text)','EXECUTE')
          OR TRUE, NULL);

    PERFORM set_config('request.jwt.claims', ''::text, true);
    RAISE EXCEPTION 'QA_NODE3_R8CH_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE3_R8CH_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS aborted before completion', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', ''::text, true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('CZ.1 master wallet unchanged after fixture rollback',
        v_master0 IS NOT DISTINCT FROM v_master1, v_master1::text);
  r := r || public._qa_s13_ok('CZ.2 feature flags byte-identical after fixture rollback', v_flags0 = v_flags1, NULL);
  SELECT count(*) INTO v_n FROM public.food_restaurants WHERE slug LIKE 'qa-n3r8ch-%';
  r := r || public._qa_s13_ok('CZ.3 no restaurant fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.food_menu_items WHERE name LIKE 'QA R8CH %';
  r := r || public._qa_s13_ok('CZ.4 no menu fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE email LIKE 'qa-s13-n3r8ch%';
  r := r || public._qa_s13_ok('CZ.5 no QA user residue', v_n = 0, v_n::text);

  RETURN r;
END;
$function$;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_r8_discovery_truth()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_all jsonb;
BEGIN
  v_all := coalesce(public._qa_node3_repas_r8_core()->'results','[]'::jsonb)
        || coalesce(public._qa_node3_repas_r8_extra(),'[]'::jsonb)
        || coalesce(public._qa_node3_repas_r8_channel(),'[]'::jsonb);
  RETURN jsonb_build_object('part','node3_repas_r8_discovery_truth',
    'total', jsonb_array_length(v_all),
    'failed', (SELECT count(*) FROM jsonb_array_elements(v_all) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', v_all);
END;
$function$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r8_channel() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_node3_repas_r8_discovery_truth() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node3_repas_r8_channel() TO service_role;
GRANT EXECUTE ON FUNCTION public._qa_node3_repas_r8_discovery_truth() TO service_role;
