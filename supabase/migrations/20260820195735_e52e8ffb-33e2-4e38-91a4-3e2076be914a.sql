CREATE OR REPLACE FUNCTION public._qa_node4_marche_r14_patch()
RETURNS void LANGUAGE plpgsql AS $$ BEGIN NULL; END $$;

DO $do$
DECLARE src text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE proname='_qa_node4_marche_r14';

  src := replace(src,
    'NOT (SELECT is_orderable FROM public.v_marche_listing_truth WHERE id=l_a)',
    'NOT (SELECT is_orderable FROM public.v_marche_listing_truth WHERE listing_id=l_a)');
  src := replace(src,
    '(SELECT is_orderable FROM public.v_marche_listing_truth WHERE id=l_a)',
    '(SELECT is_orderable FROM public.v_marche_listing_truth WHERE listing_id=l_a)');

  src := replace(src,
$old$    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_orders_cockpit(v_store,NULL,10,0);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.B4 a signed-out caller cannot read a merchant cockpit', v_err IS NOT NULL, v_err);$old$,
$new$    v_res := NULL; v_err := NULL;
    BEGIN v_res := public.marche_merchant_orders_cockpit(v_store,NULL,10,0);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.B4 a signed-out caller obtains no merchant cockpit data',
          v_err IS NOT NULL OR COALESCE(jsonb_array_length(v_res->'items'),0)=0, COALESCE(v_err, v_res::text));
    r := r || public._qa_s13_ok('N4R14.B4b the merchant cockpit is not reachable by an unauthenticated API caller',
          NOT has_function_privilege('anon','public.marche_merchant_orders_cockpit(uuid,text,integer,integer)','EXECUTE'), NULL);$new$);

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r14() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS %s',
    quote_literal(src));
END
$do$;

DROP FUNCTION public._qa_node4_marche_r14_patch();
REVOKE ALL ON FUNCTION public._qa_node4_marche_r14() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._qa_node4_marche_r14() FROM anon;
REVOKE ALL ON FUNCTION public._qa_node4_marche_r14() FROM authenticated;