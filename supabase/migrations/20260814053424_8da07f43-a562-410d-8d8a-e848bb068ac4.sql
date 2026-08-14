DO $mig$
DECLARE s text; s0 text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO s FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_chop_pay_courier_adjust_internal';
  s0 := s;
  s := replace(s, E'    END,\n    p_actor);', E'    END,\n    p_mission_type := p_source_module, p_actor := p_actor);');
  IF s = s0 THEN RAISE EXCEPTION 'courier adjust patch failed'; END IF;
  EXECUTE s;
END $mig$;

REVOKE ALL ON FUNCTION public._chop_pay_courier_adjust_internal(text,uuid,bigint,uuid,uuid) FROM PUBLIC, anon, authenticated;

DELETE FROM public._qa_s13_results WHERE part = 351;
INSERT INTO public._qa_s13_results(part, result)
VALUES (351, public._qa_node3_repas_r5_runtime());