
DO $mig$
DECLARE d text; o text; n text;
BEGIN
  -- 1. conflict scanner: closed accounts are governed by closure law, not lane law
  d := pg_get_functiondef('public._professional_conflict_scan()'::regprocedure);
  o := $a$  UNION SELECT user_id FROM public.user_roles WHERE role::text IN ('driver','merchant')
),$a$;
  n := $a$  UNION SELECT user_id FROM public.user_roles WHERE role::text IN ('driver','merchant')
),
subj_live AS (
  SELECT s.user_id FROM subj s
  LEFT JOIN public.profiles p ON p.user_id = s.user_id
  WHERE p.account_status IS DISTINCT FROM 'deleted'
),$a$;
  IF position(o in d)=0 THEN RAISE EXCEPTION 'scan anchor missing'; END IF;
  d := replace(d, o, n);
  d := replace(d, '  FROM subj s
),', '  FROM subj_live s
),');
  EXECUTE d;

  -- 2. A2 derivation sets exclude closed accounts
  d := pg_get_functiondef('public._qa_node5_identity_a2()'::regprocedure);
  o := $a$  SELECT count(*) INTO d_set FROM _qa_a2_drv;$a$;
  n := $a$  DELETE FROM _qa_a2_drv t USING public.profiles p
   WHERE p.user_id = t.user_id AND p.account_status = 'deleted';
  DELETE FROM _qa_a2_mer t USING public.profiles p
   WHERE p.user_id = t.user_id AND p.account_status = 'deleted';
  SELECT count(*) INTO d_set FROM _qa_a2_drv;$a$;
  IF position(o in d)=0 THEN RAISE EXCEPTION 'a2 anchor missing'; END IF;
  EXECUTE replace(d, o, n);

  -- 3. A4.M2 / M3 scope to live accounts
  d := pg_get_functiondef('public._qa_node5_identity_a4()'::regprocedure);
  o := $a$  SELECT count(*) INTO v_n FROM public.driver_profiles dp
   WHERE dp.status IN ('approved','suspended')
     AND NOT EXISTS$a$;
  n := $a$  SELECT count(*) INTO v_n FROM public.driver_profiles dp
   WHERE dp.status IN ('approved','suspended')
     AND NOT EXISTS (SELECT 1 FROM public.profiles cp
                      WHERE cp.user_id=dp.user_id AND cp.account_status='deleted')
     AND NOT EXISTS$a$;
  IF position(o in d)=0 THEN RAISE EXCEPTION 'a4 anchor missing'; END IF;
  EXECUTE replace(d, o, n);

  -- 4. A5.K1 / K5 scope to live accounts
  d := pg_get_functiondef('public._qa_node5_identity_a5()'::regprocedure);
  o := $a$  SELECT count(*) INTO v_n FROM public.driver_profiles dp
   WHERE COALESCE(array_length(dp.capabilities,1),0) > 0
     AND NOT EXISTS$a$;
  n := $a$  SELECT count(*) INTO v_n FROM public.driver_profiles dp
   WHERE COALESCE(array_length(dp.capabilities,1),0) > 0
     AND NOT EXISTS (SELECT 1 FROM public.profiles cp
                      WHERE cp.user_id=dp.user_id AND cp.account_status='deleted')
     AND NOT EXISTS$a$;
  IF position(o in d)=0 THEN RAISE EXCEPTION 'a5 anchor missing'; END IF;
  d := replace(d, o, n);
  o := $a$  SELECT count(*) INTO v_n FROM public.driver_profiles dp
   WHERE dp.status='approved'
     AND NOT EXISTS$a$;
  n := $a$  SELECT count(*) INTO v_n FROM public.driver_profiles dp
   WHERE dp.status='approved'
     AND NOT EXISTS (SELECT 1 FROM public.profiles cp
                      WHERE cp.user_id=dp.user_id AND cp.account_status='deleted')
     AND NOT EXISTS$a$;
  IF position(o in d)=0 THEN RAISE EXCEPTION 'a5 k5 anchor missing'; END IF;
  EXECUTE replace(d, o, n);

  -- 5. A10.L6 scopes to live accounts
  d := pg_get_functiondef('public._qa_node5_identity_a10()'::regprocedure);
  o := $a$        NOT EXISTS (SELECT 1 FROM public.driver_profiles d
                     WHERE d.status::text IN ('pending','approved','suspended')
                       AND public.professional_active_type(d.user_id) IS DISTINCT FROM 'driver'), NULL);$a$;
  n := $a$        NOT EXISTS (SELECT 1 FROM public.driver_profiles d
                     WHERE d.status::text IN ('pending','approved','suspended')
                       AND NOT EXISTS (SELECT 1 FROM public.profiles cp
                                        WHERE cp.user_id=d.user_id AND cp.account_status='deleted')
                       AND public.professional_active_type(d.user_id) IS DISTINCT FROM 'driver'), NULL);$a$;
  IF position(o in d)=0 THEN RAISE EXCEPTION 'a10 anchor missing'; END IF;
  EXECUTE replace(d, o, n);
END $mig$;
