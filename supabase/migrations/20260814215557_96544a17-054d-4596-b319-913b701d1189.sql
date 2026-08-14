DO $$
DECLARE v_def text; v_new text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname='_qa_node3_repas_r1_r4_fxcore';
  v_new := replace(v_def,
    'public.repas_order_create(uuid,jsonb,text,text,uuid,text,double precision,double precision,text)',
    'public.repas_order_create(uuid,jsonb,text,text,uuid,text,double precision,double precision,text,text,text,text)');
  IF v_new = v_def THEN
    RAISE EXCEPTION 'R11_CLOSEOUT: stale signature reference not found';
  END IF;
  EXECUTE v_new;
END $$;

DELETE FROM public._qa_s13_results r WHERE r.part = 1001;
INSERT INTO public._qa_s13_results(part, result)
VALUES (1001, public._qa_node3_repas_r1_r4());