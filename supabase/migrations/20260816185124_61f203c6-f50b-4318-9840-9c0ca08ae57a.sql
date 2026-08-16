-- =====================================================================
-- NODE 4 — MARCHÉ R1.5 : APPROVED MERCHANT SUPPLY DOCTRINE
-- =====================================================================

-- 1) CANONICAL TRUTH ---------------------------------------------------
CREATE OR REPLACE VIEW public.v_marche_listing_truth AS
SELECT listing_id, seller_id, store_id, kind, status, visibility, availability,
       quantity_in_stock, photo_count, price_gnf, pricing_mode, store_ok, is_demo,
       seller_banned, refusal_reason, refusal_reason IS NULL AS is_orderable
FROM (
  SELECT l.id AS listing_id, l.seller_id, l.store_id, l.kind, l.status, l.visibility,
         l.availability, l.quantity_in_stock, l.photo_count, l.price_gnf, l.pricing_mode,
         (s.id IS NOT NULL AND s.status = 'active' AND s.onboarding_status = 'approved') AS store_ok,
         public.marche_is_demo_seller(l.seller_id) AS is_demo,
         public.marche_seller_banned(l.seller_id) AS seller_banned,
         CASE
           -- R1.5 constitutional law: only approved active merchant stores
           -- may originate production-orderable Marché supply.
           WHEN l.store_id IS NULL OR l.kind <> 'merchant'::listing_kind THEN 'MERCHANT_STORE_REQUIRED'
           WHEN l.status = 'removed'::listing_status THEN 'LISTING_REMOVED'
           WHEN l.status = 'sold'::listing_status OR l.availability = 'sold'::listing_availability THEN 'LISTING_SOLD'
           WHEN l.status = 'paused'::listing_status THEN 'LISTING_PAUSED'
           WHEN l.visibility <> 'public' THEN 'LISTING_PRIVATE'
           WHEN public.marche_seller_banned(l.seller_id) THEN 'SELLER_NOT_ELIGIBLE'
           WHEN NOT (s.id IS NOT NULL AND s.status = 'active' AND s.onboarding_status = 'approved') THEN 'STORE_NOT_APPROVED'
           WHEN public.marche_is_demo_seller(l.seller_id) THEN 'DEMO_SUPPLY'
           WHEN l.quantity_in_stock IS NOT NULL AND l.quantity_in_stock <= 0 THEN 'OUT_OF_STOCK'
           WHEN l.pricing_mode = 'fixed' AND l.kind = 'merchant'::listing_kind AND COALESCE(l.price_gnf,0) <= 0 THEN 'INVALID_PRICE'
           ELSE NULL
         END AS refusal_reason
    FROM public.marketplace_listings l
    LEFT JOIN public.merchant_stores s ON s.id = l.store_id
) t;

-- 2) PUBLICATION GUARD -------------------------------------------------
CREATE OR REPLACE FUNCTION public.marche_publication_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE s_status text; s_onboard text;
BEGIN
  IF public.marche_seller_banned(NEW.seller_id) THEN
    NEW.visibility := 'private';
    IF NEW.status = 'active' THEN NEW.status := 'paused'; END IF;
    RETURN NEW;
  END IF;

  -- R1.5: storeless / community supply can never be production-public.
  IF NEW.store_id IS NULL OR NEW.kind <> 'merchant'::listing_kind THEN
    NEW.visibility := 'private';
    IF NEW.status = 'active' THEN NEW.status := 'paused'; END IF;
    RETURN NEW;
  END IF;

  SELECT status, onboarding_status INTO s_status, s_onboard
    FROM public.merchant_stores WHERE id = NEW.store_id;
  IF s_onboard IS DISTINCT FROM 'approved'
     OR s_status IS NULL
     OR s_status NOT IN ('active', 'paused') THEN
    NEW.visibility := 'private';
    IF NEW.status = 'active' THEN NEW.status := 'paused'; END IF;
  END IF;

  IF NEW.visibility NOT IN ('public','private') THEN
    RAISE EXCEPTION 'INVALID_VISIBILITY';
  END IF;

  RETURN NEW;
END;
$function$;

