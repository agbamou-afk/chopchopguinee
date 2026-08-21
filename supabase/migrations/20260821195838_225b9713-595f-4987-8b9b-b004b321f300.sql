DO $mig$
DECLARE def text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO def
    FROM pg_proc WHERE oid = 'public._qa_node5_identity_a14()'::regprocedure;

  def := replace(def,
'  r := r || public._qa_s13_ok(''N5A14.F4 the successor inherits no capability roles'',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = u_re), NULL);',
'  r := r || public._qa_s13_ok(''N5A14.F4 the successor inherits no professional capability role'',
        NOT EXISTS (SELECT 1 FROM public.user_roles
                     WHERE user_id = u_re
                       AND role <> ''client''::public.app_role), NULL);');

  def := replace(def,
'  r := r || public._qa_s13_ok(''N5A14.F7 the successor inherits no wallet from the closed account'',
        NOT EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id = u_re), NULL);',
'  r := r || public._qa_s13_ok(''N5A14.F7 the successor inherits no wallet from the closed account'',
        NOT EXISTS (SELECT 1 FROM public.wallets w1
                    JOIN public.wallets w2 ON w1.id = w2.id
                     WHERE w1.owner_user_id = u_re AND w2.owner_user_id = u_d)
        AND NOT EXISTS (SELECT 1 FROM public.wallets
                         WHERE owner_user_id = u_re
                           AND party_type = ''driver''::public.party_type), NULL);');

  def := replace(def,
'  r := r || public._qa_s13_ok(''N5A14.G4 an account with no history at all is not falsely flagged'',
        NOT public.user_has_financial_history(u_re), NULL);',
'  r := r || public._qa_s13_ok(''N5A14.G4 a uuid with no records at all is not falsely flagged'',
        NOT public.user_has_financial_history(gen_random_uuid()), NULL);
  r := r || public._qa_s13_ok(''N5A14.G5 a brand-new account is flagged only by its own bootstrap wallet'',
        public.user_has_financial_history(u_re)
        AND EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id = u_re), NULL);');

  IF position('N5A14.G5' in def) = 0 THEN RAISE EXCEPTION 'patch failed'; END IF;
  EXECUTE def;
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_a14() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_identity_a14() TO service_role;
