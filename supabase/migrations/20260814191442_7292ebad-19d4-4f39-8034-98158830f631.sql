-- A. Route quote + commitment through the canonical publication assertion
DO $$
DECLARE
  v_name text;
  v_def text;
  v_new text;
BEGIN
  FOREACH v_name IN ARRAY ARRAY['repas_quote_preview','repas_order_create'] LOOP
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = v_name;
    IF v_def IS NULL THEN RAISE EXCEPTION 'MISSING_FUNCTION %', v_name; END IF;
    v_new := replace(v_def,
      'IF v_r.status <> ''active'' THEN RAISE EXCEPTION ''RESTAURANT_NOT_ORDERABLE''; END IF;',
      'PERFORM public._repas_assert_orderable_publication(v_r);');
    IF v_new = v_def THEN RAISE EXCEPTION 'PUBLICATION_GUARD_ANCHOR_NOT_FOUND in %', v_name; END IF;
    EXECUTE v_new;
  END LOOP;
END $$;

-- B. Fixture publication context for the established QA harnesses
ALTER FUNCTION public._qa_node3_repas_r1_r4() RENAME TO _qa_node3_repas_r1_r4_fxcore;
ALTER FUNCTION public._qa_node3_repas_pickup() RENAME TO _qa_node3_repas_pickup_fxcore;
ALTER FUNCTION public._qa_node3_repas_r6_custody() RENAME TO _qa_node3_repas_r6_custody_fxcore;
ALTER FUNCTION public._qa_node3_repas_r7_tracking_receipt() RENAME TO _qa_node3_repas_r7_tracking_receipt_fxcore;
ALTER FUNCTION public._qa_s13_run3() RENAME TO _qa_s13_run3_fxcore;
ALTER FUNCTION public._qa_s13_run7() RENAME TO _qa_s13_run7_fxcore;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_r1_r4()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_out jsonb; BEGIN
  PERFORM set_config('app.repas_fixture_verified','1', true);
  v_out := public._qa_node3_repas_r1_r4_fxcore();
  PERFORM set_config('app.repas_fixture_verified','', true);
  RETURN v_out; END; $function$;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_pickup()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_out jsonb; BEGIN
  PERFORM set_config('app.repas_fixture_verified','1', true);
  v_out := public._qa_node3_repas_pickup_fxcore();
  PERFORM set_config('app.repas_fixture_verified','', true);
  RETURN v_out; END; $function$;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_r6_custody()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_out jsonb; BEGIN
  PERFORM set_config('app.repas_fixture_verified','1', true);
  v_out := public._qa_node3_repas_r6_custody_fxcore();
  PERFORM set_config('app.repas_fixture_verified','', true);
  RETURN v_out; END; $function$;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_r7_tracking_receipt()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_out jsonb; BEGIN
  PERFORM set_config('app.repas_fixture_verified','1', true);
  v_out := public._qa_node3_repas_r7_tracking_receipt_fxcore();
  PERFORM set_config('app.repas_fixture_verified','', true);
  RETURN v_out; END; $function$;

CREATE OR REPLACE FUNCTION public._qa_s13_run3()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_out jsonb; BEGIN
  PERFORM set_config('app.repas_fixture_verified','1', true);
  v_out := public._qa_s13_run3_fxcore();
  PERFORM set_config('app.repas_fixture_verified','', true);
  RETURN v_out; END; $function$;

CREATE OR REPLACE FUNCTION public._qa_s13_run7()
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'public' AS $function$
DECLARE v_out jsonb; BEGIN
  PERFORM set_config('app.repas_fixture_verified','1', true);
  v_out := public._qa_s13_run7_fxcore();
  PERFORM set_config('app.repas_fixture_verified','', true);
  RETURN v_out; END; $function$;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_r5_runtime()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_out jsonb; BEGIN
  PERFORM set_config('app.repas_publication_ctx','1', true);
  PERFORM set_config('app.repas_fixture_verified','1', true);
  v_out := public._qa_node3_repas_r5_runtime_core();
  PERFORM set_config('app.repas_fixture_verified','', true);
  PERFORM set_config('app.repas_publication_ctx','', true);
  RETURN v_out; END; $function$;

DO $$
DECLARE v_name text;
BEGIN
  FOREACH v_name IN ARRAY ARRAY[
    '_qa_node3_repas_r1_r4','_qa_node3_repas_pickup','_qa_node3_repas_r6_custody',
    '_qa_node3_repas_r7_tracking_receipt','_qa_s13_run3','_qa_s13_run7','_qa_node3_repas_r5_runtime',
    '_qa_node3_repas_r1_r4_fxcore','_qa_node3_repas_pickup_fxcore','_qa_node3_repas_r6_custody_fxcore',
    '_qa_node3_repas_r7_tracking_receipt_fxcore','_qa_s13_run3_fxcore','_qa_s13_run7_fxcore']
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%I() FROM PUBLIC, anon, authenticated', v_name);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I() TO service_role', v_name);
  END LOOP;
END $$;
