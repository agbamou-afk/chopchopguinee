REVOKE ALL ON FUNCTION public.marche_reputation_submit(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_reputation_eligibility(text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._marche_reputation_immutable() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marche_reputation_submit(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_reputation_eligibility(text, uuid) TO authenticated;

DO $do$
DECLARE src text;
BEGIN
  src := pg_get_functiondef('public._qa_node4_marche_r9()'::regprocedure);

  src := replace(src,
'    SELECT COALESCE(sum(held_gnf),0) INTO v_held0 FROM public.wallets;
    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_buy2), true);',
'    SELECT COALESCE(sum(held_gnf),0) INTO v_held0 FROM public.wallets;
    SELECT count(*) INTO v_obs0 FROM public.marche_procurement_price_observations;
    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_buy2), true);');

  src := replace(src,
'      v_obs1 = v_obs0 + 1, format(''%s->%s'', v_obs0, v_obs1));',
'      v_obs1 = v_obs0, format(''%s->%s'', v_obs0, v_obs1));');

  IF src LIKE '%v_obs0 + 1%' THEN RAISE EXCEPTION 'R9_HARNESS_PATCH_FAILED'; END IF;
  EXECUTE src;
END $do$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r9() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r9() TO service_role;