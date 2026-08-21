DO $mig$
DECLARE d text; o text; n text;
  PROCEDURE_MISSING boolean;
BEGIN
  d := pg_get_functiondef('public._qa_node5_identity_a14()'::regprocedure);

  -- 1) B2/B3: positive available balance is dormant liability, not a blocker
  o := $o$  r := r || public._qa_s13_ok('N5A14.B2 remaining wallet money blocks closure',
        bl->'blockers' @> '["WALLET_BALANCE_NONZERO"]'::jsonb, bl::text);
  r := r || public._qa_s13_ok('N5A14.B3 a blocked account is not reported eligible',
        (bl->>'eligible')::boolean IS FALSE, bl::text);$o$;
  n := $n$  r := r || public._qa_s13_ok('N5A14.B2 a positive spendable balance is preserved as dormant liability, never a closure blocker',
        NOT (bl->'blockers' @> '["WALLET_BALANCE_NONZERO"]'::jsonb), bl::text);
  r := r || public._qa_s13_ok('N5A14.B3 an account whose only residue is a positive balance stays closure-eligible',
        (bl->>'eligible')::boolean IS TRUE, bl::text);$n$;
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'anchor B2/B3 not found'; END IF;
  d := replace(d, o, n);

  -- 2) the fail-closed probe now uses held funds (a real current blocker)
  o := '  UPDATE public.wallets SET balance_gnf = 7000 WHERE owner_user_id = u_d';
  n := '  UPDATE public.wallets SET held_gnf = 7000 WHERE owner_user_id = u_d';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'anchor held probe not found'; END IF;
  d := replace(d, o, n);

  o := $o$        v_txt LIKE '%WALLET_BALANCE_NONZERO%', v_txt);$o$;
  n := $n$        v_txt LIKE '%WALLET_FUNDS_HELD%', v_txt);$n$;
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'anchor C2 not found'; END IF;
  d := replace(d, o, n);

  o := $o$  r := r || public._qa_s13_ok('N5A14.C7 a blocked closure did not touch the money',
        (SELECT balance_gnf FROM public.wallets WHERE owner_user_id = u_d AND party_type='driver'::public.party_type) = 7000, NULL);$o$;
  n := $n$  r := r || public._qa_s13_ok('N5A14.C7 a blocked closure did not touch the money',
        (SELECT held_gnf FROM public.wallets WHERE owner_user_id = u_d AND party_type='driver'::public.party_type) = 7000, NULL);$n$;
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'anchor C7 not found'; END IF;
  d := replace(d, o, n);

  o := $o$        res->'blockers' @> '["WALLET_BALANCE_NONZERO"]'::jsonb, res::text);$o$;
  n := $n$        res->'blockers' @> '["WALLET_FUNDS_HELD"]'::jsonb, res::text);$n$;
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'anchor C11 not found'; END IF;
  d := replace(d, o, n);

  -- 3) closure now proceeds WITH a positive balance, holds released
  o := '  UPDATE public.wallets SET balance_gnf = 0 WHERE owner_user_id = u_d';
  n := '  UPDATE public.wallets SET held_gnf = 0, balance_gnf = 7000 WHERE owner_user_id = u_d';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'anchor D-setup not found'; END IF;
  d := replace(d, o, n);

  EXECUTE d;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_a14() FROM PUBLIC, anon, authenticated;
