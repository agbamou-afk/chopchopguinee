DO $do$
DECLARE src text;
BEGIN
  src := pg_get_functiondef('public._qa_node4_marche_r9()'::regprocedure);

  src := replace(src,
'    -- ================= I. PUBLIC AGGREGATE TRUTH =================',
'    -- ================= I. PUBLIC AGGREGATE TRUTH =================
    SELECT count(*) INTO v_w0 FROM public.wallet_transactions;
    SELECT count(*) INTO v_lp0 FROM public.ledger_postings;
    SELECT COALESCE(sum(held_gnf),0) INTO v_held0 FROM public.wallets;');

  src := replace(src,
'      v_lp1 - v_lp0 = (SELECT count(*) FROM public.ledger_postings p
                        JOIN public.ledger_journals j ON j.id=p.journal_id
                        WHERE j.created_at > now() - interval ''1 second'' AND false)
      OR true, NULL);',
'      v_lp1 = v_lp0 AND v_w1 = v_w0 AND v_held1 = v_held0,
      format(''%s/%s/%s'', v_lp1 - v_lp0, v_w1 - v_w0, v_held1 - v_held0));');

  IF src LIKE '%OR true, NULL);%' THEN
    RAISE EXCEPTION 'R9_HARNESS_PATCH_FAILED';
  END IF;
  EXECUTE src;
END $do$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r9() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r9() TO service_role;