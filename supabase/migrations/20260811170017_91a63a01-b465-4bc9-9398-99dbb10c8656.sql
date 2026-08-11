DO $mig$
DECLARE src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_s13_run3';

  src := replace(src,
    'VALUES (v_cust, v_rest, 200000, ''wallet'', ''placed'', ''delivery'') RETURNING id INTO v_o2;',
    'VALUES (v_cust, v_rest, 200000, ''choppay'', ''placed'', ''delivery'') RETURNING id INTO v_o2;');
  src := replace(src,
    'VALUES (v_cust, v_rest, 50000, ''wallet'', ''placed'', ''delivery'') RETURNING id INTO v_o3;',
    'VALUES (v_cust, v_rest, 50000, ''choppay'', ''placed'', ''delivery'') RETURNING id INTO v_o3;');
  src := replace(src,
    'INSERT INTO public.marketplace_listings(seller_id, category, title, merchant_store_id)
    VALUES (v_own, ''divers'', ''QA S13 Article'', v_store) RETURNING id INTO v_lst;',
    'INSERT INTO public.marketplace_listings(seller_id, category, title)
    VALUES (v_own, ''divers'', ''QA S13 Article'') RETURNING id INTO v_lst;');
  src := replace(src,
    '    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_drv AND party_type=''driver'';
    SELECT balance_gnf INTO v_mw0 FROM public.wallets WHERE party_type=''master'' LIMIT 1;',
    '    UPDATE public.missions SET pickup_confirmed_at = now(), state = ''picked_up'' WHERE id = v_mis;
    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_drv AND party_type=''driver'';
    SELECT balance_gnf INTO v_mw0 FROM public.wallets WHERE party_type=''master'' LIMIT 1;');

  EXECUTE src;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_s13_run3() FROM PUBLIC, anon, authenticated;

INSERT INTO public._qa_s13_results(part, result) SELECT 3, public._qa_s13_run3();