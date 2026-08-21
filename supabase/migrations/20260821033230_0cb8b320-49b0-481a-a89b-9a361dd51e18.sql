-- NODE 5 · A7 — MERCHANT ARCHITECTURE MIGRATION
-- Canonical merchant professional class helpers (mirrors the A6 driver helpers).

CREATE OR REPLACE FUNCTION public._merchant_class_active(_uid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
  SELECT _uid IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.professional_identities pi
     WHERE pi.user_id = _uid
       AND pi.claim_state = 'active'
       AND pi.professional_type = 'merchant'
  );
$fn$;

CREATE OR REPLACE FUNCTION public._merchant_class_require(_uid uuid, _ctx text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE v_type text;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING DETAIL = COALESCE(_ctx,'merchant action');
  END IF;
  SELECT pi.professional_type INTO v_type
    FROM public.professional_identities pi
   WHERE pi.user_id = _uid AND pi.claim_state = 'active';
  IF v_type = 'merchant' THEN RETURN; END IF;
  IF v_type IS NOT NULL THEN
    RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_CONFLICT'
      USING DETAIL = COALESCE(_ctx,'merchant action')
                     || ' requires the MERCHANT professional class; active class is ' || v_type;
  END IF;
  RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_REQUIRED'
    USING DETAIL = COALESCE(_ctx,'merchant action')
                   || ' requires an ACTIVE MERCHANT professional identity';
END $fn$;

-- Composite: asset ownership (layer 2) -> class (layer 1) -> asset operational state (layer 3).
CREATE OR REPLACE FUNCTION public._merchant_store_require(
  _uid uuid, _store_id uuid, _ctx text DEFAULT NULL, _require_operational boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE s public.merchant_stores;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING DETAIL = COALESCE(_ctx,'merchant action'); END IF;
  SELECT * INTO s FROM public.merchant_stores WHERE id = _store_id;
  IF s.id IS NULL THEN RAISE EXCEPTION 'MERCHANT_STORE_NOT_FOUND'; END IF;
  IF s.owner_user_id IS DISTINCT FROM _uid THEN RAISE EXCEPTION 'NOT_STORE_OWNER'; END IF;
  PERFORM public._merchant_class_require(_uid, _ctx);
  IF _require_operational AND NOT (s.status = 'active' AND s.onboarding_status = 'approved') THEN
    RAISE EXCEPTION 'MERCHANT_STORE_NOT_OPERATIONAL'
      USING DETAIL = COALESCE(_ctx,'merchant action') || ': store status ' || COALESCE(s.status,'?')
                     || '/' || COALESCE(s.onboarding_status,'?');
  END IF;
END $fn$;

CREATE OR REPLACE FUNCTION public._merchant_restaurant_require(
  _uid uuid, _restaurant_id uuid, _ctx text DEFAULT NULL, _require_operational boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE r public.food_restaurants;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING DETAIL = COALESCE(_ctx,'merchant action'); END IF;
  SELECT * INTO r FROM public.food_restaurants WHERE id = _restaurant_id;
  IF r.id IS NULL THEN RAISE EXCEPTION 'RESTAURANT_NOT_FOUND'; END IF;
  IF r.owner_user_id IS DISTINCT FROM _uid THEN RAISE EXCEPTION 'NOT_RESTAURANT_OWNER'; END IF;
  PERFORM public._merchant_class_require(_uid, _ctx);
  IF _require_operational AND NOT (r.status = 'active' AND r.verification_state = 'verified') THEN
    RAISE EXCEPTION 'RESTAURANT_NOT_OPERATIONAL'
      USING DETAIL = COALESCE(_ctx,'merchant action') || ': restaurant ' || COALESCE(r.status,'?')
                     || '/' || COALESCE(r.verification_state,'?');
  END IF;
END $fn$;

REVOKE ALL ON FUNCTION public._merchant_class_require(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._merchant_store_require(uuid, uuid, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._merchant_restaurant_require(uuid, uuid, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._merchant_class_active(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._merchant_class_active(uuid) TO authenticated;

-- Surgical authority-gate insertion into the existing frozen merchant surfaces.
-- Each patch is anchored on an exact existing line and fails closed if the anchor
-- is missing or ambiguous, so no frozen body can drift silently.
DO $mig$
DECLARE
  v_patch jsonb := jsonb_build_array(
    jsonb_build_object('fn','_marche_listing_authz',
      'anchor', E'    RAISE EXCEPTION ''NOT_LISTING_OWNER'';\n  END IF;',
      'add',    E'\n  IF NOT public.has_role(auth.uid(), ''admin''::app_role) THEN\n    PERFORM public._merchant_class_require(auth.uid(), ''marche listing mutation'');\n  END IF;'),
    jsonb_build_object('fn','marche_listing_create',
      'anchor', E'    RAISE EXCEPTION ''NOT_STORE_OWNER'';\n  END IF;',
      'add',    E'\n  PERFORM public._merchant_class_require(v_uid, ''marche listing create'');'),
    jsonb_build_object('fn','marche_dispatch_request',
      'anchor', E'    RAISE EXCEPTION ''NOT_AUTHORIZED'';\n  END IF;',
      'add',    E'\n  PERFORM public._merchant_class_require(caller, ''marche merchant dispatch'');'),
    jsonb_build_object('fn','marche_merchant_transition',
      'anchor', E'    RAISE EXCEPTION ''NOT_AUTHORIZED'';\n  END IF;',
      'add',    E'\n  PERFORM public._merchant_class_require(caller, ''marche merchant transition'');'),
    jsonb_build_object('fn','repas_merchant_transition',
      'anchor', E'    RAISE EXCEPTION ''NOT_AUTHORIZED'';\n  END IF;',
      'add',    E'\n  IF NOT public._finance_privileged(v_uid) THEN\n    PERFORM public._merchant_class_require(v_uid, ''repas merchant transition'');\n  END IF;'),
    jsonb_build_object('fn','merchant_settlement_request_create',
      'anchor', E'  IF v_owner IS DISTINCT FROM v_uid THEN RAISE EXCEPTION ''NOT_AUTHORIZED''; END IF;',
      'add',    E'\n  PERFORM public._merchant_class_require(v_uid, ''merchant settlement request'');'),
    jsonb_build_object('fn','merchant_submit_location',
      'anchor', E'  IF v_store.owner_user_id <> v_uid THEN RAISE EXCEPTION ''not store owner''; END IF;',
      'add',    E'\n  PERFORM public._merchant_class_require(v_uid, ''merchant location submission'');'),
    jsonb_build_object('fn','admin_merchant_decision',
      'anchor', E'  IF _decision = ''approve'' THEN',
      'add',    NULL,
      'prefix', E'  IF _decision IN (''approve'',''reactivate'') THEN\n    IF NOT public._merchant_class_active(_row.owner_user_id) THEN\n      RAISE EXCEPTION ''MERCHANT_CLASS_REQUIRED''\n        USING DETAIL = ''store owner holds no ACTIVE MERCHANT professional identity'';\n    END IF;\n  END IF;\n\n')
  );
  r jsonb; v_oid oid; v_src text; v_anchor text; v_new text; v_cnt int;
BEGIN
  FOR r IN SELECT * FROM jsonb_array_elements(v_patch) LOOP
    SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = (r->>'fn');
    IF v_oid IS NULL THEN RAISE EXCEPTION 'A7_TARGET_MISSING: %', r->>'fn'; END IF;
    v_src := pg_get_functiondef(v_oid);
    v_anchor := r->>'anchor';
    IF (length(v_src) - length(replace(v_src, v_anchor, ''))) / NULLIF(length(v_anchor),0) <> 1 THEN
      RAISE EXCEPTION 'A7_ANCHOR_NOT_UNIQUE: %', r->>'fn';
    END IF;
    IF position('_merchant_class_' in v_src) > 0 THEN
      RAISE NOTICE 'A7 already applied to %', r->>'fn';
      CONTINUE;
    END IF;
    v_new := replace(v_src, v_anchor,
      COALESCE(r->>'prefix','') || v_anchor || COALESCE(r->>'add',''));
    EXECUTE v_new;
  END LOOP;

  SELECT count(*) INTO v_cnt FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public'
     AND p.proname IN ('_marche_listing_authz','marche_listing_create','marche_dispatch_request',
                       'marche_merchant_transition','repas_merchant_transition',
                       'merchant_settlement_request_create','merchant_submit_location',
                       'admin_merchant_decision')
     AND pg_get_functiondef(p.oid) LIKE '%_merchant_class_%';
  IF v_cnt <> 8 THEN RAISE EXCEPTION 'A7_PATCH_INCOMPLETE: % / 8', v_cnt; END IF;
END $mig$;

-- RLS: direct professional merchant DML now also requires the ACTIVE MERCHANT class.
DROP POLICY IF EXISTS "Owner updates own store" ON public.merchant_stores;
CREATE POLICY "Owner updates own store" ON public.merchant_stores FOR UPDATE TO authenticated
USING (owner_user_id = auth.uid() AND public._merchant_class_active(auth.uid()))
WITH CHECK (owner_user_id = auth.uid() AND public._merchant_class_active(auth.uid()));

DROP POLICY IF EXISTS "Owners update own restaurant" ON public.food_restaurants;
CREATE POLICY "Owners update own restaurant" ON public.food_restaurants FOR UPDATE
USING (auth.uid() = owner_user_id AND public._merchant_class_active(auth.uid()))
WITH CHECK (auth.uid() = owner_user_id AND public._merchant_class_active(auth.uid()));

DROP POLICY IF EXISTS "Owners manage own menu items" ON public.food_menu_items;
CREATE POLICY "Owners manage own menu items" ON public.food_menu_items FOR ALL
USING (EXISTS (SELECT 1 FROM public.food_restaurants r
                WHERE r.id = food_menu_items.restaurant_id AND r.owner_user_id = auth.uid())
       AND public._merchant_class_active(auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM public.food_restaurants r
                WHERE r.id = food_menu_items.restaurant_id AND r.owner_user_id = auth.uid())
       AND public._merchant_class_active(auth.uid()));

DROP POLICY IF EXISTS "Sellers manage own listing images" ON public.listing_images;
CREATE POLICY "Sellers manage own listing images" ON public.listing_images FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM public.marketplace_listings l
                WHERE l.id = listing_images.listing_id AND l.seller_id = auth.uid())
       AND public._merchant_class_active(auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM public.marketplace_listings l
                WHERE l.id = listing_images.listing_id AND l.seller_id = auth.uid())
       AND public._merchant_class_active(auth.uid()));

DROP POLICY IF EXISTS "Owner manages own merchant" ON public.merchants;
CREATE POLICY "Owner manages own merchant" ON public.merchants FOR ALL
USING (owner_user_id = auth.uid() AND public._merchant_class_active(auth.uid()))
WITH CHECK (owner_user_id = auth.uid() AND public._merchant_class_active(auth.uid()));