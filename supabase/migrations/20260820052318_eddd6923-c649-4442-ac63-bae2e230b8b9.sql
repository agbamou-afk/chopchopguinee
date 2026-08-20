DO $mig$
DECLARE s text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc WHERE proname='_qa_node4_marche_r11';
  s := replace(s,
'    r := r || public._qa_s13_ok(''N4R11.M0 the canonical eligibility surface answers a number'',
          v_elig IS NOT NULL, v_elig::text);',
'    r := r || public._qa_s13_ok(''N4R11.M0 the canonical eligibility surface answers a number'',
          v_elig IS NOT NULL, v_elig::text);
    r := r || public._qa_s13_ok(''N4R11.M0b eligibility really includes the due unallocated payable'',
          COALESCE(v_elig,0) >= 4950, v_elig::text);');
  IF s NOT LIKE '%M0b eligibility%' THEN RAISE EXCEPTION 'R11_M0B_PATCH_DID_NOT_APPLY'; END IF;
  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_node4_marche_r11() RETURNS jsonb LANGUAGE plpgsql AS %L', s);
END $mig$;