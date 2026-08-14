CREATE OR REPLACE FUNCTION public._qa_node4_probe(p_role text, p_uid uuid, p_sql text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE n integer;
BEGIN
  PERFORM set_config('request.jwt.claims',
    CASE WHEN p_uid IS NULL THEN '' ELSE public._as_user_claims(p_uid) END, true);
  EXECUTE 'SET LOCAL ROLE ' || quote_ident(p_role);
  EXECUTE p_sql INTO n;
  RESET ROLE;
  RETURN n;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  RETURN -1;
END $$;

CREATE OR REPLACE FUNCTION public._qa_node4_marche_r1()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r jsonb := '[]'::jsonb;
  v_seller uuid; v_pend uuid; v_comm uuid; v_other uuid; v_adm uuid;
  v_store uuid; v_pstore uuid;
  l_ok uuid; l_pend uuid; l_comm uuid; l_stock uuid;
  v_res jsonb; v_err text; v_n int; v_row public.marketplace_listings;
  v_flags0 jsonb; v_flags1 jsonb;
  v_w0 bigint; v_w1 bigint; v_lj0 bigint; v_lj1 bigint;
  v_ms0 bigint; v_ms1 bigint; v_pi0 bigint; v_pi1 bigint; v_wt0 bigint; v_wt1 bigint;
  v_guards int; v_demo int; v_real int;
BEGIN
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;
  SELECT count(*) INTO v_w0  FROM public.wallets;
  SELECT count(*) INTO v_wt0 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj0 FROM public.ledger_journals;
  SELECT count(*) INTO v_ms0 FROM public.missions;
  SELECT count(*) INTO v_pi0 FROM public.payment_intents;

  -- ============ STRUCTURE / PRIVILEGES ============
  SELECT count(*) INTO v_guards
    FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
   WHERE c.relname = 'marketplace_listings' AND NOT t.tgisinternal
     AND t.tgname IN ('trg_marche_publication_guard','enforce_listing_visibility_trg','trg_marche_enforce_pending_privacy');
  r := r || public._qa_s13_ok('N4.B1 exactly one canonical publication guard on marketplace_listings',
        v_guards = 1, v_guards::text);
  r := r || public._qa_s13_ok('N4.B1b legacy publication trigger functions dropped',
        NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace
                     AND proname IN ('enforce_listing_visibility','marche_enforce_pending_merchant_privacy')), NULL);

  r := r || public._qa_s13_ok('N4.B2 authenticated cannot INSERT marketplace_listings directly',
        NOT has_table_privilege('authenticated','public.marketplace_listings','INSERT'), NULL);
  r := r || public._qa_s13_ok('N4.B2b authenticated cannot UPDATE marketplace_listings directly',
        NOT has_table_privilege('authenticated','public.marketplace_listings','UPDATE'), NULL);
  r := r || public._qa_s13_ok('N4.B2c authenticated cannot DELETE marketplace_listings directly',
        NOT has_table_privilege('authenticated','public.marketplace_listings','DELETE'), NULL);
  r := r || public._qa_s13_ok('N4.B3 anon cannot write marketplace_listings',
        NOT has_table_privilege('anon','public.marketplace_listings','INSERT')
    AND NOT has_table_privilege('anon','public.marketplace_listings','UPDATE')
    AND NOT has_table_privilege('anon','public.marketplace_listings','DELETE'), NULL);
  r := r || public._qa_s13_ok('N4.B3b anon cannot execute listing mutation primitives',
        NOT has_function_privilege('anon','public.marche_listing_create(jsonb)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_listing_update(uuid,jsonb)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_listing_publish(uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_listing_set_stock(uuid,integer)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4.B3c anon trimmed off authenticated-only Marché actions',
        NOT has_function_privilege('anon','public.marche_toggle_listing_save(uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.withdraw_marketplace_offer(uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.get_listing_minimum_price(uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.set_primary_listing_image(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4.B3d anon keeps only public read RPCs',
        has_function_privilege('anon','public.marche_listings_discover(text,text,uuid,text,integer,integer)','EXECUTE')
    AND has_function_privilege('anon','public.marche_listing_public(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4.B3e anon cannot write listing_images / listing_metrics',
        NOT has_table_privilege('anon','public.listing_images','INSERT')
    AND NOT has_table_privilege('anon','public.listing_metrics','UPDATE'), NULL);

  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace='public'::regnamespace
     AND p.proname IN ('marche_listing_create','marche_listing_update','marche_listing_set_stock',
                       'marche_listing_adjust_stock','marche_listing_set_availability',
                       'marche_listing_publish','marche_listing_unpublish','marche_listing_archive',
                       'marche_listings_discover','marche_listing_public','marche_listings_owner',
                       'marche_store_listings_owner','marche_store_listing_previews',
                       'marche_listing_truth','marche_listing_is_public','marche_publication_guard')
     AND p.prosecdef
     AND EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,'{}')) c WHERE c LIKE 'search_path=%');
  r := r || public._qa_s13_ok('N4.B5 all Marché R1 primitives are SECURITY DEFINER with pinned search_path',
        v_n = 16, v_n::text);
  r := r || public._qa_s13_ok('N4.B5b canonical truth view not exposed to anon/authenticated',
        NOT has_table_privilege('anon','public.v_marche_listing_truth','SELECT')
    AND NOT has_table_privilege('authenticated','public.v_marche_listing_truth','SELECT'), NULL);

  -- ============ FIXTURES ============
  BEGIN
    v_seller := gen_random_uuid(); v_pend := gen_random_uuid(); v_comm := gen_random_uuid();
    v_other  := gen_random_uuid(); v_adm  := gen_random_uuid();
    PERFORM public._qa_s13_user(v_seller,'n4s');
    PERFORM public._qa_s13_user(v_pend,'n4p');
    PERFORM public._qa_s13_user(v_comm,'n4c');
    PERFORM public._qa_s13_user(v_other,'n4o');
    PERFORM public._qa_s13_user(v_adm,'n4a');
    PERFORM public._qa_s13_admin(v_adm);

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status)
      VALUES (v_seller, 'qa-n4-ok-'||substr(v_seller::text,1,8), 'QA N4 Store', 'active', 'approved')
      RETURNING id INTO v_store;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status)
      VALUES (v_pend, 'qa-n4-pend-'||substr(v_pend::text,1,8), 'QA N4 Pending', 'active', 'submitted')
      RETURNING id INTO v_pstore;

    -- ---- create via certified primitive ----
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_seller), true);
    l_ok := public.marche_listing_create(jsonb_build_object(
      'store_id', v_store, 'title','QA N4 Merchant Item', 'category','Autre',
      'price_gnf', 25000, 'quantity_in_stock', 5, 'publish', true));
    SELECT * INTO v_row FROM public.marketplace_listings WHERE id = l_ok;
    r := r || public._qa_s13_ok('N4.P6 approved merchant seller can publish through the primitive',
          v_row.status='active' AND v_row.visibility='public'
          AND (public.marche_listing_truth(l_ok)->>'is_orderable')::boolean, v_row.visibility);
    r := r || public._qa_s13_ok('N4.W17 create forces server-owned identity fields',
          v_row.seller_id = v_seller AND v_row.kind = 'merchant' AND v_row.store_id = v_store, NULL);

    -- ---- pending merchant store cannot publish ----
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_pend), true);
    l_pend := public.marche_listing_create(jsonb_build_object(
      'store_id', v_pstore, 'title','QA N4 Pending Item', 'category','Autre',
      'price_gnf', 30000, 'publish', true));
    SELECT * INTO v_row FROM public.marketplace_listings WHERE id = l_pend;
    r := r || public._qa_s13_ok('N4.P7 pending merchant listing is forced private/paused by the guard',
          v_row.visibility='private' AND v_row.status='paused', v_row.status::text||'/'||v_row.visibility);
    v_res := public.marche_listing_truth(l_pend);
    r := r || public._qa_s13_ok('N4.P7b pending merchant listing not orderable with honest reason',
          (v_res->>'is_orderable')::boolean = false
          AND v_res->>'refusal_reason' IN ('LISTING_PAUSED','LISTING_PRIVATE','STORE_NOT_APPROVED'),
          v_res->>'refusal_reason');
    v_res := public.marche_listing_publish(l_pend);
    r := r || public._qa_s13_ok('N4.P7c publish attempt on pending store still cannot go public',
          (v_res->>'is_orderable')::boolean = false, v_res->>'refusal_reason');

    -- ---- community listing follows its own eligibility rule ----
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_comm), true);
    l_comm := public.marche_listing_create(jsonb_build_object(
      'title','QA N4 Community Item', 'category','Autre', 'price_gnf', 15000, 'publish', true));
    SELECT * INTO v_row FROM public.marketplace_listings WHERE id = l_comm;
    r := r || public._qa_s13_ok('N4.P8 eligible community listing publishes (no store required)',
          v_row.kind='community' AND v_row.store_id IS NULL
          AND (public.marche_listing_truth(l_comm)->>'is_orderable')::boolean, NULL);

    INSERT INTO public.account_bans(user_id, status, reason)
      VALUES (v_comm, 'active', 'qa-n4-fixture');
    PERFORM public.marche_listing_unpublish(l_comm);
    v_res := public.marche_listing_publish(l_comm);
    SELECT * INTO v_row FROM public.marketplace_listings WHERE id = l_comm;
    r := r || public._qa_s13_ok('N4.P8b banned community seller cannot bypass the publication guard',
          v_row.visibility='private' AND (v_res->>'is_orderable')::boolean = false, v_res->>'refusal_reason');
    DELETE FROM public.account_bans WHERE user_id = v_comm AND reason = 'qa-n4-fixture';
    PERFORM public.marche_listing_publish(l_comm);
    r := r || public._qa_s13_ok('N4.P8c community listing recovers once the ban is lifted',
          (public.marche_listing_truth(l_comm)->>'is_orderable')::boolean, NULL);

    -- ---- paused / removed / sold excluded ----
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_seller), true);
    PERFORM public.marche_listing_unpublish(l_ok);
    r := r || public._qa_s13_ok('N4.P9 paused listing excluded from canonical truth',
          (public.marche_listing_truth(l_ok)->>'is_orderable')::boolean = false,
          public.marche_listing_truth(l_ok)->>'refusal_reason');
    PERFORM public.marche_listing_publish(l_ok);
    PERFORM public.marche_listing_set_availability(l_ok, 'sold');
    v_res := public.marche_listing_truth(l_ok);
    r := r || public._qa_s13_ok('N4.P9b sold listing excluded with LISTING_SOLD',
          (v_res->>'is_orderable')::boolean = false AND v_res->>'refusal_reason' = 'LISTING_SOLD',
          v_res->>'refusal_reason');
    PERFORM public.marche_listing_set_availability(l_ok, 'available');

    -- ---- out of stock ----
    PERFORM public.marche_listing_set_stock(l_ok, 0);
    v_res := public.marche_listing_truth(l_ok);
    r := r || public._qa_s13_ok('N4.P10 zero-stock listing excluded with OUT_OF_STOCK',
          (v_res->>'is_orderable')::boolean = false AND v_res->>'refusal_reason' = 'OUT_OF_STOCK',
          v_res->>'refusal_reason');
    PERFORM public.marche_listing_set_stock(l_ok, 3);
    r := r || public._qa_s13_ok('N4.P10b restocked listing becomes orderable again',
          (public.marche_listing_truth(l_ok)->>'is_orderable')::boolean, NULL);

    -- ---- invalid pricing combinations refused ----
    v_err := NULL;
    BEGIN
      PERFORM public.marche_listing_update(l_ok, jsonb_build_object('pricing_mode','fixed','allow_offers',true));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4.P11 offers enabled on a fixed-price listing is refused',
          v_err IS NOT NULL, v_err);
    v_err := NULL;
    BEGIN
      PERFORM public.marche_listing_update(l_ok, jsonb_build_object('price_gnf', 0));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4.P11b zero price on a fixed-price merchant listing is refused',
          v_err IS NOT NULL, v_err);

    -- ---- publish/unpublish replay idempotent ----
    PERFORM public.marche_listing_publish(l_ok);
    PERFORM public.marche_listing_publish(l_ok);
    SELECT * INTO v_row FROM public.marketplace_listings WHERE id = l_ok;
    r := r || public._qa_s13_ok('N4.P12 publish replay is idempotent',
          v_row.status='active' AND v_row.visibility='public', NULL);
    PERFORM public.marche_listing_unpublish(l_ok);
    PERFORM public.marche_listing_unpublish(l_ok);
    SELECT * INTO v_row FROM public.marketplace_listings WHERE id = l_ok;
    r := r || public._qa_s13_ok('N4.P12b unpublish replay is idempotent',
          v_row.status='paused' AND v_row.visibility='private', NULL);
    PERFORM public.marche_listing_publish(l_ok);

    -- ============ WRITE AUTHORITY ============
    PERFORM public.marche_listing_update(l_ok, jsonb_build_object('title','QA N4 Renamed','price_gnf',26000));
    SELECT * INTO v_row FROM public.marketplace_listings WHERE id = l_ok;
    r := r || public._qa_s13_ok('N4.W13 owner can update allowed listing fields via the primitive',
          v_row.title='QA N4 Renamed' AND v_row.price_gnf=26000, NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_other), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_listing_update(l_ok, jsonb_build_object('price_gnf', 1));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4.W14 non-owner cannot mutate another seller listing', v_err IS NOT NULL, v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_listing_publish(l_ok);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4.W14b non-owner cannot publish another seller listing', v_err IS NOT NULL, v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_listing_set_stock(l_ok, 99);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4.W14c non-owner cannot change another seller stock', v_err IS NOT NULL, v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_seller), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_listing_set_stock(l_ok, -1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4.W15 negative stock is refused', v_err IS NOT NULL, v_err);

    v_err := NULL;
    BEGIN
      PERFORM public.marche_listing_update(l_ok, jsonb_build_object(
        'pricing_mode','negotiable','allow_offers',true,
        'asking_price_gnf', 20000, 'minimum_price_gnf', 50000));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4.W16 minimum price above asking price is refused', v_err IS NOT NULL, v_err);

    PERFORM public.marche_listing_update(l_ok, jsonb_build_object(
      'seller_id', v_other, 'store_id', v_pstore, 'kind', 'community',
      'status','removed', 'visibility','private', 'promoted', true, 'view_count', 9999));
    SELECT * INTO v_row FROM public.marketplace_listings WHERE id = l_ok;
    r := r || public._qa_s13_ok('N4.W17b protected ownership/store/kind/promoted fields cannot be reassigned',
          v_row.seller_id=v_seller AND v_row.store_id=v_store AND v_row.kind='merchant'
          AND v_row.promoted=false AND v_row.status='active' AND v_row.visibility='public'
          AND v_row.view_count = 0, NULL);

    -- ============ DISCOVERY / MEDIA ============
    SELECT count(*) INTO v_n FROM public.marche_listings_discover(NULL,NULL,NULL,'recent',200,0) d
     WHERE d.id = l_ok;
    r := r || public._qa_s13_ok('N4.D18 orderable listing appears in canonical discovery', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_listings_discover(NULL,NULL,NULL,'recent',200,0) d
     WHERE d.id IN (l_pend);
    r := r || public._qa_s13_ok('N4.D18b non-orderable listing absent from canonical discovery', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_listings_discover(NULL,NULL,NULL,'recent',200,0) d
      JOIN public.v_marche_listing_truth v ON v.listing_id = d.id
     WHERE NOT v.is_orderable;
    r := r || public._qa_s13_ok('N4.D18c discovery contains only canonically orderable supply', v_n = 0, v_n::text);

    PERFORM set_config('request.jwt.claims', '', true);
    r := r || public._qa_s13_ok('N4.D19 non-public listing detail not returned to the public',
          public.marche_listing_public(l_pend) IS NULL, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_pend), true);
    r := r || public._qa_s13_ok('N4.D21 owner can still read their own non-public listing detail',
          public.marche_listing_public(l_pend) IS NOT NULL, NULL);

    INSERT INTO public.listing_images(listing_id, url, position, is_primary)
      VALUES (l_pend, 'https://qa.invalid/n4-private.jpg', 0, true);
    INSERT INTO public.listing_images(listing_id, url, position, is_primary)
      VALUES (l_ok, 'https://qa.invalid/n4-public.jpg', 0, true);

    v_n := public._qa_node4_probe('anon', NULL,
      format('SELECT count(*)::int FROM public.listing_images WHERE listing_id = %L', l_pend));
    r := r || public._qa_s13_ok('N4.D20 anon cannot enumerate media of a non-public listing', v_n = 0, v_n::text);
    v_n := public._qa_node4_probe('anon', NULL,
      format('SELECT count(*)::int FROM public.listing_images WHERE listing_id = %L', l_ok));
    r := r || public._qa_s13_ok('N4.D20b anon can still see media of a public orderable listing', v_n = 1, v_n::text);
    v_n := public._qa_node4_probe('authenticated', v_pend,
      format('SELECT count(*)::int FROM public.listing_images WHERE listing_id = %L', l_pend));
    r := r || public._qa_s13_ok('N4.D21b owner can still manage media of their non-public listing', v_n = 1, v_n::text);
    v_n := public._qa_node4_probe('authenticated', v_other,
      format('SELECT count(*)::int FROM public.listing_images WHERE listing_id = %L', l_pend));
    r := r || public._qa_s13_ok('N4.D20c other signed-in users cannot enumerate private media', v_n = 0, v_n::text);
    v_n := public._qa_node4_probe('anon', NULL,
      format('SELECT count(*)::int FROM public.marketplace_listings WHERE id = %L', l_pend));
    r := r || public._qa_s13_ok('N4.D19b anon cannot read the non-public listing row', v_n = 0, v_n::text);
    v_n := public._qa_node4_probe('authenticated', v_other,
      format('UPDATE public.marketplace_listings SET price_gnf = 1 WHERE id = %L; SELECT 1', l_ok));
    r := r || public._qa_s13_ok('N4.B2d direct table UPDATE by a signed-in user is rejected', v_n = -1, v_n::text);

    -- ============ DEMO SUPPLY ============
    SELECT count(*) INTO v_demo FROM public.v_marche_listing_truth v
      WHERE v.is_demo AND v.is_orderable;
    r := r || public._qa_s13_ok('N4.Q22 no demo-account listing is publicly orderable', v_demo = 0, v_demo::text);
    SELECT count(*) INTO v_demo FROM public.v_marche_listing_truth WHERE is_demo;
    r := r || public._qa_s13_ok('N4.Q22b demo supply is quarantined, not deleted', v_demo > 0, v_demo::text);
    SELECT count(*) INTO v_real FROM public.v_marche_listing_truth v
      WHERE v.refusal_reason = 'DEMO_SUPPLY' AND NOT public.marche_is_demo_seller(v.seller_id);
    r := r || public._qa_s13_ok('N4.Q23 quarantine hides no non-demo listing', v_real = 0, v_real::text);
    r := r || public._qa_s13_ok('N4.Q23b QA fixture sellers are not treated as demo supply',
          NOT public.marche_is_demo_seller(v_seller) AND NOT public.marche_is_demo_seller(v_comm), NULL);

  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok('N4.FIXTURE runtime block completed without unhandled error', false, SQLERRM);
  END;

  -- ============ CLEANUP ============
  PERFORM set_config('request.jwt.claims', '', true);
  DELETE FROM public.listing_images WHERE listing_id IN (l_ok, l_pend, l_comm, l_stock);
  DELETE FROM public.listing_metrics WHERE listing_id IN (l_ok, l_pend, l_comm, l_stock);
  DELETE FROM public.marketplace_listings WHERE seller_id IN (v_seller, v_pend, v_comm, v_other, v_adm);
  DELETE FROM public.account_bans WHERE user_id IN (v_seller, v_pend, v_comm, v_other, v_adm);
  DELETE FROM public.merchant_stores WHERE owner_user_id IN (v_seller, v_pend);
  DELETE FROM public.admin_users WHERE user_id = v_adm;
  DELETE FROM auth.users WHERE id IN (v_seller, v_pend, v_comm, v_other, v_adm);

  -- ============ SYSTEMIC ============
  SELECT count(*) INTO v_w1  FROM public.wallets;
  SELECT count(*) INTO v_wt1 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj1 FROM public.ledger_journals;
  SELECT count(*) INTO v_ms1 FROM public.missions;
  SELECT count(*) INTO v_pi1 FROM public.payment_intents;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;

  r := r || public._qa_s13_ok('N4.S24 no wallet / ledger / mission / payment rows created by R1 fixtures',
        v_w1=v_w0 AND v_wt1=v_wt0 AND v_lj1=v_lj0 AND v_ms1=v_ms0 AND v_pi1=v_pi0,
        format('%s/%s/%s/%s/%s', v_w1-v_w0, v_wt1-v_wt0, v_lj1-v_lj0, v_ms1-v_ms0, v_pi1-v_pi0));
  r := r || public._qa_s13_ok('N4.S25 feature flags byte-identical after fixture rollback',
        v_flags1 = v_flags0, NULL);

  SELECT count(*) INTO v_n FROM public.marketplace_listings
   WHERE seller_id IN (v_seller, v_pend, v_comm, v_other, v_adm) OR title LIKE 'QA N4%';
  r := r || public._qa_s13_ok('N4.S26 zero listing fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE id IN (v_seller, v_pend, v_comm, v_other, v_adm);
  r := r || public._qa_s13_ok('N4.S26b zero auth fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-n4-%';
  r := r || public._qa_s13_ok('N4.S26c zero store fixture residue', v_n = 0, v_n::text);

  RETURN public._qa_s13_summary(41, r);
END $$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r1() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_node4_probe(text, uuid, text) FROM PUBLIC, anon, authenticated;