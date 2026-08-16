DO $do$
DECLARE s text; s2 text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r3';
  s2 := s;
  s2 := replace(s2,
    $a$    BEGIN UPDATE public.marche_orders SET merchant_fee_gnf = 1000 WHERE id = v_o1;$a$,
    $a$    BEGIN UPDATE public.marche_orders SET merchant_fee_gnf = 1 WHERE id = v_o1;$a$);
  s2 := replace(s2,
    $a$    r := r || public._qa_s13_ok('N4R3.B15b commit never touches payment intents',
          v_src NOT LIKE '%payment_intent%' AND v_src NOT LIKE '%wallet%'
      AND v_src NOT LIKE '%ledger%' AND v_src NOT LIKE '%mission%', NULL);$a$,
    $a$    r := r || public._qa_s13_ok('N4R3.B15b commit never touches payment intents',
          v_src NOT LIKE '%payment_intent%' AND v_src NOT LIKE '%wallet%'
      AND v_src NOT LIKE '%ledger%' AND v_src NOT LIKE '%missions%'
      AND v_src NOT LIKE '%merchant_payables%', NULL);$a$);
  IF s2 = s THEN RAISE EXCEPTION 'R3_FINAL_AMENDMENT_NO_MATCH'; END IF;
  EXECUTE 'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r3() RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''public'' AS $qa$'||s2||'$qa$';
END $do$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r3() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r3() TO service_role;

DELETE FROM public._qa_s13_results WHERE part IN (32, 34, 35);
DO $$
BEGIN
  PERFORM public._qa_node4_marche_r4();
  PERFORM public._qa_node4_marche_r3();
  PERFORM public._qa_node4_marche_r35();
END $$;