-- 3) CREATE AUTHORITY --------------------------------------------------
CREATE OR REPLACE FUNCTION public.marche_listing_create(p_payload jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_store_id uuid;
  l public.marketplace_listings;
  v_publish boolean := COALESCE((p_payload->>'publish')::boolean, true);
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  v_store_id := NULLIF(p_payload->>'store_id','')::uuid;
  IF v_store_id IS NULL THEN
    RAISE EXCEPTION 'MERCHANT_STORE_REQUIRED';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.merchant_stores s
                  WHERE s.id = v_store_id AND s.owner_user_id = v_uid) THEN
    RAISE EXCEPTION 'NOT_STORE_OWNER';
  END IF;

  l.id                 := gen_random_uuid();
  l.seller_id          := v_uid;
  l.store_id           := v_store_id;
  l.kind               := 'merchant';
  l.category           := COALESCE(NULLIF(p_payload->>'category',''), 'Autre');
  l.title              := btrim(COALESCE(p_payload->>'title',''));
  l.description        := NULLIF(btrim(COALESCE(p_payload->>'description','')), '');
  l.price_gnf          := NULLIF(p_payload->>'price_gnf','')::bigint;
  l.asking_price_gnf   := COALESCE(NULLIF(p_payload->>'asking_price_gnf','')::bigint,
                                   NULLIF(p_payload->>'price_gnf','')::bigint);
  l.pricing_mode       := COALESCE(NULLIF(p_payload->>'pricing_mode',''), 'fixed');
  l.allow_offers       := COALESCE((p_payload->>'allow_offers')::boolean, false);
  l.minimum_price_gnf  := NULLIF(p_payload->>'minimum_price_gnf','')::bigint;
  l.quantity_in_stock  := NULLIF(p_payload->>'quantity_in_stock','')::int;
  l.barcode            := NULLIF(btrim(COALESCE(p_payload->>'barcode','')), '');
  l.is_negotiable      := COALESCE((p_payload->>'is_negotiable')::boolean, false);
  l.is_urgent          := COALESCE((p_payload->>'is_urgent')::boolean, false);
  l.delivery_available := COALESCE((p_payload->>'delivery_available')::boolean, false);
  l.condition          := NULLIF(btrim(COALESCE(p_payload->>'condition','')), '');
  l.neighborhood       := NULLIF(btrim(COALESCE(p_payload->>'neighborhood','')), '');
  l.commune            := NULLIF(btrim(COALESCE(p_payload->>'commune','')), '');
  l.landmark           := NULLIF(btrim(COALESCE(p_payload->>'landmark','')), '');
  l.availability       := COALESCE(NULLIF(p_payload->>'availability','')::listing_availability, 'to_confirm');
  l.fulfillment_options:= COALESCE(
      ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_payload->'fulfillment_options')='array'
                                                  THEN p_payload->'fulfillment_options' ELSE '[]'::jsonb END)),
      ARRAY['to_confirm']::text[]);
  IF array_length(l.fulfillment_options,1) IS NULL THEN
    l.fulfillment_options := ARRAY['to_confirm']::text[];
  END IF;
  IF NOT l.allow_offers THEN l.minimum_price_gnf := NULL; END IF;
  l.status     := CASE WHEN v_publish THEN 'active'::listing_status ELSE 'paused'::listing_status END;
  l.visibility := CASE WHEN v_publish THEN 'public' ELSE 'private' END;

  PERFORM public._marche_listing_assert_valid(l);

  PERFORM set_config('marche.rpc','1', true);
  INSERT INTO public.marketplace_listings (
    id, seller_id, store_id, kind, category, title, description, price_gnf,
    asking_price_gnf, minimum_price_gnf, pricing_mode, allow_offers,
    quantity_in_stock, barcode, is_negotiable, is_urgent, delivery_available,
    condition, neighborhood, commune, landmark, availability, fulfillment_options,
    status, visibility
  ) VALUES (
    l.id, l.seller_id, l.store_id, l.kind, l.category, l.title, l.description, l.price_gnf,
    l.asking_price_gnf, l.minimum_price_gnf, l.pricing_mode, l.allow_offers,
    l.quantity_in_stock, l.barcode, l.is_negotiable, l.is_urgent, l.delivery_available,
    l.condition, l.neighborhood, l.commune, l.landmark, l.availability, l.fulfillment_options,
    l.status, l.visibility
  );
  PERFORM set_config('marche.rpc','', true);
  RETURN l.id;
