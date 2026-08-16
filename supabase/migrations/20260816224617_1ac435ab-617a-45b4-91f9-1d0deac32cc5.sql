REVOKE ALL ON public.marche_fulfillment_transitions FROM anon, authenticated, PUBLIC;
GRANT ALL ON public.marche_fulfillment_transitions TO service_role;

CREATE OR REPLACE FUNCTION public._qa_node4_marche_r5_patch() RETURNS void LANGUAGE plpgsql AS $p$
BEGIN NULL; END $p$;
DROP FUNCTION public._qa_node4_marche_r5_patch();

DO $do$
DECLARE s text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc WHERE proname='_qa_node4_marche_r5';
  s := replace(s,
    'r := r || public._qa_s13_ok(''N4R5.H1 exactly six canonical milestones on the happy path'',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1)=6, ',
    'r := r || public._qa_s13_ok(''N4R5.H1 exactly seven canonical milestones on the happy path'',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1)=7, ');
  s := replace(s,
    '    v_err := NULL;
    BEGIN PERFORM public.marche_dispatch_request(v_o3);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok(''N4R5.K4 cancelled order cannot be dispatched'', v_err=''ORDER_NOT_ACTIVE'', v_err);',
    '    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_merch), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_dispatch_request(v_o3);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok(''N4R5.K4 cancelled order cannot be dispatched'', v_err=''ORDER_NOT_ACTIVE'', v_err);');
  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_node4_marche_r5() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS %L', s);
END $do$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r5() FROM PUBLIC, anon, authenticated;

DELETE FROM public._qa_s13_results WHERE part = 45;
INSERT INTO public._qa_s13_results(part, result) VALUES (45, public._qa_node4_marche_r5());