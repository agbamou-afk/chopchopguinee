DO $mig$
DECLARE def text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO def
    FROM pg_proc WHERE oid = 'public._qa_s13_run7_fxcore()'::regprocedure;

  def := replace(def,
'    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_god), true);
    v_probe := public.admin_anonymize_user(v_c2, ''qa s13 p7 god admin'');',
'    -- A14: closure is fail-closed on outstanding obligations, so the fixture
    -- settles its own money before proving the governance closure path.
    PERFORM set_config(''request.jwt.claims'','''',true);
    UPDATE public.wallets SET balance_gnf = 0, held_gnf = 0 WHERE owner_user_id = v_c2;
    UPDATE public.topup_requests SET status = ''cancelled''
     WHERE (client_user_id = v_c2 OR agent_user_id = v_c2)
       AND status IN (''pending'',''matched'',''needs_review'');
    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_god), true);
    v_probe := public.admin_anonymize_user(v_c2, ''qa s13 p7 god admin'');');

  IF position('A14: closure is fail-closed' in def) = 0 THEN
    RAISE EXCEPTION 'patch failed';
  END IF;
  EXECUTE def;
END
$mig$;
