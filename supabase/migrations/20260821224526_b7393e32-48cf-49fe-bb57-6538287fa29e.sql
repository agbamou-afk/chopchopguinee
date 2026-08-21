DO $mig$
DECLARE d text; old_t text; new_t text;
BEGIN
  -- 1. final remediation suite: F2 now expresses the dormant-liability law
  d := pg_get_functiondef('public._qa_node5_identity_final_remediation()'::regprocedure);
  old_t := $o$  r := r || public._qa_s13_ok('N5FR.F2 a nonzero balance still blocks full closure',
        (res->'blockers') @> '["WALLET_BALANCE_NONZERO"]'::jsonb
        AND (res->>'eligible')::boolean IS FALSE, res::text);$o$;
  new_t := $n$  r := r || public._qa_s13_ok('N5FR.F2 a positive residual balance is preserved as dormant liability, not a closure blocker',
        (res->'blockers') @> '["WALLET_BALANCE_NONZERO"]'::jsonb IS FALSE
        AND (res->>'eligible')::boolean IS TRUE, res::text);$n$;
  IF position(old_t in d) = 0 THEN RAISE EXCEPTION 'F2 anchor not found'; END IF;
  d := replace(d, old_t, new_t);
  EXECUTE d;

  -- 2. A14 suite: purge fixture liability rows before fixture wallets
  d := pg_get_functiondef('public._qa_node5_identity_a14()'::regprocedure);
  old_t := 'DELETE FROM public.wallets WHERE owner_user_id = ANY(ids);';
  new_t := 'DELETE FROM public.dormant_closed_account_liabilities WHERE user_id = ANY(ids); '
           || 'DELETE FROM public.wallets WHERE owner_user_id = ANY(ids);';
  IF position(old_t in d) = 0 THEN RAISE EXCEPTION 'A14 anchor not found'; END IF;
  d := replace(d, old_t, new_t);
  EXECUTE d;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_final_remediation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_node5_identity_a14() FROM PUBLIC, anon, authenticated;