END;
$function$;

-- 4) PUBLISH AUTHORITY -------------------------------------------------
CREATE OR REPLACE FUNCTION public.marche_listing_publish(p_listing_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE cur public.marketplace_listings;
BEGIN
  cur := public._marche_listing_authz(p_listing_id);
  IF cur.status = 'removed' THEN RAISE EXCEPTION 'LISTING_REMOVED'; END IF;
  IF cur.store_id IS NULL OR cur.kind <> 'merchant'::listing_kind THEN
    RAISE EXCEPTION 'MERCHANT_STORE_REQUIRED';
  END IF;
  PERFORM public._marche_listing_assert_valid(cur);
  PERFORM set_config('marche.rpc','1', true);
  UPDATE public.marketplace_listings
     SET status = 'active'::listing_status, visibility = 'public'
   WHERE id = p_listing_id;
  PERFORM set_config('marche.rpc','', true);
  RETURN public.marche_listing_truth(p_listing_id);
END;
$function$;

-- 5) R1 HARNESS — realign community assertions to the R1.5 law ---------
CREATE OR REPLACE FUNCTION public._qa_node4_marche_r1()
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
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

    -- R1.5 law: storeless / community supply is not a valid production path.
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_comm), true);
    v_err := NULL;
    BEGIN
      l_comm := public.marche_listing_create(jsonb_build_object(
        'title','QA N4 Community Item', 'category','Autre', 'price_gnf', 15000, 'publish', true));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4.P8 storeless community publication path is refused',
          l_comm IS NULL AND v_err = 'MERCHANT_STORE_REQUIRED', COALESCE(v_err,'created'));

    INSERT INTO public.account_bans(user_id, status, reason, banned_by)
      VALUES (v_seller, 'active', 'qa-n4-fixture', v_adm);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_seller), true);
    PERFORM public.marche_listing_unpublish(l_ok);
    v_res := public.marche_listing_publish(l_ok);
    SELECT * INTO v_row FROM public.marketplace_listings WHERE id = l_ok;
    r := r || public._qa_s13_ok('N4.P8b banned merchant seller cannot bypass the publication guard',
          v_row.visibility='private' AND (v_res->>'is_orderable')::boolean = false, v_res->>'refusal_reason');
    DELETE FROM public.account_bans WHERE user_id = v_seller AND reason = 'qa-n4-fixture';
    PERFORM public.marche_listing_publish(l_ok);
    r := r || public._qa_s13_ok('N4.P8c merchant listing recovers once the ban is lifted',
          (public.marche_listing_truth(l_ok)->>'is_orderable')::boolean, NULL);

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

    PERFORM public.marche_listing_set_stock(l_ok, 0);
    v_res := public.marche_listing_truth(l_ok);
    r := r || public._qa_s13_ok('N4.P10 zero-stock listing excluded with OUT_OF_STOCK',
          (v_res->>'is_orderable')::boolean = false AND v_res->>'refusal_reason' = 'OUT_OF_STOCK',
          v_res->>'refusal_reason');
    PERFORM public.marche_listing_set_stock(l_ok, 3);
    r := r || public._qa_s13_ok('N4.P10b restocked listing becomes orderable again',
          (public.marche_listing_truth(l_ok)->>'is_orderable')::boolean, NULL);

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

  PERFORM set_config('request.jwt.claims', '', true);
  DELETE FROM public.listing_images WHERE listing_id IN (l_ok, l_pend, l_comm, l_stock);
  DELETE FROM public.listing_metrics WHERE listing_id IN (l_ok, l_pend, l_comm, l_stock);
  DELETE FROM public.marketplace_listings WHERE seller_id IN (v_seller, v_pend, v_comm, v_other, v_adm);
  DELETE FROM public.account_bans WHERE user_id IN (v_seller, v_pend, v_comm, v_other, v_adm);
  DELETE FROM public.merchant_stores WHERE owner_user_id IN (v_seller, v_pend);
  DELETE FROM public.admin_users WHERE user_id = v_adm;
  DELETE FROM public.wallet_transactions WHERE from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (v_seller, v_pend, v_comm, v_other, v_adm)) OR to_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (v_seller, v_pend, v_comm, v_other, v_adm));
  DELETE FROM public.wallets WHERE owner_user_id IN (v_seller, v_pend, v_comm, v_other, v_adm);
  DELETE FROM auth.users WHERE id IN (v_seller, v_pend, v_comm, v_other, v_adm);

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
END $function$;

