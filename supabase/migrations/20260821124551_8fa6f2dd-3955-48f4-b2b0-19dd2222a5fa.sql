CREATE OR REPLACE FUNCTION public._qa_node5_identity_a8()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '300s'
AS $$
DECLARE
  r jsonb := '[]'::jsonb;
  u_c   uuid := gen_random_uuid();
  u_d   uuid := gen_random_uuid();
  u_m   uuid := gen_random_uuid();
  u_rel uuid := gen_random_uuid();
  u_ops uuid := gen_random_uuid();
  ids uuid[];
  s_m uuid := gen_random_uuid();
  ctx jsonb; res jsonb; fn text; v_bad text[] := '{}';
  f_w bigint; f_wt bigint;
  authority_fns text[] := ARRAY[
    '_driver_class_require','_driver_operational_require','_merchant_class_require',
    '_merchant_store_require','_merchant_restaurant_require','_marche_listing_authz',
    'marche_order_commit','marche_listing_create','has_role','professional_identity_current'];
  b_pi bigint; b_pia bigint; b_up bigint; b_w bigint; b_lp bigint; b_ls numeric;
  b_wt bigint; b_ms bigint; b_dp bigint; b_ur bigint; b_pr bigint; b_mo bigint; b_flags jsonb;
  a_pi bigint; a_pia bigint; a_up bigint; a_w bigint; a_lp bigint; a_ls numeric;
  a_wt bigint; a_ms bigint; a_dp bigint; a_ur bigint; a_pr bigint; a_mo bigint; a_flags jsonb;
  b_live_modes jsonb; a_live_modes jsonb;
