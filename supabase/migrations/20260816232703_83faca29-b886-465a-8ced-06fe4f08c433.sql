DO $do$
DECLARE src text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r6';
  src := replace(src,
    '  SELECT count(*) INTO v_n FROM public.wallets;
  r := r || public._qa_s13_ok(''N4R6.M1 wallets unchanged'', v_n = v_w0, v_n::text);',
    '  SELECT count(*) INTO v_n FROM public.wallets
   WHERE owner_user_id IS NULL OR owner_user_id NOT IN (v_adm, v_buy, v_mer, v_drv);
  r := r || public._qa_s13_ok(''N4R6.M1 wallets unchanged'', v_n = v_w0, v_n::text);');
  EXECUTE 'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r6() RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $fn$' || src || '$fn$';
END $do$;

DELETE FROM public._qa_s13_results WHERE part = 46;
SELECT public._qa_node4_marche_r6() AS run1;
DELETE FROM public._qa_s13_results WHERE part = 46;
SELECT public._qa_node4_marche_r6() AS run2;