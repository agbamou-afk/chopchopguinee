CREATE OR REPLACE FUNCTION public._qa_node5_identity_a9()
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
  u_da  uuid := gen_random_uuid();
  u_m   uuid := gen_random_uuid();
  u_m2  uuid := gen_random_uuid();
  u_rel uuid := gen_random_uuid();
  u_ops uuid := gen_random_uuid();
  ids uuid[];
  s_m  uuid := gen_random_uuid();
  s_m2 uuid := gen_random_uuid();
  ctx jsonb; res jsonb; fn text; tb text; v_bad text[] := '{}';
  f_w bigint; f_wt bigint; f_ur bigint; f_dp bigint; f_ms bigint; f_pi bigint; f_ml bigint;
  forged text;
  -- Lawful fail-closed refusal vocabulary. Every adversarial call MUST end in
  -- one of these. Some surfaces resolve the target object before the identity
  -- gate; both orders refuse, neither grants authority (A9 ordering note).
  refusals text[] := ARRAY[
    'AUTH_REQUIRED','PROFESSIONAL_IDENTITY_REQUIRED','PROFESSIONAL_IDENTITY_CONFLICT',
    'DRIVER_PROFILE_REQUIRED','DRIVER_NOT_OPERATIONAL','DRIVER_CAPABILITY_MISSING',
    'No driver profile','Offer not found','mission_not_found','ORDER_NOT_FOUND',
    'MERCHANT_STORE_NOT_FOUND','NOT_STORE_OWNER','not store owner',
    'PROCUREMENT_SHOPPER_NOT_ELIGIBLE','PROCUREMENT_MISSION_NOT_FOUND',
    'MERCHANT_STORE_NOT_OPERATIONAL','INVALID_MODE'];
  identity_tables text[] := ARRAY['user_preferences','user_roles','driver_profiles',
                                  'profiles','user_pins','user_legal_consents'];
  authority_fns text[] := ARRAY[
    '_driver_class_require','_driver_operational_require','_merchant_class_require',
    '_merchant_store_require','_merchant_restaurant_require','_marche_listing_authz',
    'marche_order_commit','marche_listing_create','has_role','professional_identity_current',
    'account_available_modes','driver_has_capability','professional_active_type',
    'marche_merchant_transition','marche_courier_transition','mission_claim',
    'driver_set_status','driver_offer_accept','merchant_settlement_request_create',
    'merchant_submit_location'];
  b_pi bigint; b_pia bigint; b_up bigint; b_w bigint; b_lp bigint; b_ls numeric;
  b_wt bigint; b_ms bigint; b_dp bigint; b_ur bigint; b_pr bigint; b_mo bigint; b_flags jsonb;
  a_pi bigint; a_pia bigint; a_up bigint; a_w bigint; a_lp bigint; a_ls numeric;
  a_wt bigint; a_ms bigint; a_dp bigint; a_ur bigint; a_pr bigint; a_mo bigint; a_flags jsonb;
  b_live_modes jsonb; a_live_modes jsonb;
