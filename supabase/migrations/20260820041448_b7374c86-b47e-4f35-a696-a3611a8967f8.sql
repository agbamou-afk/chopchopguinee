DO $$
DECLARE x jsonb; BEGIN
  BEGIN
    x := public._qa_node4_marche_r10();
  EXCEPTION WHEN OTHERS THEN
    x := jsonb_build_array(jsonb_build_object('ok',false,'label','ABORT','detail',SQLERRM));
  END;
  DELETE FROM public._qa_s13_results WHERE part = 4200;
  INSERT INTO public._qa_s13_results(part, result) VALUES (4200, x);
END $$;