GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO anon;

DO $$
DECLARE v jsonb;
BEGIN
  v := public._qa_node4_marche_r1();
  INSERT INTO public._qa_s13_results(part, result) VALUES (9947, v);
END $$;