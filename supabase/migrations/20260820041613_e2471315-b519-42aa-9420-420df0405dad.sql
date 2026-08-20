DO $$
DECLARE src text;
BEGIN
  src := pg_get_functiondef('public._qa_node4_marche_r10()'::regprocedure);
  src := replace(src, '''qa-n410-d''||g, ''qa-n410-d''||g',   'gen_random_uuid()::text, ''qa-n410-d''||g');
  src := replace(src, '''qa-n410-r1'', ''qa-n410-r1''',       'gen_random_uuid()::text, ''qa-n410-r1''');
  src := replace(src, '''qa-n410-c''||g, ''qa-n410-c''||g',   'gen_random_uuid()::text, ''qa-n410-c''||g');
  src := replace(src, '''qa-n410-old''||g, ''qa-n410-old''||g','gen_random_uuid()::text, ''qa-n410-old''||g');
  src := replace(src, '''qa-n410-f1''||i, ''qa-n410-f1''||i', 'gen_random_uuid()::text, ''qa-n410-f1''||i');
  src := replace(src, '''qa-n410-f2''||i, ''qa-n410-f2''||i', 'gen_random_uuid()::text, ''qa-n410-f2''||i');
  IF src LIKE '%''qa-n410-d''||g, ''qa-n410-d''||g%' THEN
    RAISE EXCEPTION 'R10_FIXTURE_PATCH_DID_NOT_APPLY';
  END IF;
  EXECUTE src;
END $$;

DO $$
DECLARE x jsonb; BEGIN
  BEGIN
    x := public._qa_node4_marche_r10();
  EXCEPTION WHEN OTHERS THEN
    x := jsonb_build_object('suite','node4_marche_r10','total',0,'failed',1,
         'results', jsonb_build_array(jsonb_build_object('ok',false,'label','ABORT','detail',SQLERRM)));
  END;
  DELETE FROM public._qa_s13_results WHERE part IN (4200,4201);
  INSERT INTO public._qa_s13_results(part, result) VALUES (4201, x);
END $$;