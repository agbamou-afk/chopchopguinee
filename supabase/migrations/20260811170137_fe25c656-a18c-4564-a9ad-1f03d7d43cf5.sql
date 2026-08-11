DO $mig$
DECLARE src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_s13_run3';

  src := replace(src,
    'ON CONFLICT (user_id) DO UPDATE SET status=''approved'';',
    'ON CONFLICT (user_id) DO UPDATE SET status=''approved'';
    UPDATE public.driver_profiles
       SET capabilities = ARRAY[''rides_moto'',''repas_delivery'',''marche_delivery'',''package_delivery'']
     WHERE user_id IN (v_dpromo, v_drv);');

  EXECUTE src;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_s13_run3() FROM PUBLIC, anon, authenticated;

INSERT INTO public._qa_s13_results(part, result) SELECT 3, public._qa_s13_run3();