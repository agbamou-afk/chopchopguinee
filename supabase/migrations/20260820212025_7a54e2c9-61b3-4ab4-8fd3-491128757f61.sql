DO $do$
DECLARE src text; new_src text;
BEGIN
  src := pg_get_functiondef('public._qa_node5_identity_a2()'::regprocedure);
  new_src := replace(src,
$old$  DELETE FROM public.professional_identities WHERE user_id = ANY(ids);
  DELETE FROM public.wallet_transactions WHERE wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(ids));
  DELETE FROM public.wallets WHERE owner_user_id = ANY(ids);
  DELETE FROM public.user_roles WHERE user_id = ANY(ids);
  PERFORM public._qa_users_purge(ids);$old$,
$new$  PERFORM public._qa_a2_cleanup(ids);$new$);

  IF new_src = src THEN
    RAISE EXCEPTION 'A2_QA_PATCH_TARGET_NOT_FOUND';
  END IF;
  EXECUTE new_src;
END $do$;