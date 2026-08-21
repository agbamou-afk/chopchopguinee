DO $mig$
DECLARE d text; o text; n text;
BEGIN
  d := pg_get_functiondef('public._qa_node5_finance_dormant_liability()'::regprocedure);
  o := $o$  -- ================= G. NO AUTHORITY SURVIVES THE LIABILITY =================$o$;
  n := $n$  BEGIN
    PERFORM public._driver_exact_hold_place_internal(
      'ride','qa_n5dl_spend', gen_random_uuid(), u_pos, 1000);
    r := r || public._qa_s13_ok('N5DL.F12 a real spending path refuses to draw on a dormant wallet',
          false, 'hold accepted');
  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok('N5DL.F12 a real spending path refuses to draw on a dormant wallet',
          SQLERRM ILIKE '%Wallet not active%' OR SQLERRM ILIKE '%ACCOUNT_RESTRICTED%', SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5DL.F13 the refused spend left the preserved money exactly intact',
        (SELECT balance_gnf = 29448 AND held_gnf = 0 FROM public.wallets
          WHERE owner_user_id=u_pos AND party_type='driver'), NULL);

  -- ================= G. NO AUTHORITY SURVIVES THE LIABILITY =================$n$;
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'anchor G not found'; END IF;
  d := replace(d, o, n);
  EXECUTE d;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_node5_finance_dormant_liability() FROM PUBLIC, anon, authenticated;
