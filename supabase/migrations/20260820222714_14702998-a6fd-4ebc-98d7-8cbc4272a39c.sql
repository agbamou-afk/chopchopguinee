CREATE OR REPLACE FUNCTION public._qa_a4_cleanup(p_ids uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  DELETE FROM public.missions WHERE courier_id = ANY(p_ids) OR customer_id = ANY(p_ids) OR merchant_id = ANY(p_ids);
  DELETE FROM public.audit_logs WHERE actor_user_id = ANY(p_ids);
  DELETE FROM public.admin_users WHERE user_id = ANY(p_ids);
  PERFORM public._qa_a3_cleanup(p_ids);
END $function$;

REVOKE ALL ON FUNCTION public._qa_a4_cleanup(uuid[]) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_node5_identity_a4()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
SET statement_timeout TO '180s'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  u_d1 uuid := gen_random_uuid();
  u_d2 uuid := gen_random_uuid();
  u_d3 uuid := gen_random_uuid();
  u_m1 uuid := gen_random_uuid();
  u_m2 uuid := gen_random_uuid();
  u_m3 uuid := gen_random_uuid();
  u_m4 uuid := gen_random_uuid();
  u_oth uuid := gen_random_uuid();
  u_ops uuid := gen_random_uuid();
  ids uuid[];
  v_err text; v_json jsonb; v_n int; v_store uuid; v_resto uuid; v_store4 uuid;
  b_pr bigint; a_pr bigint; b_au bigint; a_au bigint; b_ur bigint; a_ur bigint;
  b_w bigint; a_w bigint; b_wt bigint; a_wt bigint; b_lp bigint; a_lp bigint;
  b_ls bigint; a_ls bigint; b_dp bigint; a_dp bigint; b_da bigint; a_da bigint;
  b_ms bigint; a_ms bigint; b_fr bigint; a_fr bigint; b_me bigint; a_me bigint;
  b_pi bigint; a_pi bigint; b_pia bigint; a_pia bigint; b_al bigint; a_al bigint;
  b_mo bigint; a_mo bigint; b_fo bigint; a_fo bigint; b_ml bigint; a_ml bigint;
  b_mi bigint; a_mi bigint; b_ad bigint; a_ad bigint; b_flags jsonb; a_flags jsonb;
BEGIN
  ids := ARRAY[u_d1,u_d2,u_d3,u_m1,u_m2,u_m3,u_m4,u_oth,u_ops];

  SELECT count(*) INTO b_pr FROM public.profiles;
  b_au := public._qa_auth_user_count();
  SELECT count(*) INTO b_ur FROM public.user_roles;
  SELECT count(*) INTO b_w  FROM public.wallets;
  SELECT count(*) INTO b_wt FROM public.wallet_transactions;
  SELECT count(*) INTO b_lp FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO b_ls FROM public.ledger_postings;
  SELECT count(*) INTO b_dp FROM public.driver_profiles;
  SELECT count(*) INTO b_da FROM public.driver_applications;
  SELECT count(*) INTO b_ms FROM public.merchant_stores;
  SELECT count(*) INTO b_fr FROM public.food_restaurants;
  SELECT count(*) INTO b_me FROM public.merchants;
  SELECT count(*) INTO b_pi FROM public.professional_identities;
  SELECT count(*) INTO b_pia FROM public.professional_identities WHERE claim_state='active';
  SELECT count(*) INTO b_al FROM public.audit_logs;
  SELECT count(*) INTO b_mo FROM public.marche_orders;
  SELECT count(*) INTO b_fo FROM public.food_orders;
  SELECT count(*) INTO b_ml FROM public.marketplace_listings;
  SELECT count(*) INTO b_mi FROM public.missions;
  SELECT count(*) INTO b_ad FROM public.admin_users;
  SELECT jsonb_object_agg(key, enabled) INTO b_flags FROM public.feature_flags;

  -- ============ A. ARCHITECTURE + SECURITY POSTURE ============
  r := r || public._qa_s13_ok('N5A4.A1 eligibility RPC exists',
        EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                 WHERE n.nspname='public' AND p.proname='professional_identity_release_eligibility'), NULL);
  r := r || public._qa_s13_ok('N5A4.A2 eligibility RPC is SECURITY DEFINER with a pinned search_path',
        (SELECT prosecdef AND 'search_path=public' = ANY(proconfig) FROM pg_proc
          WHERE proname='professional_identity_release_eligibility'), NULL);
  r := r || public._qa_s13_ok('N5A4.A3 eligibility RPC is not executable by anon',
        NOT has_function_privilege('anon','public.professional_identity_release_eligibility(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A4.A4 eligibility RPC is executable by signed-in users',
        has_function_privilege('authenticated','public.professional_identity_release_eligibility(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A4.A5 self-release RPC is SECURITY DEFINER with a pinned search_path',
        (SELECT prosecdef AND 'search_path=public' = ANY(proconfig) FROM pg_proc
          WHERE proname='professional_identity_self_release'), NULL);
  r := r || public._qa_s13_ok('N5A4.A6 self-release RPC is not executable by anon',
        NOT has_function_privilege('anon','public.professional_identity_self_release(text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A4.A7 self-release RPC takes no target-user argument (no cross-user release)',
        (SELECT pg_get_function_identity_arguments(oid) NOT ILIKE '%uuid%' FROM pg_proc
          WHERE proname='professional_identity_self_release'), NULL);
  r := r || public._qa_s13_ok('N5A4.A8 self-release RPC cannot claim a lane (no conversion mechanism)',
        (SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname='professional_identity_self_release')
          NOT ILIKE '%_professional_identity_claim%', NULL);
  r := r || public._qa_s13_ok('N5A4.A9 no self-service lane conversion/switch RPC was introduced',
        NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                     WHERE n.nspname='public'
                       AND (p.proname ILIKE '%lane_switch%' OR p.proname ILIKE '%lane_convert%'
                            OR p.proname ILIKE '%professional_identity_convert%')), NULL);
  r := r || public._qa_s13_ok('N5A4.A10 internal release primitive stays server-only for authenticated',
        NOT has_function_privilege('authenticated','public._professional_identity_release(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A4.A11 driver_profiles carries the state-transition lock',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.driver_profiles'::regclass
                 AND tgname='professional_state_transition_guard' AND NOT tgisinternal), NULL);
  r := r || public._qa_s13_ok('N5A4.A12 merchant_stores carries the state-transition lock',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.merchant_stores'::regclass
                 AND tgname='professional_state_transition_guard' AND NOT tgisinternal), NULL);
  r := r || public._qa_s13_ok('N5A4.A13 state-transition lock fires BEFORE the row is written',
        NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='professional_state_transition_guard'
                     AND NOT tgisinternal AND (tgtype & 2) = 0), NULL);
  r := r || public._qa_s13_ok('N5A4.A14 state-transition guard fn is SECURITY DEFINER with a pinned search_path',
        (SELECT prosecdef AND 'search_path=public' = ANY(proconfig) FROM pg_proc
          WHERE proname='_professional_state_transition_guard'), NULL);
  r := r || public._qa_s13_ok('N5A4.A15 state-transition guard fn is not executable by authenticated',
        NOT has_function_privilege('authenticated','public._professional_state_transition_guard()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A4.A16 driver_status carries a truthful withdrawn terminal state',
        EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
                 WHERE t.typname='driver_status' AND e.enumlabel='withdrawn'), NULL);
  r := r || public._qa_s13_ok('N5A4.A17 driver_application_decision carries a truthful withdrawn terminal state',
        EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
                 WHERE t.typname='driver_application_decision' AND e.enumlabel='withdrawn'), NULL);
  r := r || public._qa_s13_ok('N5A4.A18 merchant onboarding_status admits withdrawn',
        (SELECT pg_get_constraintdef(oid) FROM pg_constraint
          WHERE conname='merchant_stores_onboarding_status_check') ILIKE '%withdrawn%', NULL);
  r := r || public._qa_s13_ok('N5A4.A19 store ownership uniqueness now excludes archived history',
        EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='merchant_stores'
                 AND indexname='merchant_stores_owner_active_uidx'
                 AND indexdef ILIKE '%WHERE (status <> ''archived''%'), NULL);
  r := r || public._qa_s13_ok('N5A4.A20 A3 one-active-lane unique index is intact',
        EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                 AND tablename='professional_identities'
                 AND indexdef ILIKE 'CREATE UNIQUE INDEX%(user_id)%WHERE (claim_state = ''active''::text)'), NULL);
  r := r || public._qa_s13_ok('N5A4.A21 A3 lane guards remain on all five artifact tables',
        (SELECT count(*) FROM pg_trigger WHERE tgname='professional_lane_guard' AND NOT tgisinternal) = 5, NULL);

  PERFORM public._qa_users_new(u_d1, 'qa-n5a4-d1-'||substr(u_d1::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_d2, 'qa-n5a4-d2-'||substr(u_d2::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_d3, 'qa-n5a4-d3-'||substr(u_d3::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_m1, 'qa-n5a4-m1-'||substr(u_m1::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_m2, 'qa-n5a4-m2-'||substr(u_m2::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_m3, 'qa-n5a4-m3-'||substr(u_m3::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_m4, 'qa-n5a4-m4-'||substr(u_m4::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_oth,'qa-n5a4-oth-'||substr(u_oth::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_ops,'qa-n5a4-ops-'||substr(u_ops::text,1,8)||'@example.com');
  PERFORM set_config('request.jwt.claims', NULL, true);
  INSERT INTO public.admin_users(user_id, admin_role, status)
  VALUES (u_ops, 'operations_admin', 'active') ON CONFLICT DO NOTHING;

  -- ============ B. UNAUTHENTICATED SURFACE ============
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN v_json := public.professional_identity_release_eligibility(u_d1); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A4.B1 unauthenticated eligibility read is refused', v_err = 'AUTH_REQUIRED', v_err);
  BEGIN PERFORM public.professional_identity_self_release('x'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A4.B2 unauthenticated self-release is refused', v_err = 'AUTH_REQUIRED', v_err);

  -- ============ C. NO LANE = NOTHING TO ABANDON ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_oth), true);
  v_json := public.professional_identity_release_eligibility();
  r := r || public._qa_s13_ok('N5A4.C1 plain customer reports no active lane', v_json->>'lane' = 'none', v_json::text);
  r := r || public._qa_s13_ok('N5A4.C2 plain customer is not eligible to release',
        (v_json->>'eligible')::boolean IS FALSE, v_json::text);
  r := r || public._qa_s13_ok('N5A4.C3 plain customer blocker is machine-readable',
        v_json->'blockers' ? 'NO_ACTIVE_PROFESSIONAL_LANE', v_json::text);
  BEGIN PERFORM public.professional_identity_self_release(NULL); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A4.C4 plain customer self-release is refused',
        v_err = 'NO_ACTIVE_PROFESSIONAL_LANE', v_err);

  -- ============ D. CLEAN DRIVER ONBOARDING IS ABANDONABLE ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d1), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  r := r || public._qa_s13_ok('N5A4.D1 driver onboarding claimed the DRIVER lane',
        (SELECT professional_type FROM public.professional_identities
          WHERE user_id=u_d1 AND claim_state='active') = 'driver', NULL);
  v_json := public.professional_identity_release_eligibility();
  r := r || public._qa_s13_ok('N5A4.D2 unfinished driver onboarding is eligible for abandonment',
        (v_json->>'eligible')::boolean IS TRUE, v_json::text);
  r := r || public._qa_s13_ok('N5A4.D3 eligible driver reports zero blockers',
        jsonb_array_length(v_json->'blockers') = 0, v_json::text);
  r := r || public._qa_s13_ok('N5A4.D4 eligibility echoes the lane under evaluation', v_json->>'lane'='driver', v_json::text);
  v_json := public.professional_identity_self_release('changed my mind');
  r := r || public._qa_s13_ok('N5A4.D5 driver abandonment succeeds', (v_json->>'released')::boolean IS TRUE, v_json::text);
  r := r || public._qa_s13_ok('N5A4.D6 driver lane is no longer active',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id=u_d1 AND claim_state='active'), NULL);
  r := r || public._qa_s13_ok('N5A4.D7 released lane row is kept as history, not deleted',
        (SELECT claim_state FROM public.professional_identities WHERE user_id=u_d1) = 'released', NULL);
  r := r || public._qa_s13_ok('N5A4.D8 released lane records the reason',
        (SELECT release_reason FROM public.professional_identities WHERE user_id=u_d1) = 'changed my mind', NULL);
  r := r || public._qa_s13_ok('N5A4.D9 released lane records the release timestamp',
        (SELECT released_at IS NOT NULL FROM public.professional_identities WHERE user_id=u_d1), NULL);
  r := r || public._qa_s13_ok('N5A4.D10 driver profile is marked withdrawn, not deleted',
        (SELECT status::text FROM public.driver_profiles WHERE user_id=u_d1) = 'withdrawn', NULL);
  r := r || public._qa_s13_ok('N5A4.D11 driver application is marked withdrawn, not deleted',
        (SELECT count(*) FROM public.driver_applications WHERE user_id=u_d1 AND decision='withdrawn') = 1, NULL);
  r := r || public._qa_s13_ok('N5A4.D12 abandonment left the driver offline',
        (SELECT presence::text FROM public.driver_profiles WHERE user_id=u_d1) = 'offline', NULL);
  r := r || public._qa_s13_ok('N5A4.D13 abandonment granted no professional role',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_d1 AND role IN ('driver','merchant')), NULL);
  r := r || public._qa_s13_ok('N5A4.D14 abandonment created no driver wallet',
        NOT EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id=u_d1 AND party_type='driver'), NULL);
  r := r || public._qa_s13_ok('N5A4.D15 abandonment created no ledger movement',
        (SELECT count(*) FROM public.ledger_postings) = b_lp, NULL);
  r := r || public._qa_s13_ok('N5A4.D16 abandonment is audited',
        EXISTS (SELECT 1 FROM public.audit_logs WHERE actor_user_id=u_d1
                 AND action='professional_identity.self_release'), NULL);
  BEGIN PERFORM public.professional_identity_self_release('again'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A4.D17 repeat abandonment is refused (no double release)',
        v_err = 'NO_ACTIVE_PROFESSIONAL_LANE', v_err);
  r := r || public._qa_s13_ok('N5A4.D18 abandonment did not silently claim the other lane',
        NOT EXISTS (SELECT 1 FROM public.professional_identities
                     WHERE user_id=u_d1 AND professional_type='merchant'), NULL);
  v_json := public.professional_identity_current();
  r := r || public._qa_s13_ok('N5A4.D19 the account is a plain customer again',
        v_json->>'professional_type' = 'none', v_json::text);

  -- ============ E. SAME-TYPE RE-ENTRY AFTER ABANDONMENT ============
  PERFORM public.driver_apply('{"vehicle_type":"toktok"}'::jsonb);
  r := r || public._qa_s13_ok('N5A4.E1 re-applying re-claims the DRIVER lane',
        (SELECT professional_type FROM public.professional_identities
          WHERE user_id=u_d1 AND claim_state='active') = 'driver', NULL);
  r := r || public._qa_s13_ok('N5A4.E2 re-entry creates a NEW identity row, it does not resurrect the released one',
        (SELECT count(*) FROM public.professional_identities WHERE user_id=u_d1) = 2, NULL);
  r := r || public._qa_s13_ok('N5A4.E3 exactly one row is active after re-entry',
        (SELECT count(*) FROM public.professional_identities WHERE user_id=u_d1 AND claim_state='active') = 1, NULL);
  r := r || public._qa_s13_ok('N5A4.E4 the released history row stays released',
        (SELECT count(*) FROM public.professional_identities WHERE user_id=u_d1 AND claim_state='released') = 1, NULL);
  r := r || public._qa_s13_ok('N5A4.E5 re-entry reset the driver profile to pending, not approved',
        (SELECT status::text FROM public.driver_profiles WHERE user_id=u_d1) = 'pending', NULL);
  BEGIN INSERT INTO public.merchants(owner_user_id, name) VALUES (u_d1,'QA A4 X'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A4.E6 abandonment did not open a back door to the other lane',
        v_err ILIKE '%PROFESSIONAL_IDENTITY_CONFLICT%', v_err);

  -- ============ F. APPROVED DRIVER CANNOT ABANDON ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d2), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', NULL, true);
  UPDATE public.driver_profiles SET status='approved' WHERE user_id=u_d2;
  UPDATE public.driver_applications SET decision='approved' WHERE user_id=u_d2;
  INSERT INTO public.user_roles(user_id,role) VALUES (u_d2,'driver') ON CONFLICT DO NOTHING;
  INSERT INTO public.wallets(owner_user_id, party_type) VALUES (u_d2,'driver') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d2), true);
  v_json := public.professional_identity_release_eligibility();
  r := r || public._qa_s13_ok('N5A4.F1 approved driver is not eligible to abandon',
        (v_json->>'eligible')::boolean IS FALSE, v_json::text);
  r := r || public._qa_s13_ok('N5A4.F2 approval is reported as a blocker',
        v_json->'blockers' ? 'DRIVER_ALREADY_APPROVED', v_json::text);
  r := r || public._qa_s13_ok('N5A4.F3 approved application is reported as a blocker',
        v_json->'blockers' ? 'DRIVER_APPLICATION_APPROVED', v_json::text);
  r := r || public._qa_s13_ok('N5A4.F4 granted driver role is reported as a blocker',
        v_json->'blockers' ? 'DRIVER_ROLE_GRANTED', v_json::text);
  r := r || public._qa_s13_ok('N5A4.F5 existing driver wallet is reported as a blocker',
        v_json->'blockers' ? 'DRIVER_WALLET_EXISTS', v_json::text);
  BEGIN PERFORM public.professional_identity_self_release('let me out'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A4.F6 approved driver self-release is refused',
        v_err ILIKE 'PROFESSIONAL_RELEASE_BLOCKED%', v_err);
  r := r || public._qa_s13_ok('N5A4.F7 refusal names the blockers', v_err ILIKE '%DRIVER_ALREADY_APPROVED%', v_err);
  r := r || public._qa_s13_ok('N5A4.F8 refused release left the lane active',
        (SELECT claim_state FROM public.professional_identities
          WHERE user_id=u_d2 ORDER BY claimed_at DESC LIMIT 1) = 'active', NULL);
  r := r || public._qa_s13_ok('N5A4.F9 refused release left the driver profile approved',
        (SELECT status::text FROM public.driver_profiles WHERE user_id=u_d2) = 'approved', NULL);
  r := r || public._qa_s13_ok('N5A4.F10 refused release left the application approved',
        (SELECT decision::text FROM public.driver_applications WHERE user_id=u_d2) = 'approved', NULL);
  r := r || public._qa_s13_ok('N5A4.F11 refused release left the driver role in place',
        EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_d2 AND role='driver'), NULL);
  r := r || public._qa_s13_ok('N5A4.F12 refused release wrote no audit success entry',
        NOT EXISTS (SELECT 1 FROM public.audit_logs WHERE actor_user_id=u_d2
                     AND action='professional_identity.self_release'), NULL);

  -- ============ G. OPERATIONAL HISTORY BLOCKS ABANDONMENT ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d3), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  v_json := public.professional_identity_release_eligibility();
  r := r || public._qa_s13_ok('N5A4.G1 pending driver with no history is eligible',
        (v_json->>'eligible')::boolean IS TRUE, v_json::text);
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    INSERT INTO public.missions(type, state, courier_id, customer_id)
    VALUES ('ride','assigned', u_d3, u_oth);
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A4.G2 mission-history fixture was created', v_err IS NULL, v_err);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d3), true);
  v_json := public.professional_identity_release_eligibility();
  r := r || public._qa_s13_ok('N5A4.G3 operational mission history blocks abandonment',
        (v_json->>'eligible')::boolean IS FALSE, v_json::text);
  r := r || public._qa_s13_ok('N5A4.G4 mission history is a named blocker',
        v_json->'blockers' ? 'DRIVER_HAS_MISSION_HISTORY', v_json::text);
  BEGIN PERFORM public.professional_identity_self_release(NULL); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A4.G5 driver with mission history cannot abandon',
        v_err ILIKE 'PROFESSIONAL_RELEASE_BLOCKED%', v_err);
  r := r || public._qa_s13_ok('N5A4.G6 blocked abandonment preserved the mission history',
        EXISTS (SELECT 1 FROM public.missions WHERE courier_id=u_d3), NULL);
  r := r || public._qa_s13_ok('N5A4.G7 blocked abandonment left the driver profile pending',
        (SELECT status::text FROM public.driver_profiles WHERE user_id=u_d3) = 'pending', NULL);

  -- ============ H. CLEAN MERCHANT ONBOARDING IS ABANDONABLE ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m1), true);
  INSERT INTO public.merchant_stores(owner_user_id, created_by, name, slug, status, onboarding_status)
  VALUES (u_m1, u_m1, 'QA A4 Store 1', 'qa-a4-store-1-'||substr(u_m1::text,1,8), 'pending','submitted')
  RETURNING id INTO v_store;
  r := r || public._qa_s13_ok('N5A4.H1 merchant onboarding claimed the MERCHANT lane',
        (SELECT professional_type FROM public.professional_identities
          WHERE user_id=u_m1 AND claim_state='active') = 'merchant', NULL);
  v_json := public.professional_identity_release_eligibility();
  r := r || public._qa_s13_ok('N5A4.H2 unfinished merchant onboarding is eligible for abandonment',
        (v_json->>'eligible')::boolean IS TRUE, v_json::text);
  v_json := public.professional_identity_self_release('wrong account');
  r := r || public._qa_s13_ok('N5A4.H3 merchant abandonment succeeds', (v_json->>'released')::boolean IS TRUE, v_json::text);
  r := r || public._qa_s13_ok('N5A4.H4 merchant lane is no longer active',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id=u_m1 AND claim_state='active'), NULL);
  r := r || public._qa_s13_ok('N5A4.H5 store row is archived, not deleted',
        (SELECT status FROM public.merchant_stores WHERE id=v_store) = 'archived', NULL);
  r := r || public._qa_s13_ok('N5A4.H6 store onboarding status is truthfully withdrawn',
        (SELECT onboarding_status FROM public.merchant_stores WHERE id=v_store) = 'withdrawn', NULL);
  r := r || public._qa_s13_ok('N5A4.H7 archived store is not approved',
        (SELECT approved_at IS NULL FROM public.merchant_stores WHERE id=v_store), NULL);
  r := r || public._qa_s13_ok('N5A4.H8 abandonment created no merchant payable',
        NOT EXISTS (SELECT 1 FROM public.merchant_payables WHERE merchant_store_id=v_store), NULL);
  r := r || public._qa_s13_ok('N5A4.H9 abandonment created no merchant wallet',
        NOT EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id=u_m1 AND party_type='merchant'), NULL);
  r := r || public._qa_s13_ok('N5A4.H10 merchant abandonment is audited',
        EXISTS (SELECT 1 FROM public.audit_logs WHERE actor_user_id=u_m1
                 AND action='professional_identity.self_release'), NULL);
  INSERT INTO public.merchant_stores(owner_user_id, created_by, name, slug, status, onboarding_status)
  VALUES (u_m1, u_m1, 'QA A4 Store 1b', 'qa-a4-store-1b-'||substr(u_m1::text,1,8), 'pending','submitted');
  r := r || public._qa_s13_ok('N5A4.H11 merchant re-entry re-claims the MERCHANT lane',
        (SELECT professional_type FROM public.professional_identities
          WHERE user_id=u_m1 AND claim_state='active') = 'merchant', NULL);
  r := r || public._qa_s13_ok('N5A4.H12 archived store history survived re-entry',
        (SELECT count(*) FROM public.merchant_stores WHERE owner_user_id=u_m1 AND status='archived') = 1, NULL);
  r := r || public._qa_s13_ok('N5A4.H13 only one non-archived store per owner remains enforced',
        (SELECT count(*) FROM public.merchant_stores WHERE owner_user_id=u_m1 AND status<>'archived') = 1, NULL);
  BEGIN
    INSERT INTO public.merchant_stores(owner_user_id, created_by, name, slug, status, onboarding_status)
    VALUES (u_m1, u_m1, 'QA A4 Store 1c', 'qa-a4-store-1c-'||substr(u_m1::text,1,8), 'pending','submitted');
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A4.H14 a second ACTIVE store for the same owner is still refused',
        v_err IS NOT NULL, v_err);

  -- ============ I. APPROVED MERCHANT CANNOT ABANDON ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m2), true);
  INSERT INTO public.merchant_stores(owner_user_id, created_by, name, slug, status, onboarding_status)
  VALUES (u_m2, u_m2, 'QA A4 Store 2', 'qa-a4-store-2-'||substr(u_m2::text,1,8), 'pending','submitted')
  RETURNING id INTO v_store;
  PERFORM set_config('request.jwt.claims', NULL, true);
  UPDATE public.merchant_stores SET status='active', onboarding_status='approved', approved_at=now()
   WHERE id=v_store;
  INSERT INTO public.user_roles(user_id,role) VALUES (u_m2,'merchant') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m2), true);
  v_json := public.professional_identity_release_eligibility();
  r := r || public._qa_s13_ok('N5A4.I1 approved merchant is not eligible to abandon',
        (v_json->>'eligible')::boolean IS FALSE, v_json::text);
  r := r || public._qa_s13_ok('N5A4.I2 store approval is a named blocker',
        v_json->'blockers' ? 'MERCHANT_STORE_APPROVED', v_json::text);
  r := r || public._qa_s13_ok('N5A4.I3 granted merchant role is a named blocker',
        v_json->'blockers' ? 'MERCHANT_ROLE_GRANTED', v_json::text);
  BEGIN PERFORM public.professional_identity_self_release(NULL); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A4.I4 approved merchant self-release is refused',
        v_err ILIKE 'PROFESSIONAL_RELEASE_BLOCKED%', v_err);
  r := r || public._qa_s13_ok('N5A4.I5 refused release left the store active',
        (SELECT status FROM public.merchant_stores WHERE id=v_store) = 'active', NULL);
  r := r || public._qa_s13_ok('N5A4.I6 refused release left the store approved',
        (SELECT onboarding_status FROM public.merchant_stores WHERE id=v_store) = 'approved', NULL);
  r := r || public._qa_s13_ok('N5A4.I7 refused release left the merchant lane active',
        (SELECT claim_state FROM public.professional_identities
          WHERE user_id=u_m2 ORDER BY claimed_at DESC LIMIT 1) = 'active', NULL);

  -- ============ J. RESTAURANT DEPENDENCY BLOCKS ABANDONMENT ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m3), true);
  INSERT INTO public.food_restaurants(owner_user_id, name, slug, status)
  VALUES (u_m3, 'QA A4 Resto', 'qa-a4-resto-'||substr(u_m3::text,1,8), 'active')
  RETURNING id INTO v_resto;
  v_json := public.professional_identity_release_eligibility();
  r := r || public._qa_s13_ok('N5A4.J1 active restaurant blocks abandonment',
        (v_json->>'eligible')::boolean IS FALSE, v_json::text);
  r := r || public._qa_s13_ok('N5A4.J2 active restaurant is a named blocker',
        v_json->'blockers' ? 'MERCHANT_RESTAURANT_ACTIVE', v_json::text);
  BEGIN PERFORM public.professional_identity_self_release(NULL); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A4.J3 merchant with an active restaurant cannot abandon',
        v_err ILIKE 'PROFESSIONAL_RELEASE_BLOCKED%', v_err);
  r := r || public._qa_s13_ok('N5A4.J4 blocked abandonment preserved the restaurant',
        (SELECT status FROM public.food_restaurants WHERE id=v_resto) = 'active', NULL);

  -- ============ K. CROSS-USER AUTHORITY ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_oth), true);
  BEGIN v_json := public.professional_identity_release_eligibility(u_d2); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A4.K1 a customer cannot read another account eligibility',
        v_err = 'NOT_AUTHORIZED', v_err);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  BEGIN v_json := public.professional_identity_release_eligibility(u_d2); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A4.K2 operations admin can read another account eligibility', v_err IS NULL, v_err);
  r := r || public._qa_s13_ok('N5A4.K3 admin read is the same fail-closed truth',
        (v_json->>'eligible')::boolean IS FALSE, v_json::text);
  r := r || public._qa_s13_ok('N5A4.K4 admin read cannot release anything on its own',
        (SELECT claim_state FROM public.professional_identities
          WHERE user_id=u_d2 ORDER BY claimed_at DESC LIMIT 1) = 'active', NULL);

  -- ============ L. RELEASE vs APPROVAL RACE ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d1), true);
  PERFORM public.professional_identity_self_release('race setup');
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    UPDATE public.driver_profiles SET status='approved' WHERE user_id=u_d1;
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A4.L1 a driver approval after lane release is refused',
        v_err ILIKE '%PROFESSIONAL_LANE_RELEASED%', v_err);
  r := r || public._qa_s13_ok('N5A4.L2 refused approval left the profile withdrawn',
        (SELECT status::text FROM public.driver_profiles WHERE user_id=u_d1) = 'withdrawn', NULL);
  r := r || public._qa_s13_ok('N5A4.L3 refused approval granted no driver role',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_d1 AND role='driver'), NULL);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m4), true);
  INSERT INTO public.merchant_stores(owner_user_id, created_by, name, slug, status, onboarding_status)
  VALUES (u_m4, u_m4, 'QA A4 Store 4', 'qa-a4-store-4-'||substr(u_m4::text,1,8), 'pending','submitted')
  RETURNING id INTO v_store4;
  PERFORM public.professional_identity_self_release('race setup merchant');
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    UPDATE public.merchant_stores SET status='active', onboarding_status='approved' WHERE id=v_store4;
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A4.L4 an archived store cannot be approved without a held lane',
        v_err ILIKE '%PROFESSIONAL_LANE_RELEASED%', v_err);
  r := r || public._qa_s13_ok('N5A4.L5 refused approval left the store archived',
        (SELECT status FROM public.merchant_stores WHERE id=v_store4) = 'archived', NULL);
  r := r || public._qa_s13_ok('N5A4.L6 refused approval left the onboarding status withdrawn',
        (SELECT onboarding_status FROM public.merchant_stores WHERE id=v_store4) = 'withdrawn', NULL);
  r := r || public._qa_s13_ok('N5A4.L7 the lane remains the single source of professional truth',
        (SELECT count(*) FROM public.professional_identities
          WHERE user_id IN (u_d1,u_m4) AND claim_state='active') = 0, NULL);

  -- ============ M. GLOBAL INVARIANTS ============
  SELECT count(*) INTO v_n FROM (
    SELECT user_id FROM public.professional_identities WHERE claim_state='active'
    GROUP BY user_id HAVING count(*) > 1) s;
  r := r || public._qa_s13_ok('N5A4.M1 no user holds more than one ACTIVE professional lane', v_n = 0, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.driver_profiles dp
   WHERE dp.status IN ('approved','suspended')
     AND NOT EXISTS (SELECT 1 FROM public.professional_identities pi
                      WHERE pi.user_id=dp.user_id AND pi.claim_state='active' AND pi.professional_type='driver');
  r := r || public._qa_s13_ok('N5A4.M2 every operational driver still holds an active driver lane', v_n = 0, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.merchant_stores ms
   WHERE ms.status IN ('active','suspended','paused') AND ms.owner_user_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.professional_identities pi
                      WHERE pi.user_id=ms.owner_user_id AND pi.claim_state='active' AND pi.professional_type='merchant');
  r := r || public._qa_s13_ok('N5A4.M3 every operational store owner still holds an active merchant lane', v_n = 0, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.professional_identities
   WHERE claim_state='released' AND released_at IS NULL;
  r := r || public._qa_s13_ok('N5A4.M4 every released lane carries a release timestamp', v_n = 0, 'n='||v_n);

  -- ============ N. CLEANUP + NON-DRIFT ============
  PERFORM set_config('request.jwt.claims', NULL, true);
  PERFORM public._qa_a4_cleanup(ids);

  SELECT count(*) INTO a_pr FROM public.profiles;
  a_au := public._qa_auth_user_count();
  SELECT count(*) INTO a_ur FROM public.user_roles;
  SELECT count(*) INTO a_w  FROM public.wallets;
  SELECT count(*) INTO a_wt FROM public.wallet_transactions;
  SELECT count(*) INTO a_lp FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO a_ls FROM public.ledger_postings;
  SELECT count(*) INTO a_dp FROM public.driver_profiles;
  SELECT count(*) INTO a_da FROM public.driver_applications;
  SELECT count(*) INTO a_ms FROM public.merchant_stores;
  SELECT count(*) INTO a_fr FROM public.food_restaurants;
  SELECT count(*) INTO a_me FROM public.merchants;
  SELECT count(*) INTO a_pi FROM public.professional_identities;
  SELECT count(*) INTO a_pia FROM public.professional_identities WHERE claim_state='active';
  SELECT count(*) INTO a_al FROM public.audit_logs;
  SELECT count(*) INTO a_mo FROM public.marche_orders;
  SELECT count(*) INTO a_fo FROM public.food_orders;
  SELECT count(*) INTO a_ml FROM public.marketplace_listings;
  SELECT count(*) INTO a_mi FROM public.missions;
  SELECT count(*) INTO a_ad FROM public.admin_users;
  SELECT jsonb_object_agg(key, enabled) INTO a_flags FROM public.feature_flags;

  r := r || public._qa_s13_ok('N5A4.N1 QA fixtures fully purged from auth', a_au = b_au, b_au||'->'||a_au);
  r := r || public._qa_s13_ok('N5A4.N2 profiles unchanged', a_pr = b_pr, b_pr||'->'||a_pr);
  r := r || public._qa_s13_ok('N5A4.N3 user_roles unchanged', a_ur = b_ur, b_ur||'->'||a_ur);
  r := r || public._qa_s13_ok('N5A4.N4 wallets unchanged', a_w = b_w, b_w||'->'||a_w);
  r := r || public._qa_s13_ok('N5A4.N5 wallet_transactions unchanged', a_wt = b_wt, b_wt||'->'||a_wt);
  r := r || public._qa_s13_ok('N5A4.N6 ledger_postings unchanged', a_lp = b_lp, b_lp||'->'||a_lp);
  r := r || public._qa_s13_ok('N5A4.N7 ledger balance sum unchanged', a_ls = b_ls, b_ls||'->'||a_ls);
  r := r || public._qa_s13_ok('N5A4.N8 driver_profiles unchanged', a_dp = b_dp, b_dp||'->'||a_dp);
  r := r || public._qa_s13_ok('N5A4.N9 driver_applications unchanged', a_da = b_da, b_da||'->'||a_da);
  r := r || public._qa_s13_ok('N5A4.N10 merchant_stores unchanged', a_ms = b_ms, b_ms||'->'||a_ms);
  r := r || public._qa_s13_ok('N5A4.N11 food_restaurants unchanged', a_fr = b_fr, b_fr||'->'||a_fr);
  r := r || public._qa_s13_ok('N5A4.N12 merchants unchanged', a_me = b_me, b_me||'->'||a_me);
  r := r || public._qa_s13_ok('N5A4.N13 professional_identities returned to baseline', a_pi = b_pi, b_pi||'->'||a_pi);
  r := r || public._qa_s13_ok('N5A4.N14 active professional census unchanged', a_pia = b_pia, b_pia||'->'||a_pia);
  r := r || public._qa_s13_ok('N5A4.N15 audit_logs returned to baseline', a_al = b_al, b_al||'->'||a_al);
  r := r || public._qa_s13_ok('N5A4.N16 Marché orders unchanged', a_mo = b_mo, b_mo||'->'||a_mo);
  r := r || public._qa_s13_ok('N5A4.N17 Repas orders unchanged', a_fo = b_fo, b_fo||'->'||a_fo);
  r := r || public._qa_s13_ok('N5A4.N18 marketplace listings unchanged', a_ml = b_ml, b_ml||'->'||a_ml);
  r := r || public._qa_s13_ok('N5A4.N19 missions unchanged', a_mi = b_mi, b_mi||'->'||a_mi);
  r := r || public._qa_s13_ok('N5A4.N20 admin_users unchanged', a_ad = b_ad, b_ad||'->'||a_ad);
  r := r || public._qa_s13_ok('N5A4.N21 feature flags unchanged', a_flags = b_flags, NULL);
  r := r || public._qa_s13_ok('N5A4.N22 no QA residue in professional_identities',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id = ANY(ids)), NULL);

  RETURN jsonb_build_object(
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'failures', (SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(r) e
                  WHERE (e->>'ok')::boolean IS NOT TRUE)
  );
EXCEPTION WHEN others THEN
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN PERFORM public._qa_a4_cleanup(ids); EXCEPTION WHEN others THEN NULL; END;
  RAISE;
END $function$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_a4() FROM PUBLIC, anon, authenticated;