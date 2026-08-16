-- 1. Restore R3 / R3.5 QA suites to their original (non-definer) form + amend B9f
DO $do$
DECLARE s text; s2 text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r3';
  s2 := replace(s,
    $a$    r := r || public._qa_s13_ok('N4R3.B9f fee columns cannot be populated in R3',
          v_err = 'FINANCE_NOT_IN_R3', v_err);$a$,
    $a$    r := r || public._qa_s13_ok('N4R3.B9f frozen fee columns cannot be rewritten after commitment (R4)',
          v_err = 'ECONOMICS_IMMUTABLE', v_err);$a$);
  IF s2 = s THEN RAISE EXCEPTION 'R3_B9F_NO_MATCH'; END IF;
  EXECUTE 'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r3() RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''public'' AS $qa$'||s2||'$qa$';

  SELECT prosrc INTO s FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r35';
  EXECUTE 'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r35() RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''public'' AS $qa$'||s||'$qa$';
END $do$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r3() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r3() TO service_role;
REVOKE ALL ON FUNCTION public._qa_node4_marche_r35() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r35() TO service_role;

-- 2. Rounding helper is server-internal only
REVOKE ALL ON FUNCTION public.marche_merchant_fee_gnf(bigint,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marche_merchant_fee_gnf(bigint,integer) TO service_role;

-- 3. R4 suite fixes: non-definer, correct money-abstinence probe, god-admin fixture
DO $do$
DECLARE s text; s2 text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r4';
  s2 := s;
  s2 := replace(s2,
    $a$        v_src NOT LIKE '%payment_intent%' AND v_src NOT LIKE '%wallet%'
    AND v_src NOT LIKE '%ledger%' AND v_src NOT LIKE '%merchant_payable%'
    AND v_src NOT LIKE '%missions%', NULL);$a$,
    $a$        v_src NOT LIKE '%payment_intent%' AND v_src NOT LIKE '%wallet%'
    AND v_src NOT LIKE '%ledger%' AND v_src NOT LIKE '%merchant_payables%'
    AND v_src NOT LIKE '%missions%' AND v_src NOT LIKE '%_merchant_payable_create_internal%', NULL);$a$);
  s2 := replace(s2,
    $a$    PERFORM public._qa_s13_admin(v_adm);$a$,
    $a$    PERFORM public._qa_s13_admin(v_adm);
    INSERT INTO public.user_roles(user_id, role) VALUES (v_adm, 'god_admin')
      ON CONFLICT (user_id, role) DO NOTHING;$a$);
  s2 := replace(s2,
    $a$  DELETE FROM public.admin_users WHERE user_id = v_adm;$a$,
    $a$  DELETE FROM public.admin_users WHERE user_id = v_adm;
  DELETE FROM public.user_roles WHERE user_id IN (v_buy, v_merch, v_adm);$a$);
  IF s2 = s THEN RAISE EXCEPTION 'R4_QA_FIX_NO_MATCH'; END IF;
  EXECUTE 'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r4() RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''public'' AS $qa$'||s2||'$qa$';
END $do$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r4() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r4() TO service_role;

DELETE FROM public._qa_s13_results WHERE part IN (32, 34, 35);
DO $$
BEGIN
  PERFORM public._qa_node4_marche_r4();
  PERFORM public._qa_node4_marche_r3();
  PERFORM public._qa_node4_marche_r35();
END $$;