CREATE OR REPLACE FUNCTION public._qa_node3_repas_r8_extra()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_merch uuid; v_cust uuid; v_stranger uuid; v_admin uuid;
  v_resto uuid; v_empty uuid; v_item uuid; v_item2 uuid; v_store uuid;
  v_n int; v_err text; v_res jsonb; v_ord uuid;
  v_rec0 jsonb; v_rec1 jsonb; v_trk jsonb;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_flag_prev boolean; v_owner_role text;
BEGIN
  v_owner_role := current_user;
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  -- ============ P12. STATIC PUBLICATION-BYPASS CONTRACT ============
  r := r || public._qa_s13_ok('P12.0 canonical publication assertion helper exists',
        EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                 WHERE n.nspname='public' AND p.proname='_repas_assert_orderable_publication'), NULL);
  r := r || public._qa_s13_ok('P12.1 quote calls the canonical publication assertion',
        (SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname='repas_quote_preview' LIMIT 1)
        LIKE '%_repas_assert_orderable_publication%', NULL);
  r := r || public._qa_s13_ok('P12.2 commit calls the canonical publication assertion',
        (SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname='repas_order_create' LIMIT 1)
        LIKE '%_repas_assert_orderable_publication%', NULL);
  r := r || public._qa_s13_ok('P12.3 publication RPC refuses empty supply in source',
        (SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname='repas_admin_set_publication' LIMIT 1)
        LIKE '%PUBLISH_REQUIRES_MENU%', NULL);
  r := r || public._qa_s13_ok('P12.4 admin ops overview read model exists',
        to_regprocedure('public.repas_admin_restaurant_overview()') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('P12.5 admin ops overview closed to anon',
        NOT has_function_privilege('anon','public.repas_admin_restaurant_overview()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P12.6 admin ops overview invents no rating/revenue metric',
        (SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname='repas_admin_restaurant_overview' LIMIT 1)
        NOT LIKE '%rating%', NULL);
  r := r || public._qa_s13_ok('P12.7 restaurant INSERT policy exists (no self-serve supply)',
        EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='food_restaurants' AND cmd IN ('INSERT','ALL')), NULL);
  r := r || public._qa_s13_ok('P12.8 every restaurant INSERT path demands a real caller identity',
        (SELECT coalesce(bool_and(with_check LIKE '%auth.uid()%'), false) FROM pg_policies
          WHERE schemaname='public' AND tablename='food_restaurants' AND cmd IN ('INSERT','ALL')), NULL);
  r := r || public._qa_s13_ok('P12.9 every menu INSERT path demands a real caller identity',
        (SELECT coalesce(bool_and(with_check LIKE '%auth.uid()%'), false) FROM pg_policies
          WHERE schemaname='public' AND tablename='food_menu_items' AND cmd IN ('INSERT','ALL')), NULL);
  r := r || public._qa_s13_ok('P12.10 row level security is enforced on both supply tables',
        (SELECT bool_and(c.relrowsecurity) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
          WHERE n.nspname='public' AND c.relname IN ('food_restaurants','food_menu_items')), NULL);

  BEGIN
    v_merch := gen_random_uuid(); v_cust := gen_random_uuid();
    v_stranger := gen_random_uuid(); v_admin := gen_random_uuid();
    PERFORM public._qa_s13_user(v_merch,'n3r8xm');
    PERFORM public._qa_s13_user(v_cust,'n3r8xc');
    PERFORM public._qa_s13_user(v_stranger,'n3r8xs');
    PERFORM public._qa_s13_user(v_admin,'n3r8xa');
    INSERT INTO public.user_roles(user_id, role) VALUES (v_admin,'admin');
    PERFORM public._qa_s13_wallet(v_cust,'client',3000000,0);
    PERFORM public._qa_s13_wallet(v_merch,'merchant',0,0);

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, delivery_available, status)
      VALUES (v_merch,'qa-n3r8x-store-'||substr(v_merch::text,1,8),'QA R8X Store', true,'active')
      RETURNING id INTO v_store;
    INSERT INTO public.food_restaurants(owner_user_id, merchant_store_id, slug, name, status,
        verification_state, is_open, delivery_available, pickup_available, choppay_enabled,
        prep_time_min, latitude, longitude)
      VALUES (v_merch, v_store,'qa-n3r8x-resto-'||substr(v_merch::text,1,8),'QA R8X Resto',
              'active','none', true, true, true, true, 20, 9.5370, -13.6785)
      RETURNING id INTO v_resto;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA R8X Plat A',100000,true) RETURNING id INTO v_item;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA R8X Plat B',50000,true) RETURNING id INTO v_item2;
    INSERT INTO public.food_restaurants(owner_user_id, slug, name, status, verification_state,
        is_open, delivery_available, pickup_available, prep_time_min)
      VALUES (v_stranger,'qa-n3r8x-empty-'||substr(v_stranger::text,1,8),'QA R8X Resto Empty',
              'active','none', true, false, true, 15)
      RETURNING id INTO v_empty;

    SELECT enabled INTO v_flag_prev FROM public.feature_flags WHERE key='chop_pay_checkout_enabled';
    UPDATE public.feature_flags SET enabled = true WHERE key='chop_pay_checkout_enabled';

    -- ===== P13. DRAFT CANNOT BE QUOTED OR COMMITTED (BYPASS PROOF) =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN
      PERFORM public.repas_quote_preview(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),'pickup', NULL, NULL);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P13.1 draft restaurant refuses the customer quote',
          v_err LIKE '%RESTAURANT_NOT_PUBLISHED%', v_err);

    BEGIN
      PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'pickup','choppay', gen_random_uuid());
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P13.2 draft restaurant refuses the order commitment',
          v_err LIKE '%RESTAURANT_NOT_PUBLISHED%', v_err);
    r := r || public._qa_s13_ok('P13.3 quote and commit use one canonical refusal',
          v_err LIKE '%RESTAURANT_NOT_PUBLISHED%', v_err);

    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT count(*) INTO v_n FROM public.food_orders WHERE restaurant_id = v_resto;
    r := r || public._qa_s13_ok('P13.4 refusal happened before any durable order', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.missions WHERE customer_id = v_cust;
    r := r || public._qa_s13_ok('P13.5 refusal happened before any mission', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.wallet_transactions WHERE wallet_id IN
      (SELECT id FROM public.wallets WHERE owner_user_id = v_cust);
    r := r || public._qa_s13_ok('P13.6 refusal moved no money', v_n = 0, v_n::text);
    SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('P13.7 refusal left the master wallet untouched',
          v_master0 IS NOT DISTINCT FROM v_master1, v_master1::text);

    -- ===== P14. ZERO-MENU PUBLICATION IS REFUSED SERVER-SIDE =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_admin), true);
    BEGIN PERFORM public.repas_admin_set_publication(v_empty,'publish','QA R8X empty'); v_err:='NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P14.1 publishing a zero-menu restaurant is refused',
          v_err LIKE '%PUBLISH_REQUIRES_MENU%', v_err);
    SELECT verification_state INTO v_err FROM public.food_restaurants WHERE id=v_empty;
    r := r || public._qa_s13_ok('P14.2 the refused restaurant stayed unpublished', v_err = 'none', v_err);
    SELECT count(*) INTO v_n FROM public.audit_logs
     WHERE module='repas' AND target_id = v_empty::text AND action='restaurant_publish';
    r := r || public._qa_s13_ok('P14.3 a refused publication writes no success audit', v_n = 0, v_n::text);

    UPDATE public.food_menu_items SET is_available=false WHERE restaurant_id=v_resto;
    PERFORM public.repas_admin_set_publication(v_resto,'publish','QA R8X publish');
    SELECT verification_state INTO v_err FROM public.food_restaurants WHERE id=v_resto;
    r := r || public._qa_s13_ok('P14.4 a real menu that is temporarily unavailable may still publish',
          v_err = 'verified', v_err);
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover(NULL,100) d
     WHERE d.id = v_resto AND d.orderable_now = false AND d.blocked_reason='no_available_items';
    r := r || public._qa_s13_ok('P14.5 discovery shows it visible but not orderable', v_n = 1, v_n::text);
    UPDATE public.food_menu_items SET is_available=true WHERE restaurant_id=v_resto;

    -- ===== P15. STRANGER / ANON DIRECT TABLE MUTATION =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_stranger), true);
    r := r || public._qa_s13_ok('P15.1 restaurant UPDATE policies are owner/staff scoped',
          (SELECT coalesce(bool_and(coalesce(qual,with_check) LIKE '%auth.uid()%'), false)
             FROM pg_policies WHERE schemaname='public' AND tablename='food_restaurants'
              AND cmd IN ('UPDATE','ALL')), NULL);
    r := r || public._qa_s13_ok('P15.2 menu mutation policies are owner/staff scoped',
          (SELECT coalesce(bool_and(coalesce(qual,with_check) LIKE '%auth.uid()%'), false)
             FROM pg_policies WHERE schemaname='public' AND tablename='food_menu_items'
              AND cmd IN ('INSERT','UPDATE','DELETE','ALL')), NULL);
    BEGIN
      UPDATE public.food_restaurants SET name='QA R8X hijacked' WHERE id=v_resto;
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P15.3 stranger cannot rename another restaurant',
          (SELECT name FROM public.food_restaurants WHERE id=v_resto) = 'QA R8X Resto', v_err);

    -- live anonymous session: RLS must block despite the guard's trusted-server bypass
    PERFORM set_config('request.jwt.claims', ''::text, true);
    BEGIN
      SET LOCAL ROLE anon;
      BEGIN
        INSERT INTO public.food_restaurants(owner_user_id, slug, name, status, verification_state)
          VALUES (NULL,'qa-n3r8x-anon','QA R8X Anon','active','verified');
        v_err := 'NO_ERROR';
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
      EXECUTE format('SET LOCAL ROLE %I', v_owner_role);
    EXCEPTION WHEN OTHERS THEN
      EXECUTE format('SET LOCAL ROLE %I', v_owner_role);
      v_err := SQLERRM;
    END;
    r := r || public._qa_s13_ok('P15.4 an anonymous session cannot insert a restaurant',
          v_err <> 'NO_ERROR', v_err);
    SELECT count(*) INTO v_n FROM public.food_restaurants WHERE slug='qa-n3r8x-anon';
    r := r || public._qa_s13_ok('P15.5 no anonymous restaurant row exists', v_n = 0, v_n::text);

    BEGIN
      SET LOCAL ROLE anon;
      BEGIN
        INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
          VALUES (v_resto,'QA R8X Anon Plat',1000,true);
        v_err := 'NO_ERROR';
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
      EXECUTE format('SET LOCAL ROLE %I', v_owner_role);
    EXCEPTION WHEN OTHERS THEN
      EXECUTE format('SET LOCAL ROLE %I', v_owner_role);
      v_err := SQLERRM;
    END;
    r := r || public._qa_s13_ok('P15.6 an anonymous session cannot insert a menu item',
          v_err <> 'NO_ERROR', v_err);
    SELECT count(*) INTO v_n FROM public.food_menu_items WHERE name='QA R8X Anon Plat';
    r := r || public._qa_s13_ok('P15.7 no anonymous menu row exists', v_n = 0, v_n::text);

    -- ===== P16. DRAFT / SUSPENDED DIRECT READS STAY HIDDEN =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    r := r || public._qa_s13_ok('P16.1 restaurant SELECT policy hides non-verified rows',
          (SELECT coalesce(bool_and(qual LIKE '%verified%'), false) FROM pg_policies
            WHERE schemaname='public' AND tablename='food_restaurants' AND cmd='SELECT'), NULL);
    r := r || public._qa_s13_ok('P16.2 menu SELECT policy hides non-verified supply',
          (SELECT coalesce(bool_and(qual LIKE '%verified%'), false) FROM pg_policies
            WHERE schemaname='public' AND tablename='food_menu_items' AND cmd='SELECT'), NULL);
    r := r || public._qa_s13_ok('P16.3 canonical detail read hides the still-draft empty restaurant',
          public.repas_restaurant_public(v_empty) IS NULL
          OR (public.repas_restaurant_public(v_empty)->>'published')::boolean = false, NULL);

    -- ===== P17. HISTORICAL R7 INVARIANT (NON-VACUOUS) =====
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                          jsonb_build_object('menu_item_id',v_item2,'qty',2)),
        'pickup','choppay', gen_random_uuid());
    v_ord := (v_res->>'order_id')::uuid;
    r := r || public._qa_s13_ok('P17.1 a real order commits against published supply',
          v_ord IS NOT NULL, v_res::text);
    v_rec0 := public.repas_order_receipt(v_ord);
    r := r || public._qa_s13_ok('P17.2 the canonical receipt is readable at commit time',
          v_rec0 IS NOT NULL AND (v_rec0 ? 'items'), NULL);
    r := r || public._qa_s13_ok('P17.3 the receipt froze the item names',
          v_rec0::text LIKE '%QA R8X Plat A%', NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    UPDATE public.food_menu_items SET name='QA R8X Plat A RENAMED', price_gnf=777000 WHERE id=v_item;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_admin), true);
    PERFORM public.repas_admin_set_publication(v_resto,'suspend','QA R8X suspension');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);

    v_rec1 := public.repas_order_receipt(v_ord);
    r := r || public._qa_s13_ok('P17.4 the historical receipt is still readable after unpublish',
          v_rec1 IS NOT NULL, NULL);
    r := r || public._qa_s13_ok('P17.5 frozen item names did not drift',
          v_rec1::text LIKE '%QA R8X Plat A%' AND v_rec1::text NOT LIKE '%RENAMED%', NULL);
    r := r || public._qa_s13_ok('P17.6 frozen unit prices and line totals did not drift',
          v_rec1->'items' = v_rec0->'items', NULL);
    r := r || public._qa_s13_ok('P17.7 frozen order total did not drift',
          v_rec1->>'order_total_gnf' = v_rec0->>'order_total_gnf', v_rec1->>'order_total_gnf');
    r := r || public._qa_s13_ok('P17.8 frozen pricing/payment truth did not drift',
          v_rec1->>'payment_rail' IS NOT DISTINCT FROM v_rec0->>'payment_rail'
          AND v_rec1->>'subtotal_gnf' IS NOT DISTINCT FROM v_rec0->>'subtotal_gnf', NULL);
    v_trk := public.repas_order_tracking(v_ord);
    r := r || public._qa_s13_ok('P17.9 participant tracking still resolves after unpublish',
          v_trk IS NOT NULL, NULL);

    BEGIN
      PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'pickup','choppay', gen_random_uuid());
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P17.10 no new order may be placed after unpublish',
          v_err LIKE '%RESTAURANT_NOT_PUBLISHED%' OR v_err LIKE '%RESTAURANT_NOT_ORDERABLE%', v_err);
    SELECT count(*) INTO v_n FROM public.food_orders WHERE restaurant_id = v_resto;
    r := r || public._qa_s13_ok('P17.11 exactly one historical order exists', v_n = 1, v_n::text);
    PERFORM set_config('request.jwt.claims', ''::text, true);
    SELECT count(*) INTO v_n FROM public.repas_restaurants_discover(NULL,100) d WHERE d.id=v_resto;
    r := r || public._qa_s13_ok('P17.12 the suspended restaurant left customer discovery', v_n = 0, v_n::text);

    UPDATE public.feature_flags SET enabled = coalesce(v_flag_prev,false) WHERE key='chop_pay_checkout_enabled';
    RAISE EXCEPTION 'QA_NODE3_R8X_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE3_R8X_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS-X aborted before completion', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', ''::text, true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('ZX.1 master wallet unchanged after fixture rollback',
        v_master0 IS NOT DISTINCT FROM v_master1, v_master1::text);
  r := r || public._qa_s13_ok('ZX.2 feature flags byte-identical after fixture rollback',
        v_flags0 = v_flags1, NULL);
  SELECT count(*) INTO v_n FROM public.food_restaurants WHERE slug LIKE 'qa-n3r8x-%';
  r := r || public._qa_s13_ok('ZX.3 no restaurant fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.food_menu_items WHERE name LIKE 'QA R8X %';
  r := r || public._qa_s13_ok('ZX.4 no menu fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.food_orders o
    JOIN public.food_restaurants fr ON fr.id=o.restaurant_id WHERE fr.slug LIKE 'qa-n3r8x-%';
  r := r || public._qa_s13_ok('ZX.5 no order residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE email LIKE 'qa-s13-n3r8x%';
  r := r || public._qa_s13_ok('ZX.6 no QA user residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.audit_logs WHERE note LIKE 'QA R8X %';
  r := r || public._qa_s13_ok('ZX.7 no audit residue', v_n = 0, v_n::text);

  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r8_extra() FROM PUBLIC, anon, authenticated;
