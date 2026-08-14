DO $$
DECLARE s text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_probe';
  s := replace(s, 'CASE WHEN p_uid IS NULL THEN '''' ELSE public._as_user_claims(p_uid) END',
                  'CASE WHEN p_uid IS NULL THEN ''{"role":"anon"}'' ELSE public._as_user_claims(p_uid) END');
  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_node4_probe(p_role text, p_uid uuid, p_sql text) RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''public'' AS %L', s);

  SELECT prosrc INTO s FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r1';
  s := replace(s,
    '  DELETE FROM auth.users WHERE id IN (v_seller, v_pend, v_comm, v_other, v_adm);',
    '  DELETE FROM public.wallet_transactions WHERE from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (v_seller, v_pend, v_comm, v_other, v_adm)) OR to_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (v_seller, v_pend, v_comm, v_other, v_adm));
  DELETE FROM public.wallets WHERE owner_user_id IN (v_seller, v_pend, v_comm, v_other, v_adm);
  DELETE FROM auth.users WHERE id IN (v_seller, v_pend, v_comm, v_other, v_adm);');
  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_node4_marche_r1() RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''public'' AS %L', s);
END $$;

DO $$
DECLARE v jsonb;
BEGIN
  v := public._qa_node4_marche_r1();
  INSERT INTO public._qa_s13_results(part, result) VALUES (9945, v);
END $$;