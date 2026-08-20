DO $do$
DECLARE s text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc WHERE proname='_qa_node4_marche_r11';
  s := replace(s, 'v_off_x,''marketplace_delivery''', 'v_off_x,''marche''');
  s := replace(s, 'v_off,''marketplace_delivery''', 'v_off,''marche''');
  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_node4_marche_r11() RETURNS jsonb LANGUAGE plpgsql AS $qa$%s$qa$', s);
END $do$;
REVOKE ALL ON FUNCTION public._qa_node4_marche_r11() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r11() TO postgres, service_role;
INSERT INTO public._qa_s13_results(part, result) VALUES (411, public._qa_node4_marche_r11());