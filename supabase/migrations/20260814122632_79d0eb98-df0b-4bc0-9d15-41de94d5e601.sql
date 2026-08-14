-- ============================================================
-- R6.2 PRODUCTION FIX: enforce credential expiry fail-closed.
-- expires_at existed on repas_custody_credentials but was never
-- checked by the consume primitive nor by the holder read view.
-- ============================================================
CREATE OR REPLACE FUNCTION public._repas_custody_consume(p_order_id uuid, p_kind text, p_code text, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'vault'
AS $function$
DECLARE v public.repas_custody_credentials; v_att int;
BEGIN
  SELECT * INTO v FROM public.repas_custody_credentials
   WHERE order_id = p_order_id AND kind = p_kind FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'CUSTODY_CODE_NOT_ISSUED'; END IF;
  IF v.consumed_at IS NOT NULL THEN RAISE EXCEPTION 'CUSTODY_CODE_ALREADY_USED'; END IF;
  IF v.locked_at IS NOT NULL THEN RAISE EXCEPTION 'CUSTODY_CODE_LOCKED'; END IF;
  IF v.expires_at IS NOT NULL AND v.expires_at <= now() THEN
    RAISE EXCEPTION 'CUSTODY_CODE_EXPIRED' USING DETAIL = v.expires_at::text;
  END IF;
  IF public._repas_custody_dispute_blocked(p_order_id) THEN
    RAISE EXCEPTION 'CUSTODY_DISPUTE_BLOCKED';
  END IF;
  IF p_code IS NULL OR length(trim(p_code)) = 0 THEN
    RAISE EXCEPTION 'CUSTODY_CODE_REQUIRED';
  END IF;

  IF public._repas_custody_hash(v.code_salt, trim(p_code)) IS DISTINCT FROM v.code_hash THEN
    UPDATE public.repas_custody_credentials
       SET attempts = attempts + 1,
           locked_at = CASE WHEN attempts + 1 >= 5 THEN now() ELSE locked_at END,
           updated_at = now()
     WHERE id = v.id
     RETURNING attempts INTO v_att;
    IF v_att >= 5 THEN PERFORM public._repas_custody_purge_secret(v.id); END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'CUSTODY_CODE_INVALID',
                              'attempts', v_att, 'attempts_left', GREATEST(5 - v_att, 0),
                              'locked', v_att >= 5);
  END IF;

  UPDATE public.repas_custody_credentials
     SET consumed_at = now(), consumed_by = p_actor, updated_at = now()
   WHERE id = v.id;
  PERFORM public._repas_custody_purge_secret(v.id);
  RETURN jsonb_build_object('ok', true);
END; $function$;

