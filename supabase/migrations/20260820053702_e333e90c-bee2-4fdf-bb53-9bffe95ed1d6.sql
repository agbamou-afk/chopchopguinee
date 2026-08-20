-- QA-only: the D4 append-only probe issued an unqualified UPDATE, which the
-- PostgREST session rejects with "UPDATE requires a WHERE clause" before the
-- product append-only trigger can fire. Add an all-rows predicate so the same
-- product path is exercised. Assertion label, count and expectation unchanged.
DO $mig$
DECLARE d text; nd text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node4_marche_r65';
  nd := replace(d,
    'BEGIN UPDATE public.marche_procurement_price_observations SET observed_unit_price_gnf = 1;',
    'BEGIN UPDATE public.marche_procurement_price_observations SET observed_unit_price_gnf = 1 WHERE id IS NOT NULL;');
  IF nd = d THEN RAISE EXCEPTION 'D4 probe pattern drift'; END IF;
  EXECUTE nd;
END $mig$;