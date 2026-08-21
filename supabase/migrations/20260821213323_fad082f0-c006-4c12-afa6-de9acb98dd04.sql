
DO $mig$
DECLARE d text; o text; n text;
BEGIN
  d := pg_get_functiondef('public._qa_node5_identity_final_remediation()'::regprocedure);

  o := $a$  r := r || public._qa_s13_ok('N5FR.B2 fixture legacy driver really holds capability roles',
        (SELECT count(*) FROM public.user_roles WHERE user_id=u_d) = 2, NULL);$a$;
  n := $a$  r := r || public._qa_s13_ok('N5FR.B2 fixture legacy driver really holds capability roles',
        EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_d AND role='driver')
        AND (SELECT count(*) FROM public.user_roles WHERE user_id=u_d) >= 2,
        (SELECT string_agg(role::text,',' ORDER BY role::text) FROM public.user_roles WHERE user_id=u_d));$a$;
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'B2 anchor missing'; END IF;
  d := replace(d, o, n);

  o := $a$  SELECT balance_gnf INTO v_bal FROM public.wallets WHERE owner_user_id=u_fin;$a$;
  n := $a$  SELECT balance_gnf INTO v_bal FROM public.wallets WHERE owner_user_id=u_fin AND party_type='driver';$a$;
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'F anchor missing'; END IF;
  d := replace(d, o, n);

  o := $a$  r := r || public._qa_s13_ok('N5FR.I3 the successor inherits no capability role',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_re), NULL);
  r := r || public._qa_s13_ok('N5FR.I4 the successor inherits no wallet or balance',
        NOT EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id=u_re), NULL);$a$;
  n := $a$  r := r || public._qa_s13_ok('N5FR.I3 the successor inherits no professional or governance role',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_re AND role::text <> 'client')
        AND NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id=u_re)
        AND EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_re AND role::text = 'client'),
        (SELECT string_agg(role::text,',' ORDER BY role::text) FROM public.user_roles WHERE user_id=u_re));
  r := r || public._qa_s13_ok('N5FR.I4 the successor owns only its own empty bootstrap wallet',
        (SELECT count(*) FROM public.wallets WHERE owner_user_id=u_re) = 1
        AND (SELECT balance_gnf + held_gnf FROM public.wallets
              WHERE owner_user_id=u_re AND party_type='client') = 0
        AND NOT EXISTS (SELECT 1 FROM public.wallet_transactions
                         WHERE related_user_id=u_re
                            OR from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id=u_re)
                            OR to_wallet_id   IN (SELECT id FROM public.wallets WHERE owner_user_id=u_re)),
        NULL);$a$;
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'I anchor missing'; END IF;
  d := replace(d, o, n);

  EXECUTE d;
END $mig$;

REVOKE EXECUTE ON FUNCTION public._qa_node5_identity_final_remediation() FROM anon, authenticated, PUBLIC;
GRANT  EXECUTE ON FUNCTION public._qa_node5_identity_final_remediation() TO service_role;
