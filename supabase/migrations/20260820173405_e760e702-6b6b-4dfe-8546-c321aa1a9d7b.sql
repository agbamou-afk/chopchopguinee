DO $mig$
DECLARE
  v_src text;
  v_new text;
BEGIN
  -- R3.5
  SELECT pg_get_functiondef(oid) INTO v_src FROM pg_proc
   WHERE proname = '_qa_node4_marche_r35' AND pronamespace = 'public'::regnamespace;
  IF position('DELETE FROM auth.users WHERE id IN (v_buy,v_merch,v_adm);' IN v_src) = 0 THEN
    RAISE EXCEPTION 'QA_FIX_PATTERN_NOT_FOUND_R35';
  END IF;
  v_new := replace(v_src,
    'DELETE FROM auth.users WHERE id IN (v_buy,v_merch,v_adm);',
    'PERFORM public._qa_users_purge(ARRAY[v_buy,v_merch,v_adm]);');
  EXECUTE v_new;

  -- R5
  SELECT pg_get_functiondef(oid) INTO v_src FROM pg_proc
   WHERE proname = '_qa_node4_marche_r5' AND pronamespace = 'public'::regnamespace;
  IF position('DELETE FROM auth.users WHERE id IN (v_buy,v_merch,v_merch2,v_other,v_adm,v_drv,v_drv2);' IN v_src) = 0 THEN
    RAISE EXCEPTION 'QA_FIX_PATTERN_NOT_FOUND_R5';
  END IF;
  v_new := replace(v_src,
    'DELETE FROM auth.users WHERE id IN (v_buy,v_merch,v_merch2,v_other,v_adm,v_drv,v_drv2);',
    'PERFORM public._qa_users_purge(ARRAY[v_buy,v_merch,v_merch2,v_other,v_adm,v_drv,v_drv2]);');
  EXECUTE v_new;
END $mig$;

select public._qa_users_purge(array(
  select p.user_id from public.profiles p
  where not exists (select 1 from auth.users u where u.id = p.user_id)
    and p.created_at >= '2026-08-20 17:30:00+00'
    and p.email like '%@qa.invalid'
));