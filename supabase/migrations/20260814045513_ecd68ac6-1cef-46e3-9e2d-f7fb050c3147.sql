DO $do$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r1_r4';
  v_def := replace(v_def,
    $x$v_args LIKE '%p_delivery_lat::numeric%' AND v_args LIKE '%p_delivery_lng::numeric%'$x$,
    $x$v_args LIKE '%v_lat::numeric%' AND v_args LIKE '%v_lng::numeric%'$x$);
  EXECUTE v_def;
END $do$;

INSERT INTO public._qa_s13_results(part, result)
SELECT 453, public._qa_node3_repas_r1_r4();
INSERT INTO public._qa_s13_results(part, result)
SELECT 454, public._qa_node3_repas_pickup();