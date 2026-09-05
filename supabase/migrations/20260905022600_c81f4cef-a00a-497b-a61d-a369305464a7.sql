DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node5_identity_a2';
  d := replace(d,
$x$  SELECT count(*) INTO v_n FROM public.professional_identities
   WHERE claim_state='active' AND claim_source='a2_backfill';
  r := r || public._qa_s13_ok('N5A2.B4 backfilled active identity count equals live derivation',
        v_n = d_set + m_set, 'backfilled='||v_n||' derived='||(d_set+m_set));$x$,
$x$  SELECT count(*) INTO v_n FROM public.professional_identities
   WHERE claim_state='active';
  r := r || public._qa_s13_ok('N5A2.B4 active identity count equals live derivation',
        v_n = d_set + m_set, 'active='||v_n||' derived='||(d_set+m_set));$x$);
  EXECUTE d;
END $$;