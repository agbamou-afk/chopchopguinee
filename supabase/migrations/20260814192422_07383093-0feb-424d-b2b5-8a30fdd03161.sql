DO $do$
DECLARE v_src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r8_extra';
  v_src := replace(v_src,
    'SELECT count(*) INTO v_n FROM public.wallet_transactions WHERE wallet_id IN
      (SELECT id FROM public.wallets WHERE owner_user_id = v_cust);',
    'SELECT count(*) INTO v_n FROM public.wallet_transactions t
      WHERE t.from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id = v_cust)
         OR t.to_wallet_id   IN (SELECT id FROM public.wallets WHERE owner_user_id = v_cust);');
  EXECUTE v_src;
END
$do$;