-- 6) R1.5 DEDICATED HARNESS -------------------------------------------
CREATE OR REPLACE FUNCTION public._qa_node4_marche_r15()
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_merch uuid; v_pend uuid; v_cust uuid; v_other uuid; v_adm uuid;
  v_store uuid; v_pstore uuid;
  l_ok uuid; l_pend uuid; l_none uuid; l_legacy uuid;
  v_err text; v_n int; v_res jsonb; v_row public.marketplace_listings;
  v_flags0 jsonb; v_flags1 jsonb;
  v_w0 bigint; v_w1 bigint; v_wt0 bigint; v_wt1 bigint; v_lj0 bigint; v_lj1 bigint;
  v_ms0 bigint; v_ms1 bigint; v_pi0 bigint; v_pi1 bigint;
  v_demo0 bigint; v_demo1 bigint; v_total0 bigint; v_total1 bigint;
BEGIN
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;
  SELECT count(*) INTO v_w0 FROM public.wallets;
  SELECT count(*) INTO v_wt0 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj0 FROM public.ledger_journals;
  SELECT count(*) INTO v_ms0 FROM public.missions;
  SELECT count(*) INTO v_pi0 FROM public.payment_intents;
  SELECT count(*) INTO v_total0 FROM public.marketplace_listings;
  SELECT count(*) INTO v_demo0 FROM public.v_marche_listing_truth WHERE is_demo;

  -- ===== A. CONSTITUTIONAL LAW (STATIC) =====
  r := r || public._qa_s13_ok('N4R15.A1 canonical truth encodes MERCHANT_STORE_REQUIRED',
        pg_get_viewdef('public.v_marche_listing_truth'::regclass, true) LIKE '%MERCHANT_STORE_REQUIRED%', NULL);
  r := r || public._qa_s13_ok('N4R15.A2 publication guard refuses storeless production supply',
        (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND proname='marche_publication_guard') LIKE '%NEW.store_id IS NULL%', NULL);
  r := r || public._qa_s13_ok('N4R15.A3 create primitive requires a merchant store',
        (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND proname='marche_listing_create') LIKE '%MERCHANT_STORE_REQUIRED%', NULL);
  r := r || public._qa_s13_ok('N4R15.A4 publish primitive requires a merchant store',
        (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND proname='marche_listing_publish') LIKE '%MERCHANT_STORE_REQUIRED%', NULL);
  r := r || public._qa_s13_ok('N4R15.A5 has_role remains not executable by anon',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R15.A6 direct table CRUD stays denied to anon/authenticated',
        NOT has_table_privilege('authenticated','public.marketplace_listings','INSERT')
    AND NOT has_table_privilege('authenticated','public.marketplace_listings','UPDATE')
    AND NOT has_table_privilege('authenticated','public.marketplace_listings','DELETE')
    AND NOT has_table_privilege('anon','public.marketplace_listings','INSERT')
    AND NOT has_table_privilege('anon','public.marketplace_listings','UPDATE')
    AND NOT has_table_privilege('anon','public.marketplace_listings','DELETE'), NULL);
  r := r || public._qa_s13_ok('N4R15.A7 anon cannot execute seller mutation authority',
        NOT has_function_privilege('anon','public.marche_listing_create(jsonb)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_listing_publish(uuid)','EXECUTE'), NULL);

  -- ===== B. RUNTIME =====
  BEGIN
    v_merch := gen_random_uuid(); v_pend := gen_random_uuid(); v_cust := gen_random_uuid();
    v_other := gen_random_uuid(); v_adm := gen_random_uuid();
    PERFORM public._qa_s13_user(v_merch,'n45m');
    PERFORM public._qa_s13_user(v_pend,'n45p');
    PERFORM public._qa_s13_user(v_cust,'n45c');
    PERFORM public._qa_s13_user(v_other,'n45o');
    PERFORM public._qa_s13_user(v_adm,'n45a');
    PERFORM public._qa_s13_admin(v_adm);

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status)
      VALUES (v_merch, 'qa-n45-ok-'||substr(v_merch::text,1,8), 'QA N45 Store', 'active', 'approved')
      RETURNING id INTO v_store;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status)
      VALUES (v_pend, 'qa-n45-pend-'||substr(v_pend::text,1,8), 'QA N45 Pending', 'active', 'submitted')
      RETURNING id INTO v_pstore;

    -- B1: approved active store can originate orderable supply
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    l_ok := public.marche_listing_create(jsonb_build_object(
      'store_id', v_store, 'title','QA N45 Approved Item', 'category','Autre',
      'price_gnf', 40000, 'quantity_in_stock', 4, 'publish', true));
    v_res := public.marche_listing_truth(l_ok);
    r := r || public._qa_s13_ok('N4R15.B1 approved active store listing is orderable',
          (v_res->>'is_orderable')::boolean, v_res->>'refusal_reason');

    -- B2: ordinary customer (no store) cannot create supply
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_err := NULL;
    BEGIN
      l_none := public.marche_listing_create(jsonb_build_object(
        'title','QA N45 Customer Item','category','Autre','price_gnf',9000,'publish',true));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R15.B2 ordinary customer cannot create storeless supply',
          l_none IS NULL AND v_err = 'MERCHANT_STORE_REQUIRED', COALESCE(v_err,'created'));

    -- B3: customer cannot borrow someone else store
    v_err := NULL;
    BEGIN
      l_none := public.marche_listing_create(jsonb_build_object(
        'store_id', v_store, 'title','QA N45 Hijack','category','Autre','price_gnf',9000,'publish',true));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R15.B3 customer cannot publish into a store they do not own',
          l_none IS NULL AND v_err = 'NOT_STORE_OWNER', COALESCE(v_err,'created'));

    -- B4: pending store may keep a private draft but never orderable
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_pend), true);
    l_pend := public.marche_listing_create(jsonb_build_object(
      'store_id', v_pstore, 'title','QA N45 Pending Item','category','Autre',
      'price_gnf', 12000, 'publish', true));
    SELECT * INTO v_row FROM public.marketplace_listings WHERE id = l_pend;
    r := r || public._qa_s13_ok('N4R15.B4 unapproved store draft stays private/paused',
          v_row.visibility='private' AND v_row.status='paused',
          v_row.status::text||'/'||v_row.visibility);
    v_res := public.marche_listing_publish(l_pend);
    r := r || public._qa_s13_ok('N4R15.B4b unapproved store cannot publish orderable supply',
          (v_res->>'is_orderable')::boolean = false, v_res->>'refusal_reason');

    -- B5: inactive store removes orderability from existing supply
    UPDATE public.merchant_stores SET status='suspended' WHERE id = v_store;
    v_res := public.marche_listing_truth(l_ok);
    r := r || public._qa_s13_ok('N4R15.B5 inactive store makes its supply non-orderable',
          (v_res->>'is_orderable')::boolean = false, v_res->>'refusal_reason');
    UPDATE public.merchant_stores SET status='active' WHERE id = v_store;
    r := r || public._qa_s13_ok('N4R15.B5b reactivated approved store restores orderability',
          (public.marche_listing_truth(l_ok)->>'is_orderable')::boolean, NULL);

    -- B6: legacy storeless row is preserved but never orderable
    PERFORM set_config('marche.rpc','1', true);
    INSERT INTO public.marketplace_listings(seller_id, store_id, kind, category, title,
      price_gnf, pricing_mode, status, visibility, availability)
      VALUES (v_cust, NULL, 'community', 'Autre', 'QA N45 Legacy Community',
              11000, 'fixed', 'active', 'public', 'available')
      RETURNING id INTO l_legacy;
    PERFORM set_config('marche.rpc','', true);
    SELECT * INTO v_row FROM public.marketplace_listings WHERE id = l_legacy;
    v_res := public.marche_listing_truth(l_legacy);
    r := r || public._qa_s13_ok('N4R15.B6 legacy storeless row is preserved but forced private',
          v_row.visibility='private' AND v_row.status='paused', v_row.visibility);
    r := r || public._qa_s13_ok('N4R15.B6b legacy storeless row refuses with MERCHANT_STORE_REQUIRED',
          (v_res->>'is_orderable')::boolean = false
          AND v_res->>'refusal_reason' = 'MERCHANT_STORE_REQUIRED', v_res->>'refusal_reason');
    v_err := NULL;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN PERFORM public.marche_listing_publish(l_legacy);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R15.B6c publishing a storeless row is refused',
          v_err = 'MERCHANT_STORE_REQUIRED', v_err);

    -- B7: non-owner authority
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_other), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_listing_update(l_ok, jsonb_build_object('price_gnf', 1));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R15.B7 non-owner cannot mutate approved-store supply', v_err IS NOT NULL, v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_listing_publish(l_ok);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R15.B7b non-owner cannot publish approved-store supply', v_err IS NOT NULL, v_err);
    v_n := public._qa_node4_probe('authenticated', v_other,
      format('UPDATE public.marketplace_listings SET price_gnf = 1 WHERE id = %L; SELECT 1', l_ok));
    r := r || public._qa_s13_ok('N4R15.B7c direct table write by a signed-in user is rejected', v_n = -1, v_n::text);

    -- B8: canonical discovery only exposes approved-store orderable supply
    SELECT count(*) INTO v_n FROM public.marche_listings_discover(NULL,NULL,NULL,'recent',200,0) d
      LEFT JOIN public.merchant_stores s ON s.id = d.store_id
     WHERE d.store_id IS NULL OR s.status <> 'active' OR s.onboarding_status <> 'approved';
    r := r || public._qa_s13_ok('N4R15.B8 discovery exposes only approved active store supply', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_listings_discover(NULL,NULL,NULL,'recent',200,0) d
     WHERE d.id IN (l_legacy, l_pend);
    r := r || public._qa_s13_ok('N4R15.B8b storeless/unapproved supply absent from discovery', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_store_listing_previews(ARRAY[v_pstore]::uuid[]);
    r := r || public._qa_s13_ok('N4R15.B8c store previews expose no unapproved supply', v_n = 0, v_n::text);

    -- B9: media privacy on non-orderable parents
    INSERT INTO public.listing_images(listing_id, url, position, is_primary)
      VALUES (l_legacy, 'https://qa.invalid/n45-legacy.jpg', 0, true);
    INSERT INTO public.listing_images(listing_id, url, position, is_primary)
      VALUES (l_ok, 'https://qa.invalid/n45-public.jpg', 0, true);
    v_n := public._qa_node4_probe('anon', NULL,
      format('SELECT count(*)::int FROM public.listing_images WHERE listing_id = %L', l_legacy));
    r := r || public._qa_s13_ok('N4R15.B9 anon cannot enumerate storeless listing media', v_n = 0, v_n::text);
    v_n := public._qa_node4_probe('anon', NULL,
      format('SELECT count(*)::int FROM public.listing_images WHERE listing_id = %L', l_ok));
    r := r || public._qa_s13_ok('N4R15.B9b anon still sees approved-store public media', v_n = 1, v_n::text);
    v_n := public._qa_node4_probe('anon', NULL,
      format('SELECT count(*)::int FROM public.marketplace_listings WHERE id = %L', l_legacy));
    r := r || public._qa_s13_ok('N4R15.B9c anon cannot read the storeless listing row', v_n = 0, v_n::text);
    PERFORM set_config('request.jwt.claims', '', true);
    r := r || public._qa_s13_ok('N4R15.B9d public detail RPC refuses storeless listing',
          public.marche_listing_public(l_legacy) IS NULL, NULL);
    v_n := public._qa_node4_probe('anon', NULL,
      'SELECT count(*)::int FROM public.marche_listings_discover(NULL,NULL,NULL,''recent'',50,0)');
    r := r || public._qa_s13_ok('N4R15.B9e anon discovery still works without has_role', v_n >= 0, v_n::text);

    -- B10: production supply invariant
    SELECT count(*) INTO v_n FROM public.v_marche_listing_truth
     WHERE is_orderable AND (store_id IS NULL OR kind <> 'merchant'::listing_kind);
    r := r || public._qa_s13_ok('N4R15.B10 zero orderable storeless supply in production', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.v_marche_listing_truth v
      JOIN public.merchant_stores s ON s.id = v.store_id
     WHERE v.is_orderable AND (s.status <> 'active' OR s.onboarding_status <> 'approved');
    r := r || public._qa_s13_ok('N4R15.B10b every orderable listing sits in an approved active store', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.v_marche_listing_truth WHERE is_demo AND is_orderable;
    r := r || public._qa_s13_ok('N4R15.B10c demo supply remains non-orderable', v_n = 0, v_n::text);

  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok('N4R15.FIXTURE runtime block completed without unhandled error', false, SQLERRM);
  END;

  -- ===== CLEANUP =====
  PERFORM set_config('request.jwt.claims', '', true);
  DELETE FROM public.listing_images WHERE listing_id IN (l_ok, l_pend, l_legacy);
  DELETE FROM public.listing_metrics WHERE listing_id IN (l_ok, l_pend, l_legacy);
  DELETE FROM public.marketplace_listings WHERE seller_id IN (v_merch, v_pend, v_cust, v_other, v_adm);
  DELETE FROM public.account_bans WHERE user_id IN (v_merch, v_pend, v_cust, v_other, v_adm);
  DELETE FROM public.merchant_stores WHERE owner_user_id IN (v_merch, v_pend);
  DELETE FROM public.admin_users WHERE user_id = v_adm;
  DELETE FROM public.wallet_transactions WHERE from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (v_merch, v_pend, v_cust, v_other, v_adm)) OR to_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (v_merch, v_pend, v_cust, v_other, v_adm));
  DELETE FROM public.wallets WHERE owner_user_id IN (v_merch, v_pend, v_cust, v_other, v_adm);
  DELETE FROM auth.users WHERE id IN (v_merch, v_pend, v_cust, v_other, v_adm);

  -- ===== SYSTEMIC =====
  SELECT count(*) INTO v_w1 FROM public.wallets;
  SELECT count(*) INTO v_wt1 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj1 FROM public.ledger_journals;
  SELECT count(*) INTO v_ms1 FROM public.missions;
  SELECT count(*) INTO v_pi1 FROM public.payment_intents;
  SELECT count(*) INTO v_total1 FROM public.marketplace_listings;
  SELECT count(*) INTO v_demo1 FROM public.v_marche_listing_truth WHERE is_demo;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;

  r := r || public._qa_s13_ok('N4R15.S1 no wallet / ledger / mission / payment drift',
        v_w1=v_w0 AND v_wt1=v_wt0 AND v_lj1=v_lj0 AND v_ms1=v_ms0 AND v_pi1=v_pi0,
        format('%s/%s/%s/%s/%s', v_w1-v_w0, v_wt1-v_wt0, v_lj1-v_lj0, v_ms1-v_ms0, v_pi1-v_pi0));
  r := r || public._qa_s13_ok('N4R15.S2 feature flags byte-identical', v_flags1 = v_flags0, NULL);
  r := r || public._qa_s13_ok('N4R15.S3 demo quarantine intact, nothing deleted',
        v_demo1 = v_demo0 AND v_demo1 > 0, v_demo1::text);
  r := r || public._qa_s13_ok('N4R15.S4 production listing population unchanged',
        v_total1 = v_total0, format('%s->%s', v_total0, v_total1));

  SELECT count(*) INTO v_n FROM public.marketplace_listings WHERE title LIKE 'QA N45%';
  r := r || public._qa_s13_ok('N4R15.S5 zero listing fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE id IN (v_merch, v_pend, v_cust, v_other, v_adm);
  r := r || public._qa_s13_ok('N4R15.S5b zero auth fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-n45-%';
  r := r || public._qa_s13_ok('N4R15.S5c zero store fixture residue', v_n = 0, v_n::text);

  RETURN public._qa_s13_summary(30, r);
END $function$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r15() FROM PUBLIC, anon, authenticated;