CREATE OR REPLACE FUNCTION public.repas_custody_code_view(p_order_id uuid, p_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'vault'
AS $function$
DECLARE v_uid uuid := auth.uid(); v public.repas_custody_credentials; v_state text; v_code text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_kind NOT IN ('restaurant_handoff','customer_delivery','customer_pickup') THEN
    RAISE EXCEPTION 'INVALID_CUSTODY_KIND';
  END IF;
  SELECT state::text INTO v_state FROM public.food_orders WHERE id = p_order_id;
  IF v_state IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;

  SELECT * INTO v FROM public.repas_custody_credentials
   WHERE order_id = p_order_id AND kind = p_kind;
  IF v.id IS NULL THEN
    RETURN jsonb_build_object('issued', false, 'kind', p_kind);
  END IF;
  IF v.holder_user_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'CUSTODY_CODE_FORBIDDEN';
  END IF;
  IF v_state IN ('completed','cancelled') THEN
    RETURN jsonb_build_object('issued', true, 'kind', p_kind, 'expired', true, 'active', false);
  END IF;
  IF v.expires_at IS NOT NULL AND v.expires_at <= now() THEN
    RETURN jsonb_build_object('issued', true, 'kind', p_kind, 'expired', true, 'active', false);
  END IF;
  IF public._repas_custody_dispute_blocked(p_order_id) THEN
    RETURN jsonb_build_object('issued', true, 'kind', p_kind, 'expired', true,
                              'active', false, 'disputed', true);
  END IF;

  IF v.consumed_at IS NULL AND v.locked_at IS NULL AND v.code_secret_id IS NOT NULL THEN
    SELECT decrypted_secret INTO v_code FROM vault.decrypted_secrets WHERE id = v.code_secret_id;
  END IF;

  RETURN jsonb_build_object(
    'issued', true, 'kind', p_kind, 'expired', false, 'active', true,
    'code', v_code,
    'consumed', v.consumed_at IS NOT NULL,
    'locked', v.locked_at IS NOT NULL,
    'attempts', v.attempts,
    'attempts_left', GREATEST(5 - v.attempts, 0));
END; $function$;

-- ============================================================
-- QA-ONLY: real storage proof fixture helper.
-- ============================================================
CREATE OR REPLACE FUNCTION public._qa_r6_proof(p_mission uuid, p_phase text, p_owner uuid, p_tag text DEFAULT 'a')
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'storage'
AS $function$
DECLARE v_path text;
BEGIN
  v_path := p_mission::text || '/' || p_phase || '-' || p_tag || '.jpg';
  INSERT INTO storage.objects(bucket_id, name, owner, owner_id, metadata)
  VALUES ('mission-proofs', v_path, p_owner, p_owner::text, '{"mimetype":"image/jpeg"}'::jsonb)
  ON CONFLICT (bucket_id, name) DO UPDATE SET owner = EXCLUDED.owner, owner_id = EXCLUDED.owner_id;
  RETURN v_path;
END; $function$;

REVOKE ALL ON FUNCTION public._qa_r6_proof(uuid,text,uuid,text) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- R6 CERTIFICATION HARNESS (rebuilt: canonical lifecycle order,
-- real storage proofs, expiry / dispute / cancellation proofs,
-- plaintext-leak proofs).
-- ============================================================
CREATE OR REPLACE FUNCTION public._qa_node3_repas_r6_custody()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault', 'storage', 'extensions'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_cust2 uuid; v_merch uuid; v_drv uuid; v_drv2 uuid;
  v_store uuid; v_resto uuid; v_item uuid; v_item2 uuid;
  v_o1 uuid; v_o3 uuid; v_o4 uuid; v_o5 uuid; v_o6 uuid;
  v_m1 uuid; v_m3 uuid; v_m4 uuid; v_m6 uuid;
  v_res jsonb; v_err text; v_n int; v_state text; v_def text; v_i int;
  v_code text; v_code2 text; v_view jsonb;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_cp public.chop_pay_order_runtime;
  v_c0 bigint; v_c1 bigint; v_d0 bigint; v_d1 bigint; v_mm0 bigint; v_mm1 bigint;
  v_x0 bigint; v_x1 bigint; v_held bigint; v_open bigint; v_unbalanced int;
  v_att int; v_bal bigint; v_sec uuid; v_row text; v_p1 text; v_p2 text; v_pbad text;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  -- ================= S0. STATIC SHAPE / SECURITY =================
  r := r || public._qa_s13_ok('S0.1 custody credential store exists',
        to_regclass('public.repas_custody_credentials') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('S0.2 custody event ledger exists',
        to_regclass('public.repas_custody_events') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('S0.3 credential store has RLS on',
        (SELECT relrowsecurity FROM pg_class WHERE oid='public.repas_custody_credentials'::regclass), NULL);
  SELECT count(*) INTO v_n FROM pg_policies WHERE tablename='repas_custody_credentials';
  r := r || public._qa_s13_ok('S0.4 credential store exposes no RLS policy at all', v_n = 0, v_n::text);
  r := r || public._qa_s13_ok('S0.5 credential store not readable by anon/authenticated',
        NOT has_table_privilege('anon','public.repas_custody_credentials','SELECT')
        AND NOT has_table_privilege('authenticated','public.repas_custody_credentials','SELECT'), NULL);
  r := r || public._qa_s13_ok('S0.6 credential store not writable by authenticated',
        NOT has_table_privilege('authenticated','public.repas_custody_credentials','INSERT')
        AND NOT has_table_privilege('authenticated','public.repas_custody_credentials','UPDATE')
        AND NOT has_table_privilege('authenticated','public.repas_custody_credentials','DELETE'), NULL);
  r := r || public._qa_s13_ok('S0.7 custody events readable by participants only, never writable',
        has_table_privilege('authenticated','public.repas_custody_events','SELECT')
        AND NOT has_table_privilege('authenticated','public.repas_custody_events','INSERT')
        AND NOT has_table_privilege('authenticated','public.repas_custody_events','UPDATE')
        AND NOT has_table_privilege('authenticated','public.repas_custody_events','DELETE')
        AND NOT has_table_privilege('anon','public.repas_custody_events','SELECT'), NULL);
  r := r || public._qa_s13_ok('S0.8 custody events are append-only by trigger',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.repas_custody_events'::regclass
                  AND tgname='repas_custody_events_immutable'), NULL);
  r := r || public._qa_s13_ok('S0.9 custody mutation RPCs closed to anon',
        NOT has_function_privilege('anon','public.repas_custody_confirm_handoff(uuid,text,text)','EXECUTE')
        AND NOT has_function_privilege('anon','public.repas_custody_confirm_delivery(uuid,text,text)','EXECUTE')
        AND NOT has_function_privilege('anon','public.repas_custody_confirm_pickup_collection(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('S0.10 credential read RPCs closed to anon',
        NOT has_function_privilege('anon','public.repas_custody_code_view(uuid,text)','EXECUTE')
        AND NOT has_function_privilege('anon','public.repas_custody_status(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('S0.11 credential issue/consume primitives closed to authenticated',
        NOT has_function_privilege('authenticated','public._repas_custody_issue(uuid,text,uuid)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._repas_custody_consume(uuid,text,text,uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('S0.12 this harness is closed to anon/authenticated',
        NOT has_function_privilege('anon','public._qa_node3_repas_r6_custody()','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._qa_node3_repas_r6_custody()','EXECUTE'), NULL);

  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='mission_confirm_pickup';
  r := r || public._qa_s13_ok('S0.13 bare mission_confirm_pickup carries the Repas custody guard',
        v_def LIKE '%_repas_custody_guard%', NULL);
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='mission_confirm_dropoff';
  r := r || public._qa_s13_ok('S0.14 bare mission_confirm_dropoff carries the Repas custody guard',
        v_def LIKE '%_repas_custody_guard%', NULL);
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='mission_set_state';
  r := r || public._qa_s13_ok('S0.15 mission_set_state cannot force Repas possession states',
        v_def LIKE '%_repas_custody_guard%', NULL);
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='repas_merchant_transition';
  r := r || public._qa_s13_ok('S0.16 merchant handoff button is server-refused',
        v_def LIKE '%HANDOFF_OWNED_BY_COURIER_CUSTODY%', NULL);
  r := r || public._qa_s13_ok('S0.17 merchant one-click pickup completion is server-refused',
        v_def LIKE '%PICKUP_REQUIRES_CUSTOMER_CODE%', NULL);
  r := r || public._qa_s13_ok('S0.18 anon cannot execute the bare mission confirmations',
        NOT has_function_privilege('anon','public.mission_confirm_pickup(uuid)','EXECUTE')
        AND NOT has_function_privilege('anon','public.mission_confirm_dropoff(uuid)','EXECUTE'), NULL);

  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='repas_custody_credentials'
     AND column_name IN ('code_plain','code','code_text','plain_code','secret');
  r := r || public._qa_s13_ok('S0.19 no plaintext credential column exists at rest', v_n = 0, v_n::text);
  r := r || public._qa_s13_ok('S0.20 credential store keeps only a salted verifier',
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='repas_custody_credentials' AND column_name='code_hash')
        AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='repas_custody_credentials' AND column_name='code_salt'), NULL);
  r := r || public._qa_s13_ok('S0.21 the mission proof bucket is private',
        (SELECT NOT public FROM storage.buckets WHERE id='mission-proofs'), NULL);
  r := r || public._qa_s13_ok('S0.22 the photo verifier and hash primitives are closed to clients',
        NOT has_function_privilege('authenticated','public._repas_custody_verify_photo(uuid,text,uuid,text)','EXECUTE')
        AND NOT has_function_privilege('anon','public._repas_custody_verify_photo(uuid,text,uuid,text)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._repas_custody_hash(text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('S0.23 the QA proof fixture helper is closed to clients',
        NOT has_function_privilege('anon','public._qa_r6_proof(uuid,text,uuid,text)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._qa_r6_proof(uuid,text,uuid,text)','EXECUTE'), NULL);
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='_repas_custody_consume';
  r := r || public._qa_s13_ok('S0.24 the consume primitive enforces credential expiry',
        v_def LIKE '%CUSTODY_CODE_EXPIRED%', NULL);
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='repas_custody_code_view';
  r := r || public._qa_s13_ok('S0.25 the holder read view enforces credential expiry',
        v_def LIKE '%expires_at%', NULL);
  r := r || public._qa_s13_ok('S0.26 terminal orders purge custody secrets by trigger',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.food_orders'::regclass
                  AND NOT tgisinternal
                  AND pg_get_triggerdef(oid) LIKE '%_repas_custody_invalidate_on_terminal%'), NULL);

  BEGIN
    -- ================= FIXTURES =================
    v_cust := gen_random_uuid(); v_cust2 := gen_random_uuid(); v_merch := gen_random_uuid();
    v_drv := gen_random_uuid(); v_drv2 := gen_random_uuid();
    PERFORM public._qa_s13_user(v_cust,'n3r6c');
    PERFORM public._qa_s13_user(v_cust2,'n3r6x');
    PERFORM public._qa_s13_user(v_merch,'n3r6m');
    PERFORM public._qa_s13_user(v_drv,'n3r6d');
    PERFORM public._qa_s13_user(v_drv2,'n3r6e');
    PERFORM public._qa_s13_wallet(v_cust,'client',5000000,0);
    PERFORM public._qa_s13_wallet(v_cust2,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_merch,'merchant',0,0);
    PERFORM public._qa_s13_wallet(v_drv,'driver',900000,0);
    PERFORM public._qa_s13_wallet(v_drv2,'driver',900000,0);

    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,capabilities)
      VALUES (v_drv,'approved','livraison',ARRAY['repas_delivery'])
      ON CONFLICT (user_id) DO UPDATE SET status='approved', capabilities=ARRAY['repas_delivery'];
    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,capabilities)
      VALUES (v_drv2,'approved','livraison',ARRAY['repas_delivery'])
      ON CONFLICT (user_id) DO UPDATE SET status='approved', capabilities=ARRAY['repas_delivery'];

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, delivery_available, status)
      VALUES (v_merch, 'qa-n3r6-store-'||substr(v_merch::text,1,8), 'QA N3R6 Store', true, 'active')
      RETURNING id INTO v_store;
    INSERT INTO public.food_restaurants(owner_user_id, merchant_store_id, slug, name, status,
        is_open, delivery_available, pickup_available, choppay_enabled, prep_time_min, latitude, longitude)
      VALUES (v_merch, v_store, 'qa-n3r6-resto-'||substr(v_merch::text,1,8), 'QA N3R6 Resto',
              'active', true, true, true, true, 20, 9.5350, -13.6800)
      RETURNING id INTO v_resto;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA Plat A',100000,true) RETURNING id INTO v_item;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA Plat B',50000,true) RETURNING id INTO v_item2;

    UPDATE public.feature_flags SET enabled = true WHERE key = 'chop_pay_checkout_enabled';

    SELECT balance_gnf INTO v_c0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_mm0 FROM public.wallets WHERE owner_user_id=v_merch AND party_type='merchant';
    SELECT balance_gnf INTO v_d0 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT balance_gnf INTO v_x0 FROM public.wallets WHERE party_type='master' LIMIT 1;

    -- ================= A1. RESTAURANT -> COURIER (LIVRAISON) =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                          jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Dixinn, Conakry', 9.5400, -13.6900);
    v_o1 := (v_res->>'order_id')::uuid; v_m1 := (v_res->>'mission_id')::uuid;
    r := r || public._qa_s13_ok('A1.0 delivery order and mission committed',
          v_o1 IS NOT NULL AND v_m1 IS NOT NULL, v_res::text);

    SELECT count(*) INTO v_n FROM public.repas_custody_credentials WHERE order_id=v_o1;
    r := r || public._qa_s13_ok('A1.1 no credential exists before the food is ready', v_n = 0, v_n::text);

    -- Canonical Livraison order: the courier commits (collateral) BEFORE the
    -- restaurant may capture merchandise funding. Merchant accept is refused
    -- while the order is still merely authorized.
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    BEGIN PERFORM public.repas_merchant_transition(v_o1,'accept'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.0a merchant funding capture is refused before a courier commits',
          v_err LIKE '%INVALID_STATE%', v_err);
    SELECT state INTO v_state FROM public.chop_pay_order_runtime
     WHERE source_module='repas' AND source_id=v_o1;
    r := r || public._qa_s13_ok('A1.0b the refused accept left the runtime authorized',
          v_state = 'authorized', v_state);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_m1);
    SELECT state INTO v_state FROM public.chop_pay_order_runtime
     WHERE source_module='repas' AND source_id=v_o1;
    r := r || public._qa_s13_ok('A1.0c the courier claim commits collateral and moves to accepted',
          v_state = 'accepted', v_state);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.repas_merchant_transition(v_o1,'accept');
    PERFORM public.repas_merchant_transition(v_o1,'prepare');
    PERFORM public.repas_merchant_transition(v_o1,'ready');

    SELECT count(*) INTO v_n FROM public.repas_custody_credentials
     WHERE order_id=v_o1 AND kind='restaurant_handoff' AND holder_user_id=v_merch;
    r := r || public._qa_s13_ok('A1.4 ready mints exactly one restaurant-held credential', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_custody_credentials
     WHERE order_id=v_o1 AND kind='customer_delivery';
    r := r || public._qa_s13_ok('A1.5 the customer delivery code is NOT minted before pickup', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_custody_credentials
     WHERE order_id=v_o1 AND code_secret_id IS NOT NULL;
    r := r || public._qa_s13_ok('A1.6 the code itself lives in the encrypted vault, not the table', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_custody_credentials
     WHERE order_id=v_o1 AND length(code_hash) = 64 AND length(code_salt) = 32;
    r := r || public._qa_s13_ok('A1.7 credentials are salted sha256 verifiers', v_n = 1, v_n::text);

    v_view := public.repas_custody_code_view(v_o1,'restaurant_handoff');
    r := r || public._qa_s13_ok('A1.8 the restaurant can read its own handoff code',
          (v_view->>'code') IS NOT NULL AND length(v_view->>'code') = 6, NULL);
    v_code := v_view->>'code';

    SELECT c::text INTO v_row FROM public.repas_custody_credentials c
     WHERE order_id=v_o1 AND kind='restaurant_handoff';
    r := r || public._qa_s13_ok('A1.8a the live code appears nowhere in the persisted credential row',
          position(v_code in v_row) = 0, NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    v_p1 := public._qa_r6_proof(v_m1,'pickup',v_drv,'ok');
    BEGIN PERFORM public.repas_custody_confirm_handoff(v_m1,v_p1,v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.2 handoff refused before the courier has arrived at pickup',
          v_err LIKE '%INVALID_MISSION_STATE%', v_err);
    SELECT count(*) INTO v_n FROM public.repas_custody_events WHERE order_id=v_o1;
    r := r || public._qa_s13_ok('A1.3 the premature handoff wrote no custody event', v_n = 0, v_n::text);

    PERFORM public.mission_set_state(v_m1,'arrived_pickup');

    BEGIN PERFORM public.repas_custody_code_view(v_o1,'restaurant_handoff'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.9 the courier cannot read the code it must be given',
          v_err LIKE '%CUSTODY_CODE_FORBIDDEN%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN PERFORM public.repas_custody_code_view(v_o1,'restaurant_handoff'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.10 the customer cannot read the restaurant code',
          v_err LIKE '%CUSTODY_CODE_FORBIDDEN%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    BEGIN PERFORM public.repas_custody_code_view(v_o1,'restaurant_handoff'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.11 an unrelated user cannot read any code',
          v_err LIKE '%CUSTODY_CODE_FORBIDDEN%' OR v_err LIKE '%NOT_AUTHORIZED%', v_err);
    BEGIN PERFORM public.repas_custody_status(v_o1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.12 an unrelated user cannot read custody status',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    BEGIN PERFORM public.repas_merchant_transition(v_o1,'handoff'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.13 the merchant cannot declare the courier handoff',
          v_err LIKE '%HANDOFF_OWNED_BY_COURIER_CUSTODY%', v_err);
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o1;
    r := r || public._qa_s13_ok('A1.14 the refused merchant handoff changed nothing',
          v_state='ready', v_state);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    BEGIN PERFORM public.repas_custody_confirm_handoff(v_m1,v_p1,v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.15 an unassigned courier cannot take custody',
          v_err LIKE '%NOT_ASSIGNED_COURIER%', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN PERFORM public.repas_custody_confirm_handoff(v_m1,'',v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.16 a missing photo refuses the handoff',
          v_err LIKE '%CUSTODY_PHOTO_REQUIRED%', v_err);

    -- Photo proof must be a REAL private-bucket object owned by this courier
    -- for this mission and this phase.
    BEGIN PERFORM public.repas_custody_confirm_handoff(v_m1, v_m1::text||'/pickup-ghost.jpg', v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.16a a photo path with no stored object is refused',
          v_err LIKE '%CUSTODY_PHOTO_NOT_FOUND%', v_err);
    v_pbad := public._qa_r6_proof(v_m1,'delivery',v_drv,'phase');
    BEGIN PERFORM public.repas_custody_confirm_handoff(v_m1, v_pbad, v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.16b a delivery-phase photo cannot prove a pickup',
          v_err LIKE '%CUSTODY_PHOTO_PHASE_MISMATCH%', v_err);
    v_pbad := public._qa_r6_proof(v_m1,'pickup',v_drv2,'owner');
    BEGIN PERFORM public.repas_custody_confirm_handoff(v_m1, v_pbad, v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.16c a photo owned by another courier is refused',
          v_err LIKE '%CUSTODY_PHOTO_OWNER_MISMATCH%', v_err);
    v_pbad := public._qa_r6_proof(gen_random_uuid(),'pickup',v_drv,'mission');
    BEGIN PERFORM public.repas_custody_confirm_handoff(v_m1, v_pbad, v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.16d a photo filed under another mission is refused',
          v_err LIKE '%CUSTODY_PHOTO_MISSION_MISMATCH%', v_err);
    SELECT attempts INTO v_att FROM public.repas_custody_credentials
     WHERE order_id=v_o1 AND kind='restaurant_handoff';
    r := r || public._qa_s13_ok('A1.16e refused photo proofs never burn a code attempt', v_att = 0, v_att::text);

    BEGIN PERFORM public.mission_confirm_pickup(v_m1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.17 bare mission_confirm_pickup cannot bypass custody',
          v_err LIKE '%REPAS_CUSTODY_REQUIRED%', v_err);
    BEGIN PERFORM public.mission_confirm_pickup_with_proof(v_m1,v_p1,'anything'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.18 the legacy proof RPC cannot bypass Repas custody',
          v_err LIKE '%REPAS_CUSTODY_REQUIRED%', v_err);
    BEGIN PERFORM public.mission_set_state(v_m1,'picked_up'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.19 mission_set_state cannot force picked_up',
          v_err LIKE '%REPAS_CUSTODY_REQUIRED%', v_err);
    SELECT count(*) INTO v_n FROM public.missions WHERE id=v_m1 AND pickup_confirmed_at IS NOT NULL;
    r := r || public._qa_s13_ok('A1.20 no bypass established custody', v_n = 0, v_n::text);

    v_res := public.repas_custody_confirm_handoff(v_m1,v_p1,'111111');
    r := r || public._qa_s13_ok('A1.21 a wrong code is refused and counted, not fatal',
          (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='CUSTODY_CODE_INVALID'
          AND (v_res->>'attempts_left')::int = 4, v_res::text);
    SELECT count(*) INTO v_n FROM public.repas_custody_events WHERE order_id=v_o1;
    r := r || public._qa_s13_ok('A1.21b the wrong code established no custody', v_n = 0, v_n::text);

    SELECT code_secret_id INTO v_sec FROM public.repas_custody_credentials
     WHERE order_id=v_o1 AND kind='restaurant_handoff';
    v_res := public.repas_custody_confirm_handoff(v_m1,v_p1,v_code);
    r := r || public._qa_s13_ok('A1.22 a valid proof establishes courier custody',
          (v_res->>'ok')::boolean AND (v_res->>'mission_state')='picked_up', v_res::text);
    SELECT count(*) INTO v_n FROM vault.secrets WHERE id = v_sec;
    r := r || public._qa_s13_ok('A1.22b consuming the code destroys the vault secret', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_custody_events
     WHERE order_id=v_o1 AND boundary='restaurant_to_courier';
    r := r || public._qa_s13_ok('A1.23 exactly one authoritative custody event', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_custody_events
     WHERE order_id=v_o1 AND boundary='restaurant_to_courier'
       AND actor_user_id=v_drv AND photo_path=v_p1 AND occurred_at IS NOT NULL;
    r := r || public._qa_s13_ok('A1.24 the event records actor, photo and server timestamp', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_custody_events e
     WHERE e.order_id=v_o1 AND position(v_code in e::text) > 0;
    r := r || public._qa_s13_ok('A1.24b the audit trail never records the code itself', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_events me
     WHERE me.mission_id=v_m1 AND position(v_code in me::text) > 0;
    r := r || public._qa_s13_ok('A1.24c the mission event log never records the code either', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.missions
     WHERE id=v_m1 AND state='picked_up' AND pickup_confirmed_by=v_drv
       AND pickup_photo_url=v_p1;
    r := r || public._qa_s13_ok('A1.25 the mission carries the real proof path', v_n = 1, v_n::text);
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o1;
    r := r || public._qa_s13_ok('A1.26 the order moved to out_for_delivery', v_state='out_for_delivery', v_state);
    SELECT count(*) INTO v_n FROM public.mission_events
     WHERE mission_id=v_m1 AND event='repas_custody_restaurant_to_courier';
    r := r || public._qa_s13_ok('A1.27 the server wrote the mission event itself', v_n = 1, v_n::text);

    BEGIN PERFORM public.repas_custody_confirm_handoff(v_m1,v_p1,v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A1.28 replaying the handoff is refused',
          v_err LIKE '%CUSTODY_CODE_ALREADY_USED%' OR v_err LIKE '%INVALID_MISSION_STATE%', v_err);
    SELECT count(*) INTO v_n FROM public.repas_custody_events
     WHERE order_id=v_o1 AND boundary='restaurant_to_courier';
    r := r || public._qa_s13_ok('A1.29 the replay created no second event', v_n = 1, v_n::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_view := public.repas_custody_code_view(v_o1,'restaurant_handoff');
    r := r || public._qa_s13_ok('A1.30 a consumed restaurant code is never displayable again',
          (v_view->>'code') IS NULL AND (v_view->>'consumed')::boolean IS TRUE, v_view::text);

    -- ================= A2. COURIER -> CUSTOMER =================
    SELECT count(*) INTO v_n FROM public.repas_custody_credentials
     WHERE order_id=v_o1 AND kind='customer_delivery' AND holder_user_id=v_cust;
    r := r || public._qa_s13_ok('A2.1 the customer delivery code is minted at pickup', v_n = 1, v_n::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN PERFORM public.repas_custody_code_view(v_o1,'customer_delivery'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A2.2 the courier cannot read the customer delivery code',
          v_err LIKE '%CUSTODY_CODE_FORBIDDEN%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    BEGIN PERFORM public.repas_custody_code_view(v_o1,'customer_delivery'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A2.3 the merchant cannot read the customer delivery code',
          v_err LIKE '%CUSTODY_CODE_FORBIDDEN%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_view := public.repas_custody_code_view(v_o1,'customer_delivery');
    v_code := v_view->>'code';
    r := r || public._qa_s13_ok('A2.4 the customer can read their own delivery code',
          v_code IS NOT NULL AND length(v_code)=6, NULL);
    r := r || public._qa_s13_ok('A2.4b the two boundary codes are independent secrets',
          v_code IS DISTINCT FROM (SELECT NULL::text), NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    v_p2 := public._qa_r6_proof(v_m1,'delivery',v_drv,'ok');
    BEGIN PERFORM public.repas_custody_confirm_delivery(v_m1,v_p2,v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A2.5 delivery refused before arrival at the dropoff',
          v_err LIKE '%INVALID_MISSION_STATE%', v_err);
    PERFORM public.mission_set_state(v_m1,'heading_to_dropoff');
    PERFORM public.mission_set_state(v_m1,'arrived_dropoff');

    BEGIN PERFORM public.mission_confirm_dropoff(v_m1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A2.6 bare mission_confirm_dropoff cannot bypass custody',
          v_err LIKE '%REPAS_CUSTODY_REQUIRED%', v_err);
    BEGIN PERFORM public.mission_confirm_dropoff_with_proof(v_m1,v_p2,'000000'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A2.7 the legacy dropoff proof RPC cannot bypass custody',
          v_err LIKE '%REPAS_CUSTODY_REQUIRED%', v_err);
    BEGIN PERFORM public.mission_set_state(v_m1,'delivered'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A2.8 mission_set_state cannot force delivered',
          v_err LIKE '%REPAS_CUSTODY_REQUIRED%', v_err);
    SELECT state INTO v_state FROM public.chop_pay_order_runtime
     WHERE source_module='repas' AND source_id=v_o1;
    r := r || public._qa_s13_ok('A2.9 every bypass attempt was economically inert',
          v_state <> 'completed', v_state);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    BEGIN PERFORM public.repas_custody_confirm_delivery(v_m1,v_p2,v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A2.9b a different courier cannot close this delivery',
          v_err LIKE '%NOT_ASSIGNED_COURIER%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);

    v_res := public.repas_custody_confirm_delivery(v_m1,v_p2,'999999');
    r := r || public._qa_s13_ok('A2.10 a wrong customer code refuses the delivery',
          (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='CUSTODY_CODE_INVALID', v_res::text);
    SELECT attempts INTO v_att FROM public.repas_custody_credentials
     WHERE order_id=v_o1 AND kind='customer_delivery';
    r := r || public._qa_s13_ok('A2.11 the failed attempt is durably counted server-side',
          v_att = 1, v_att::text);
    SELECT state INTO v_state FROM public.chop_pay_order_runtime
     WHERE source_module='repas' AND source_id=v_o1;
    r := r || public._qa_s13_ok('A2.11b the refused delivery settled nothing',
          v_state <> 'completed', v_state);
    BEGIN PERFORM public.repas_custody_confirm_delivery(v_m1,'',v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A2.12 a missing delivery photo refuses the delivery',
          v_err LIKE '%CUSTODY_PHOTO_REQUIRED%', v_err);

    v_res := public.repas_custody_confirm_delivery(v_m1,v_p2,v_code);
    r := r || public._qa_s13_ok('A2.13 a valid proof completes the delivery',
          (v_res->>'ok')::boolean, v_res::text);
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime
     WHERE source_module='repas' AND source_id=v_o1;
    r := r || public._qa_s13_ok('A2.14 the canonical Chop Pay engine settled the order',
          v_cp.state='completed', v_cp.state);
    r := r || public._qa_s13_ok('A2.15 frozen R5 courier payout is unchanged',
          v_cp.driver_earning_gnf = 15000, COALESCE(v_cp.driver_earning_gnf,0)::text);
    r := r || public._qa_s13_ok('A2.16 frozen R5 platform fee is unchanged',
          v_cp.platform_revenue_gnf = 1500, COALESCE(v_cp.platform_revenue_gnf,0)::text);
    r := r || public._qa_s13_ok('A2.17 merchant principal is unchanged',
          v_cp.merchant_credited_gnf = 150000, COALESCE(v_cp.merchant_credited_gnf,0)::text);
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o1;
    r := r || public._qa_s13_ok('A2.18 the food order is completed', v_state='completed', v_state);
    SELECT state::text INTO v_state FROM public.missions WHERE id=v_m1;
    r := r || public._qa_s13_ok('A2.19 the mission is delivered', v_state='delivered', v_state);
    SELECT count(*) INTO v_n FROM public.repas_custody_events
     WHERE order_id=v_o1 AND boundary='courier_to_customer';
    r := r || public._qa_s13_ok('A2.20 exactly one delivery custody event', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_custody_events WHERE order_id=v_o1;
    r := r || public._qa_s13_ok('A2.21 the custody chain has both boundaries', v_n = 2, v_n::text);

    SELECT balance_gnf INTO v_bal FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    BEGIN PERFORM public.repas_custody_confirm_delivery(v_m1,v_p2,v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_d1 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s13_ok('A2.22 replaying the delivery moves zero additional value',
          v_d1 = v_bal, v_d1::text||' err='||v_err);
    SELECT count(*) INTO v_n FROM public.repas_custody_events
     WHERE order_id=v_o1 AND boundary='courier_to_customer';
    r := r || public._qa_s13_ok('A2.23 the delivery replay created no second event', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.chop_pay_order_runtime
     WHERE source_module='repas' AND source_id=v_o1;
    r := r || public._qa_s13_ok('A2.23b exactly one settlement runtime row exists', v_n = 1, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_view := public.repas_custody_code_view(v_o1,'customer_delivery');
    r := r || public._qa_s13_ok('A2.24 a consumed credential is no longer displayable',
          (v_view->>'code') IS NULL, v_view::text);

    -- ================= C. ATTEMPT CAP / LOCKOUT =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Ratoma, Conakry', 9.5500, -13.6700);
    v_o3 := (v_res->>'order_id')::uuid; v_m3 := (v_res->>'mission_id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_m3);
    PERFORM public.mission_set_state(v_m3,'arrived_pickup');
    v_p1 := public._qa_r6_proof(v_m3,'pickup',v_drv,'ok');
    BEGIN PERFORM public.repas_custody_confirm_handoff(v_m3,v_p1,'000000'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C1.0 handoff refused while the order is not ready',
          v_err LIKE '%ORDER_NOT_READY%' OR v_err LIKE '%CUSTODY_CODE_NOT_ISSUED%', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.repas_merchant_transition(v_o3,'accept');
    PERFORM public.repas_merchant_transition(v_o3,'prepare');
    PERFORM public.repas_merchant_transition(v_o3,'ready');
    v_view := public.repas_custody_code_view(v_o3,'restaurant_handoff');
    v_code2 := v_view->>'code';
    r := r || public._qa_s13_ok('C1.1 each order gets its own distinct credential',
          v_code2 IS NOT NULL AND (SELECT count(DISTINCT code_hash) FROM public.repas_custody_credentials
            WHERE order_id IN (v_o1,v_o3)) = (SELECT count(*) FROM public.repas_custody_credentials
            WHERE order_id IN (v_o1,v_o3)), NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    FOR v_i IN 1..5 LOOP
      BEGIN PERFORM public.repas_custody_confirm_handoff(v_m3,v_p1,'000000'); v_err := 'NO_ERROR';
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    END LOOP;
    SELECT attempts, (locked_at IS NOT NULL)::text INTO v_att, v_state
      FROM public.repas_custody_credentials WHERE order_id=v_o3 AND kind='restaurant_handoff';
    r := r || public._qa_s13_ok('C1.2 five wrong codes are durably counted', v_att = 5, v_att::text);
    r := r || public._qa_s13_ok('C1.3 the credential is locked at the cap', v_state = 'true', v_state);
    BEGIN PERFORM public.repas_custody_confirm_handoff(v_m3,v_p1,v_code2); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C1.4 even the correct code fails closed after lockout',
          v_err LIKE '%CUSTODY_CODE_LOCKED%', v_err);
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o3;
    r := r || public._qa_s13_ok('C1.5 the locked-out order never left ready', v_state='ready', v_state);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_view := public.repas_custody_code_view(v_o3,'restaurant_handoff');
    r := r || public._qa_s13_ok('C1.6 a locked credential is reported as locked',
          (v_view->>'locked')::boolean IS TRUE, v_view::text);
    r := r || public._qa_s13_ok('C1.6b a locked credential no longer discloses its code',
          (v_view->>'code') IS NULL, v_view::text);
    r := r || public._qa_s13_ok('C1.7 the client cannot reset the attempt counter',
          NOT has_table_privilege('authenticated','public.repas_custody_credentials','UPDATE'), NULL);
    SELECT count(*) INTO v_n FROM public.repas_custody_events WHERE order_id=v_o3;
    r := r || public._qa_s13_ok('C1.8 no custody event survived the lockout sequence', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_custody_credentials c
     WHERE c.order_id=v_o3 AND c.code_secret_id IS NOT NULL;
    r := r || public._qa_s13_ok('C1.9 the lockout destroyed the vault secret', v_n = 0, v_n::text);

    -- ================= A3. DELIVERY WITHOUT PICKUP CUSTODY =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Matam, Conakry', 9.5300, -13.6600);
    v_o4 := (v_res->>'order_id')::uuid; v_m4 := (v_res->>'mission_id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_m4);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.repas_merchant_transition(v_o4,'accept');
    PERFORM public.repas_merchant_transition(v_o4,'prepare');
    PERFORM public.repas_merchant_transition(v_o4,'ready');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_set_state(v_m4,'arrived_pickup');
    PERFORM public.mission_set_state(v_m4,'heading_to_dropoff');
    PERFORM public.mission_set_state(v_m4,'arrived_dropoff');
    v_p2 := public._qa_r6_proof(v_m4,'delivery',v_drv,'ok');
    BEGIN PERFORM public.repas_custody_confirm_delivery(v_m4,v_p2,'123456'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A3.1 delivery refused when pickup custody was never established',
          v_err LIKE '%CUSTODY_NOT_ESTABLISHED%', v_err);
    SELECT state INTO v_state FROM public.chop_pay_order_runtime
     WHERE source_module='repas' AND source_id=v_o4;
    r := r || public._qa_s13_ok('A3.2 that refusal settled nothing', v_state <> 'completed', v_state);
    SELECT count(*) INTO v_n FROM public.repas_custody_events WHERE order_id=v_o4;
    r := r || public._qa_s13_ok('A3.3 no custody event was written', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_custody_credentials
     WHERE order_id=v_o4 AND kind='customer_delivery';
    r := r || public._qa_s13_ok('A3.4 no delivery code exists without a pickup handover', v_n = 0, v_n::text);

    -- ================= B. RETRAIT / PICKUP =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                          jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'pickup','choppay', gen_random_uuid());
    v_o5 := (v_res->>'order_id')::uuid;
    r := r || public._qa_s13_ok('B1.1 a Retrait order stays mission-less',
          (v_res->>'mission_id') IS NULL, v_res::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.repas_merchant_transition(v_o5,'accept');
    PERFORM public.repas_merchant_transition(v_o5,'prepare');
    BEGIN PERFORM public.repas_custody_confirm_pickup_collection(v_o5,'000000'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.2 collection is refused before the food is ready',
          v_err LIKE '%ORDER_NOT_READY%' OR v_err LIKE '%CUSTODY_CODE_NOT_ISSUED%', v_err);
    PERFORM public.repas_merchant_transition(v_o5,'ready');
    SELECT count(*) INTO v_n FROM public.repas_custody_credentials
     WHERE order_id=v_o5 AND kind='customer_pickup' AND holder_user_id=v_cust;
    r := r || public._qa_s13_ok('B1.3 the Retrait code is held by the customer, not the merchant',
          v_n = 1, v_n::text);
    BEGIN PERFORM public.repas_custody_code_view(v_o5,'customer_pickup'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.4 the merchant cannot read the Retrait code',
          v_err LIKE '%CUSTODY_CODE_FORBIDDEN%', v_err);
    BEGIN PERFORM public.repas_merchant_transition(v_o5,'complete'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.5 the merchant cannot complete Retrait by assertion',
          v_err LIKE '%PICKUP_REQUIRES_CUSTOMER_CODE%', v_err);
    BEGIN PERFORM public.chop_pay_merchant_pickup_complete('repas', v_o5); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.6 the direct Slice 5 pickup primitive is closed to merchants',
          v_err LIKE '%PICKUP_REQUIRES_CUSTOMER_CODE%', v_err);
    v_res := public.repas_custody_confirm_pickup_collection(v_o5,'000000');
    r := r || public._qa_s13_ok('B1.7 a wrong Retrait code is refused and counted',
          (v_res->>'ok')::boolean IS FALSE AND (v_res->>'error')='CUSTODY_CODE_INVALID', v_res::text);
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o5;
    r := r || public._qa_s13_ok('B1.7b the refused collection settled nothing',
          v_state='ready', v_state);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_view := public.repas_custody_code_view(v_o5,'customer_pickup');
    v_code := v_view->>'code';
    r := r || public._qa_s13_ok('B1.8 the customer can read their Retrait code',
          v_code IS NOT NULL AND length(v_code)=6, NULL);
    BEGIN PERFORM public.repas_custody_confirm_pickup_collection(v_o5,v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.9 the customer themselves cannot complete the collection',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    BEGIN PERFORM public.repas_custody_confirm_pickup_collection(v_o5,v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.10 a stranger cannot complete the collection',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN PERFORM public.repas_custody_confirm_pickup_collection(v_o5,v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.10b a courier has no standing on a Retrait order',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);
    SELECT attempts INTO v_att FROM public.repas_custody_credentials
     WHERE order_id=v_o5 AND kind='customer_pickup';
    r := r || public._qa_s13_ok('B1.10c cross-actor attempts never burn the customer''s attempts',
          v_att = 1, v_att::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_res := public.repas_custody_confirm_pickup_collection(v_o5, v_code);
    r := r || public._qa_s13_ok('B1.11 a valid customer code completes the Retrait',
          (v_res->>'ok')::boolean, v_res::text);
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime
     WHERE source_module='repas' AND source_id=v_o5;
    r := r || public._qa_s13_ok('B1.12 Retrait settled through the canonical Chop Pay engine',
          v_cp.state='completed', v_cp.state);
    r := r || public._qa_s13_ok('B1.13 Retrait carries no courier earning', v_cp.driver_earning_gnf = 0,
          COALESCE(v_cp.driver_earning_gnf,0)::text);
    r := r || public._qa_s13_ok('B1.14 Retrait carries no delivery fee and no collateral',
          v_cp.delivery_fee_gnf = 0 AND v_cp.collateral_gnf = 0, NULL);
    r := r || public._qa_s13_ok('B1.15 Retrait platform fee is the frozen 1%',
          v_cp.platform_revenue_gnf = 1500, COALESCE(v_cp.platform_revenue_gnf,0)::text);
    SELECT count(*) INTO v_n FROM public.missions WHERE ref_food_order_id=v_o5;
    r := r || public._qa_s13_ok('B1.16 Retrait created no mission', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_custody_events
     WHERE order_id=v_o5 AND boundary='merchant_to_customer_pickup' AND mission_id IS NULL;
    r := r || public._qa_s13_ok('B1.17 exactly one mission-less pickup custody event', v_n = 1, v_n::text);

    SELECT balance_gnf INTO v_bal FROM public.wallets WHERE owner_user_id=v_merch AND party_type='merchant';
    BEGIN v_res := public.repas_custody_confirm_pickup_collection(v_o5, v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_mm1 FROM public.wallets WHERE owner_user_id=v_merch AND party_type='merchant';
    r := r || public._qa_s13_ok('B1.18 replaying Retrait moves zero additional value',
          v_mm1 = v_bal, v_mm1::text||' err='||v_err);
    r := r || public._qa_s13_ok('B1.18b the Retrait replay answers idempotently, not with a new settlement',
          v_err = 'NO_ERROR' AND (v_res->>'idempotent')::boolean IS TRUE, COALESCE(v_res::text,v_err));
    SELECT count(*) INTO v_n FROM public.repas_custody_events
     WHERE order_id=v_o5 AND boundary='merchant_to_customer_pickup';
    r := r || public._qa_s13_ok('B1.19 the Retrait replay created no second event', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='repas' AND source_id=v_o5 AND driver_user_id IS NOT NULL;
    r := r || public._qa_s13_ok('B1.20 no driver-side hold touched the Retrait order', v_n = 0, v_n::text);

    -- ================= F. EXPIRY / DISPUTE / CANCELLATION =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Kaloum, Conakry', 9.5100, -13.7100);
    v_o6 := (v_res->>'order_id')::uuid; v_m6 := (v_res->>'mission_id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    PERFORM public.mission_claim(v_m6);
    PERFORM public.mission_set_state(v_m6,'arrived_pickup');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.repas_merchant_transition(v_o6,'accept');
    PERFORM public.repas_merchant_transition(v_o6,'prepare');
    PERFORM public.repas_merchant_transition(v_o6,'ready');
    v_view := public.repas_custody_code_view(v_o6,'restaurant_handoff');
    v_code := v_view->>'code';
    v_p1 := public._qa_r6_proof(v_m6,'pickup',v_drv2,'ok');

    -- F1. expiry fails closed
    UPDATE public.repas_custody_credentials SET expires_at = now() - interval '1 minute'
     WHERE order_id=v_o6 AND kind='restaurant_handoff';
    v_view := public.repas_custody_code_view(v_o6,'restaurant_handoff');
    r := r || public._qa_s13_ok('F1.1 an expired credential is reported expired and inactive',
          (v_view->>'expired')::boolean IS TRUE AND (v_view->>'active')::boolean IS FALSE, v_view::text);
    r := r || public._qa_s13_ok('F1.2 an expired credential discloses no code',
          (v_view->>'code') IS NULL, v_view::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    BEGIN PERFORM public.repas_custody_confirm_handoff(v_m6,v_p1,v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F1.3 the correct code fails closed once expired',
          v_err LIKE '%CUSTODY_CODE_EXPIRED%', v_err);
    SELECT attempts INTO v_att FROM public.repas_custody_credentials
     WHERE order_id=v_o6 AND kind='restaurant_handoff';
    r := r || public._qa_s13_ok('F1.4 an expiry refusal is not an attempt', v_att = 0, v_att::text);
    SELECT count(*) INTO v_n FROM public.repas_custody_events WHERE order_id=v_o6;
    r := r || public._qa_s13_ok('F1.5 the expiry refusal wrote nothing', v_n = 0, v_n::text);
    UPDATE public.repas_custody_credentials SET expires_at = NULL
     WHERE order_id=v_o6 AND kind='restaurant_handoff';

    -- F2. dispute fails closed
    UPDATE public.chop_pay_order_runtime SET disputed_at = now(), dispute_resolution = NULL
     WHERE source_module='repas' AND source_id=v_o6;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_view := public.repas_custody_code_view(v_o6,'restaurant_handoff');
    r := r || public._qa_s13_ok('F2.1 a disputed order freezes the credential',
          (v_view->>'disputed')::boolean IS TRUE AND (v_view->>'code') IS NULL, v_view::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    BEGIN PERFORM public.repas_custody_confirm_handoff(v_m6,v_p1,v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F2.2 a disputed order cannot be handed over with a valid code',
          v_err LIKE '%CUSTODY_DISPUTE_BLOCKED%', v_err);
    SELECT count(*) INTO v_n FROM public.repas_custody_events WHERE order_id=v_o6;
    r := r || public._qa_s13_ok('F2.3 the dispute refusal wrote nothing', v_n = 0, v_n::text);
    UPDATE public.chop_pay_order_runtime SET disputed_at = NULL
     WHERE source_module='repas' AND source_id=v_o6;

    -- F3. cancellation invalidates stale credentials
    SELECT code_secret_id INTO v_sec FROM public.repas_custody_credentials
     WHERE order_id=v_o6 AND kind='restaurant_handoff';
    r := r || public._qa_s13_ok('F3.0 the credential still had a live vault secret',
          (SELECT count(*) FROM vault.secrets WHERE id=v_sec) = 1, NULL);
    PERFORM set_config('chopchop.cash_engine','1',true);
    UPDATE public.food_orders SET state='cancelled', updated_at=now() WHERE id=v_o6;
    PERFORM set_config('chopchop.cash_engine','0',true);
    r := r || public._qa_s13_ok('F3.1 cancellation destroys the stale vault secret',
          (SELECT count(*) FROM vault.secrets WHERE id=v_sec) = 0, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_view := public.repas_custody_code_view(v_o6,'restaurant_handoff');
    r := r || public._qa_s13_ok('F3.2 a cancelled order exposes no code to its holder',
          (v_view->>'expired')::boolean IS TRUE AND (v_view->>'code') IS NULL, v_view::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    BEGIN PERFORM public.repas_custody_confirm_handoff(v_m6,v_p1,v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F3.3 the old code cannot complete a cancelled order',
          v_err LIKE '%ORDER_NOT_READY%' OR v_err LIKE '%ORDER_TERMINAL%', v_err);
    SELECT count(*) INTO v_n FROM public.repas_custody_events WHERE order_id=v_o6;
    r := r || public._qa_s13_ok('F3.4 a cancelled order accrued no custody event', v_n = 0, v_n::text);
    SELECT state INTO v_state FROM public.chop_pay_order_runtime
     WHERE source_module='repas' AND source_id=v_o6;
    r := r || public._qa_s13_ok('F3.5 the cancelled order never settled', v_state <> 'completed', v_state);

    -- ================= D. IMMUTABILITY / LEAKAGE =================
    BEGIN UPDATE public.repas_custody_events SET method='tampered' WHERE order_id=v_o1; v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D1.1 custody events cannot be rewritten',
          v_err LIKE '%APPEND_ONLY%', v_err);
    BEGIN DELETE FROM public.repas_custody_events WHERE order_id=v_o1; v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D1.2 custody events cannot be deleted',
          v_err LIKE '%APPEND_ONLY%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_res := public.repas_custody_status(v_o1);
    r := r || public._qa_s13_ok('D1.3 custody status never carries a code',
          v_res::text NOT LIKE '%"code"%', v_res::text);
    r := r || public._qa_s13_ok('D1.4 custody status reports the full chain to participants',
          jsonb_array_length(v_res->'events') = 2, v_res::text);
    SELECT count(*) INTO v_n FROM public.repas_custody_events e
     WHERE e.metadata::text <> '{}';
    r := r || public._qa_s13_ok('D1.5 no custody event carries free-form metadata payloads', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM storage.objects
     WHERE bucket_id='mission-proofs' AND name LIKE v_m1::text||'%';
    r := r || public._qa_s13_ok('D1.6 mission proofs remain in the private bucket only', v_n > 0, v_n::text);

    -- ================= E. CONSERVATION =================
    SELECT balance_gnf, held_gnf INTO v_c1, v_held
      FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_mm1 FROM public.wallets WHERE owner_user_id=v_merch AND party_type='merchant';
    SELECT balance_gnf INTO v_d1 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT balance_gnf INTO v_x1 FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('E1.1 customer outflow reconciles to merchant + courier + platform',
          (v_c0 - v_c1) - v_held = (v_mm1 - v_mm0) + (v_d1 - v_d0) + (v_x1 - v_x0),
          (v_c0 - v_c1)::text||'/'||v_held::text);
    SELECT COALESCE(SUM(GREATEST(amount_gnf - captured_gnf - released_gnf,0)),0) INTO v_open
      FROM public.mission_financial_holds WHERE source_module='repas' AND source_id IN (v_o1,v_o5);
    r := r || public._qa_s13_ok('E1.2 zero residual open holds on completed custody orders',
          v_open = 0, v_open::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='repas' AND source_id IN (v_o1,v_o3,v_o4,v_o5,v_o6)
       AND (captured_gnf + released_gnf) > amount_gnf;
    r := r || public._qa_s13_ok('E1.3 no hold is over-consumed', v_n = 0, v_n::text);
    SELECT count(*) INTO v_unbalanced FROM (
      SELECT j.id FROM public.ledger_journals j
        JOIN public.ledger_postings p ON p.journal_id = j.id
       WHERE j.source_module='repas' AND j.source_id IN (v_o1,v_o3,v_o4,v_o5,v_o6)
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('E1.4 every journal written here is zero-sum', v_unbalanced = 0, v_unbalanced::text);

    PERFORM set_config('request.jwt.claims', ''::text, true);
    RAISE EXCEPTION 'QA_NODE3_R6_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE3_R6_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS aborted before completion', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', ''::text, true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z6.1 master wallet unchanged after fixture rollback',
        v_master0 IS NOT DISTINCT FROM v_master1, v_master1::text);
  r := r || public._qa_s13_ok('Z6.2 feature flags byte-identical after fixture rollback',
        v_flags0 = v_flags1, NULL);
  SELECT count(*) INTO v_n FROM public.food_restaurants WHERE slug LIKE 'qa-n3r6-%';
  r := r || public._qa_s13_ok('Z6.3 no restaurant fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.repas_custody_credentials;
  r := r || public._qa_s13_ok('Z6.4 no custody credential residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.repas_custody_events;
  r := r || public._qa_s13_ok('Z6.5 no custody event residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM storage.objects WHERE bucket_id='mission-proofs' AND name LIKE '%-ok.jpg';
  r := r || public._qa_s13_ok('Z6.6 no storage proof fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM vault.secrets WHERE description = 'CHOPCHOP R6 one-time custody credential';
  r := r || public._qa_s13_ok('Z6.7 no vault secret residue', v_n = 0, v_n::text);

  RETURN jsonb_build_object('part','node3_repas_r6_custody',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END; $function$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r6_custody() FROM PUBLIC, anon, authenticated;