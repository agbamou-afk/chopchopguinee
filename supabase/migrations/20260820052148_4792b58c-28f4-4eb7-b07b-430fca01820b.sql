DO $mig$
DECLARE s text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc WHERE proname='_qa_node4_marche_r11';

  s := replace(s,
'  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok(''N4R11.X fixture run raised'', false, SQLERRM);
  END;',
'    RAISE EXCEPTION ''QA_N4R11_ROLLBACK'';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> ''QA_N4R11_ROLLBACK'' THEN
      r := r || public._qa_s13_ok(''N4R11.X fixture run raised'', false, SQLERRM);
    END IF;
  END;');

  s := regexp_replace(s,
    '  -- ===== CLEANUP =====.*?DELETE FROM auth\.users WHERE id IN \(v_buy,v_merch,v_merch2,v_adm,v_drv\);',
'  -- ===== CLEANUP: the fixture block above rolled itself back =====
  PERFORM set_config(''request.jwt.claims'','''', true);
  PERFORM set_config(''marche.rpc'','''', true);');

  s := replace(s,
'  SELECT count(*) INTO v_n FROM auth.users WHERE id IN (v_buy,v_merch,v_merch2,v_adm,v_drv);
  r := r || public._qa_s13_ok(''N4R11.S9 zero auth fixture residue'', v_n=0, v_n::text);',
'  SELECT count(*) INTO v_n FROM public.profiles WHERE id IN (v_buy,v_merch,v_merch2,v_adm,v_drv);
  r := r || public._qa_s13_ok(''N4R11.S9 zero identity fixture residue'', v_n=0, v_n::text);');

  IF s LIKE '%DELETE FROM auth.users%' OR s NOT LIKE '%QA_N4R11_ROLLBACK%' THEN
    RAISE EXCEPTION 'R11_HARNESS_PATCH_DID_NOT_APPLY';
  END IF;

  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_node4_marche_r11() RETURNS jsonb LANGUAGE plpgsql AS %L', s);
END $mig$;