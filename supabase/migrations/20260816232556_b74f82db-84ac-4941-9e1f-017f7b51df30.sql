DO $do$
DECLARE src text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r6';
  src := replace(src,
    '  INSERT INTO public.user_roles(user_id, role) VALUES (v_mer,''merchant''), (v_drv,''driver'');',
    '  INSERT INTO public.user_roles(user_id, role) VALUES (v_mer,''merchant''), (v_drv,''driver'');
  SELECT count(*) INTO v_w0 FROM public.wallets
   WHERE owner_user_id IS NULL OR owner_user_id NOT IN (v_adm, v_buy, v_mer, v_drv);
  SELECT count(*) INTO v_wt0 FROM public.wallet_transactions;');
  src := replace(src,
    'FROM public.wallets WHERE owner_user_id NOT IN (v_adm, v_buy, v_mer, v_drv)',
    'FROM public.wallets WHERE owner_user_id IS NULL OR owner_user_id NOT IN (v_adm, v_buy, v_mer, v_drv)');
  EXECUTE 'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r6() RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $fn$' || src || '$fn$';
END $do$;

DELETE FROM public._qa_s13_results WHERE part = 46;
SELECT public._qa_node4_marche_r6() AS run1;
DELETE FROM public._qa_s13_results WHERE part = 46;
SELECT public._qa_node4_marche_r6() AS run2;