BEGIN
  ids := ARRAY[u_c,u_d,u_da,u_m,u_m2,u_rel,u_ops];

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

  -- ================= A. STATIC NON-AUTHORITY =================
  FOREACH fn IN ARRAY authority_fns LOOP
    IF (SELECT bool_or(prosrc ~ 'app_mode' OR prosrc ~ 'preferred_mode' OR prosrc ~ 'effective_mode'
                       OR prosrc ~ 'user_preferences')
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname=fn) THEN
      v_bad := v_bad || fn;
    END IF;
  END LOOP;
  r := r || public._qa_s13_ok('N5A9.A1 no authority surface reads UI mode or preferences',
        array_length(v_bad,1) IS NULL, array_to_string(v_bad,','));
  r := r || public._qa_s13_ok('N5A9.A2 authority census covers twenty surfaces',
        array_length(authority_fns,1) = 20, array_length(authority_fns,1)::text);
  r := r || public._qa_s13_ok('N5A9.A3 no RLS policy reads app_mode',
        NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                     AND (COALESCE(qual,'') ~ 'app_mode' OR COALESCE(with_check,'') ~ 'app_mode')), NULL);
  r := r || public._qa_s13_ok('N5A9.A4 no RLS policy outside user_preferences reads user_preferences',
        NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename <> 'user_preferences'
                     AND (COALESCE(qual,'') ~ 'user_preferences' OR COALESCE(with_check,'') ~ 'user_preferences')),
        (SELECT string_agg(tablename||'.'||policyname,',') FROM pg_policies
          WHERE schemaname='public' AND tablename <> 'user_preferences'
            AND (COALESCE(qual,'') ~ 'user_preferences' OR COALESCE(with_check,'') ~ 'user_preferences')));
  r := r || public._qa_s13_ok('N5A9.A5 no RLS policy reads a client-supplied mode claim',
        NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                     AND (COALESCE(qual,'') ~ 'request\.jwt\.claims.*mode'
                       OR COALESCE(with_check,'') ~ 'request\.jwt\.claims.*mode')), NULL);
  r := r || public._qa_s13_ok('N5A9.A6 user_preferences carries no role, capability or approval column',
        NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema='public' AND table_name='user_preferences'
                       AND column_name ~ '(role|capabilit|approv|status|verified|admin)'),
        (SELECT string_agg(column_name,',') FROM information_schema.columns
          WHERE table_schema='public' AND table_name='user_preferences'));
  r := r || public._qa_s13_ok('N5A9.A7 preference writer never touches identity, roles, wallets or ledger',
        (SELECT prosrc !~ 'professional_identities' AND prosrc !~ 'user_roles'
                AND prosrc !~ 'wallets' AND prosrc !~ 'ledger' AND prosrc !~ 'driver_profiles'
                AND prosrc !~ 'merchant_stores'
           FROM pg_proc WHERE oid='public.account_mode_set(text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A9.A8 mode derivation depends on professional identity only',
        (SELECT prosrc ~ 'professional_active_type' AND prosrc !~ 'user_roles'
                AND prosrc !~ 'user_preferences'
           FROM pg_proc WHERE oid='public.account_available_modes(uuid)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A9.A9 arbitrary-user derivation stays server-only',
        NOT has_function_privilege('authenticated','public.account_available_modes(uuid)','EXECUTE')
        AND NOT has_function_privilege('anon','public.account_available_modes(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A9.A10 anon can never read or write mode state',
        NOT has_function_privilege('anon','public.account_mode_context()','EXECUTE')
        AND NOT has_function_privilege('anon','public.account_mode_set(text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A9.A11 preference guard trigger is installed',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.user_preferences'::regclass
                 AND NOT tgisinternal AND tgfoid='public._account_mode_preference_guard'::regproc), NULL);
  r := r || public._qa_s13_ok('N5A9.A12 every user_preferences policy is self-scoped',
        NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_preferences'
                     AND COALESCE(qual,'') !~ 'auth\.uid\(\)' AND COALESCE(with_check,'') !~ 'auth\.uid\(\)'),
        (SELECT string_agg(policyname,',') FROM pg_policies
          WHERE schemaname='public' AND tablename='user_preferences'));
  v_bad := '{}';
  FOREACH tb IN ARRAY identity_tables LOOP
    IF has_table_privilege('anon','public.'||tb,'SELECT')
       OR has_table_privilege('anon','public.'||tb,'INSERT')
       OR has_table_privilege('anon','public.'||tb,'UPDATE')
       OR has_table_privilege('anon','public.'||tb,'DELETE')
       OR has_table_privilege('anon','public.'||tb,'TRUNCATE') THEN
      v_bad := v_bad || tb;
    END IF;
  END LOOP;
  r := r || public._qa_s13_ok('N5A9.A13 anon holds no privilege on any identity table',
        array_length(v_bad,1) IS NULL, array_to_string(v_bad,','));
  r := r || public._qa_s13_ok('N5A9.A14 no capability vocabulary entry is a UI mode',
        NOT EXISTS (SELECT 1 FROM unnest(public.driver_capability_vocabulary()) c
                     WHERE c IN ('client','driver','merchant')), NULL);
  v_bad := '{}';
  FOREACH tb IN ARRAY identity_tables LOOP
    IF has_table_privilege('authenticated','public.'||tb,'TRUNCATE')
       OR has_table_privilege('authenticated','public.'||tb,'TRIGGER')
       OR has_table_privilege('authenticated','public.'||tb,'REFERENCES')
       OR has_table_privilege('anon','public.'||tb,'TRUNCATE') THEN
      v_bad := v_bad || tb;
    END IF;
  END LOOP;
  r := r || public._qa_s13_ok('N5A9.A15 no client role can truncate or re-wire an identity table',
        array_length(v_bad,1) IS NULL, array_to_string(v_bad,','));
  r := r || public._qa_s13_ok('N5A9.A16 signed-in users cannot delete role, preference or profile rows',
        NOT has_table_privilege('authenticated','public.user_roles','DELETE')
        AND NOT has_table_privilege('authenticated','public.user_preferences','DELETE')
        AND NOT has_table_privilege('authenticated','public.profiles','DELETE')
        AND NOT has_table_privilege('authenticated','public.driver_profiles','DELETE'), NULL);
  r := r || public._qa_s13_ok('N5A9.A17 role table stays read-only for signed-in users',
        has_table_privilege('authenticated','public.user_roles','SELECT')
        AND NOT has_table_privilege('authenticated','public.user_roles','INSERT')
        AND NOT has_table_privilege('authenticated','public.user_roles','UPDATE'), NULL);

  -- ================= FIXTURES =================
  PERFORM public._qa_users_new(u_c,  'qa-n5a9-c-' ||substr(u_c::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_d,  'qa-n5a9-d-' ||substr(u_d::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_da, 'qa-n5a9-da-'||substr(u_da::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_m,  'qa-n5a9-m-' ||substr(u_m::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_m2, 'qa-n5a9-m2-'||substr(u_m2::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_rel,'qa-n5a9-r-' ||substr(u_rel::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_ops,'qa-n5a9-o-' ||substr(u_ops::text,1,8)||'@example.com');
  UPDATE public.profiles SET phone = '+22462' || lpad((floor(random()*10000000))::bigint::text, 7, '0')
   WHERE user_id = ANY(ids) AND (phone IS NULL OR phone = '');
  INSERT INTO public.user_roles(user_id, role) VALUES (u_ops,'admin') ON CONFLICT DO NOTHING;

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_da), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_rel), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', NULL, true);
  UPDATE public.driver_profiles SET status='approved' WHERE user_id = u_da;
  PERFORM public._professional_identity_release(u_rel, 'qa_a9_release');

  INSERT INTO public.merchant_stores(id, owner_user_id, name, slug, status, onboarding_status)
  VALUES (s_m,  u_m,  'QA A9 Store A', 'qa-a9-a-'||substr(s_m::text,1,8),  'active','approved'),
         (s_m2, u_m2, 'QA A9 Store B', 'qa-a9-b-'||substr(s_m2::text,1,8), 'active','approved');

  SELECT count(*) INTO f_w  FROM public.wallets WHERE owner_user_id = ANY(ids);
  SELECT count(*) INTO f_wt FROM public.wallet_transactions wt
    WHERE wt.related_user_id = ANY(ids)
       OR wt.from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(ids))
       OR wt.to_wallet_id   IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(ids));
  SELECT count(*) INTO f_ur FROM public.user_roles WHERE user_id = ANY(ids);
  SELECT count(*) INTO f_dp FROM public.driver_profiles WHERE user_id = ANY(ids);
  SELECT count(*) INTO f_ms FROM public.merchant_stores WHERE owner_user_id = ANY(ids);
  SELECT count(*) INTO f_pi FROM public.professional_identities WHERE user_id = ANY(ids);
  SELECT count(*) INTO f_ml FROM public.marketplace_listings WHERE seller_id = ANY(ids);

  -- ================= B. CUSTOMER FORGING A DRIVER WORKSPACE =================
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_c), true);
  res := public.account_mode_set('driver');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A9.B1 customer cannot persist a driver workspace',
        res->>'effective_mode' = 'client' AND (res->>'refused')::boolean, res::text);
  INSERT INTO public.user_preferences(user_id, app_mode) VALUES (u_c,'driver')
    ON CONFLICT (user_id) DO UPDATE SET app_mode='driver';
  r := r || public._qa_s13_ok('N5A9.B2 tampered driver preference is neutralised in storage',
        (SELECT app_mode FROM public.user_preferences WHERE user_id=u_c) = 'client', NULL);
  forged := jsonb_build_object('sub',u_c::text,'role','authenticated','app_mode','driver',
              'user_role','driver','professional_type','driver','is_admin',true,
              'capabilities', jsonb_build_array('marche_shopper'))::text;
  PERFORM set_config('request.jwt.claims', forged, true);
  ctx := public.account_mode_context();
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A9.B3 forged mode claims do not change the derived workspace set',
        ctx->'available_modes' = '["client"]'::jsonb, ctx::text);
  r := r || public._qa_s13_ok('N5A9.B4 forged claims do not create a professional class',
        ctx->>'professional_type' = 'none', ctx::text);
  BEGIN
    PERFORM set_config('request.jwt.claims', forged, true);
    PERFORM public.driver_set_status('online'::public.driver_presence);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.B5 customer in forged driver mode cannot go online', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.B5 customer in forged driver mode cannot go online',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims', forged, true);
    PERFORM public.driver_offer_accept(gen_random_uuid());
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.B6 customer in forged driver mode cannot accept an offer', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.B6 customer in forged driver mode cannot accept an offer',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims', forged, true);
    PERFORM public.mission_claim(gen_random_uuid());
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.B7 customer in forged driver mode cannot claim a mission', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.B7 customer in forged driver mode cannot claim a mission',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims', forged, true);
    PERFORM public.driver_set_capabilities(ARRAY['marche_shopper']);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.B8 customer in forged driver mode cannot self-grant a capability', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.B8 customer in forged driver mode cannot self-grant a capability', true, SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A9.B9 forged driver traffic created no driver profile',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id=u_c), NULL);
  r := r || public._qa_s13_ok('N5A9.B10 forged driver traffic created no professional identity',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id=u_c), NULL);
  r := r || public._qa_s13_ok('N5A9.B11 forged driver traffic created no presence row',
        NOT EXISTS (SELECT 1 FROM public.driver_locations WHERE user_id=u_c), NULL);
  r := r || public._qa_s13_ok('N5A9.B12 forged admin claim grants no admin role',
        NOT public.has_role(u_c,'admin'::public.app_role), NULL);

  -- ================= C. CUSTOMER / DRIVER FORGING A MERCHANT WORKSPACE =================
  forged := jsonb_build_object('sub',u_c::text,'role','authenticated','app_mode','merchant',
              'professional_type','merchant','store_id',s_m::text)::text;
  BEGIN
    PERFORM set_config('request.jwt.claims', forged, true);
    PERFORM public.marche_listing_create(jsonb_build_object('store_id',s_m,'title','forged','price_gnf',1000));
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.C1 customer in forged merchant mode cannot create supply', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.C1 customer in forged merchant mode cannot create supply',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims', forged, true);
    PERFORM public.merchant_settlement_request_create(100000, 'qa-a9-'||substr(u_c::text,1,8), s_m, NULL);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.C2 customer in forged merchant mode cannot request settlement', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.C2 customer in forged merchant mode cannot request settlement', true, SQLERRM);
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims', forged, true);
    PERFORM public.merchant_submit_location(s_m, 9.5, -13.7, 'forged', NULL, NULL, NULL, NULL);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.C3 customer in forged merchant mode cannot mutate a store', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.C3 customer in forged merchant mode cannot mutate a store',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  forged := jsonb_build_object('sub',u_da::text,'role','authenticated','app_mode','merchant',
              'professional_type','merchant')::text;
  BEGIN
    PERFORM set_config('request.jwt.claims', forged, true);
    PERFORM public.marche_listing_create(jsonb_build_object('store_id',s_m,'title','forged','price_gnf',1000));
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.C4 driver in forged merchant mode cannot create supply', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.C4 driver in forged merchant mode cannot create supply',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims', forged, true);
    PERFORM public.marche_merchant_transition(gen_random_uuid(), 'accept', NULL);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.C5 driver in forged merchant mode cannot run merchant ops', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.C5 driver in forged merchant mode cannot run merchant ops',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A9.C6 forged merchant traffic created no store',
        NOT EXISTS (SELECT 1 FROM public.merchant_stores WHERE owner_user_id IN (u_c,u_da)), NULL);
  r := r || public._qa_s13_ok('N5A9.C7 forged merchant traffic created no listing',
        (SELECT count(*) FROM public.marketplace_listings WHERE seller_id = ANY(ids)) = f_ml, NULL);
  r := r || public._qa_s13_ok('N5A9.C8 forged merchant traffic created no settlement request',
        NOT EXISTS (SELECT 1 FROM public.merchant_settlement_requests
                     WHERE merchant_store_id IN (s_m,s_m2)), NULL);
  r := r || public._qa_s13_ok('N5A9.C9 store A location was not mutated by the forgery',
        (SELECT address_label IS DISTINCT FROM 'forged' FROM public.merchant_stores WHERE id=s_m), NULL);
  r := r || public._qa_s13_ok('N5A9.C10 driver class survived the merchant forgery intact',
        public.professional_active_type(u_da) = 'driver', NULL);

  -- ================= D. MERCHANT FORGING A DRIVER WORKSPACE =================
  forged := jsonb_build_object('sub',u_m::text,'role','authenticated','app_mode','driver',
              'professional_type','driver')::text;
  BEGIN
    PERFORM set_config('request.jwt.claims', forged, true);
    PERFORM public.driver_set_status('online'::public.driver_presence);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.D1 merchant in forged driver mode cannot go online', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.D1 merchant in forged driver mode cannot go online',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims', forged, true);
    PERFORM public.marche_courier_transition(gen_random_uuid(), 'collected');
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.D2 merchant in forged driver mode cannot move a courier leg', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.D2 merchant in forged driver mode cannot move a courier leg',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims', forged, true);
    PERFORM public.marche_shopper_claim(gen_random_uuid());
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.D3 merchant in forged driver mode cannot claim a shopper mission', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.D3 merchant in forged driver mode cannot claim a shopper mission',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A9.D4 forged driver mode created no driver profile for the merchant',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id=u_m), NULL);
  r := r || public._qa_s13_ok('N5A9.D5 merchant class survived the driver forgery intact',
        public.professional_active_type(u_m) = 'merchant', NULL);
  r := r || public._qa_s13_ok('N5A9.D6 no account acquired a second active professional identity',
        NOT EXISTS (SELECT user_id FROM public.professional_identities
                     WHERE user_id = ANY(ids) AND claim_state='active'
                     GROUP BY user_id HAVING count(*) > 1), NULL);

  -- ================= E. RELEASED PROFESSIONAL STATE =================
  INSERT INTO public.user_preferences(user_id, app_mode) VALUES (u_rel,'driver')
    ON CONFLICT (user_id) DO UPDATE SET app_mode='driver';
  r := r || public._qa_s13_ok('N5A9.E1 stale driver preference cannot be restored after release',
        (SELECT app_mode FROM public.user_preferences WHERE user_id=u_rel) = 'client', NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_rel), true);
  ctx := public.account_mode_context();
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A9.E2 released account resolves to the client workspace',
        ctx->>'effective_mode' = 'client' AND ctx->'available_modes' = '["client"]'::jsonb, ctx::text);
  forged := jsonb_build_object('sub',u_rel::text,'role','authenticated','app_mode','driver')::text;
  BEGIN
    PERFORM set_config('request.jwt.claims', forged, true);
    PERFORM public.driver_set_status('online'::public.driver_presence);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.E3 released driver cannot resume duty through UI mode', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.E3 released driver cannot resume duty through UI mode',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims', forged, true);
    PERFORM public.mission_claim(gen_random_uuid());
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.E4 released driver cannot claim work through UI mode', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.E4 released driver cannot claim work through UI mode',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A9.E5 release remains recorded, not erased',
        EXISTS (SELECT 1 FROM public.professional_identities
                 WHERE user_id=u_rel AND professional_type='driver' AND claim_state<>'active'), NULL);
  r := r || public._qa_s13_ok('N5A9.E6 released account holds no active class',
        COALESCE(public.professional_active_type(u_rel),'none') = 'none',
        COALESCE(public.professional_active_type(u_rel),'(null)'));
  r := r || public._qa_s13_ok('N5A9.E7 released driver profile was not silently reactivated',
        (SELECT status FROM public.driver_profiles WHERE user_id=u_rel)::text <> 'approved', NULL);
  r := r || public._qa_s13_ok('N5A9.E8 released account still holds the client workspace',
        public.account_available_modes(u_rel) = ARRAY['client'], NULL);

  -- ================= F. ROLE + MODE ISOLATION =================
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  res := public.account_mode_set('driver');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A9.F1 admin role alone cannot select a driver workspace',
        res->>'effective_mode' = 'client' AND (res->>'refused')::boolean, res::text);
  r := r || public._qa_s13_ok('N5A9.F2 admin role grants no professional mode',
        public.account_available_modes(u_ops) = ARRAY['client'], NULL);
  r := r || public._qa_s13_ok('N5A9.F3 mode traffic granted no new role to anyone',
        (SELECT count(*) FROM public.user_roles WHERE user_id = ANY(ids)) = f_ur,
        (SELECT string_agg(user_id::text||':'||role::text,',') FROM public.user_roles WHERE user_id = ANY(ids)));
  r := r || public._qa_s13_ok('N5A9.F4 customer holds no professional or admin role',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_c
                     AND role::text NOT IN ('user','client')), NULL);
  r := r || public._qa_s13_ok('N5A9.F5 driver mode did not grant the driver an admin role',
        NOT public.has_role(u_da,'admin'::public.app_role), NULL);
  r := r || public._qa_s13_ok('N5A9.F6 merchant mode did not grant the merchant an admin role',
        NOT public.has_role(u_m,'admin'::public.app_role), NULL);
  r := r || public._qa_s13_ok('N5A9.F7 has_role never consults preferences',
        (SELECT bool_and(prosrc !~ 'user_preferences' AND prosrc !~ 'app_mode')
           FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname='has_role'), NULL);
  r := r || public._qa_s13_ok('N5A9.F8 admin helpers remain out of reach for anon',
        NOT has_function_privilege('anon','public.has_role(uuid,public.app_role)','EXECUTE'), NULL);

  -- ================= G. WALLET + MODE ISOLATION =================
  r := r || public._qa_s13_ok('N5A9.G1 mode traffic created no wallet',
        (SELECT count(*) FROM public.wallets WHERE owner_user_id = ANY(ids)) = f_w, NULL);
  r := r || public._qa_s13_ok('N5A9.G2 mode traffic created no wallet transaction',
        (SELECT count(*) FROM public.wallet_transactions wt
          WHERE wt.related_user_id = ANY(ids)
             OR wt.from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(ids))
             OR wt.to_wallet_id   IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(ids))) = f_wt, NULL);
  r := r || public._qa_s13_ok('N5A9.G3 no wallet changed status through mode traffic',
        NOT EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id = ANY(ids) AND status <> 'active'), NULL);
  r := r || public._qa_s13_ok('N5A9.G4 ledger postings unchanged',
        (SELECT count(*) FROM public.ledger_postings) = b_lp, NULL);
  r := r || public._qa_s13_ok('N5A9.G5 ledger balance unchanged',
        (SELECT COALESCE(sum(amount_gnf),0) FROM public.ledger_postings) = b_ls, NULL);
  r := r || public._qa_s13_ok('N5A9.G6 no payable or payout produced by mode traffic',
        (SELECT count(*) FROM public.merchant_payables WHERE merchant_user_id = ANY(ids)) = 0
        AND (SELECT count(*) FROM public.payout_orders WHERE party_user_id = ANY(ids)) = 0, NULL);

  -- ================= H. ARTIFACT + MODE ISOLATION =================
  r := r || public._qa_s13_ok('N5A9.H1 no driver profile appeared or disappeared',
        (SELECT count(*) FROM public.driver_profiles WHERE user_id = ANY(ids)) = f_dp, NULL);
  r := r || public._qa_s13_ok('N5A9.H2 no store appeared or disappeared',
        (SELECT count(*) FROM public.merchant_stores WHERE owner_user_id = ANY(ids)) = f_ms, NULL);
  r := r || public._qa_s13_ok('N5A9.H3 professional identity census unchanged by mode traffic',
        (SELECT count(*) FROM public.professional_identities WHERE user_id = ANY(ids)) = f_pi, NULL);
  r := r || public._qa_s13_ok('N5A9.H4 no marche order was created',
        (SELECT count(*) FROM public.marche_orders) = b_mo, NULL);
  r := r || public._qa_s13_ok('N5A9.H5 no mission was created for a QA account',
        NOT EXISTS (SELECT 1 FROM public.missions WHERE courier_id = ANY(ids) OR customer_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A9.H6 no ride was created for a QA account',
        NOT EXISTS (SELECT 1 FROM public.rides WHERE driver_id = ANY(ids) OR client_id = ANY(ids)), NULL);

  -- ================= I. SUSPENSION / CAPABILITY / APPROVAL ISOLATION =================
  forged := jsonb_build_object('sub',u_d::text,'role','authenticated','app_mode','driver',
              'driver_status','approved')::text;
  BEGIN
    PERFORM set_config('request.jwt.claims', forged, true);
    PERFORM public.mission_claim(gen_random_uuid());
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.I1 pending driver in driver mode is still not operational', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.I1 pending driver in driver mode is still not operational',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A9.I2 pending driver still owns the driver workspace (class, not approval)',
        public.account_available_modes(u_d) = ARRAY['client','driver'], NULL);
  BEGIN
    PERFORM set_config('request.jwt.claims',
      jsonb_build_object('sub',u_da::text,'role','authenticated','app_mode','driver',
        'capabilities', jsonb_build_array('marche_shopper'))::text, true);
    PERFORM public.marche_shopper_claim(gen_random_uuid());
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.I3 approved driver cannot claim a capability through UI context', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.I3 approved driver cannot claim a capability through UI context',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A9.I4 no capability was granted by the forged claim',
        NOT public.driver_has_capability(u_da,'marche_shopper'), NULL);
  r := r || public._qa_s13_ok('N5A9.I5 capability truth lives on the driver profile, not the session',
        (SELECT bool_and(prosrc ~ 'driver_profiles')
           FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname='driver_has_capability'), NULL);
  UPDATE public.merchant_stores SET onboarding_status='submitted' WHERE id=s_m2;
  BEGIN
    PERFORM set_config('request.jwt.claims',
      jsonb_build_object('sub',u_m2::text,'role','authenticated','app_mode','merchant',
        'store_status','approved')::text, true);
    PERFORM public.merchant_settlement_request_create(100000, 'qa-a9-m2-'||substr(u_m2::text,1,8), s_m2, NULL);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.I6 unapproved store cannot be made operational by UI context', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.I6 unapproved store cannot be made operational by UI context', true, SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A9.I7 store approval state was not rewritten by the attempt',
        (SELECT onboarding_status FROM public.merchant_stores WHERE id=s_m2) = 'submitted', NULL);
  r := r || public._qa_s13_ok('N5A9.I8 unapproved store still grants the merchant workspace',
        public.account_available_modes(u_m2) = ARRAY['client','merchant'], NULL);

  -- ================= J. OBJECT-LEVEL ISOLATION =================
  BEGIN
    PERFORM set_config('request.jwt.claims',
      jsonb_build_object('sub',u_m2::text,'role','authenticated','app_mode','merchant',
        'store_id',s_m::text)::text, true);
    PERFORM public.merchant_submit_location(s_m, 9.5, -13.7, 'cross-tenant', NULL, NULL, NULL, NULL);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.J1 merchant B cannot mutate merchant A store via mode context', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.J1 merchant B cannot mutate merchant A store via mode context',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims',
      jsonb_build_object('sub',u_m2::text,'role','authenticated','app_mode','merchant')::text, true);
    PERFORM public.marche_listing_create(jsonb_build_object('store_id',s_m,'title','cross','price_gnf',1000));
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.J2 merchant B cannot publish supply into merchant A store', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.J2 merchant B cannot publish supply into merchant A store', true, SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A9.J3 store A remains untouched by cross-tenant attempts',
        (SELECT address_label IS DISTINCT FROM 'cross-tenant' FROM public.merchant_stores WHERE id=s_m), NULL);
  r := r || public._qa_s13_ok('N5A9.J4 no listing was published into store A',
        NOT EXISTS (SELECT 1 FROM public.marketplace_listings WHERE store_id=s_m), NULL);
  BEGIN
    PERFORM set_config('request.jwt.claims',
      jsonb_build_object('sub',u_c::text,'role','authenticated','app_mode','driver')::text, true);
    PERFORM public.account_mode_set('driver');
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.J5 preference writer only ever touches the caller row',
          (SELECT count(*) FROM public.user_preferences
            WHERE user_id = ANY(ids) AND app_mode IS DISTINCT FROM 'client') = 0,
          (SELECT string_agg(user_id::text||':'||COALESCE(app_mode,'-'),',')
             FROM public.user_preferences WHERE user_id = ANY(ids)));
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A9.J5 preference writer only ever touches the caller row', false, SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A9.J6 live production preferences were never rewritten',
        (SELECT COALESCE(jsonb_agg(jsonb_build_array(user_id, app_mode) ORDER BY user_id),'[]'::jsonb)
           FROM public.user_preferences WHERE NOT (user_id = ANY(ids))) = b_live_modes, NULL);

  -- ================= K. PREFERENCE RPC INTEGRITY =================
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_da), true);
  BEGIN
    PERFORM public.account_mode_set('driver''; DROP TABLE public.user_preferences; --');
    r := r || public._qa_s13_ok('N5A9.K1 injection payload is refused as an invalid mode', false, 'no refusal');
  EXCEPTION WHEN others THEN
    r := r || public._qa_s13_ok('N5A9.K1 injection payload is refused as an invalid mode',
          SQLERRM = 'INVALID_MODE', SQLERRM);
  END;
  BEGIN
    PERFORM public.account_mode_set(NULL);
    r := r || public._qa_s13_ok('N5A9.K2 null mode is refused', false, 'no refusal');
  EXCEPTION WHEN others THEN
    r := r || public._qa_s13_ok('N5A9.K2 null mode is refused', SQLERRM = 'INVALID_MODE', SQLERRM);
  END;
  BEGIN
    PERFORM public.account_mode_set('DRIVER');
    r := r || public._qa_s13_ok('N5A9.K3 case-variant mode value is not silently accepted', false, 'no refusal');
  EXCEPTION WHEN others THEN
    r := r || public._qa_s13_ok('N5A9.K3 case-variant mode value is not silently accepted',
          SQLERRM = 'INVALID_MODE', SQLERRM);
  END;
  res := public.account_mode_set('driver');
  r := r || public._qa_s13_ok('N5A9.K4 lawful driver workspace is still selectable',
        res->>'effective_mode' = 'driver' AND (res->>'refused')::boolean IS FALSE, res::text);
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A9.K5 the table survived the injection attempt',
        to_regclass('public.user_preferences') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A9.K6 selecting the driver workspace changed no approval state',
        (SELECT status FROM public.driver_profiles WHERE user_id=u_da)::text = 'approved', NULL);
  r := r || public._qa_s13_ok('N5A9.K7 selecting the driver workspace granted no capability',
        NOT public.driver_has_capability(u_da,'marche_shopper'), NULL);
  r := r || public._qa_s13_ok('N5A9.K8 selecting the driver workspace changed no presence',
        NOT EXISTS (SELECT 1 FROM public.driver_locations WHERE user_id=u_da AND status::text = 'online'), NULL);
  BEGIN
    PERFORM set_config('request.jwt.claims', NULL, true);
    PERFORM public.account_mode_set('client');
    r := r || public._qa_s13_ok('N5A9.K9 signed-out preference write refuses', false, 'no refusal');
  EXCEPTION WHEN others THEN
    r := r || public._qa_s13_ok('N5A9.K9 signed-out preference write refuses', SQLERRM = 'AUTH_REQUIRED', SQLERRM);
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims', NULL, true);
    PERFORM public.account_mode_context();
    r := r || public._qa_s13_ok('N5A9.K10 signed-out context read refuses', false, 'no refusal');
  EXCEPTION WHEN others THEN
    r := r || public._qa_s13_ok('N5A9.K10 signed-out context read refuses', SQLERRM = 'AUTH_REQUIRED', SQLERRM);
  END;

  -- ================= CLEANUP =================
  PERFORM set_config('request.jwt.claims', NULL, true);
  DELETE FROM public.user_preferences WHERE user_id = ANY(ids);
  DELETE FROM public.merchant_settlement_requests WHERE merchant_store_id IN (s_m,s_m2);
  DELETE FROM public.marketplace_listings WHERE seller_id = ANY(ids) OR store_id IN (s_m,s_m2);
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

  r := r || public._qa_s13_ok('N5A9.L1 professional_identities returned to baseline', a_pi = b_pi, b_pi||'->'||a_pi);
  r := r || public._qa_s13_ok('N5A9.L2 active professional census unchanged', a_pia = b_pia, b_pia||'->'||a_pia);
  r := r || public._qa_s13_ok('N5A9.L3 user_preferences returned to baseline', a_up = b_up, b_up||'->'||a_up);
  r := r || public._qa_s13_ok('N5A9.L4 no live mode preference was rewritten', a_live_modes = b_live_modes, NULL);
  r := r || public._qa_s13_ok('N5A9.L5 wallets returned to baseline', a_w = b_w, b_w||'->'||a_w);
  r := r || public._qa_s13_ok('N5A9.L6 wallet transactions unchanged', a_wt = b_wt, b_wt||'->'||a_wt);
  r := r || public._qa_s13_ok('N5A9.L7 ledger postings returned to baseline', a_lp = b_lp, NULL);
  r := r || public._qa_s13_ok('N5A9.L8 ledger sum returned to baseline', a_ls = b_ls, NULL);
  r := r || public._qa_s13_ok('N5A9.L9 merchant_stores returned to baseline', a_ms = b_ms, b_ms||'->'||a_ms);
  r := r || public._qa_s13_ok('N5A9.L10 driver_profiles returned to baseline', a_dp = b_dp, b_dp||'->'||a_dp);
  r := r || public._qa_s13_ok('N5A9.L11 user_roles returned to baseline', a_ur = b_ur, b_ur||'->'||a_ur);
  r := r || public._qa_s13_ok('N5A9.L12 profiles returned to baseline', a_pr = b_pr, b_pr||'->'||a_pr);
  r := r || public._qa_s13_ok('N5A9.L13 marche_orders unchanged', a_mo = b_mo, NULL);
  r := r || public._qa_s13_ok('N5A9.L14 feature flags unchanged', a_flags = b_flags, NULL);
  r := r || public._qa_s13_ok('N5A9.L15 no QA residue in user_preferences',
        NOT EXISTS (SELECT 1 FROM public.user_preferences WHERE user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A9.L16 no QA residue in professional_identities',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A9.L17 no QA residue in merchant_stores',
        NOT EXISTS (SELECT 1 FROM public.merchant_stores WHERE owner_user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A9.L18 no QA residue in driver_profiles',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id = ANY(ids)), NULL);

  RETURN jsonb_build_object(
    'fn','_qa_node5_identity_a9',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'failures', (SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(r) e
                  WHERE (e->>'ok')::boolean IS NOT TRUE)
  );
EXCEPTION WHEN others THEN
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    DELETE FROM public.user_preferences WHERE user_id = ANY(ids);
    DELETE FROM public.merchant_settlement_requests WHERE merchant_store_id IN (s_m,s_m2);
    DELETE FROM public.marketplace_listings WHERE seller_id = ANY(ids) OR store_id IN (s_m,s_m2);
    DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(ids);
    PERFORM public._qa_a5_cleanup(ids);
  EXCEPTION WHEN others THEN NULL; END;
  RAISE;
END $$;
REVOKE ALL ON FUNCTION public._qa_node5_identity_a9() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_identity_a9() TO service_role;
