DO $$
DECLARE v jsonb;
BEGIN
  SELECT to_jsonb(public._qa_node3_repas_r8_discovery()) INTO v;
  INSERT INTO public._qa_s13_results(part, result) VALUES (9951, v);
END $$;