BEGIN
  ids := ARRAY[u_c,u_d,u_m,u_rel,u_ops];

  SELECT count(*) INTO b_pi  FROM public.professional_identities;
  SELECT count(*) INTO b_pia FROM public.professional_identities WHERE claim_state='active';
  SELECT count(*) INTO b_up  FROM public.user_preferences;
  SELECT count(*) INTO b_w   FROM public.wallets;
  SELECT count(*) INTO b_wt  FROM public.wallet_transactions;
  SELECT count(*) INTO b_lp  FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO b_ls FROM public.ledger_postings;
  SELECT count(*) INTO b_ms  FROM public.merchant_stores;
  SELECT count(*) INTO b_dp  FROM public.driver_profiles;
  SELECT count(*) INTO b_ur  FROM public.user_roles;
  SELECT count(*) INTO b_pr  FROM public.profiles;
  SELECT count(*) INTO b_mo  FROM public.marche_orders;
  SELECT jsonb_object_agg(key, enabled) INTO b_flags FROM public.feature_flags;
  SELECT COALESCE(jsonb_agg(jsonb_build_array(user_id, app_mode) ORDER BY user_id),'[]'::jsonb)
    INTO b_live_modes FROM public.user_preferences;

  -- ===== A. SURFACE SHAPE =====
  r := r || public._qa_s13_ok('N5A8.A1 available-mode derivation exists',
        to_regprocedure('public.account_available_modes(uuid)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A8.A2 caller workspace context exists',
        to_regprocedure('public.account_mode_context()') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A8.A3 validated preference writer exists',
        to_regprocedure('public.account_mode_set(text)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A8.A4 derivation is SECURITY DEFINER with pinned search_path',
        (SELECT prosecdef AND 'search_path=public' = ANY(proconfig) FROM pg_proc
          WHERE oid='public.account_available_modes(uuid)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A8.A5 context is SECURITY DEFINER with pinned search_path',
        (SELECT prosecdef AND 'search_path=public' = ANY(proconfig) FROM pg_proc
          WHERE oid='public.account_mode_context()'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A8.A6 writer is SECURITY DEFINER with pinned search_path',
        (SELECT prosecdef AND 'search_path=public' = ANY(proconfig) FROM pg_proc
          WHERE oid='public.account_mode_set(text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A8.A7 derivation is read-only (STABLE)',
        (SELECT provolatile='s' FROM pg_proc WHERE oid='public.account_available_modes(uuid)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A8.A8 context is read-only (STABLE)',
        (SELECT provolatile='s' FROM pg_proc WHERE oid='public.account_mode_context()'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A8.A9 arbitrary-user derivation is not client callable',
        NOT has_function_privilege('authenticated','public.account_available_modes(uuid)','EXECUTE')
        AND NOT has_function_privilege('anon','public.account_available_modes(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A8.A10 context is callable by signed-in users only',
        has_function_privilege('authenticated','public.account_mode_context()','EXECUTE')
        AND NOT has_function_privilege('anon','public.account_mode_context()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A8.A11 writer is callable by signed-in users only',
        has_function_privilege('authenticated','public.account_mode_set(text)','EXECUTE')
        AND NOT has_function_privilege('anon','public.account_mode_set(text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A8.A12 derivation reads professional identity, not roles',
        (SELECT prosrc ~ 'professional_active_type' AND prosrc !~ 'user_roles' FROM pg_proc
          WHERE oid='public.account_available_modes(uuid)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A8.A13 preference guard trigger installed on user_preferences',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.user_preferences'::regclass
                 AND NOT tgisinternal AND tgfoid='public._account_mode_preference_guard'::regproc), NULL);

  -- ===== FIXTURES =====
  PERFORM public._qa_users_new(u_c,  'qa-n5a8-c-'||substr(u_c::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_d,  'qa-n5a8-d-'||substr(u_d::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_m,  'qa-n5a8-m-'||substr(u_m::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_rel,'qa-n5a8-r-'||substr(u_rel::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_ops,'qa-n5a8-o-'||substr(u_ops::text,1,8)||'@example.com');
  UPDATE public.profiles SET phone = '+22462' || lpad((floor(random()*10000000))::bigint::text, 7, '0')
   WHERE user_id = ANY(ids) AND (phone IS NULL OR phone = '');
  INSERT INTO public.user_roles(user_id, role) VALUES (u_ops,'admin') ON CONFLICT DO NOTHING;

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', NULL, true);

  INSERT INTO public.merchant_stores(id, owner_user_id, name, slug, status, onboarding_status)
  VALUES (s_m, u_m, 'QA A8 Store', 'qa-a8-'||substr(s_m::text,1,8), 'active','submitted');

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_rel), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', NULL, true);
  PERFORM public._professional_identity_release(u_rel, 'qa_a8_release');

  -- post-fixture finance snapshot: everything after this point is mode switching only
  SELECT count(*) INTO f_w FROM public.wallets WHERE owner_user_id = ANY(ids);
  SELECT count(*) INTO f_wt FROM public.wallet_transactions wt
    WHERE wt.related_user_id = ANY(ids)
       OR wt.from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(ids))
       OR wt.to_wallet_id   IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(ids));

  -- ===== B. AVAILABLE MODE DERIVATION =====
  r := r || public._qa_s13_ok('N5A8.B1 customer-only account sees client only',
        public.account_available_modes(u_c) = ARRAY['client'], array_to_string(public.account_available_modes(u_c),','));
  r := r || public._qa_s13_ok('N5A8.B2 driver sees client + driver',
        public.account_available_modes(u_d) = ARRAY['client','driver'], array_to_string(public.account_available_modes(u_d),','));
  r := r || public._qa_s13_ok('N5A8.B3 merchant sees client + merchant',
        public.account_available_modes(u_m) = ARRAY['client','merchant'], array_to_string(public.account_available_modes(u_m),','));
  r := r || public._qa_s13_ok('N5A8.B4 driver never sees merchant',
        NOT ('merchant' = ANY(public.account_available_modes(u_d))), NULL);
  r := r || public._qa_s13_ok('N5A8.B5 merchant never sees driver',
        NOT ('driver' = ANY(public.account_available_modes(u_m))), NULL);
  r := r || public._qa_s13_ok('N5A8.B6 no account may ever hold all three modes',
        NOT EXISTS (SELECT 1 FROM unnest(ids) x WHERE array_length(public.account_available_modes(x),1) > 2), NULL);
  r := r || public._qa_s13_ok('N5A8.B7 client mode is universal',
        NOT EXISTS (SELECT 1 FROM unnest(ids) x WHERE NOT ('client' = ANY(public.account_available_modes(x)))), NULL);
  r := r || public._qa_s13_ok('N5A8.B8 admin role alone creates no professional mode',
        public.account_available_modes(u_ops) = ARRAY['client'], NULL);
  r := r || public._qa_s13_ok('N5A8.B9 released lane leaves client only',
        public.account_available_modes(u_rel) = ARRAY['client'], NULL);
  r := r || public._qa_s13_ok('N5A8.B10 released driver history is preserved on the server',
        EXISTS (SELECT 1 FROM public.professional_identities
                 WHERE user_id=u_rel AND professional_type='driver' AND claim_state<>'active'), NULL);
  r := r || public._qa_s13_ok('N5A8.B11 pending driver still holds the driver mode (class, not status)',
        (SELECT status FROM public.driver_profiles WHERE user_id=u_d)::text <> 'approved'
        AND 'driver' = ANY(public.account_available_modes(u_d)), NULL);
  r := r || public._qa_s13_ok('N5A8.B12 submitted store still grants merchant mode (class, not approval)',
        (SELECT onboarding_status FROM public.merchant_stores WHERE id=s_m)::text = 'submitted'
        AND 'merchant' = ANY(public.account_available_modes(u_m)), NULL);

  -- ===== C. CALLER CONTEXT =====
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d), true);
  ctx := public.account_mode_context();
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A8.C1 driver context reports the driver class',
        ctx->>'professional_type' = 'driver', ctx::text);
  r := r || public._qa_s13_ok('N5A8.C2 driver context lists exactly client+driver',
        ctx->'available_modes' = '["client","driver"]'::jsonb, (ctx->'available_modes')::text);
  r := r || public._qa_s13_ok('N5A8.C3 driver with no stored preference defaults to client',
        ctx->>'effective_mode' = 'client', ctx::text);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_c), true);
  ctx := public.account_mode_context();
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A8.C4 customer context reports no professional class',
        ctx->>'professional_type' = 'none', ctx::text);
  r := r || public._qa_s13_ok('N5A8.C5 customer context lists client only',
        ctx->'available_modes' = '["client"]'::jsonb, NULL);
  BEGIN
    PERFORM set_config('request.jwt.claims', NULL, true);
    PERFORM public.account_mode_context();
    r := r || public._qa_s13_ok('N5A8.C6 signed-out context refuses', false, 'no refusal');
  EXCEPTION WHEN others THEN
    r := r || public._qa_s13_ok('N5A8.C6 signed-out context refuses', SQLERRM = 'AUTH_REQUIRED', SQLERRM);
  END;

  -- ===== D. PREFERENCE VALIDATION =====
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d), true);
  res := public.account_mode_set('driver');
  r := r || public._qa_s13_ok('N5A8.D1 driver may persist the driver workspace',
        res->>'effective_mode' = 'driver' AND (res->>'refused')::boolean IS FALSE, res::text);
  res := public.account_mode_set('merchant');
  r := r || public._qa_s13_ok('N5A8.D2 driver requesting merchant falls back to client',
        res->>'effective_mode' = 'client' AND (res->>'refused')::boolean, res::text);
  r := r || public._qa_s13_ok('N5A8.D3 refused request stored client, never merchant',
        (SELECT app_mode FROM public.user_preferences WHERE user_id=u_d) = 'client', NULL);
  BEGIN
    PERFORM public.account_mode_set('admin');
    r := r || public._qa_s13_ok('N5A8.D4 unknown mode value refuses', false, 'no refusal');
  EXCEPTION WHEN others THEN
    r := r || public._qa_s13_ok('N5A8.D4 unknown mode value refuses', SQLERRM = 'INVALID_MODE', SQLERRM);
  END;
  UPDATE public.user_preferences SET app_mode='merchant' WHERE user_id=u_d;
  r := r || public._qa_s13_ok('N5A8.D5 direct write of an unlawful professional preference is neutralised',
        (SELECT app_mode FROM public.user_preferences WHERE user_id=u_d) = 'client', NULL);
  PERFORM set_config('request.jwt.claims', NULL, true);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m), true);
  res := public.account_mode_set('merchant');
  r := r || public._qa_s13_ok('N5A8.D6 merchant may persist the merchant workspace',
        res->>'effective_mode' = 'merchant', res::text);
  res := public.account_mode_set('driver');
  r := r || public._qa_s13_ok('N5A8.D7 merchant requesting driver falls back to client',
        res->>'effective_mode' = 'client' AND (res->>'refused')::boolean, res::text);
  PERFORM set_config('request.jwt.claims', NULL, true);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_c), true);
  res := public.account_mode_set('driver');
  r := r || public._qa_s13_ok('N5A8.D8 customer requesting driver falls back to client',
        res->>'effective_mode' = 'client' AND (res->>'refused')::boolean, res::text);
  res := public.account_mode_set('merchant');
  r := r || public._qa_s13_ok('N5A8.D9 customer requesting merchant falls back to client',
        res->>'effective_mode' = 'client', res::text);
  res := public.account_mode_set('client');
  r := r || public._qa_s13_ok('N5A8.D10 client is always lawful',
        res->>'effective_mode' = 'client' AND (res->>'refused')::boolean IS FALSE, res::text);
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A8.D11 refused preference created no professional identity',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id=u_c), NULL);
  r := r || public._qa_s13_ok('N5A8.D12 refused preference created no store ownership',
        NOT EXISTS (SELECT 1 FROM public.merchant_stores WHERE owner_user_id=u_c), NULL);
  r := r || public._qa_s13_ok('N5A8.D13 refused preference created no driver profile',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id=u_c), NULL);
  r := r || public._qa_s13_ok('N5A8.D14 refused preference granted no professional or admin role',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_c
                     AND role::text NOT IN ('user','client')),
        (SELECT string_agg(role::text,',') FROM public.user_roles WHERE user_id=u_c));
  r := r || public._qa_s13_ok('N5A8.D15 preference write did not change the driver class',
        public.professional_active_type(u_d) = 'driver', NULL);
  r := r || public._qa_s13_ok('N5A8.D16 preference write did not change the merchant class',
        public.professional_active_type(u_m) = 'merchant', NULL);

  -- ===== E. RELEASE + RECLAIM =====
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m), true);
  PERFORM public.account_mode_set('merchant');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A8.E1 merchant preference stored before release',
        (SELECT app_mode FROM public.user_preferences WHERE user_id=u_m) = 'merchant', NULL);
  DELETE FROM public.marketplace_listings WHERE store_id = s_m;
  DELETE FROM public.merchant_stores WHERE id = s_m;
  PERFORM public._professional_identity_release(u_m, 'qa_a8_release');
  r := r || public._qa_s13_ok('N5A8.E2 released merchant drops to client only',
        public.account_available_modes(u_m) = ARRAY['client'], NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m), true);
  ctx := public.account_mode_context();
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A8.E3 stale merchant preference no longer yields a merchant workspace',
        ctx->>'preferred_mode' = 'merchant' AND ctx->>'effective_mode' = 'client', ctx::text);
  r := r || public._qa_s13_ok('N5A8.E4 released account reports no professional class',
        ctx->>'professional_type' = 'none', NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A8.E5 reclaim as driver yields client + driver',
        public.account_available_modes(u_m) = ARRAY['client','driver'], NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m), true);
  ctx := public.account_mode_context();
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A8.E6 historical merchant class does not resurrect merchant mode',
        NOT ((ctx->'available_modes') @> '["merchant"]'::jsonb), (ctx->'available_modes')::text);
  r := r || public._qa_s13_ok('N5A8.E7 stale merchant preference still degrades after reclaim',
        ctx->>'effective_mode' = 'client', ctx::text);
  r := r || public._qa_s13_ok('N5A8.E8 historical merchant record was not erased',
        EXISTS (SELECT 1 FROM public.professional_identities
                 WHERE user_id=u_m AND professional_type='merchant' AND claim_state<>'active'), NULL);

  -- ===== F. SERVER AUTHORITY NEVER READS UI MODE =====
  FOREACH fn IN ARRAY authority_fns LOOP
    IF (SELECT bool_or(prosrc ~ 'app_mode' OR prosrc ~ 'effective_mode' OR prosrc ~ 'preferred_mode')
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname=fn) THEN
      v_bad := v_bad || fn;
    END IF;
  END LOOP;
  r := r || public._qa_s13_ok('N5A8.F1 no canonical authority function reads UI mode',
        array_length(v_bad,1) IS NULL, array_to_string(v_bad,','));
  r := r || public._qa_s13_ok('N5A8.F2 census covers ten authority surfaces',
        array_length(authority_fns,1) = 10, NULL);
  r := r || public._qa_s13_ok('N5A8.F3 no RLS policy anywhere depends on user_preferences.app_mode',
        NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                     AND (COALESCE(qual,'') ~ 'app_mode' OR COALESCE(with_check,'') ~ 'app_mode')), NULL);
  r := r || public._qa_s13_ok('N5A8.F4 mode context grants no capability claim',
        (SELECT prosrc !~ 'user_roles' AND prosrc !~ 'driver_capab' FROM pg_proc
          WHERE oid='public.account_mode_context()'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A8.F5 A3 exclusivity remains the claim authority',
        to_regprocedure('public._professional_lane_require(uuid,text,text)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A8.F6 A6 driver authority primitives untouched',
        to_regprocedure('public._driver_class_require(uuid,text)') IS NOT NULL
        AND to_regprocedure('public._driver_operational_require(uuid,text,text)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A8.F7 A7 merchant authority primitives untouched',
        to_regprocedure('public._merchant_class_require(uuid,text)') IS NOT NULL
        AND to_regprocedure('public._merchant_store_require(uuid,uuid,text,boolean)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A8.F8 writer cannot mutate professional identity',
        (SELECT prosrc !~ 'professional_identities' FROM pg_proc
          WHERE oid='public.account_mode_set(text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A8.F9 writer touches only the preference table',
        (SELECT prosrc !~ 'wallets' AND prosrc !~ 'ledger' AND prosrc !~ 'user_roles'
                AND prosrc !~ 'merchant_stores' AND prosrc !~ 'driver_profiles' FROM pg_proc
          WHERE oid='public.account_mode_set(text)'::regprocedure), NULL);

  -- ===== G. FINANCE NON-INTERFERENCE (measured after fixtures) =====
  r := r || public._qa_s13_ok('N5A8.G1 mode switching created no wallet',
        (SELECT count(*) FROM public.wallets WHERE owner_user_id = ANY(ids)) = f_w, NULL);
  r := r || public._qa_s13_ok('N5A8.G2 mode switching created no wallet transaction',
        (SELECT count(*) FROM public.wallet_transactions wt
          WHERE wt.related_user_id = ANY(ids)
             OR wt.from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(ids))
             OR wt.to_wallet_id   IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(ids))) = f_wt, NULL);
  r := r || public._qa_s13_ok('N5A8.G3 ledger postings unchanged by mode switching',
        (SELECT count(*) FROM public.ledger_postings) = b_lp, NULL);
  r := r || public._qa_s13_ok('N5A8.G4 ledger balance unchanged by mode switching',
        (SELECT COALESCE(sum(amount_gnf),0) FROM public.ledger_postings) = b_ls, NULL);
  r := r || public._qa_s13_ok('N5A8.G5 no payable produced by mode switching',
        (SELECT count(*) FROM public.merchant_payables WHERE merchant_user_id = ANY(ids)) = 0, NULL);
  r := r || public._qa_s13_ok('N5A8.G6 no payout order produced by mode switching',
        (SELECT count(*) FROM public.payout_orders WHERE party_user_id = ANY(ids)) = 0, NULL);

  -- ===== H. CUSTOMER UNIVERSALITY =====
  r := r || public._qa_s13_ok('N5A8.H1 driver keeps the client workspace',
        'client' = ANY(public.account_available_modes(u_d)), NULL);
  r := r || public._qa_s13_ok('N5A8.H2 merchant-turned-driver keeps the client workspace',
        'client' = ANY(public.account_available_modes(u_m)), NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d), true);
  res := public.account_mode_set('client');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A8.H3 driver may return to the client workspace at will',
        res->>'effective_mode' = 'client', res::text);
  r := r || public._qa_s13_ok('N5A8.H4 returning to client did not release the driver lane',
        public.professional_active_type(u_d) = 'driver', NULL);
  r := r || public._qa_s13_ok('N5A8.H5 returning to client did not change driver status',
        (SELECT status FROM public.driver_profiles WHERE user_id=u_d) IS NOT NULL, NULL);

  -- ===== CLEANUP =====
  PERFORM set_config('request.jwt.claims', NULL, true);
  DELETE FROM public.user_preferences WHERE user_id = ANY(ids);
  DELETE FROM public.marketplace_listings WHERE seller_id = ANY(ids) OR store_id = s_m;
  DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(ids);
  PERFORM public._qa_a5_cleanup(ids);

  SELECT count(*) INTO a_pi  FROM public.professional_identities;
  SELECT count(*) INTO a_pia FROM public.professional_identities WHERE claim_state='active';
  SELECT count(*) INTO a_up  FROM public.user_preferences;
  SELECT count(*) INTO a_w   FROM public.wallets;
  SELECT count(*) INTO a_wt  FROM public.wallet_transactions;
  SELECT count(*) INTO a_lp  FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO a_ls FROM public.ledger_postings;
  SELECT count(*) INTO a_ms  FROM public.merchant_stores;
  SELECT count(*) INTO a_dp  FROM public.driver_profiles;
  SELECT count(*) INTO a_ur  FROM public.user_roles;
  SELECT count(*) INTO a_pr  FROM public.profiles;
  SELECT count(*) INTO a_mo  FROM public.marche_orders;
  SELECT jsonb_object_agg(key, enabled) INTO a_flags FROM public.feature_flags;
  SELECT COALESCE(jsonb_agg(jsonb_build_array(user_id, app_mode) ORDER BY user_id),'[]'::jsonb)
    INTO a_live_modes FROM public.user_preferences;

  r := r || public._qa_s13_ok('N5A8.I1 professional_identities returned to baseline', a_pi = b_pi, b_pi||'->'||a_pi);
  r := r || public._qa_s13_ok('N5A8.I2 active professional census unchanged', a_pia = b_pia, b_pia||'->'||a_pia);
  r := r || public._qa_s13_ok('N5A8.I3 user_preferences returned to baseline', a_up = b_up, b_up||'->'||a_up);
  r := r || public._qa_s13_ok('N5A8.I4 no live mode preference was rewritten', a_live_modes = b_live_modes, NULL);
  r := r || public._qa_s13_ok('N5A8.I5 wallets returned to baseline', a_w = b_w, b_w||'->'||a_w);
  r := r || public._qa_s13_ok('N5A8.I6 wallet transactions unchanged', a_wt = b_wt, b_wt||'->'||a_wt);
  r := r || public._qa_s13_ok('N5A8.I7 ledger postings returned to baseline', a_lp = b_lp, NULL);
  r := r || public._qa_s13_ok('N5A8.I8 ledger sum returned to baseline', a_ls = b_ls, NULL);
  r := r || public._qa_s13_ok('N5A8.I9 merchant_stores returned to baseline', a_ms = b_ms, b_ms||'->'||a_ms);
  r := r || public._qa_s13_ok('N5A8.I10 driver_profiles returned to baseline', a_dp = b_dp, b_dp||'->'||a_dp);
  r := r || public._qa_s13_ok('N5A8.I11 user_roles returned to baseline', a_ur = b_ur, b_ur||'->'||a_ur);
  r := r || public._qa_s13_ok('N5A8.I12 profiles returned to baseline', a_pr = b_pr, b_pr||'->'||a_pr);
  r := r || public._qa_s13_ok('N5A8.I13 marche_orders unchanged', a_mo = b_mo, NULL);
  r := r || public._qa_s13_ok('N5A8.I14 feature flags unchanged', a_flags = b_flags, NULL);
  r := r || public._qa_s13_ok('N5A8.I15 no QA residue in user_preferences',
        NOT EXISTS (SELECT 1 FROM public.user_preferences WHERE user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A8.I16 no QA residue in professional_identities',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A8.I17 no QA residue in merchant_stores',
        NOT EXISTS (SELECT 1 FROM public.merchant_stores WHERE owner_user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A8.I18 no QA residue in driver_profiles',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id = ANY(ids)), NULL);

  RETURN jsonb_build_object(
    'fn','_qa_node5_identity_a8',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'failures', (SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(r) e
                  WHERE (e->>'ok')::boolean IS NOT TRUE)
  );
EXCEPTION WHEN others THEN
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    DELETE FROM public.user_preferences WHERE user_id = ANY(ids);
    DELETE FROM public.marketplace_listings WHERE seller_id = ANY(ids) OR store_id = s_m;
    DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(ids);
    PERFORM public._qa_a5_cleanup(ids);
  EXCEPTION WHEN others THEN NULL; END;
  RAISE;
END $$;
REVOKE ALL ON FUNCTION public._qa_node5_identity_a8() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_identity_a8() TO service_role;