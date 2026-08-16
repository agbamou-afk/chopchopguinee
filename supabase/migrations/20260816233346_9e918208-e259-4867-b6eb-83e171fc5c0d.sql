DO $do$
DECLARE w0 bigint; o0 bigint; w1 bigint; o1 bigint; w2 bigint; o2 bigint; r1 jsonb; r2 jsonb;
BEGIN
  SELECT count(*) INTO w0 FROM public.wallets;
  SELECT count(*) INTO o0 FROM public.wallets w WHERE w.owner_user_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = w.owner_user_id);
  r1 := public._qa_node4_marche_r6();
  SELECT count(*) INTO w1 FROM public.wallets;
  SELECT count(*) INTO o1 FROM public.wallets w WHERE w.owner_user_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = w.owner_user_id);
  r2 := public._qa_node4_marche_r6();
  SELECT count(*) INTO w2 FROM public.wallets;
  SELECT count(*) INTO o2 FROM public.wallets w WHERE w.owner_user_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = w.owner_user_id);
  RAISE NOTICE 'RUN1 total=% failed=% | RUN2 total=% failed=% | wallets %/%/% orphans %/%/%',
    r1->>'total', r1->>'failed', r2->>'total', r2->>'failed', w0,w1,w2,o0,o1,o2;
  IF (r1->>'failed')::int > 0 OR (r2->>'failed')::int > 0 OR w0 <> w2 OR o0 <> o2 THEN
    RAISE EXCEPTION 'R6 NOT DETERMINISTIC: %', jsonb_build_object('r1',r1->'failures','r2',r2->'failures','w',ARRAY[w0,w1,w2],'o',ARRAY[o0,o1,o2]);
  END IF;
END $do$;
SELECT (public._qa_node4_marche_r6())->>'total' AS r6_third_run_total;