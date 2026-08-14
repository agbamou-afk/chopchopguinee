DO $$
DECLARE s text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r1';
  s := replace(s,
    'INSERT INTO public.account_bans(user_id, status, reason)
      VALUES (v_comm, ''active'', ''qa-n4-fixture'');',
    'INSERT INTO public.account_bans(user_id, status, reason, banned_by)
      VALUES (v_comm, ''active'', ''qa-n4-fixture'', v_adm);');
  IF position('banned_by' in s) = 0 THEN
    RAISE EXCEPTION 'patch did not apply';
  END IF;
  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r1() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''public'' AS %L', s);
END $$;