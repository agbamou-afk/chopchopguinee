
DO $mig$
DECLARE v_src text; v_new text; v_old text; v_rep text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid='public._qa_s13_run2()'::regprocedure;

  v_old := $o$    BEGIN
      UPDATE public.profiles SET phone = '622000111' WHERE user_id = v_d2;
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A9.4b canonical phone uniqueness refuses duplicate identity at write time',
      v_err <> 'NO_ERROR', v_err);
    UPDATE public.profiles SET phone = '622000112' WHERE user_id = v_d2;
    v_res := public.driver_starter_credit_grant(v_d2);
    r := r || public._qa_s13_ok('A9.5 duplicate identity can no longer exist; grant proceeds on canonical identity',
      v_res->>'status' = 'needs_review' AND COALESCE((v_res->>'granted_gnf')::bigint,0) = 0, v_res::text);
    SELECT count(*) INTO v_n FROM public.driver_promo_credits WHERE driver_user_id = v_d2;
    r := r || public._qa_s13_ok('A9.6 canonical phone uniqueness holds across all profiles', v_n = 0, v_n::text);$o$;

  v_rep := $n$    -- Post-A13 law: a phone number is a mutable contact attribute, never an
    -- identity key. The second fixture account may not take the first account's
    -- canonical phone, and must inherit nothing from it.
    BEGIN
      UPDATE public.profiles SET phone = '622000111' WHERE user_id = v_d2;
      v_err := 'NO_ERROR';
    EXCEPTION
      WHEN unique_violation THEN v_err := 'UNIQUE_REFUSED';
      WHEN OTHERS THEN v_err := SQLSTATE || ':' || SQLERRM;
    END;
    r := r || public._qa_s13_ok(
      'A9.4b duplicate canonical phone assignment to fixture account 2 refused at write time (unique_violation)',
      v_err = 'UNIQUE_REFUSED', v_err);

    BEGIN
      UPDATE public.profiles SET phone = '12345' WHERE user_id = v_d2;
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
    END;
    r := r || public._qa_s13_ok(
      'A9.4c invalid phone input on fixture account 2 rejected with INVALID_PHONE',
      v_err = 'INVALID_PHONE', v_err);

    UPDATE public.profiles SET phone = '00224 622 000 112' WHERE user_id = v_d2;
    r := r || public._qa_s13_ok(
      'A9.5 fixture pair holds distinct canonical phones after refusal (+224622000111 / +224622000112)',
      (SELECT p.phone FROM public.profiles p WHERE p.user_id = v_d1) = '+224622000111'
      AND (SELECT p.phone FROM public.profiles p WHERE p.user_id = v_d2) = '+224622000112',
      COALESCE((SELECT p.phone FROM public.profiles p WHERE p.user_id = v_d1),'null') || ' | ' ||
      COALESCE((SELECT p.phone FROM public.profiles p WHERE p.user_id = v_d2),'null'));

    r := r || public._qa_s13_ok(
      'A9.6 fixture account 2 inherits no identity: each canonical phone resolves only to its own account',
      (SELECT p.user_id FROM public.profiles p WHERE p.phone = '+224622000111') = v_d1
      AND (SELECT p.user_id FROM public.profiles p WHERE p.phone = '+224622000112') = v_d2
      AND (SELECT count(*) FROM public.profiles p
             WHERE p.user_id IN (v_d1, v_d2) AND p.phone = '+224622000111') = 1,
      COALESCE((SELECT p.user_id::text FROM public.profiles p WHERE p.phone = '+224622000111'),'null') || ' | ' ||
      COALESCE((SELECT p.user_id::text FROM public.profiles p WHERE p.phone = '+224622000112'),'null'));$n$;

  IF position(v_old in v_src) = 0 THEN RAISE EXCEPTION 'S13_PATCH_NO_MATCH'; END IF;
  v_new := replace(v_src, v_old, v_rep);
  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public._qa_s13_run2() RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''public'' SET statement_timeout TO ''300s'' AS %L',
    v_new);
END $mig$;
REVOKE ALL ON FUNCTION public._qa_s13_run2() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s13_run2() TO service_role;
