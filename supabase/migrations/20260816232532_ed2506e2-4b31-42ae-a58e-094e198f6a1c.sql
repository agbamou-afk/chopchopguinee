DELETE FROM public.wallets w
 WHERE w.owner_user_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = w.owner_user_id)
   AND w.created_at >= timestamptz '2026-08-16 23:00:00+00';

DO $do$
DECLARE src text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r6';
  src := replace(src,
    '  DELETE FROM public.profiles WHERE id IN (v_adm, v_buy, v_mer, v_drv);',
    '  DELETE FROM public.wallets WHERE owner_user_id IN (v_adm, v_buy, v_mer, v_drv);
  DELETE FROM public.profiles WHERE id IN (v_adm, v_buy, v_mer, v_drv);');
  EXECUTE 'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r6() RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $fn$' || src || '$fn$';
END $do$;

DELETE FROM public._qa_s13_results WHERE part = 46;
SELECT public._qa_node4_marche_r6() AS run1;
DELETE FROM public._qa_s13_results WHERE part = 46;
SELECT public._qa_node4_marche_r6() AS run2;