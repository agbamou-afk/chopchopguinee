CREATE OR REPLACE FUNCTION public._qa_node3_repas_r8_discovery()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  v_merch uuid; v_cust uuid; v_stranger uuid; v_admin uuid;
  v_resto uuid; v_resto2 uuid; v_empty uuid;
  v_item uuid; v_item2 uuid;
  v_n int; v_err text; v_def text; v_qual text;
  v_det jsonb; v_row record;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_unbalanced int;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  -- ===================== P0. STATIC CONTRACT =====================
  r := r || public._qa_s13_ok('P0.1 discovery read model exists',
        to_regprocedure('public.repas_restaurants_discover(text,int)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('P0.2 canonical restaurant detail read exists',
        to_regprocedure('public.repas_restaurant_public(uuid)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('P0.3 canonical public menu read exists',
        to_regprocedure('public.repas_restaurant_menu_public(uuid)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('P0.4 staff publication RPC exists',
        to_regprocedure('public.repas_admin_set_publication(uuid,text,text)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('P0.5 privileged-column guard trigger installed',
        EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
                 WHERE c.relname='food_restaurants' AND t.tgname='trg_food_restaurant_guard'), NULL);
  r := r || public._qa_s13_ok('P0.6 anon may browse canonical discovery',
        has_function_privilege('anon','public.repas_restaurants_discover(text,int)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.7 anon may read canonical detail',
        has_function_privilege('anon','public.repas_restaurant_public(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.8 publication action closed to anon',
        NOT has_function_privilege('anon','public.repas_admin_set_publication(uuid,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.9 this harness is closed to anon/authenticated',
        NOT has_function_privilege('anon','public._qa_node3_repas_r8_discovery()','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._qa_node3_repas_r8_discovery()','EXECUTE'), NULL);

  SELECT qual INTO v_qual FROM pg_policies
   WHERE schemaname='public' AND tablename='food_restaurants' AND cmd='SELECT' LIMIT 1;
  r := r || public._qa_s13_ok('P0.10 restaurant public SELECT policy demands verified publication',
        v_qual LIKE '%verified%', v_qual);
  SELECT qual INTO v_qual FROM pg_policies
   WHERE schemaname='public' AND tablename='food_menu_items' AND cmd='SELECT' LIMIT 1;
  r := r || public._qa_s13_ok('P0.11 menu public SELECT policy demands verified publication',
        v_qual LIKE '%verified%', v_qual);

  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='repas_restaurants_discover';
  r := r || public._qa_s13_ok('P0.12 discovery invents no rating dimension', v_def NOT LIKE '%rating%', NULL);
  r := r || public._qa_s13_ok('P0.13 discovery invents no ETA dimension', v_def NOT LIKE '%eta%', NULL);
  r := r || public._qa_s13_ok('P0.14 discovery invents no distance dimension', v_def NOT LIKE '%distance%', NULL);
  r := r || public._qa_s13_ok('P0.15 discovery never exposes owner identity', v_def NOT LIKE '%owner_user_id%', NULL);
  r := r || public._qa_s13_ok('P0.16 discovery separates orderable_now from discoverability',
        v_def LIKE '%orderable_now%' AND v_def LIKE '%blocked_reason%', NULL);
  r := r || public._qa_s13_ok('P0.17 zero-menu supply is excluded at source',
        v_def LIKE '%b.tot > 0%', NULL);

  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_food_restaurant_guard';
  r := r || public._qa_s13_ok('P0.18 guard blocks self-publication',
        v_def LIKE '%RESTAURANT_PUBLICATION_IS_STAFF_ONLY%', NULL);
  r := r || public._qa_s13_ok('P0.19 guard blocks self-enabling Chop Pay',
        v_def LIKE '%RESTAURANT_CHOPPAY_IS_STAFF_ONLY%', NULL);
  r := r || public._qa_s13_ok('P0.20 guard blocks owner/store reassignment',
        v_def LIKE '%RESTAURANT_OWNER_IS_IMMUTABLE%' AND v_def LIKE '%RESTAURANT_STORE_LINK_IS_STAFF_ONLY%', NULL);

  BEGIN
    v_merch := gen_random_uuid(); v_cust := gen_random_uuid();
    v_stranger := gen_random_uuid(); v_admin := gen_random_uuid();
    PERFORM public._qa_s13_user(v_merch,'n3r8m');
    PERFORM public._qa_s13_user(v_cust,'n3r8c');
    PERFORM public._qa_s13_user(v_stranger,'n3r8x');
    PERFORM public._qa_s13_user(v_admin,'n3r8a');
    INSERT INTO public.user_roles(user_id, role) VALUES (v_admin, 'admin');

    INSERT INTO public.food_restaurants(owner_user_id, slug, name, status, verification_state,
        is_open, delivery_available, pickup_available, choppay_enabled, prep_time_min, cuisine, district)
      VALUES (v_merch, 'qa-n3r8-resto-'||substr(v_merch::text,1,8), 'QA R8 Resto Alpha',
              'active','none', true, true, true, false, 20, 'Cuisine locale', 'Matam')
      RETURNING id INTO v_resto;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA R8 Plat A',100000,true) RETURNING id INTO v_item;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA R8 Plat B',50000,true) RETURNING id INTO v_item2;

    INSERT INTO public.food_restaurants(owner_user_id, slug, name, status, verification_state,
        is_open, delivery_available, pickup_available, prep_time_min)
      VALUES (v_stranger, 'qa-n3r8-empty-'||substr(v_stranger::text,1,8), 'QA R8 Resto Alpha Empty',
              'active','verified', true, false, true, 20)
      RETURNING id INTO v_empty;

    -- ===== P1. DRAFT / PENDING IS NOT CUSTOMER SUPPLY =====
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover(NULL, 100) d WHERE d.id = v_resto;
    r := r || public._qa_s13_ok('P1.1 unverified active restaurant is not discoverable', v_n = 0, v_n::text);
    r := r || public._qa_s13_ok('P1.2 anon detail read of a draft returns nothing',
          public.repas_restaurant_public(v_resto) IS NULL, NULL);
    SELECT count(*) INTO v_n FROM public.repas_restaurant_menu_public(v_resto);
    r := r || public._qa_s13_ok('P1.3 anon menu read of a draft returns nothing', v_n = 0, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    r := r || public._qa_s13_ok('P1.4 signed-in customer cannot read a draft either',
          public.repas_restaurant_public(v_resto) IS NULL, NULL);
    SELECT count(*) INTO v_n FROM public.repas_restaurant_menu_public(v_resto);
    r := r || public._qa_s13_ok('P1.5 signed-in customer cannot read a draft menu', v_n = 0, v_n::text);

    -- ===== P2. OWNER MAY PREPARE AND INSPECT =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_det := public.repas_restaurant_public(v_resto);
    r := r || public._qa_s13_ok('P2.1 owner can inspect its own draft', v_det IS NOT NULL, NULL);
    r := r || public._qa_s13_ok('P2.2 owner draft is labelled draft, not published',
          v_det->>'publication_state' = 'draft' AND (v_det->>'published')::boolean = false, v_det->>'publication_state');
    r := r || public._qa_s13_ok('P2.3 owner draft is not orderable',
          (v_det->>'orderable_now')::boolean = false AND v_det->>'blocked_reason' = 'not_published', v_det->>'blocked_reason');
    SELECT count(*) INTO v_n FROM public.repas_restaurant_menu_public(v_resto);
    r := r || public._qa_s13_ok('P2.4 owner can inspect its own draft menu', v_n = 2, v_n::text);
    r := r || public._qa_s13_ok('P2.5 owner flag is honest in the detail payload',
          (v_det->>'viewer_is_owner')::boolean = true, NULL);

    -- ===== P3. OWNER CANNOT SELF-CERTIFY =====
    BEGIN UPDATE public.food_restaurants SET verification_state='verified' WHERE id=v_resto; v_err:='NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P3.1 owner cannot self-publish',
          v_err LIKE '%RESTAURANT_PUBLICATION_IS_STAFF_ONLY%', v_err);
    BEGIN UPDATE public.food_restaurants SET choppay_enabled=true WHERE id=v_resto; v_err:='NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P3.2 owner cannot self-enable Chop Pay',
          v_err LIKE '%RESTAURANT_CHOPPAY_IS_STAFF_ONLY%', v_err);
    BEGIN UPDATE public.food_restaurants SET owner_user_id=v_stranger WHERE id=v_resto; v_err:='NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P3.3 owner cannot hand the restaurant to someone else',
          v_err LIKE '%RESTAURANT_OWNER_IS_IMMUTABLE%', v_err);
    BEGIN UPDATE public.food_restaurants SET status='inactive' WHERE id=v_resto; v_err:='NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P3.4 owner cannot move canonical status',
          v_err LIKE '%RESTAURANT_STATUS_IS_STAFF_ONLY%', v_err);
    UPDATE public.food_restaurants SET name='QA R8 Resto Alpha', cuisine='Cuisine locale' WHERE id=v_resto;
    r := r || public._qa_s13_ok('P3.5 owner can still edit its own profile fields',
          (SELECT cuisine FROM public.food_restaurants WHERE id=v_resto) = 'Cuisine locale', NULL);
    SELECT verification_state INTO v_err FROM public.food_restaurants WHERE id=v_resto;
    r := r || public._qa_s13_ok('P3.6 refused self-publication left state untouched', v_err = 'none', v_err);

    BEGIN PERFORM public.repas_admin_set_publication(v_resto,'publish','owner tries'); v_err:='NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P3.7 owner cannot invoke the staff publication RPC',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_stranger), true);
    BEGIN PERFORM public.repas_admin_set_publication(v_resto,'publish','stranger tries'); v_err:='NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P3.8 stranger cannot publish another restaurant',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);

    -- ===== P4. STAFF PUBLICATION =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_admin), true);
    PERFORM public.repas_admin_set_publication(v_resto,'publish','QA R8 approval');
    SELECT verification_state INTO v_err FROM public.food_restaurants WHERE id=v_resto;
    r := r || public._qa_s13_ok('P4.1 staff publication sets the verified state', v_err = 'verified', v_err);
    SELECT count(*) INTO v_n FROM public.audit_logs
     WHERE module='repas' AND action='restaurant_publish' AND target_id = v_resto::text;
    r := r || public._qa_s13_ok('P4.2 publication is audited exactly once', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.audit_logs
     WHERE module='repas' AND target_id = v_resto::text AND actor_user_id = v_admin;
    r := r || public._qa_s13_ok('P4.3 audit row carries the deciding staff identity', v_n = 1, v_n::text);

    -- ===== P5. PUBLISHED SUPPLY IS REAL =====
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover(NULL, 100) d WHERE d.id = v_resto;
    r := r || public._qa_s13_ok('P5.1 published restaurant appears exactly once', v_n = 1, v_n::text);
    SELECT * INTO v_row FROM public.repas_restaurants_discover(NULL, 100) d WHERE d.id = v_resto;
    r := r || public._qa_s13_ok('P5.2 discovery reports real total menu count', v_row.menu_items_total = 2, v_row.menu_items_total::text);
    r := r || public._qa_s13_ok('P5.3 discovery reports real available menu count', v_row.menu_items_available = 2, v_row.menu_items_available::text);
    r := r || public._qa_s13_ok('P5.4 published + open + stock + fulfilment => orderable now',
          v_row.orderable_now = true AND v_row.blocked_reason IS NULL, coalesce(v_row.blocked_reason,'null'));
    r := r || public._qa_s13_ok('P5.5 delivery without coordinates is not advertised as ready',
          v_row.delivery_available = true AND v_row.has_coordinates = false AND v_row.delivery_ready = false, NULL);
    r := r || public._qa_s13_ok('P5.6 pickup remains genuinely supported', v_row.pickup_ready = true, NULL);
    r := r || public._qa_s13_ok('P5.7 Chop Pay capability stays off until staff approve it',
          v_row.choppay_enabled = false, NULL);
    v_det := public.repas_restaurant_public(v_resto);
    r := r || public._qa_s13_ok('P5.8 anon detail read works once published', v_det IS NOT NULL, NULL);
    r := r || public._qa_s13_ok('P5.9 public detail payload leaks no owner uuid',
          NOT (v_det ? 'owner_user_id') AND v_det::text NOT LIKE '%'||v_merch::text||'%', NULL);
    r := r || public._qa_s13_ok('P5.10 public detail payload leaks no merchant store link',
          NOT (v_det ? 'merchant_store_id'), NULL);
    r := r || public._qa_s13_ok('P5.11 public detail payload carries no coordinates',
          NOT (v_det ? 'latitude') AND NOT (v_det ? 'longitude'), NULL);
    r := r || public._qa_s13_ok('P5.12 public detail payload carries no rating/eta invention',
          NOT (v_det ? 'rating') AND NOT (v_det ? 'eta_min') AND NOT (v_det ? 'distance_km'), NULL);
    SELECT count(*) INTO v_n FROM public.repas_restaurant_menu_public(v_resto);
    r := r || public._qa_s13_ok('P5.13 anon can now read the real published menu', v_n = 2, v_n::text);

    -- ===== P6. ZERO-MENU SUPPLY =====
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover(NULL, 100) d WHERE d.id = v_empty;
    r := r || public._qa_s13_ok('P6.1 published restaurant with zero menu items is not usable supply',
          v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover('QA R8 Resto Alpha', 100) d WHERE d.id = v_empty;
    r := r || public._qa_s13_ok('P6.2 search cannot resurrect zero-menu supply', v_n = 0, v_n::text);
    v_det := public.repas_restaurant_public(v_empty);
    r := r || public._qa_s13_ok('P6.3 direct detail read of a zero-menu restaurant is explicit, not orderable',
          (v_det->>'orderable_now')::boolean = false AND v_det->>'blocked_reason' = 'no_menu', v_det->>'blocked_reason');

    -- ===== P7. SEARCH / FILTER TRUTH =====
    INSERT INTO public.food_restaurants(owner_user_id, slug, name, status, verification_state,
        is_open, delivery_available, pickup_available, prep_time_min, cuisine, district)
      VALUES (v_stranger, 'qa-n3r8-hidden-'||substr(v_cust::text,1,8), 'QA R8 Resto Alpha Hidden',
              'active','none', true, false, true, 20, 'Cuisine locale', 'Matam')
      RETURNING id INTO v_resto2;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto2,'QA R8 Plat cache',10000,true);
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover('QA R8 Resto Alpha', 100);
    r := r || public._qa_s13_ok('P7.1 name search returns only the published match', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover('QA R8 Resto Alpha', 100) d WHERE d.id = v_resto2;
    r := r || public._qa_s13_ok('P7.2 a pending restaurant with a real menu stays out of search', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover('Cuisine locale', 100) d WHERE d.id = v_resto;
    r := r || public._qa_s13_ok('P7.3 cuisine search matches the published restaurant', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover('Matam', 100) d WHERE d.id = v_resto;
    r := r || public._qa_s13_ok('P7.4 district search matches the published restaurant', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover('zzz-nothing-here', 100);
    r := r || public._qa_s13_ok('P7.5 a non-matching search yields an honest empty result', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover(NULL, 100) d
      JOIN public.food_restaurants fr ON fr.id = d.id
     WHERE fr.verification_state <> 'verified' OR fr.status <> 'active';
    r := r || public._qa_s13_ok('P7.6 discovery never returns a row outside the published set', v_n = 0, v_n::text);

    -- ===== P8. CLOSED / OUT-OF-STOCK TRUTH =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    UPDATE public.food_restaurants SET is_open=false WHERE id=v_resto;
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT * INTO v_row FROM public.repas_restaurants_discover(NULL, 100) d WHERE d.id = v_resto;
    r := r || public._qa_s13_ok('P8.1 a closed published restaurant is still shown', v_row.id IS NOT NULL, NULL);
    r := r || public._qa_s13_ok('P8.2 closed means not orderable now',
          v_row.orderable_now = false AND v_row.blocked_reason = 'closed', coalesce(v_row.blocked_reason,'null'));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'pickup','choppay', gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P8.3 checkout cannot bypass a closed restaurant',
          v_err LIKE '%RESTAURANT_CLOSED%', v_err);
    SELECT count(*) INTO v_n FROM public.food_orders WHERE user_id=v_cust;
    r := r || public._qa_s13_ok('P8.4 the refused checkout created zero orders', v_n = 0, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    UPDATE public.food_restaurants SET is_open=true WHERE id=v_resto;
    UPDATE public.food_menu_items SET is_available=false WHERE restaurant_id=v_resto;
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT * INTO v_row FROM public.repas_restaurants_discover(NULL, 100) d WHERE d.id = v_resto;
    r := r || public._qa_s13_ok('P8.5 a menu with zero available items is not orderable',
          v_row.orderable_now = false AND v_row.blocked_reason = 'no_available_items', coalesce(v_row.blocked_reason,'null'));
    r := r || public._qa_s13_ok('P8.6 total vs available counts stay distinct',
          v_row.menu_items_total = 2 AND v_row.menu_items_available = 0, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'pickup','choppay', gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P8.7 an unavailable item cannot be ordered', v_err <> 'NO_ERROR', v_err);
    SELECT count(*) INTO v_n FROM public.food_orders WHERE user_id=v_cust;
    r := r || public._qa_s13_ok('P8.8 the refused unavailable-item checkout created zero orders', v_n = 0, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    UPDATE public.food_menu_items SET is_available=true WHERE restaurant_id=v_resto;

    -- ===== P9. SUSPENSION IS IMMEDIATE =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_admin), true);
    PERFORM public.repas_admin_set_publication(v_resto,'suspend','QA R8 suspension');
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover(NULL, 100) d WHERE d.id = v_resto;
    r := r || public._qa_s13_ok('P9.1 a suspended restaurant disappears from discovery at once', v_n = 0, v_n::text);
    r := r || public._qa_s13_ok('P9.2 anon detail read of a suspended restaurant returns nothing',
          public.repas_restaurant_public(v_resto) IS NULL, NULL);
    SELECT count(*) INTO v_n FROM public.repas_restaurant_menu_public(v_resto);
    r := r || public._qa_s13_ok('P9.3 a suspended restaurant menu is no longer public', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.audit_logs
     WHERE module='repas' AND action='restaurant_suspend' AND target_id = v_resto::text;
    r := r || public._qa_s13_ok('P9.4 suspension is audited', v_n = 1, v_n::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'pickup','choppay', gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P9.5 checkout on a suspended restaurant fails closed',
          v_err LIKE '%RESTAURANT_NOT_ORDERABLE%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_det := public.repas_restaurant_public(v_resto);
    r := r || public._qa_s13_ok('P9.6 owner still sees its suspended restaurant, labelled suspended',
          v_det IS NOT NULL AND v_det->>'publication_state' = 'suspended', v_det->>'publication_state');

    -- ===== P10. RE-PUBLICATION AND HISTORY =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_admin), true);
    PERFORM public.repas_admin_set_publication(v_resto,'publish','QA R8 re-publication');
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover(NULL, 100) d WHERE d.id = v_resto;
    r := r || public._qa_s13_ok('P10.1 re-publication restores discovery exactly once', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.audit_logs WHERE module='repas' AND target_id = v_resto::text;
    r := r || public._qa_s13_ok('P10.2 every publication transition is audited', v_n = 3, v_n::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    UPDATE public.food_menu_items SET name='QA R8 Plat A v2', price_gnf=123000 WHERE id=v_item;
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT * INTO v_row FROM public.repas_restaurants_discover(NULL, 100) d WHERE d.id = v_resto;
    r := r || public._qa_s13_ok('P10.3 post-publication menu edits update future discovery honestly',
          v_row.menu_items_available = 2, v_row.menu_items_available::text);

    -- ===== P11. NO VALUE / FLAG DRIFT =====
    SELECT count(*) INTO v_n FROM public.food_orders WHERE user_id = v_cust;
    r := r || public._qa_s13_ok('P11.1 the whole discovery pass created zero orders', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.missions WHERE customer_id = v_cust;
    r := r || public._qa_s13_ok('P11.2 the whole discovery pass created zero missions', v_n = 0, v_n::text);
    SELECT count(*) INTO v_unbalanced FROM (
      SELECT j.id FROM public.ledger_journals j
        JOIN public.ledger_postings p ON p.journal_id = j.id
       WHERE j.created_at >= now() - interval '5 minutes'
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('P11.3 no imbalanced journal was produced', v_unbalanced = 0, v_unbalanced::text);

    PERFORM set_config('request.jwt.claims', ''::text, true);
    RAISE EXCEPTION 'QA_NODE3_R8_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE3_R8_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS aborted before completion', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', ''::text, true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z.1 master wallet unchanged after fixture rollback',
        v_master0 IS NOT DISTINCT FROM v_master1, v_master1::text);
  r := r || public._qa_s13_ok('Z.2 feature flags byte-identical after fixture rollback',
        v_flags0 = v_flags1, NULL);
  SELECT count(*) INTO v_n FROM public.food_restaurants WHERE slug LIKE 'qa-n3r8-%';
  r := r || public._qa_s13_ok('Z.3 no restaurant fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.food_menu_items WHERE name LIKE 'QA R8 %';
  r := r || public._qa_s13_ok('Z.4 no menu fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.audit_logs WHERE module='repas' AND note LIKE 'QA R8 %';
  r := r || public._qa_s13_ok('Z.5 no audit residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE email LIKE 'qa-s13-n3r8%';
  r := r || public._qa_s13_ok('Z.6 no QA user residue', v_n = 0, v_n::text);

  RETURN jsonb_build_object('part','node3_repas_r8_discovery',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END;
$fn$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r8_discovery() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node3_repas_r8_discovery() TO service_role;

INSERT INTO public._qa_s13_results(part, result)
SELECT 980, jsonb_build_object(
  'total', v->>'total',
  'failed', v->>'failed',
  'failures', (SELECT jsonb_agg(e) FROM jsonb_array_elements(v->'results') e WHERE (e->>'ok')::boolean IS NOT TRUE)
) FROM (SELECT public._qa_node3_repas_r8_discovery() AS v) s;