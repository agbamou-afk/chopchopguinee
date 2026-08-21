DO $mig$
DECLARE def text;
BEGIN
  -- 1. closure core: merchant_stores has no is_active column
  SELECT pg_get_functiondef(oid) INTO def
    FROM pg_proc WHERE oid = 'public._account_closure_core(uuid,text,text)'::regprocedure;
  def := replace(def,
    'UPDATE public.merchant_stores SET status=''suspended'', is_active=false, updated_at=now()',
    'UPDATE public.merchant_stores SET status=''suspended'', updated_at=now()');
  IF position('is_active' in def) > 0 THEN RAISE EXCEPTION 'core patch failed'; END IF;
  EXECUTE def;

  -- 2. suite fixture + assertion
  SELECT pg_get_functiondef(oid) INTO def
    FROM pg_proc WHERE oid = 'public._qa_node5_identity_a14()'::regprocedure;
  def := replace(def,
    'INSERT INTO public.merchant_stores(id, owner_user_id, slug, name, status, is_active)
  VALUES (s_m, u_m, ''qa-n5a14-''||substr(s_m::text,1,8), ''QA A14 Store'',''active'',true);',
    'INSERT INTO public.merchant_stores(id, owner_user_id, slug, name, status)
  VALUES (s_m, u_m, ''qa-n5a14-''||substr(s_m::text,1,8), ''QA A14 Store'',''active'');');
  def := replace(def,
    '        (SELECT is_active FROM public.merchant_stores WHERE id = s_m) IS FALSE, NULL);',
    '        (SELECT status FROM public.merchant_stores WHERE id = s_m) <> ''active'', NULL);');
  IF position('is_active' in def) > 0 THEN RAISE EXCEPTION 'suite patch failed'; END IF;
  EXECUTE def;
END
$mig$;

REVOKE ALL ON FUNCTION public._account_closure_core(uuid,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._account_closure_core(uuid,text,text) TO service_role;
REVOKE ALL ON FUNCTION public._qa_node5_identity_a14() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_identity_a14() TO service_role;
