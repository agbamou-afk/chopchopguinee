DO $do$
DECLARE src text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r6';
  src := replace(src,
    'FROM public.wallets WHERE user_id NOT IN (v_adm, v_buy, v_mer, v_drv)',
    'FROM public.wallets WHERE owner_user_id NOT IN (v_adm, v_buy, v_mer, v_drv)');
  src := replace(src,
    'WHERE NOT EXISTS (SELECT 1 FROM public.wallets w WHERE w.id = wt.wallet_id
                      AND w.user_id IN (v_adm, v_buy, v_mer, v_drv))',
    'WHERE NOT EXISTS (SELECT 1 FROM public.wallets w
                       WHERE w.id IN (wt.from_wallet_id, wt.to_wallet_id)
                         AND w.owner_user_id IN (v_adm, v_buy, v_mer, v_drv))');
  EXECUTE 'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r6() RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $fn$' || src || '$fn$';
END $do$;

DELETE FROM public._qa_s13_results WHERE part = 46;
SELECT public._qa_node4_marche_r6();